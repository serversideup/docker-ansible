#!/bin/bash
set -eo pipefail

# Simplify directory references
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT_DIR="$SCRIPT_DIR"

ANSIBLE_VARIATION=""
ANSIBLE_VERSION=""
PYTHON_VERSION=""
BASE_OS=""
GITHUB_REF_NAME="${GITHUB_REF_NAME:-""}"
RELEASE_TYPE="dev"
DOCKER_ORGANIZATIONS="${DOCKER_ORGANIZATIONS:-"docker.io/serversideup ghcr.io/serversideup"}"
DOCKER_ADDITIONAL_BUILD_ARGS=()
ANSIBLE_VERSIONS_FILE="${ANSIBLE_VERSIONS_FILE:-$SCRIPT_DIR/ansible-versions.yml}"
PRINT_TAGS_ONLY=false

##################################################
# Functions
##################################################

add_tag() {
    local tag=$1
    for org in $DOCKER_ORGANIZATIONS; do
        local repo="${org}/${ANSIBLE_VARIATION}"
        tags+=("$repo:$tag")
        if [ -n "$GITHUB_REF_NAME" ] && [[ "$RELEASE_TYPE" == "latest" || "$RELEASE_TYPE" == "beta" ]]; then
            # Replace the prefix with the GitHub release tag if it exists
            if [[ "$tag" == "$tag_prefix"* ]]; then
                new_tag="${GITHUB_REF_NAME}-${tag#$tag_prefix}"
            else
                new_tag="${GITHUB_REF_NAME}-${tag}"
            fi
            tags+=("$repo:$new_tag")
        fi
    done
}

are_other_components_latest() {
    local exclude=$1
    local conditions=("$is_ansible_latest" "$is_python_latest" "$is_os_latest" "$is_os_version_latest" "$is_os_family_latest")
    
    for component in "${conditions[@]}"; do
        if [ "$component" != "$exclude" ] && [ "$component" != "true" ]; then
            return 1
        fi
    done
    
    return 0
}

build_docker_image() {
    tags=($(generate_tags))
  
    # Use the centralized functions to get OS family and package dependencies
    local os_family=$(get_os_family)
    local package_dependencies=$(get_package_dependencies "$os_family")

    # Get the full patch version and save it to GITHUB_ENV
    local full_ansible_version=$(lookup_and_save_ansible_version "$ANSIBLE_VARIATION" "$ANSIBLE_VERSION" | tail -n1)

    # Remove any ANSI color codes from the version string
    full_ansible_version=$(echo "$full_ansible_version" | sed 's/\x1b\[[0-9;]*m//g')

    build_args=(
        --build-arg ANSIBLE_VARIATION="$ANSIBLE_VARIATION"
        --build-arg ANSIBLE_VERSION="$full_ansible_version"
        --build-arg PYTHON_VERSION="$PYTHON_VERSION"
        --build-arg BASE_OS_VERSION="$BASE_OS"
    )

    if [ -n "$package_dependencies" ]; then
        build_args+=(--build-arg PACKAGE_DEPENDENCIES="$package_dependencies")
    fi

    for tag in "${tags[@]}"; do
        build_args+=(--tag "$tag")
    done

    echo_color_message yellow "🐳 Building Docker Image with tags:"
    printf '%s\n' "${tags[@]}"
    
    # Set default platform if not specified
    if [ -z "$PLATFORM" ]; then
        PLATFORM="linux/amd64"
    fi

    # Add platform to build args
    build_args+=(--platform "$PLATFORM")

    # Construct the Docker command as an array
    docker_command=(
        docker buildx build
        "${DOCKER_ADDITIONAL_BUILD_ARGS[@]}"
        "${build_args[@]}"
        --file "src/Dockerfile"
        "$PROJECT_ROOT_DIR"
    )
    
    # Show the Docker command
    echo_color_message yellow "Docker command to be executed:"
    echo "${docker_command[*]}"
    
    # Execute the Docker command
    "${docker_command[@]}"

    # Echo out the tags at the end
    echo_color_message green "✅ Docker image built successfully with the following tags:"
    printf '%s\n' "${tags[@]}" | sort
}

check_vars() {
  message=$1
  shift

  for variable in "$@"; do
    if [ -z "${!variable}" ]; then
      echo_color_message red "$message: $variable"
      echo
      help_menu
      return 1
    fi
  done
  return 0
}

echo_color_message (){
  color=$1
  message=$2

  ui_set_$color
  echo "$message"
  ui_reset_colors
}

# UI Colors
function ui_set_yellow {
    printf $'\033[0;33m'
}

function ui_set_green {
    printf $'\033[0;32m'
}

function ui_set_red {
    printf $'\033[0;31m'
}

function ui_reset_colors {
    printf "\e[0m"
}

fetch_latest_component_versions() {
    local yaml_file="$ANSIBLE_VERSIONS_FILE"
    local variation="$1"
    
    # Get latest stable Ansible version for the specified variation
    local ansible_version=$(yq e ".ansible_variations[] | select(.name == \"$variation\") | .versions[] | select(.latest_stable == true) | .version" "$yaml_file")
    ansible_version=$(lookup_pypi_version "$variation" "$ansible_version")
    
    # Get latest stable Python version
    local python_version=$(yq e ".python_versions[] | select(.latest_stable == true) | .name" "$yaml_file")
    
    # Get latest stable OS
    local base_os=$(yq e ".operating_system_distributions[].versions[] | select(.latest_stable == true) | .name" "$yaml_file" | head -n1)
    
    echo "$ansible_version $python_version $base_os"
}

generate_tags() {
    local tags=()
    local os_family=$(yq e ".operating_system_distributions[] | select(.versions[].name == \"$BASE_OS\") | .name" "$ANSIBLE_VERSIONS_FILE")

    # Get latest stable values
    local latest_ansible latest_python latest_os
    read -r latest_ansible latest_python latest_os <<< $(fetch_latest_component_versions "$ANSIBLE_VARIATION")

    # Check if each component is the latest stable
    local is_ansible_latest=$([ "$ANSIBLE_VERSION" == "$latest_ansible" ] && echo true || echo false)
    local is_python_latest=$([ "$PYTHON_VERSION" == "$latest_python" ] && echo true || echo false)
    local is_os_latest=$([ "$BASE_OS" == "$latest_os" ] && echo true || echo false)
    local is_os_family_latest=$(yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")
    local is_os_version_latest=$(yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .versions[] | select(.name == \"$BASE_OS\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")

    is_latest_ansible_version_and_python_version() {
        [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ]
    }

    is_default_os() {
        [ "$is_os_latest" == "true" ] && [ "$is_os_version_latest" == "true" ] && [ "$is_os_family_latest" == "true" ]
    }

    is_default_release() {
        is_latest_ansible_version_and_python_version && is_default_os
    }

    # Determine the tag prefix based on release type
    local tag_prefix=""
    if [ "$RELEASE_TYPE" != "latest" ]; then
        tag_prefix="${RELEASE_TYPE}-"
    fi

    # Most specific tag
    add_tag "${tag_prefix}${ANSIBLE_VERSION}-${BASE_OS}-python${PYTHON_VERSION}"

    # Tag without Ansible Version if it's the latest
    if [ "$is_ansible_latest" == "true" ]; then
        add_tag "${tag_prefix}${BASE_OS}-python${PYTHON_VERSION}"
    fi

    # Tag with OS family instead of specific OS if it's the latest in its family
    if [ "$is_os_family_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${os_family}-python${PYTHON_VERSION}"
    fi

    # Tag without OS if it's the default
    if [ "$is_os_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-python${PYTHON_VERSION}"
    fi

    # Tag without Python Version if it's the latest
    if [ "$is_python_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${BASE_OS}"
    fi

    # Tag without Python Version or OS if both are default
    if [ "$is_python_latest" == "true" ] && is_default_os; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
    fi

    # Most general tag if everything is default
    if is_default_release; then
        add_tag "$RELEASE_TYPE"
        if [ -n "$GITHUB_REF_NAME" ] && [[ "$RELEASE_TYPE" == "latest" || "$RELEASE_TYPE" == "beta" ]]; then
            add_tag "${GITHUB_REF_NAME}"
        fi
    fi

    # Tag for OS family if it's the latest stable and Ansible and Python are latest
    if [ "$is_os_version_latest" == "true" ] && [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ]; then
        add_tag "${tag_prefix}${os_family}"
    fi

    # Tag for specific OS when Ansible and Python are latest, regardless of OS being latest
    if [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ]; then
        add_tag "${tag_prefix}${BASE_OS}"
    fi

    # Tag for Python version
    if are_other_components_latest "$is_python_latest" && is_default_os; then
        add_tag "${tag_prefix}python${PYTHON_VERSION}"
    fi

    # Tag for Ansible version (only if everything else is latest)
    if are_other_components_latest "$is_ansible_latest"; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
    fi

    # Remove duplicates and print tags
    printf '%s\n' "${tags[@]}" | sort -u
}

get_os_family() {
    yq e ".operating_system_distributions[] | select(.versions[].name == \"$BASE_OS\") | .name" "$ANSIBLE_VERSIONS_FILE"
}

get_package_dependencies() {
    local os_family=$1
    yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .versions[] | select(.name == \"$BASE_OS\") | .package_dependencies[]" "$ANSIBLE_VERSIONS_FILE" | tr '\n' ',' | sed 's/,$//'
}

get_yq_value() {
    local option=$1
    local value=$2
    local yq_query=$3
    
    if [ -n "$value" ]; then
        if [[ $option == "Ansible version" ]]; then
            # For Ansible version, we'll validate it later when we get the full version
            return
        fi
        local valid_options
        valid_options=$(yq e "$yq_query" "$ANSIBLE_VERSIONS_FILE" | tr '\n' ' ')
        if [[ ! " $valid_options " =~ " $value " ]]; then
            echo_color_message red "Error: Invalid $option '$value'"
            echo "Valid options are:"
            echo "$valid_options"
            exit 1
        fi
    fi
}

help_menu() {
    echo "Usage: $0 [--variation <variation>] [--version <version>] [--python <python_version>] [--os <os>] [additional options]"
    echo
    echo "This script builds and tags a Docker image for a specific Ansible version,"
    echo "variation, Python version, and base OS. It can be used for local development"
    echo "or in CI/CD pipelines."
    echo
    echo "At least one of the following options is required:"
    echo "  --variation <variation>   Set the Ansible variation (e.g., ansible, ansible-core)"
    echo "  --version <version>       Set the Ansible version (e.g., 2.15.3, 2.16.5, 2.17.4)"
    echo "  --python <python_version> Set the Python version (e.g., 3.9, 3.10, 3.11, 3.12)"
    echo "  --os <os>                 Set the base OS (e.g., alpine3.20, bullseye)"
    echo
    echo "Optional arguments:"
    echo "  --github-release-tag <tag> Set the GitHub release tag"
    echo "  --release-type <type>    Set the release type (e.g., latest, beta, rc). Default: dev"
    echo "  --repository <repos>      Space-separated list of Docker repositories (default: 'docker.io/serversideup/ansible ghcr.io/serversideup/ansible')"
    echo "  --ansible-versions-file <file> Path to Ansible versions file (default: ansible-versions.yml in script directory)"
    echo "  --print-tags-only         Print the tags without building the image"
    echo "  --platform <platform>     Set the platform (default: 'linux/amd64')"
    echo "  --*                       Any additional options will be passed to the docker build command"
}

lookup_pypi_version() {
    local variation=$1
    local version=$2
    
    # If it's already a full patch version (x.y.z), return it as is
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
        return 0
    fi
    
    local api_url="https://pypi.org/pypi/${variation}/json"
    
    # Fetch the JSON data
    local json_data=$(curl -s "$api_url")
    
    # Extract all versions
    local versions=$(echo "$json_data" | jq -r '.releases | keys[]')
    
    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Major.Minor version provided, find latest patch
        local latest_version=$(echo "$versions" | grep "^$version\." | grep -v "[a-zA-Z]" | sort -V | tail -n1)
        if [ -z "$latest_version" ]; then
            echo "No stable version found for $version" >&2
            return 1
        fi
        echo "$latest_version"
    elif [[ "$version" =~ ^[0-9]+$ ]]; then
        # Only Major version provided, find latest minor.patch
        local latest_version=$(echo "$versions" | grep "^$version\." | grep -v "[a-zA-Z]" | sort -V | tail -n1)
        if [ -z "$latest_version" ]; then
            echo "No stable version found for $version" >&2
            return 1
        fi
        echo "$latest_version"
    else
        # Invalid version format
        echo "Invalid version format: $version" >&2
        return 1
    fi
}

print_tags() {
    local tags=($(generate_tags))
    echo "Docker tags that would be generated (Release type: $RELEASE_TYPE):"
    printf '%s\n' "${tags[@]}" | sort

    # Save to GitHub's environment
    save_to_github_env "DOCKER_TAGS" "$(printf '%s\n' "${tags[@]}")" true
    save_to_github_env "ANSIBLE_VERSION" "${ANSIBLE_VERSION}"

    # Use the centralized functions to get OS family and package dependencies
    local os_family=$(get_os_family)
    local package_dependencies=$(get_package_dependencies "$os_family")

    # Save PACKAGE_DEPENDENCIES to GitHub's environment
    save_to_github_env "PACKAGE_DEPENDENCIES" "$package_dependencies"


}

save_to_github_env() {
    local key=$1
    local value=$2
    local is_multiline=${3:-false}

    if [[ $CI == "true" ]]; then
        if [[ -n "$GITHUB_ENV" ]]; then
            if [[ "$is_multiline" == "true" ]]; then
                echo "${key}<<EOF" >> "$GITHUB_ENV"
                echo "$value" >> "$GITHUB_ENV"
                echo "EOF" >> "$GITHUB_ENV"
            else
                echo "${key}=${value}" >> "$GITHUB_ENV"
            fi
            echo_color_message green "✅ Saved ${key} to GITHUB_ENV"
        else
            echo_color_message yellow "⚠️ GITHUB_ENV is not set. Skipping writing ${key} to GITHUB_ENV."
        fi
    else
        echo_color_message yellow "Not running in CI environment. Skipping writing ${key} to GITHUB_ENV."
    fi
}

##################################################
# Main
##################################################

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    echo_color_message red "Error: No arguments provided."
    echo
    help_menu
    exit 1
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --variation)
        ANSIBLE_VARIATION="$2"
        shift 2
        ;;
        --version)
        ANSIBLE_VERSION="$2"
        shift 2
        ;;
        --python)
        PYTHON_VERSION="$2"
        shift 2
        ;;
        --os)
        BASE_OS="$2"
        shift 2
        ;;
        --github-release-tag)
        GITHUB_REF_NAME="$2"
        shift 2
        ;;
        --release-type)
        RELEASE_TYPE="$2"
        shift 2
        ;;
        --repository)
        DOCKER_ORGANIZATIONS="$2"
        shift 2
        ;;
        --ansible-versions-file)
        ANSIBLE_VERSIONS_FILE="$2"
        shift 2
        ;;
        --print-tags-only)
        PRINT_TAGS_ONLY=true
        shift
        ;;
        --platform)
        PLATFORM="$2"
        shift 2
        ;;
        --help)
        help_menu
        exit 0
        ;;
        --*)
        if [[ $# -gt 1 && $2 =~ ^-- ]]; then
            DOCKER_ADDITIONAL_BUILD_ARGS+=("$1")
            shift
        else
            DOCKER_ADDITIONAL_BUILD_ARGS+=("$1")
            [[ $# -gt 1 ]] && DOCKER_ADDITIONAL_BUILD_ARGS+=("$2") && shift
            shift
        fi
        ;;
        *)
        echo "Unknown option: $1"
        help_menu
        exit 1
        ;;
    esac
done

# First, check if we need to fill in missing parameters
if [ -z "$ANSIBLE_VERSION" ] || [ -z "$PYTHON_VERSION" ] || [ -z "$BASE_OS" ]; then
    echo_color_message yellow "Automatically filling in missing parameters based on ansible-versions.yml"
fi

# Set default Ansible variation if not provided
if [ -z "$ANSIBLE_VARIATION" ]; then
    ANSIBLE_VARIATION=$(yq e '.ansible_variations[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")
    echo_color_message green "Using default Ansible variation: $ANSIBLE_VARIATION"
fi

# Look up Ansible version
if [ -n "$ANSIBLE_VERSION" ]; then
    if [[ $ANSIBLE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo_color_message green "Using provided Ansible version: $ANSIBLE_VERSION"
    else
        ANSIBLE_VERSION=$(lookup_pypi_version "$ANSIBLE_VARIATION" "$ANSIBLE_VERSION")
        if [ $? -ne 0 ]; then
            # Error message already printed by lookup_pypi_version
            exit 1
        fi
        echo_color_message green "Using Ansible version: $ANSIBLE_VERSION"
    fi
fi

# Fill in missing values with latest stable
if [ -z "$ANSIBLE_VERSION" ] || [ -z "$PYTHON_VERSION" ] || [ -z "$BASE_OS" ]; then
    read -r latest_ansible latest_python latest_os <<< $(fetch_latest_component_versions "$ANSIBLE_VARIATION")
    if [ -z "$ANSIBLE_VERSION" ]; then
        ANSIBLE_VERSION=$latest_ansible
        echo_color_message green "Using Ansible version: $ANSIBLE_VERSION"
    fi
    if [ -z "$PYTHON_VERSION" ]; then
        PYTHON_VERSION=$latest_python
        echo_color_message green "Using Python version: $PYTHON_VERSION"
    fi
    if [ -z "$BASE_OS" ]; then
        BASE_OS=$latest_os
        echo_color_message green "Using Base OS: $BASE_OS"
    fi
fi

get_yq_value "Ansible variation" "$ANSIBLE_VARIATION" '.ansible_variations[].name'
get_yq_value "Ansible version" "$ANSIBLE_VERSION" ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .versions[].version"
get_yq_value "Python version" "$PYTHON_VERSION" '.python_versions[].name'
get_yq_value "Base OS" "$BASE_OS" '.operating_system_distributions[].versions[].name'

if [ "$PRINT_TAGS_ONLY" = true ]; then
    print_tags
else
    build_docker_image
fi
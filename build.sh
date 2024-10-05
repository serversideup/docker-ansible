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

function echo_color_message (){
  color=$1
  message=$2

  ui_set_$color
  echo "$message"
  ui_reset_colors
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

lookup_pypi_version() {
    local variation=$1
    local version=$2
    local api_url="https://pypi.org/pypi/${variation}/json"
    
    # Check if the version is already a full patch version
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
    else
        # Fetch the JSON data and extract the latest stable version for the given major.minor
        local latest_version=$(curl -s "$api_url" | jq -r ".releases | keys[] | select(startswith(\"$version.\") and (contains(\"b\") or contains(\"rc\") | not))" | sort -V | tail -n1)
        echo "$latest_version"
    fi
}

# Update generate_tags function
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
    local is_os_family_default=$(yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .versions[] | select(.name == \"$BASE_OS\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")
    local is_variation_latest=$(yq e ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")

    is_latest_ansible_version_and_python_version() {
        [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ]
    }

    is_default_os() {
        [ "$is_os_latest" == "true" ] && [ "$is_os_family_default" == "true" ]
    }

    is_default_release() {
        is_latest_ansible_version_and_python_version && is_default_os
    }

    # Determine the tag prefix based on release type
    local tag_prefix=""
    if [ "$RELEASE_TYPE" != "latest" ]; then
        tag_prefix="${RELEASE_TYPE}-"
    fi

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

    # Most specific tag
    add_tag "${tag_prefix}${ANSIBLE_VERSION}-${BASE_OS}-python${PYTHON_VERSION}"

    # Tag without Ansible Version if it's the latest
    if [ "$is_ansible_latest" == "true" ]; then
        add_tag "${tag_prefix}${BASE_OS}-python${PYTHON_VERSION}"
    fi

    # Tag with OS family instead of specific OS if it's the latest in its family
    if [ "$is_os_family_default" == "true" ]; then
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
    if [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
    fi

    # Most general tag if everything is default
    if is_default_release; then
        add_tag "$RELEASE_TYPE"
        if [ -n "$GITHUB_REF_NAME" ] && [[ "$RELEASE_TYPE" == "latest" || "$RELEASE_TYPE" == "beta" ]]; then
            add_tag "${GITHUB_REF_NAME}"
        fi
    fi

    # Function to check if all other components are latest stable
    are_other_components_latest() {
        local exclude=$1
        local conditions=("$is_ansible_latest" "$is_python_latest" "$is_os_latest")
        
        for component in "${conditions[@]}"; do
            if [ "$component" != "$exclude" ] && [ "$component" != "true" ]; then
                return 1
            fi
        done
        
        return 0
    }

    # Tag for OS family if it's the latest stable
    if [ "$is_os_family_default" == "true" ] && are_other_components_latest "$is_os_latest"; then
        add_tag "${tag_prefix}${os_family}"
    fi

    # Tag for specific OS
    if are_other_components_latest "$is_os_latest"; then
        add_tag "${tag_prefix}${BASE_OS}"
    fi

    # Tag for Python version
    if are_other_components_latest "$is_python_latest"; then
        add_tag "${tag_prefix}python${PYTHON_VERSION}"
    fi

    # Tag for Ansible version (only if everything else is latest)
    if are_other_components_latest "$is_ansible_latest"; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
    fi

    # Remove duplicates and print tags
    printf '%s\n' "${tags[@]}" | sort -u
}

build_docker_image() {
  tags=($(generate_tags))
  
  # Get package dependencies from ansible-versions.yml
  local os_family=$(yq e ".operating_system_distributions[] | select(.versions[].name == \"$BASE_OS\") | .name" "$ANSIBLE_VERSIONS_FILE")
  local package_dependencies=$(yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .versions[] | select(.name == \"$BASE_OS\") | .package_dependencies[]" "$ANSIBLE_VERSIONS_FILE" | tr '\n' ' ')

  # Get the full patch version
  local full_ansible_version=$(lookup_pypi_version "$ANSIBLE_VARIATION" "$ANSIBLE_VERSION")

  build_args=(
    --build-arg ANSIBLE_VARIATION="$ANSIBLE_VARIATION"
    --build-arg ANSIBLE_VERSION="$full_ansible_version"
    --build-arg PYTHON_VERSION="$PYTHON_VERSION"
    --build-arg BASE_OS_VERSION="$BASE_OS"
    --build-arg PACKAGE_DEPENDENCIES="'$package_dependencies'"
  )

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

  # Construct the full Docker command
  docker_command="docker build ${DOCKER_ADDITIONAL_BUILD_ARGS[@]} ${build_args[@]} --file \"src/Dockerfile\" \"$PROJECT_ROOT_DIR\""
  
  # Show the Docker command
  echo_color_message yellow "Docker command to be executed:"
  echo "$docker_command"
  
  # Execute the Docker command
  eval $docker_command

  if [[ "$CI" == "true" ]]; then
    if [[ -n "$GITHUB_ENV" ]]; then
        echo "DOCKER_TAGS<<EOF" >> "$GITHUB_ENV"
        printf '%s\n' "${tags[@]}" >> "$GITHUB_ENV"
        echo "EOF" >> "$GITHUB_ENV"
        echo_color_message green "✅ Saved Docker Tags to GITHUB_ENV"
    else
        echo_color_message yellow "⚠️ GITHUB_ENV is not set. Skipping writing to GITHUB_ENV."
    fi
  else
    echo_color_message yellow "Not running in CI environment. Skipping writing to GITHUB_ENV."
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

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    echo_color_message red "Error: No arguments provided."
    echo
    help_menu
    exit 1
fi

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

# In the argument parsing section, add this after setting ANSIBLE_VARIATION
if [ -z "$ANSIBLE_VARIATION" ]; then
    ANSIBLE_VARIATION=$(yq e '.ansible_variations[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")
    echo_color_message green "Using default Ansible variation: $ANSIBLE_VARIATION"
fi

# Update the validation block
validate_option() {
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

# Validate options
validate_option "Ansible variation" "$ANSIBLE_VARIATION" '.ansible_variations[].name'
validate_option "Ansible version" "$ANSIBLE_VERSION" ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .versions[].version"
validate_option "Python version" "$PYTHON_VERSION" '.python_versions[].name'
validate_option "Base OS" "$BASE_OS" '.operating_system_distributions[].versions[].name'

if [ -n "$ANSIBLE_VARIATION" ] && [ -z "$ANSIBLE_VERSION" ] && [ -z "$PYTHON_VERSION" ] && [ -z "$BASE_OS" ]; then
    echo_color_message yellow "Automatically filling in missing parameters based on ansible-versions.yml"
    read -r ANSIBLE_VERSION PYTHON_VERSION BASE_OS <<< $(fetch_latest_component_versions "$ANSIBLE_VARIATION")
    echo_color_message green "Using Ansible version: $ANSIBLE_VERSION"
    echo_color_message green "Using Python version: $PYTHON_VERSION"
    echo_color_message green "Using Base OS: $BASE_OS"
else
    # Check if at least one required argument is provided
    if [[ -z $ANSIBLE_VARIATION && -z $ANSIBLE_VERSION && -z $PYTHON_VERSION && -z $BASE_OS ]]; then
        echo_color_message red "Error: At least one of --variation, --version, --python, or --os must be provided."
        echo
        help_menu
        exit 1
    fi

    # Fill in missing values with latest stable
    if [ -z "$ANSIBLE_VERSION" ] || [ -z "$PYTHON_VERSION" ] || [ -z "$BASE_OS" ]; then
        echo_color_message yellow "Automatically filling in missing parameters based on ansible-versions.yml"
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
fi

# Function to print tags
print_tags() {
    local tags=($(generate_tags))
    echo "Docker tags that would be generated (Release type: $RELEASE_TYPE):"
    printf '%s\n' "${tags[@]}" | sort

    # Save to GitHub's environment
    if [[ $CI == "true" ]]; then
        if [[ -n "$GITHUB_ENV" ]]; then
            echo "DOCKER_TAGS<<EOF" >> "$GITHUB_ENV"
            printf '%s\n' "${tags[@]}" >> "$GITHUB_ENV"
            echo "EOF" >> "$GITHUB_ENV"
            echo_color_message green "✅ Saved Docker Tags to GITHUB_ENV"
        else
            echo_color_message yellow "⚠️ GITHUB_ENV is not set. Skipping writing to GITHUB_ENV."
        fi
    else
        echo_color_message yellow "Not running in CI environment. Skipping writing to GITHUB_ENV."
    fi
}

# Main execution
if [ "$PRINT_TAGS_ONLY" = true ]; then
    print_tags
else
    build_docker_image
fi
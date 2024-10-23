#!/bin/bash
set -eo pipefail

# Simplify directory references
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT_DIR="$SCRIPT_DIR"

ANSIBLE_VERSIONS_FILE="${ANSIBLE_VERSIONS_FILE:-$SCRIPT_DIR/ansible-versions.yml}"
BUILD_ANSIBLE_PATCH_VERSION=""
BUILD_ANSIBLE_VARIATION=""
BUILD_BASE_OS=""
BUILD_PYTHON_VERSION=""
DOCKER_ADDITIONAL_BUILD_ARGS=()
DOCKER_ORGANIZATIONS="${DOCKER_ORGANIZATIONS:-"docker.io/serversideup ghcr.io/serversideup"}"
GITHUB_REF_NAME="${GITHUB_REF_NAME:-""}"
INPUT_BUILD_VERSION=""
PRINT_TAGS_ONLY=false
RELEASE_TYPE="dev"

##################################################
# Functions
##################################################

add_tag() {
    local new_tag="$1"
    local prefix=""
    local suffix=""

    # Set prefix based on RELEASE_TYPE
    if [ "$RELEASE_TYPE" != "latest" ]; then
        prefix="${RELEASE_TYPE}-"
    fi

    # Prevent things like "beta-beta" from happening
    if [[ "$new_tag-" == "$prefix" ]]; then
        prefix=""
    fi

    # Construct the full tag
    full_tag="${prefix}${new_tag}${suffix}"

    # Add tags for each Docker organization
    for org in $DOCKER_ORGANIZATIONS; do
        if [ -n "$GITHUB_REF_NAME" ] && [ "$RELEASE_TYPE" == "pr" ]; then
            tags+=("${org}/${BUILD_ANSIBLE_VARIATION}:${full_tag}-${GITHUB_REF_NAME}")
            break
        fi
        tags+=("${org}/${BUILD_ANSIBLE_VARIATION}:${full_tag}")
        if [ -n "$GITHUB_REF_NAME" ] && [ "${full_tag}" != "$RELEASE_TYPE" ] && [ "$GITHUB_REF_TYPE" == "tag" ]; then
            tags+=("${org}/${BUILD_ANSIBLE_VARIATION}:${full_tag}-${GITHUB_REF_NAME}")
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
    local package_dependencies=$(get_package_dependencies "$BUILD_BASE_OS")

    build_args=(
        --build-arg BUILD_ANSIBLE_VARIATION="$BUILD_ANSIBLE_VARIATION"
        --build-arg BUILD_ANSIBLE_PATCH_VERSION="$BUILD_ANSIBLE_PATCH_VERSION"
        --build-arg BUILD_PYTHON_VERSION="$BUILD_PYTHON_VERSION"
        --build-arg BUILD_BASE_OS_VERSION="$BUILD_BASE_OS"
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
        PLATFORM=$(detect_platform)
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

detect_platform() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "linux/amd64"
            ;;
        arm64|aarch64)
            echo "linux/arm64/v8"
            ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

echo_color_message (){
  color=$1
  message=$2

  ui_set_$color
  echo "$message"
  ui_reset_colors
}

generate_tags() {
    local tags=()
    local build_ansible_minor_version="$(echo "$BUILD_ANSIBLE_PATCH_VERSION" | cut -d. -f1,2)"
    local build_base_os_family="$(get_build_base_os_family)"
    local default_os_family="$(get_version_default_os_family)"
    local latest_ansible_version_global="$(lookup_latest_pypi_version)"
    local latest_ansible_version_within_minor="$(lookup_latest_pypi_version "$build_ansible_minor_version")"
    local latest_os_version_within_family="$(get_version_os_latest_within_family)"
    local latest_stable_python_version="$(get_version_python_latest_stable)"

    # Helper functions
    is_latest_ansible_global() { [ "$BUILD_ANSIBLE_PATCH_VERSION" == "$latest_ansible_version_global" ]; }
    is_latest_ansible_minor() { [ "$BUILD_ANSIBLE_PATCH_VERSION" == "$latest_ansible_version_within_minor" ]; }
    is_latest_python() { [ "$BUILD_PYTHON_VERSION" == "$latest_stable_python_version" ]; }
    is_latest_os_family() { [ "$BUILD_BASE_OS" == "$latest_os_version_within_family" ]; }
    is_default_os_family() { [ "$build_base_os_family" == "$default_os_family" ]; }

    # Most specific tag
    add_tag "${BUILD_ANSIBLE_PATCH_VERSION}-${BUILD_BASE_OS}-python${BUILD_PYTHON_VERSION}"

    # Tag without Python version if it's the latest
    if is_latest_python; then
        add_tag "${BUILD_ANSIBLE_PATCH_VERSION}-${BUILD_BASE_OS}"
    fi

    # Tag with only Ansible version and OS if it's the latest Python
    if is_latest_python && is_default_os_family; then
        add_tag "${BUILD_ANSIBLE_PATCH_VERSION}"
    fi

    # Tag without Ansible patch version if it's the latest within its minor version
    if is_latest_ansible_minor; then
        add_tag "${build_ansible_minor_version}-${BUILD_BASE_OS}-python${BUILD_PYTHON_VERSION}"
        if is_latest_python; then
            add_tag "${build_ansible_minor_version}-${BUILD_BASE_OS}"
        fi
        if is_latest_python && is_default_os_family; then
            add_tag "${build_ansible_minor_version}"
        fi
    fi

    # Tag without Ansible version if it's the latest global version
    if is_latest_ansible_global; then
        add_tag "${BUILD_BASE_OS}-python${BUILD_PYTHON_VERSION}"
        if is_latest_python; then
            add_tag "${BUILD_BASE_OS}"
        fi
    fi

    # Tag for latest everything
    if is_latest_ansible_global && is_latest_python && is_default_os_family && is_latest_os_family; then
        add_tag "$RELEASE_TYPE"
    fi

    # OS family-based tags
    add_tag "${BUILD_ANSIBLE_PATCH_VERSION}-${build_base_os_family}-python${BUILD_PYTHON_VERSION}"
    if is_latest_python; then
        add_tag "${BUILD_ANSIBLE_PATCH_VERSION}-${build_base_os_family}"
    fi

    if is_latest_ansible_minor; then
        add_tag "${build_ansible_minor_version}-${build_base_os_family}-python${BUILD_PYTHON_VERSION}"
        if is_latest_python; then
            add_tag "${build_ansible_minor_version}-${build_base_os_family}"
        fi
    fi

    if is_latest_ansible_global && is_latest_python; then
        add_tag "${build_base_os_family}"
    fi

    # Remove duplicates and print tags
    printf '%s\n' "${tags[@]}" | sort -u
}

get_build_base_os_family() {
    local base_os="${BUILD_BASE_OS}"
    local os_family

    os_family=$(yq e ".operating_system_distributions[] | select(.versions[].name == \"$base_os\") | .name" "$ANSIBLE_VERSIONS_FILE")

    if [ -z "$os_family" ]; then
        echo "Error: Could not determine OS family for $base_os" >&2
        return 1
    fi

    echo "$os_family"
}

get_package_dependencies() {
    local base_os="${1:-$BUILD_BASE_OS}"
    local dependencies

    dependencies=$(yq e "
        .operating_system_distributions[].versions[] |
        select(.name == \"$base_os\") |
        .package_dependencies[] |
        select(. != null)
    " "$ANSIBLE_VERSIONS_FILE" | tr '\n' ',' | sed 's/,$//')

    if [ -z "$dependencies" ]; then
        echo "Error: Could not find package dependencies for $base_os" >&2
        return 1
    fi

    echo "$dependencies"
}

get_version_default_ansible_variation() {
    local default_variation

    # Parse the YAML file and extract the default ansible variation
    default_variation=$(yq eval '.ansible_variations[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")

    # Check if a default variation was found
    if [ -z "$default_variation" ]; then
        echo "Error: No default ansible variation found with latest_stable: true" >&2
        return 1
    fi

    echo "$default_variation"
}

get_version_default_os_family() {
    local default_os_family

    # Parse the YAML file and extract the default OS family
    default_os_family=$(yq eval '.operating_system_distributions[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")

    # Check if a default OS family was found
    if [ -z "$default_os_family" ]; then
        echo "Error: No default OS family found with latest_stable: true" >&2
        return 1
    fi

    echo "$default_os_family"
}

get_version_latest_default_os_version() {
    local default_os_family
    local latest_version

    # Get the default OS family
    default_os_family=$(get_version_default_os_family)

    if [ -z "$default_os_family" ]; then
        echo "Error: Could not determine default OS family" >&2
        return 1
    fi

    # Find the latest version within the default family
    latest_version=$(yq eval "
        .operating_system_distributions[] |
        select(.name == \"$default_os_family\") |
        .versions[] |
        select(.latest_stable == true) |
        .name
    " "$ANSIBLE_VERSIONS_FILE")

    if [ -z "$latest_version" ]; then
        echo "Error: No latest stable version found for $default_os_family" >&2
        return 1
    else
        echo "$latest_version"
    fi
}

get_version_os_latest_within_family() {
    local base_os="$BUILD_BASE_OS"
    local os_family
    local latest_version

    # Get the OS family for the given BUILD_BASE_OS
    os_family=$(yq eval ".operating_system_distributions[] | select(.versions[].name == \"$base_os\") | .name" "$ANSIBLE_VERSIONS_FILE")

    if [ -z "$os_family" ]; then
        echo "Error: Could not determine OS family for $base_os" >&2
        return 1
    fi

    # Find the latest version within the same family
    latest_version=$(yq eval "
        .operating_system_distributions[] |
        select(.name == \"$os_family\") |
        .versions[] |
        select(.latest_stable == true) |
        .name
    " "$ANSIBLE_VERSIONS_FILE")

    if [ -z "$latest_version" ]; then
        # If no version is marked as latest_stable, return the input BUILD_BASE_OS
        echo "$base_os"
    else
        echo "$latest_version"
    fi
}

get_version_python_latest_stable() {
    local latest_python_version

    # Parse the YAML file and extract the latest stable Python version
    latest_python_version=$(yq eval '.python_versions[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")

    # Check if a latest stable Python version was found
    if [ -z "$latest_python_version" ]; then
        echo "Error: No latest stable Python version found with latest_stable: true" >&2
        return 1
    fi

    echo "$latest_python_version"
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

lookup_latest_pypi_version() {
    local variation=${BUILD_ANSIBLE_VARIATION}
    local input_version=${1:-}
    local api_url="https://pypi.org/pypi/${variation}/json"
    local json_data=$(curl -s "$api_url")

    if [ -z "$json_data" ]; then
        echo "Error: Failed to fetch data from PyPI" >&2
        return 1
    fi
    
    if [ -z "$variation" ]; then
        echo "Error: Ansible variation is required" >&2
        return 1
    fi

    # Extract all versions
    local versions=$(echo "$json_data" | jq -r '.releases | keys[]')
    
    # Function to filter and sort versions
    filter_and_sort_versions() {
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1
    }
    
    # Find latest stable release across all releases
    local latest_stable_global=$(echo "$versions" | filter_and_sort_versions)

    if [ -z "$input_version" ]; then
        # No version provided, use latest stable
        echo "$latest_stable_global"
    elif [[ "$input_version" =~ ^[0-9]+$ ]]; then
        # Only Major version provided, find latest minor.patch
        local latest_stable_within_major=$(echo "$versions" | grep "^$input_version\." | filter_and_sort_versions)
        [ -n "$latest_stable_within_major" ] && echo "$latest_stable_within_major" || { echo "No stable version found for major version $input_version" >&2; return 1; }
    elif [[ "$input_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # Major.Minor version provided, find latest patch
        local latest_stable_within_minor=$(echo "$versions" | grep "^$input_version\." | filter_and_sort_versions)
        [ -n "$latest_stable_within_minor" ] && echo "$latest_stable_within_minor" || { echo "No stable version found for minor version $input_version" >&2; return 1; }
    elif [[ "$input_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Full version provided, validate it exists
        if echo "$versions" | grep -q "^$input_version$"; then
            echo "$input_version"
        else
            echo "Version $input_version does not exist on PyPI" >&2
            return 1
        fi
    else
        echo "Invalid version format: $input_version" >&2
        return 1
    fi
}

print_tags() {
    local tags=($(generate_tags))
    echo "The following tags have been generated (Release type: $RELEASE_TYPE):"
    printf '%s\n' "${tags[@]}" | sort

    # Save to GitHub's environment
    save_to_github_env "DOCKER_TAGS" "$(printf '%s\n' "${tags[@]}")" true
    save_to_github_env "BUILD_ANSIBLE_PATCH_VERSION" "${BUILD_ANSIBLE_PATCH_VERSION}"

    # Get package dependencies for the given OS
    local package_dependencies=$(get_package_dependencies "$BUILD_BASE_OS")

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

ui_set_yellow() {
    printf $'\033[0;33m'
}

ui_set_green() {
    printf $'\033[0;32m'
}

ui_set_red()     {
    printf $'\033[0;31m'
}

ui_reset_colors() {
    printf "\e[0m"
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
        BUILD_ANSIBLE_VARIATION="$2"
        shift 2
        ;;
        --version)
        INPUT_BUILD_VERSION="$2"
        shift 2
        ;;
        --python)
        BUILD_PYTHON_VERSION="$2"
        shift 2
        ;;
        --os)
        BUILD_BASE_OS="$2"
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
if [ -z "$INPUT_BUILD_VERSION" ] || [ -z "$BUILD_PYTHON_VERSION" ] || [ -z "$BUILD_BASE_OS" ]; then
    echo_color_message yellow "Automatically filling in missing parameters based on ansible-versions.yml"
fi

# Set default Ansible variation if not provided
if [ -z "$BUILD_ANSIBLE_VARIATION" ]; then
    BUILD_ANSIBLE_VARIATION="$(get_version_default_ansible_variation)"
    echo_color_message green "Using default Ansible variation: $BUILD_ANSIBLE_VARIATION"
fi

# Set default OS if not provided
if [ -z "$BUILD_BASE_OS" ]; then
    BUILD_BASE_OS="$(get_version_latest_default_os_version)"
    echo_color_message green "Using default OS: $BUILD_BASE_OS"
fi

# Set default Python version if not provided
if [ -z "$BUILD_PYTHON_VERSION" ]; then
    BUILD_PYTHON_VERSION="$(get_version_python_latest_stable)"
    echo_color_message green "Using default Python version: $BUILD_PYTHON_VERSION"
fi

# Set latest Ansible version if not provided
if [ -z "$BUILD_ANSIBLE_PATCH_VERSION" ]; then
    BUILD_ANSIBLE_PATCH_VERSION="$(lookup_latest_pypi_version)"
    echo_color_message green "Using latest Ansible version: $BUILD_ANSIBLE_PATCH_VERSION"
fi

# Set Ansible patch version if input version is provided
if [ -n "$INPUT_BUILD_VERSION" ]; then
    BUILD_ANSIBLE_PATCH_VERSION="$(lookup_latest_pypi_version "${INPUT_BUILD_VERSION}")"
    echo_color_message green "Using Ansible version: $BUILD_ANSIBLE_PATCH_VERSION"
fi

if [ "$PRINT_TAGS_ONLY" = true ]; then
    print_tags
else
    build_docker_image
fi
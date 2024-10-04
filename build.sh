#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ANSIBLE_VARIATION=""
ANSIBLE_VERSION=""
PYTHON_VERSION=""
BASE_OS=""
GITHUB_RELEASE_TAG=""
RELEASE_TYPE="dev"
DOCKER_REPOSITORY="${DOCKER_REPOSITORY:-"docker.io/serversideup/ansible ghcr.io/serversideup/ansible"}"
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

# New function to get latest stable values
get_latest_stable() {
    local yaml_file="$ANSIBLE_VERSIONS_FILE"
    
    # Get latest stable Ansible version
    local ansible_version=$(yq e ".ansible_versions[] | select(.latest_stable == true) | .version" "$yaml_file")
    
    # Get latest stable Python version
    local python_version=$(yq e ".python_versions[] | select(.latest_stable == true) | .name" "$yaml_file")
    
    # Get latest stable OS
    local base_os=$(yq e ".operating_system_distributions[].versions[] | select(.latest_stable == true) | .name" "$yaml_file" | head -n1)
    
    echo "$ansible_version $python_version $base_os"
}

generate_tags() {
    local tags=()
    local os_family=$(yq e ".operating_system_distributions[] | select(.versions[].name == \"$BASE_OS\") | .name" "$ANSIBLE_VERSIONS_FILE")
    local ansible_variation_tag=$(yq e ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .tag_name" "$ANSIBLE_VERSIONS_FILE")

    # Get latest stable values
    local latest_ansible latest_python latest_os
    read -r latest_ansible latest_python latest_os <<< $(get_latest_stable)

    # Check if each component is the latest stable
    local is_ansible_latest=$([ "$ANSIBLE_VERSION" == "$latest_ansible" ] && echo true || echo false)
    local is_python_latest=$([ "$PYTHON_VERSION" == "$latest_python" ] && echo true || echo false)
    local is_os_latest=$([ "$BASE_OS" == "$latest_os" ] && echo true || echo false)
    local is_os_family_default=$(yq e ".operating_system_distributions[] | select(.name == \"$os_family\") | .versions[] | select(.name == \"$BASE_OS\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")

    # Determine the tag prefix based on release type
    local tag_prefix=""
    if [ "$RELEASE_TYPE" != "latest" ]; then
        tag_prefix="${RELEASE_TYPE}-"
    fi

    add_tag() {
        local tag=$1
        for repo in $DOCKER_REPOSITORY; do
            tags+=("$repo:$tag")
            if [ -n "$GITHUB_RELEASE_TAG" ] && [[ "$RELEASE_TYPE" == "latest" || "$RELEASE_TYPE" == "beta" ]]; then
                # Replace the prefix with the GitHub release tag if it exists
                if [[ "$tag" == "$tag_prefix"* ]]; then
                    new_tag="${GITHUB_RELEASE_TAG}-${tag#$tag_prefix}"
                else
                    new_tag="${GITHUB_RELEASE_TAG}-${tag}"
                fi
                tags+=("$repo:$new_tag")
            fi
        done
    }

    # Most specific tag
    add_tag "${tag_prefix}${ANSIBLE_VERSION}-${ansible_variation_tag}-${BASE_OS}-python${PYTHON_VERSION}"

    # Tag without Ansible Version if it's the latest
    if [ "$is_ansible_latest" == "true" ]; then
        add_tag "${tag_prefix}${ansible_variation_tag}-${BASE_OS}-python${PYTHON_VERSION}"
    fi

    # Tag with OS family instead of specific OS if it's the latest in its family
    if [ "$is_os_family_default" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${ansible_variation_tag}-${os_family}-python${PYTHON_VERSION}"
    fi

    # Tag without OS if it's the default
    if [ "$is_os_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${ansible_variation_tag}-python${PYTHON_VERSION}"
    fi

    # Tag without Python Version if it's the latest
    if [ "$is_python_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${ansible_variation_tag}-${BASE_OS}"
    fi

    # Tag without Python Version or OS if both are default
    if [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}-${ansible_variation_tag}"
    fi

    # Most general tag if everything is default
    if [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
        add_tag "${tag_prefix}${ansible_variation_tag}"
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
        if [ -n "$GITHUB_RELEASE_TAG" ] && [[ "$RELEASE_TYPE" == "latest" || "$RELEASE_TYPE" == "beta" ]]; then
            add_tag "${GITHUB_RELEASE_TAG}"
        fi
        # Only add "latest" tag if the release type is "latest"
        if [ "$RELEASE_TYPE" == "latest" ]; then
            add_tag "latest"
        else
            add_tag "$RELEASE_TYPE"
        fi
    fi

    # Add these new conditions after the existing tag generations:

    # Function to check if all other components are latest stable
    are_other_components_latest() {
        local exclude=$1
        local conditions=("$is_ansible_latest" "$is_python_latest" "$is_os_latest")
        local latest_ansible_variation=$(yq e '.ansible_variations[] | select(.latest_stable == true) | .name' "$ANSIBLE_VERSIONS_FILE")
        
        for component in "${conditions[@]}"; do
            if [ "$component" != "$exclude" ] && [ "$component" != "true" ]; then
                return 1
            fi
        done
        
        [ "$ANSIBLE_VARIATION" == "$latest_ansible_variation" ]
        return $?
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

    # Tag for Ansible version
    if are_other_components_latest "$is_ansible_latest"; then
        add_tag "${tag_prefix}${ANSIBLE_VERSION}"
    fi

    # Remove duplicates and print tags
    printf '%s\n' "${tags[@]}" | sort -u
}

build_docker_image() {
  tags=($(generate_tags))
  build_args=(
    --build-arg ANSIBLE_VARIATION="$ANSIBLE_VARIATION"
    --build-arg ANSIBLE_VERSION="$ANSIBLE_VERSION"
    --build-arg PYTHON_VERSION="$PYTHON_VERSION"
    --build-arg BASE_OS_VERSION="$BASE_OS"
  )

  for tag in "${tags[@]}"; do
    build_args+=(--tag "$tag")
  done

  echo_color_message yellow "🐳 Building Docker Image with tags:"
  printf '%s\n' "${tags[@]}"
  
  # Construct the full Docker command
  docker_command="docker build ${DOCKER_ADDITIONAL_BUILD_ARGS[@]} ${build_args[@]} --file \"$PROJECT_ROOT_DIR/Dockerfile\" \"$PROJECT_ROOT_DIR\""
  
  # Show the Docker command
  echo_color_message yellow "Docker command to be executed:"
  echo "$docker_command"
  
  # Execute the Docker command
  eval $docker_command

  echo_color_message green "✅ Docker Image Built with tags:"
  printf '%s\n' "${tags[@]}"

  if [[ "$CI" == "true" ]]; then
    echo "DOCKER_TAGS<<EOF" >> $GITHUB_ENV
    printf '%s\n' "${tags[@]}" >> $GITHUB_ENV
    echo "EOF" >> $GITHUB_ENV
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
    echo "  --version <version>       Set the Ansible version (e.g., 2.15.0, 2.16.2, 2.17.1)"
    echo "  --python <python_version> Set the Python version (e.g., 3.9, 3.10, 3.11, 3.12)"
    echo "  --os <os>                 Set the base OS (e.g., alpine3.20, bullseye)"
    echo
    echo "Optional arguments:"
    echo "  --github-release-tag <tag> Set the GitHub release tag"
    echo "  --release-type <type>    Set the release type (e.g., latest, beta, rc). Default: dev"
    echo "  --repository <repos>      Space-separated list of Docker repositories (default: 'docker.io/serversideup/ansible ghcr.io/serversideup/ansible')"
    echo "  --ansible-versions-file <file> Path to Ansible versions file (default: ansible-versions.yml in script directory)"
    echo "  --print-tags-only         Print the tags without building the image"
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
        GITHUB_RELEASE_TAG="$2"
        shift 2
        ;;
        --release-type)
        RELEASE_TYPE="$2"
        shift 2
        ;;
        --repository)
        DOCKER_REPOSITORY="$2"
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

# After argument parsing, add this validation block:

validate_option() {
    local option=$1
    local value=$2
    local yq_query=$3
    
    if [ -n "$value" ]; then
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
validate_option "Ansible version" "$ANSIBLE_VERSION" '.ansible_versions[].version'
validate_option "Python version" "$PYTHON_VERSION" '.python_versions[].name'
validate_option "Base OS" "$BASE_OS" '.operating_system_distributions[].versions[].name'

if [ -n "$ANSIBLE_VARIATION" ] && [ -z "$ANSIBLE_VERSION" ] && [ -z "$PYTHON_VERSION" ] && [ -z "$BASE_OS" ]; then
    echo_color_message yellow "Automatically filling in missing parameters based on ansible-versions.yml"
    read -r ANSIBLE_VERSION PYTHON_VERSION BASE_OS <<< $(get_latest_stable)
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
        read -r latest_ansible latest_python latest_os <<< $(get_latest_stable)
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
}

# Main execution
if [ "$PRINT_TAGS_ONLY" = true ]; then
    print_tags
else
    build_docker_image
fi
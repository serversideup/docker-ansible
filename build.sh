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
    local full_version="$ANSIBLE_VERSION"
    local major_version="${ANSIBLE_VERSION%%.*}"
    local minor_version="${ANSIBLE_VERSION#*.}"
    local os_name=$(yq e ".operating_system_distributions[] | select(.versions[].name == \"$BASE_OS\") | .name" "$ANSIBLE_VERSIONS_FILE")
    local tag_variation=$(yq e ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .tag_name" "$ANSIBLE_VERSIONS_FILE")

    # Get latest stable values
    local latest_ansible latest_python latest_os
    read -r latest_ansible latest_python latest_os <<< $(get_latest_stable)

    # Check if each component is the latest stable
    local is_ansible_latest=$([ "$ANSIBLE_VERSION" == "$latest_ansible" ] && echo true || echo false)
    local is_python_latest=$([ "$PYTHON_VERSION" == "$latest_python" ] && echo true || echo false)
    local is_os_latest=$([ "$BASE_OS" == "$latest_os" ] && echo true || echo false)
    local is_variation_latest=$(yq e ".ansible_variations[] | select(.name == \"$ANSIBLE_VARIATION\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")

    # Check if the OS is the latest stable within its family
    local is_os_family_latest=$(yq e ".operating_system_distributions[] | select(.name == \"$os_name\") | .versions[] | select(.name == \"$BASE_OS\") | .latest_stable // false" "$ANSIBLE_VERSIONS_FILE")

    for repo in $DOCKER_REPOSITORY; do
        # Always add the full version tags
        tags+=("$repo:$full_version-$tag_variation-$BASE_OS-python$PYTHON_VERSION")
        tags+=("$repo:$full_version-$BASE_OS-python$PYTHON_VERSION")
        tags+=("$repo:$full_version-python$PYTHON_VERSION")

        # Add tags based on provided inputs and latest stable checks
        if [ "$is_variation_latest" == "true" ] && [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
            tags+=("$repo:$RELEASE_TYPE")
        fi

        if [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
            tags+=("$repo:$tag_variation")
        fi

        if [ "$is_variation_latest" == "true" ] && [ "$is_python_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
            tags+=("$repo:$full_version")
        fi

        if [ "$is_variation_latest" == "true" ] && [ "$is_ansible_latest" == "true" ] && [ "$is_python_latest" == "true" ]; then
            tags+=("$repo:python$PYTHON_VERSION")
        fi

        if [ "$is_variation_latest" == "true" ] && [ "$is_ansible_latest" == "true" ] && [ "$is_os_latest" == "true" ]; then
            tags+=("$repo:$BASE_OS")
            if [ "$is_os_family_latest" == "true" ]; then
                tags+=("$repo:$os_name")
            fi
        fi

        # Add combined tags
        if [ "$is_variation_latest" == "true" ] && [ "$is_ansible_latest" == "true" ]; then
            tags+=("$repo:$BASE_OS-python$PYTHON_VERSION")
            if [ "$is_os_family_latest" == "true" ]; then
                tags+=("$repo:$os_name-python$PYTHON_VERSION")
            fi
        fi

        # Add release type prefix if not 'latest'
        if [ "$RELEASE_TYPE" != "latest" ]; then
            local temp_tags=("${tags[@]}")
            tags=()
            for tag in "${temp_tags[@]}"; do
                if [[ "$tag" != *":$RELEASE_TYPE" && "$tag" != *":$RELEASE_TYPE-"* ]]; then
                    tags+=("${tag/:/:$RELEASE_TYPE-}")
                else
                    tags+=("$tag")
                fi
            done
        fi

        # Add GitHub Release tag if set
        if [ -n "$GITHUB_RELEASE_TAG" ]; then
            local github_tags=()
            for tag in "${tags[@]}"; do
                if [ "$RELEASE_TYPE" == "latest" ]; then
                    # For 'latest' release type, add both with and without the GitHub tag
                    if [[ "$tag" != *":latest-"* ]]; then
                        github_tags+=("$tag")
                        # Ensure we don't duplicate the GitHub release tag
                        if [[ "$tag" != *":$GITHUB_RELEASE_TAG-"* ]]; then
                            github_tags+=("${tag/:/:$GITHUB_RELEASE_TAG-}")
                        fi
                    fi
                else
                    # For other release types, just append the GitHub tag if not already present
                    if [[ "$tag" != *"-$GITHUB_RELEASE_TAG" ]]; then
                        github_tags+=("${tag}-${GITHUB_RELEASE_TAG}")
                    else
                        github_tags+=("$tag")
                    fi
                fi
            done
            tags=("${github_tags[@]}")
        fi
    done

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
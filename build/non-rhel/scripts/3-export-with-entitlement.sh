#!/bin/bash
set -e


## ISSUE: https://github.com/osbuild/bootc-image-builder/issues/927


# Default values
ARCH=""  # Empty by default - will be detected from system if not specified
ENTITLEMENTS_DIR="$HOME/.rh-entitlements"
CONTAINERFILE="Containerfile"
CONFIG_FILE="./config.toml"
OUTPUT_DIR="./bootc-exports"
BOOTC_BUILDER_IMAGE="registry.redhat.io/rhel9/bootc-image-builder:latest"
#BOOTC_BUILDER_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"
IMAGE=""
FORMAT="anaconda-iso"
ARCH_SPECIFIED=false

usage() {
    echo "Usage: $0 [OPTIONS] -i IMAGE"
    echo ""
    echo "OPTIONS:"
    echo "  -i IMAGE             Container image name (required)"
    echo "  -a ARCH              Architecture (default: system architecture)"
    echo "  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)"
    echo "  -c CONTEXT           Build context directory (default: .)"
    echo "  -o                   Output dir (default: ./bootc-exports)"
    echo "  -f                   Target format. Valid values: anaconda-iso (default), qcow2, ami, vmdk, raw, vhd, gce."
    echo "  -t                   TOML config file. Default: ./config.toml"
    echo "  -h                   Show this help message"
    echo ""
    exit 1
}

# Function to detect system architecture
detect_arch() {
    local system_arch=$(uname -m)
    case $system_arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "Unsupported architecture: $system_arch. Supported: amd64, arm64" >&2
            exit 1
            ;;
    esac
}


VALID_FORMATS=("anaconda-iso" "qcow2" "ami" "vmdk" "raw" "vhd" "gce")
is_valid_format() {
    local fmt="$1"
    for valid in "${VALID_FORMATS[@]}"; do
        if [[ "$fmt" == "$valid" ]]; then
            return 0
        fi
    done
    return 1
}

while getopts "i:a:e:c:o:t:f:h" opt; do
    case $opt in
        i)
            IMAGE="$OPTARG"
            ;;
        a)
            ARCH="$OPTARG"
            ARCH_SPECIFIED=true
            ;;
        e)
            ENTITLEMENTS_DIR="$OPTARG"
            ;;
        c)
            CONTEXT="$OPTARG"
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        t)
            CONFIG_FILE="$OPTARG"
            ;;
        f)
            FORMAT="$OPTARG"
            if ! is_valid_format "$FORMAT"; then
                echo "Error: Invalid format '$FORMAT'. Must be one of: ${VALID_FORMATS[*]}" >&2
                exit 1
            fi
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "$IMAGE" ]; then
    echo "Error: Image name is required."
    echo "Use -i to specify the container image name."
    echo ""
    usage
fi

# If no architecture was specified, detect system architecture
if [ -z "$ARCH" ]; then
    ARCH=$(detect_arch)
fi

ENTITLEMENTS_DIR="${ENTITLEMENTS_DIR/#\~/$HOME}"
CONTEXT="${CONTEXT/#\~/$HOME}"

IMAGE="${IMAGE#http://}"
IMAGE="${IMAGE#https://}"
IMAGE="${IMAGE//\/\//\/}"


echo "Bootc Export Configuration"
echo "-------------------------"
if [ "$ARCH_SPECIFIED" = true ]; then
    echo "Architecture: $ARCH (explicitly specified)"
else
    echo "Architecture: $ARCH (system detected)"
fi
echo "Image: $IMAGE"
echo "Export format: $FORMAT"
echo "Output dir: $OUTPUT_DIR"
echo "Config file: $CONFIG_FILE"
echo "Entitlements directory: ${ENTITLEMENTS_DIR}/${ARCH}"
echo "-------------------------"
echo ""

# Validate required files and directories

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi



if [ ! -d "${ENTITLEMENTS_DIR}/${ARCH}" ]; then
    echo "Error: Entitlements directory not found at ${ENTITLEMENTS_DIR}/${ARCH}"
    echo "Please run the entitlements script first to generate entitlements for $ARCH"
    exit 1
fi

if [ -z "$(ls -A "${ENTITLEMENTS_DIR}/${ARCH}")" ]; then
    echo "Error: Entitlements directory is empty at ${ENTITLEMENTS_DIR}/${ARCH}"
    echo "Please run the entitlements script first to generate entitlements for $ARCH"
    exit 1
fi

echo "Sudo is required."
sudo echo ""

mkdir -p $OUTPUT_DIR

# Registry login
if sudo podman login --get-login "${BOOTC_BUILDER_IMAGE%%/*}" &>/dev/null; then
  echo "Already logged in to ${BOOTC_BUILDER_IMAGE%%/*} as $(sudo podman login --get-login "${BOOTC_BUILDER_IMAGE%%/*}")"
else
  echo "Not logged in to ${BOOTC_BUILDER_IMAGE%%/*}. Logging in..."
  sudo podman login -u "$USERNAME" -p "$PASSWORD" "${BOOTC_BUILDER_IMAGE%%/*}"
fi

# Only enable binfmt_misc for cross-arch
if [ "$ARCH_SPECIFIED" = true ]; then
    echo "Enabling binfmt_misc for cross-arch builds..."
    sudo podman run --rm --privileged docker.io/multiarch/qemu-user-static --reset -p yes 2>/dev/null \
        || echo "binfmt setup completed (some handlers may have already existed)"
fi




echo "Exporting image to ..."
# export command
EXPORT_CMD="sudo podman run --rm -it --privileged --pull=newer --security-opt label=type:unconfined_t   -v ${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:Z  -v $CONFIG_FILE:/config.toml:ro -v $OUTPUT_DIR:/output -v /var/lib/containers/storage:/var/lib/containers/storage"

# Only add --platform if architecture was explicitly specified
if [ "$ARCH_SPECIFIED" = true ]; then
    EXPORT_CMD="$EXPORT_CMD --platform linux/$ARCH"
fi

EXPORT_CMD="$EXPORT_CMD $BOOTC_BUILDER_IMAGE --type $FORMAT  --use-librepo=True --progress debug"

if [ "$ARCH_SPECIFIED" = true ]; then
    EXPORT_CMD="$EXPORT_CMD --target-arch $ARCH"
fi


# Check if image is already pulled
if sudo podman image exists "$IMAGE"; then
  echo "Image $IMAGE already exists locally — no need to pull."
else
  # Try pulling directly (anonymous/public access)
  echo "Attempting to pull $IMAGE (anonymous/public pull)..."
  if sudo podman pull --quiet --platform linux/$ARCH "$IMAGE"; then
    echo "Successfully pulled $IMAGE without login."
  else
    echo "Failed to pull $IMAGE anonymously. Trying with registry login..."

    # Try logging in—prompt or use credentials
    REGISTRY_HOST="${IMAGE%%/*}"
    if sudo podman login --get-login "$REGISTRY_HOST" &>/dev/null; then
      echo "Already logged in to $REGISTRY_HOST."
    else
      # Prompt for credentials interactively, or read from env vars
      echo "Logging in to $REGISTRY_HOST..."
      read -p "Registry username: " USERNAME
      read -s -p "Registry password: " PASSWORD
      echo
      sudo podman login -u "$USERNAME" -p "$PASSWORD" "$REGISTRY_HOST"
    fi

    # Retry pull with credentials
    echo "Retrying pull with login..."
    sudo podman pull --platform linux/$ARCH "$IMAGE"
  fi
fi


EXPORT_CMD="$EXPORT_CMD $IMAGE"

echo "Running command:"
echo "$EXPORT_CMD"
echo ""

eval "$EXPORT_CMD"

echo "Export completed successfully!"
echo "Output in: $OUTPUT_DIR"
#!/bin/bash
set -e

# Default values
ARCH=""  # Empty by default - will be detected from system if not specified
ENTITLEMENTS_DIR="$HOME/.rh-entitlements"
CONTAINERFILE="Containerfile"
CONTEXT="."
IMAGE=""
ARCH_SPECIFIED=false

usage() {
    echo "Usage: $0 [OPTIONS] -i IMAGE"
    echo ""
    echo "OPTIONS:"
    echo "  -i IMAGE             Container image name (required)"
    echo "  -a ARCH              Architecture (default: system architecture)"
    echo "  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)"
    echo "  -f CONTAINERFILE     Path to Containerfile (default: Containerfile)"
    echo "  -c CONTEXT           Build context directory (default: .)"
    echo "  -h                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic build (uses system architecture)"
    echo "  $0 -i myregistry.com/myimage:latest"
    echo ""
    echo "  # Build for specific architecture"
    echo "  $0 -i myregistry.com/myimage:latest -a arm64 -e /path/to/entitlements"
    echo ""
    echo "  # Build with custom Containerfile"
    echo "  $0 -i myregistry.com/myimage:latest -f custom.Containerfile -c /path/to/context"
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

while getopts "i:a:e:s:f:c:t:Ph" opt; do
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
        f)
            CONTAINERFILE="$OPTARG"
            ;;
        c)
            CONTEXT="$OPTARG"
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
CONTAINERFILE="${CONTAINERFILE/#\~/$HOME}"
CONTEXT="${CONTEXT/#\~/$HOME}"

IMAGE="${IMAGE#http://}"
IMAGE="${IMAGE#https://}"
IMAGE="${IMAGE//\/\//\/}"


echo "Bootc Build Configuration"
echo "-------------------------"
if [ "$ARCH_SPECIFIED" = true ]; then
    echo "Architecture: $ARCH (explicitly specified)"
else
    echo "Architecture: $ARCH (system detected)"
fi
echo "Image: $IMAGE"
echo "Containerfile: $CONTAINERFILE"
echo "Build context: $CONTEXT"
echo "Entitlements directory: ${ENTITLEMENTS_DIR}/${ARCH}"
echo "-------------------------"
echo ""

# Validate required files and directories

if [ ! -f "$CONTAINERFILE" ]; then
    echo "Error: Containerfile not found at $CONTAINERFILE"
    exit 1
fi

if [ ! -d "$CONTEXT" ]; then
    echo "Error: Build context directory not found at $CONTEXT"
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


# Registry login
BUILD_FROM=$(grep -i '^FROM ' "${CONTEXT}/${CONTAINERFILE}" | head -n1 | awk '{print $2}')
if podman login --get-login "${BUILD_FROM%%/*}" &>/dev/null; then
  echo "Already logged in to ${BUILD_FROM%%/*} as $(podman login --get-login "${BUILD_FROM%%/*}")"
else
  echo "Not logged in to ${BUILD_FROM%%/*}!"
  podman login "${BUILD_FROM%%/*}"
fi

# Only enable binfmt_misc for cross-arch builds when architecture is explicitly specified
if [ "$ARCH_SPECIFIED" = true ]; then
    echo "Enabling binfmt_misc for cross-arch builds..."
    podman run --rm --privileged docker.io/multiarch/qemu-user-static --reset -p yes 2>/dev/null \
        || echo "binfmt setup completed (some handlers may have already existed)"
fi

echo "Building image for $ARCH..."

# Build the podman command
PODMAN_CMD="podman build"

# Only add --platform if architecture was explicitly specified
if [ "$ARCH_SPECIFIED" = true ]; then
    PODMAN_CMD="$PODMAN_CMD --platform linux/$ARCH"
fi

PODMAN_CMD="$PODMAN_CMD -f $CONTAINERFILE -t $IMAGE -v ${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:z $CONTEXT"

echo "$PODMAN_CMD"


podman build \
    --platform "linux/$ARCH" \
    -f "$CONTAINERFILE" \
    -t "$IMAGE" \
    -v "${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:z" \
    "$CONTEXT"


echo "Build completed successfully!"
echo "Image tagged as: $IMAGE"
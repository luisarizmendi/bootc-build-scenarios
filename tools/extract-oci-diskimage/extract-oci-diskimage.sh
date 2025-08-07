#!/bin/bash
set -euo pipefail
OCI_DISK_IMAGE_REPO=""
OCI_IMAGE_TAG="latest"
OUTPUT_DIR="/output"

usage() {
cat <<EOF
Usage: $0 <image[:tag]> [-o <output-dir>]
Arguments:
 <image[:tag]> OCI disk image repo with optional tag (e.g. quay.io/user/repo:tag) [required]
Options:
 -o <output-dir> Output directory (default: output)
 -h Show this help message
EOF
exit 1
}

while getopts ":o:h" opt; do
case $opt in
o) OUTPUT_DIR="$OPTARG" ;;
h) usage ;;
\?) echo "Invalid option: -$OPTARG" >&2; usage ;;
:) echo "Option -$OPTARG requires an argument." >&2; usage ;;
esac
done

# Shift past the options to get the positional argument
shift $((OPTIND-1))

# Check if image argument is provided
if [[ $# -eq 0 ]]; then
    echo "Error: <image[:tag]> is required" >&2
    usage
fi

full_image="$1"

# Default tag
OCI_IMAGE_TAG="latest"
# If full_image contains a colon after last slash, split
# Extract last part after slash
last_part="${full_image##*/}"
if [[ "$last_part" == *":"* ]]; then
    OCI_DISK_IMAGE_REPO="${full_image%:*}"
    OCI_IMAGE_TAG="${full_image##*:}"
else
    OCI_DISK_IMAGE_REPO="$full_image"
fi



echo "Extracting contents from ${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG}"

# Create a temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo "skopeo copy docker://${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG} dir:${TEMP_DIR}"
skopeo copy docker://${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG} dir:${TEMP_DIR}

# Function to determine extension from various sources
determine_extension() {
    local manifest_file="$1"
    local ext=""
    
    # First try to get extension from artifactType
    local artifact_type=$(jq -r '.artifactType // empty' "$manifest_file")
    if [[ -n "$artifact_type" ]]; then
        case "$artifact_type" in
            *diskimage.iso*) ext="iso" ;;
            *diskimage.qcow2*) ext="qcow2" ;;
            *diskimage.vmdk*) ext="vmdk" ;;
            *diskimage.raw*) ext="raw" ;;
            *diskimage.ami*) ext="ami" ;;
            *diskimage.vhd*) ext="vhd" ;;
            *diskimage.gce*) ext="gce" ;;
        esac
    fi
    
    # If no extension found, try layer annotations
    if [[ -z "$ext" ]]; then
        local title=$(jq -r '.layers[0].annotations["org.opencontainers.image.title"] // empty' "$manifest_file")
        if [[ -n "$title" ]]; then
            case "$title" in
                *.iso) ext="iso" ;;
                *.qcow2) ext="qcow2" ;;
                *.vmdk) ext="vmdk" ;;
                *.raw) ext="raw" ;;
                *.ami) ext="ami" ;;
                *.vhd) ext="vhd" ;;
                *.gce) ext="gce" ;;
            esac
        fi
    fi
    
    # Fallback to mediaType (original logic)
    if [[ -z "$ext" ]]; then
        local media_type=$(jq -r '.layers[0].mediaType' "$manifest_file")
        case "$media_type" in
            application/*.iso) ext="iso" ;;
            application/*.qcow2) ext="qcow2" ;;
            application/*.vmdk) ext="vmdk" ;;
            application/*.raw) ext="raw" ;;
            application/*.ami) ext="ami" ;;
            application/*.vhd) ext="vhd" ;;
            application/*.gce) ext="gce" ;;
        esac
    fi
    
    echo "$ext"
}

# Determine the file extension
ext=$(determine_extension "${TEMP_DIR}/manifest.json")

if [[ -z "$ext" ]]; then
    echo "Error: Could not determine disk image type from manifest" >&2
    echo "Manifest content:" >&2
    cat "${TEMP_DIR}/manifest.json" >&2
    exit 1
fi

echo "Detected disk image type: $ext"

# Find the actual disk file (largest file that's not metadata)
disk_file=$(find "$TEMP_DIR" -type f ! -name 'manifest.json' ! -name 'version' ! -name '*.json' -exec ls -la {} \; | sort -k5 -nr | head -n1 | awk '{print $NF}')

if [[ -z "$disk_file" ]]; then
    echo "Error: Could not find disk image file" >&2
    exit 1
fi

echo "Disk file: $disk_file"

mkdir -p "$OUTPUT_DIR"

mv "$disk_file" "${OUTPUT_DIR}/disk.${ext}"

echo "Extracted disk.${ext}!"
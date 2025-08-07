# Extract OCI Disk Image

A containerized tool for extracting disk images (QCOW2, ISO, etc.) from OCI-compliant container images. This utility simplifies the process of retrieving disk image artifacts that have been packaged and distributed using container registries.

## Overview

This tool is designed to work with OCI artifacts that contain disk images, such as those created using the following workflow:

```bash
sudo podman manifest create \
    ${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG}

sudo podman manifest add \
    --artifact --artifact-type application/vnd.diskimage.iso \
    --arch=${ARCH} --os=linux \
    ${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG} \
    "${PWD}/install.iso"

sudo podman manifest push --all \
    ${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG} \
    docker://${OCI_DISK_IMAGE_REPO}:${OCI_IMAGE_TAG}
```

## Container Image

> 📦 `quay.io/luisarizmendi/extract-oci-diskimage:latest`  
This is the container image built using the `Containerfile` provided in this repository.

## Usage Examples

### 1. Extracting a QCOW2 Image with Default Credentials

Extract a QCOW2 image from a container located at  `quay.io/luisarizmendi/myrhel/diskimage-qcow2:test-amd64`, and save it to a local folder named `my-output`.

```bash
podman run --rm \
  -v $(pwd)/my-output:/output:Z \
  quay.io/luisarizmendi/extract-oci-diskimage:latest \
  quay.io/luisarizmendi/myrhel/diskimage-qcow2:test-amd64
```

### 2. Extracting with Authentication Credentials

If the image requires authentication, mount your local Podman or Docker authentication file (typically found at `~/.config/containers/auth.json`):

```bash
podman run --rm  \
  -v ~/.config/containers/auth.json:/home/extractor/.config/containers/auth.json:Z \
  -v $(pwd)/my-output:/output:Z \
  quay.io/luisarizmendi/extract-oci-diskimage:latest \
  quay.io/luisarizmendi/myrhel/diskimage-qcow2:test-amd64
```



## Notes

- Ensure the output directory (`my-output` in the examples above) exists and is writable by the container.
- The tool expects that the container image layers contain the desired disk image artifact (e.g., `.qcow2` files).



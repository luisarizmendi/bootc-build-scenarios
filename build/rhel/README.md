# Build Bootc Images Using RHEL

Using a subscribed RHEL system (RHEL 9+) is the most straightforward way to create a `bootc` image because you can re-use the host subscription to install RHEL packages in your images without further preparation.

## Prerequisites

- RHEL 9+ system with active subscription
- Podman installed
- Access to container registries (registry.redhat.io)
- Root privileges for image building

## Part 1: Image Build

### Step 1: Subscribe Your System

First, ensure your RHEL system is properly registered and subscribed:

```bash
sudo subscription-manager register
```

### Step 2: Create Project Structure

Create a directory for your bootc image project with the necessary files:

```bash
mkdir my-bootc-image
cd my-bootc-image
```

Create a `Containerfile` (or `Dockerfile`) using a bootc-prepared base image:

```dockerfile
FROM registry.redhat.io/rhel9/rhel-bootc:9.6

# Install base packages
RUN dnf -y install tmux python3-pip && \
    pip3 install podman-compose && \
    dnf clean all

# Add any additional customizations here
# COPY custom-files/ /path/to/destination/
```

### Step 3: Authenticate to Registry (if needed)

If your base image is from a private registry, authenticate before building:

```bash
podman login registry.redhat.io
```

### Step 4: Build the Container Image

Build your bootc image using standard container build commands:

```bash
podman build -t <YOUR_BOOTC_IMAGE_NAME> .
```

**Example:**
```bash
podman build -t quay.io/myuser/my-bootc-image:latest .
```

#### Cross-Architecture Builds

If you need to build for a different architecture (e.g., building ARM64 images on x86_64), you can specify the target platform:

```bash
podman build --platform <TARGET_PLATFORM> -t <YOUR_BOOTC_IMAGE_NAME> .
```

**Examples:**
```bash
# Build ARM64 image on x86_64 host
podman build --platform linux/arm64 -t quay.io/myuser/my-bootc-image:arm64 .

# Build x86_64 image on ARM64 host
podman build --platform linux/amd64 -t quay.io/myuser/my-bootc-image:amd64 .
```

**Prerequisites for cross-architecture builds:**
- Your host system must have cross-architecture container execution enabled (e.g., using `qemu-user-static` and `binfmt_misc`)
- On most systems, this can be enabled with: `sudo podman run --privileged --rm tonistiigi/binfmt --install all`

**⚠️ Performance Note:** Cross-architecture builds are significantly slower than native builds due to emulation overhead. Build times can be 5-10x longer depending on the complexity of your image.

### Step 5: Push to Registry

Push your built image to a container registry:

```bash
podman push <YOUR_BOOTC_IMAGE_NAME>
```

## Part 2: Create Installable Artifacts

If you want to install this image on bare metal servers or VMs, you'll need to create bootable artifacts using `bootc-image-builder`.

### Step 6: Prepare Build Configuration

Create a TOML configuration file (`config.toml`) to specify users and other system settings:

```toml
[[customizations.user]]
name = "alice"
password = "bob"
key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... user@email.com"
groups = ["wheel"]

# Optional: Add additional users
[[customizations.user]]
name = "admin" 
password = "secure_password"
groups = ["wheel"]
```

### Step 7: Create Output Directory

Create a directory to store the generated artifacts:

```bash
mkdir output
```

### Step 8: Pull Image as Root User

The `bootc-image-builder` runs as root and needs access to your bootc image. Pull the image for the root user:

```bash
sudo podman pull <YOUR_BOOTC_IMAGE_NAME>
```

### Step 9: Run bootc-image-builder

Run the `bootc-image-builder` container to generate your desired artifact format:

```bash
sudo podman run \
    --rm \
    --interactive \
    --tty \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    --volume ./config.toml:/config.toml:ro \
    --volume ./output:/output \
    --volume /var/lib/containers/storage:/var/lib/containers/storage \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type <IMAGE_TYPE> \
    <YOUR_BOOTC_IMAGE_NAME>
```

Choose the appropriate `--type` parameter based on your target environment:

| Image Type | Description | Use Case |
|------------|-------------|----------|
| `qcow2` **(default)** | QEMU Copy-On-Write format | KVM/QEMU virtualization, OpenStack |
| `ami` | Amazon Machine Image | AWS EC2 instances |
| `vmdk` | Virtual Machine Disk | VMware vSphere, VirtualBox |
| `vhd` | Virtual Hard Disk | Microsoft Hyper-V, Azure |
| `raw` | Raw disk image | Direct disk writing, custom deployments |
| `anaconda-iso` | Bootable ISO installer | Unattended installation on physical hardware |
| `gce` | Google Compute Engine image | Google Cloud Platform |

## Example Complete Workflow

Here's a complete example building a QEMU-compatible image:

```bash
# 1. Create project
mkdir my-web-server && cd my-web-server

# 2. Create Containerfile
cat << 'EOF' > Containerfile
FROM registry.redhat.io/rhel9/rhel-bootc:9.6
RUN dnf -y install httpd && \
    systemctl enable httpd && \
    dnf clean all
EOF

# 3. Create config
cat << 'EOF' > config.toml
[[customizations.user]]
name = "webadmin"
password = "$6$salt$hashedpassword"
key = "ssh-rsa AAAAB3NzaC1yc2E... webadmin@company.com"
groups = ["wheel"]
EOF

# 4. Build and push
podman build -t quay.io/myuser/web-server-bootc:latest .
podman push quay.io/myuser/web-server-bootc:latest

# 5. Generate QEMU image
mkdir output
sudo podman pull quay.io/myuser/web-server-bootc:latest
sudo podman run \
    --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./config.toml:/config.toml:ro \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type qcow2 \
    quay.io/myuser/web-server-bootc:latest
```

## Scripts

In order to simplify the procedure I created some scripts that you can find under the `scripts` directory, for example:


### Container Image Builder (`build-image.sh`)

#### Purpose
This bash script automates container image building using Podman with automatic architecture detection and cross-platform build support for bootc (boot container) images.

#### Key Features
- **Auto-detection**: Automatically detects system architecture (amd64/arm64) if not specified
- **Cross-platform builds**: Supports explicit architecture specification with binfmt_misc setup for cross-compilation
- **Registry authentication**: Automatically handles login to the base image registry
- **Flexible configuration**: Customizable Containerfile path, build context, and image name
- **Validation**: Checks for required files and directories before building

#### Usage
```bash
./build-image.sh [OPTIONS] -i IMAGE

OPTIONS:
  -i IMAGE             Container image name (required)
  -a ARCH              Architecture (default: system architecture)
  -f CONTAINERFILE     Path to Containerfile (default: Containerfile)
  -c CONTEXT           Build context directory (default: .)
  -h                   Show this help message
```

#### Examples
```bash
# Basic build (uses system architecture)
./build-image.sh -i myregistry.com/myimage:latest

# Build for specific architecture
./build-image.sh -i myregistry.com/myimage:latest -a arm64

# Build with custom Containerfile
./build-image.sh -i myregistry.com/myimage:latest -f custom.Containerfile -c /path/to/context
```

---

### Bootc Image Exporter (`export-image.sh`)

#### Purpose
This bash script exports bootc container images to various disk formats using the bootc-image-builder tool. It converts container images into bootable system images for different platforms and virtualization environments.

#### Key Features
- **Multiple output formats**: Supports anaconda-iso (default), qcow2, ami, vmdk, raw, vhd, and gce formats
- **Architecture handling**: Auto-detects system architecture with support for cross-architecture exports
- **Registry management**: Handles authentication for both builder image and target image registries
- **Configuration support**: Uses TOML configuration files for customization
- **Privileged operations**: Manages sudo requirements for container operations
- **Smart image pulling**: Attempts anonymous pulls before requiring authentication

#### Usage
```bash
./export-image.sh [OPTIONS] -i IMAGE

OPTIONS:
  -i IMAGE             Container image name (required)
  -a ARCH              Architecture (default: system architecture)
  -c CONTEXT           Build context directory (default: .)
  -o                   Output dir (default: ./bootc-exports)
  -f                   Target format. Valid values: anaconda-iso (default), qcow2, ami, vmdk, raw, vhd, gce
  -t                   TOML config file. Default: ./config.toml
  -h                   Show this help message
```

#### Supported Export Formats
- **anaconda-iso**: Bootable ISO image (default)
- **qcow2**: QEMU/KVM virtual disk format
- **ami**: Amazon Machine Image format
- **vmdk**: VMware virtual disk format
- **raw**: Raw disk image
- **vhd**: Hyper-V virtual hard disk format
- **gce**: Google Compute Engine format

#### Examples
```bash
# Export to ISO (default format)
./export-image.sh -i myregistry.com/myimage:latest

# Export to QCOW2 for virtualization
./export-image.sh -i myregistry.com/myimage:latest -f qcow2

# Export with custom config and output directory
./export-image.sh -i myregistry.com/myimage:latest -f ami -t custom-config.toml -o /path/to/exports
```

#### Requirements
- **sudo access**: Required for privileged container operations
- **config.toml**: Configuration file must exist (default: ./config.toml)
- **bootc-image-builder**: Uses Red Hat's bootc-image-builder container

#### Known Issues
- References GitHub issue #927 in osbuild/bootc-image-builder

#### Registry Configuration
The script uses `registry.redhat.io/rhel9/bootc-image-builder:latest` as the default builder image, with an alternative CentOS option available in comments.
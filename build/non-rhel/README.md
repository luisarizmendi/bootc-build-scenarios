# Build Bootc Images Using Non-RHEL Base Images

Building `bootc` images from non-RHEL base images (such as CentOS Stream, Fedora, or other distributions) requires special handling when you need access to RHEL repositories and packages. Since these base images cannot be directly subscribed to Red Hat, you must obtain and use Red Hat entitlement files.

## Prerequisites

- **Active Red Hat subscription** (required for accessing RHEL repositories)
- System with Podman installed
- Access to container registries (registry.redhat.io, quay.io, etc.)
- Root privileges for image building and exports

---

## ⚠️ Important Notes About Red Hat Entitlements

### Why Entitlements Are Needed
Unlike RHEL systems that can use `subscription-manager` directly, non-RHEL base images cannot be subscribed to Red Hat repositories. To access RHEL packages and repositories, you need **Red Hat entitlement files** that contain the necessary certificates and repository configurations.

### How Entitlements Are Obtained
You will need your Red Hat subscription credentials. Since it is not RHEL you cannot subscribe it directly, so you will need to use Red Hat entitlement files that you need to get beforehand. You can get them from a subscribed RHEL system or by creating a container image, subscribing it, extracting the files and then removing the subscription (which is what the scripts do automatically).

### Architecture-Specific Entitlements
**The entitlements are bound to the architecture type:**
- If you use x86_64 build you need x86_64 entitlements
- If you use ARM64 build you need ARM64 entitlements  
- Same applies for any other architecture

### Entitlement Expiration
**Entitlements cannot be used forever.** If you detect that those are not working anymore you will need to get them again.

### Getting Entitlements from a Subscribed RHEL System
If you already have a subscribed RHEL system, you can manually copy entitlement files:

```bash
# On a subscribed RHEL system:
mkdir -p ~/.rh-entitlements/amd64/{etc-pki-entitlement,rhsm}

# Copy entitlement certificates  
sudo cp -a /etc/pki/entitlement/* ~/.rh-entitlements/amd64/etc-pki-entitlement/

# Copy subscription manager configuration
sudo cp -a /etc/rhsm/* ~/.rh-entitlements/amd64/rhsm/

# Extract required repository configurations
sudo awk '/-appstream-/' RS= ORS="\n\n" /etc/yum.repos.d/redhat.repo >> ~/.rh-entitlements/amd64/redhat.repo
sudo awk '/-baseos-/' RS= ORS="\n\n" /etc/yum.repos.d/redhat.repo >> ~/.rh-entitlements/amd64/redhat.repo

# Fix ownership
sudo chown -R $(whoami):$(whoami) ~/.rh-entitlements/
```

### Getting Entitlements from a non-Subscribed system

If you don't have access to a subscribed RHEL system, you can obtain entitlements by creating a temporary RHEL container, subscribing it, extracting the entitlement files, and then unsubscribing it.

#### Create Entitlements Directory

```bash
ENTITLEMENTS_DIR="$HOME/.rh-entitlements"
mkdir -p "${ENTITLEMENTS_DIR}/${ARCH}"
```

#### Login to Red Hat Registry

```bash
podman login registry.redhat.io -u "$RH_USERNAME" -p "$RH_PASSWORD"
```

#### Create Temporary RHEL Container for Entitlement Extraction

Create a Containerfile for the entitlement extraction process:

```bash
cat << EOF > Containerfile.subs
FROM registry.redhat.io/rhel9/rhel-bootc:9.6
ARG RH_USERNAME=""
ARG RH_PASSWORD=""
RUN if [ -n "\$RH_USERNAME" ] && [ -n "\$RH_PASSWORD" ]; then \\
    echo "Registering with Red Hat subscription manager..." && \\
    rm -rf /etc/rhsm-host && \\
    subscription-manager register --username "\$RH_USERNAME" --password "\$RH_PASSWORD" && \\
    subscription-manager attach --auto; \\
    fi
RUN dnf -y --nogpgcheck install curl jq && dnf clean all
RUN mkdir -p /entitlements/etc-pki-entitlement && \\
    mkdir -p /entitlements/rhsm && \\
    cp -a /etc/pki/entitlement/* /entitlements/etc-pki-entitlement && \\
    cp -a /etc/rhsm/* /entitlements/rhsm && \\
    awk '/-appstream-/' RS= ORS="\\n\\n" /etc/yum.repos.d/redhat.repo >> /entitlements/redhat.repo && \\
    awk '/-baseos-/' RS= ORS="\\n\\n" /etc/yum.repos.d/redhat.repo >> /entitlements/redhat.repo
RUN if [ -n "\$RH_USERNAME" ] && [ -n "\$RH_PASSWORD" ]; then \\
    subscription-manager unregister && \\
    subscription-manager clean; \\
    fi
EOF
```

#### Build Entitlement Container

```bash
# Enable cross-architecture builds if needed
podman run --rm --privileged docker.io/multiarch/qemu-user-static --reset -p yes

# Build the entitlement container
podman build -f Containerfile.subs \
    --build-arg RH_USERNAME="$RH_USERNAME" \
    --build-arg RH_PASSWORD="$RH_PASSWORD" \
    --platform "linux/$ARCH" \
    --no-cache \
    -t "entitlement-$ARCH" .
```

#### Extract Entitlement Files

```bash
# Create temporary directory
mkdir -p entitlements/$ARCH

# Extract entitlements from container
CONTAINER_ID=$(podman create "entitlement-$ARCH")
podman cp "${CONTAINER_ID}:/entitlements/." "entitlements/$ARCH/"
podman rm "${CONTAINER_ID}"
podman rmi "entitlement-$ARCH"

# Copy to final location
cp -r "entitlements/$ARCH"/* "${ENTITLEMENTS_DIR}/${ARCH}/"

# Clean up
rm -f Containerfile.subs
rm -rf entitlements
```

---

## Part 1: Image Build

### Step 1: Create Project Structure

Create a directory for your bootc image project:

```bash
mkdir my-bootc-image
cd my-bootc-image
```

Create a `Containerfile` using a non-RHEL bootc base image and configure it to use the mounted entitlements:

```dockerfile
FROM quay.io/centos-bootc/centos-bootc:stream9

# Mount Red Hat entitlements (available at /run/secrets during build)
COPY --from=/run/secrets/etc-pki-entitlement /etc/pki/entitlement
COPY --from=/run/secrets/rhsm /etc/rhsm
COPY --from=/run/secrets/redhat.repo /etc/yum.repos.d/

# Install packages from RHEL repositories
RUN dnf -y install tmux python3-pip && \
    pip3 install podman-compose && \
    dnf clean all

# IMPORTANT: Clean up entitlements for security
RUN rm -rf /etc/pki/entitlement && \
    rm -rf /etc/rhsm && \
    rm -f /etc/yum.repos.d/redhat.repo

# Add any additional customizations here
# COPY custom-files/ /path/to/destination/
```

### Step 2: Authenticate to Registry (if needed)

If your base image is from a private registry, authenticate before building:

```bash
podman login quay.io
```

### Step 3: Build the Container Image with Entitlements

Build your bootc image with the entitlement files mounted:

```bash
podman build \
    --platform "linux/$ARCH" \
    -f Containerfile \
    -t <YOUR_BOOTC_IMAGE_NAME> \
    -v "${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:z" \
    .
```

**Example:**
```bash
podman build \
    --platform "linux/$ARCH" \
    -f Containerfile \
    -t quay.io/myuser/my-bootc-image:latest \
    -v "${HOME}/.rh-entitlements/${ARCH}:/run/secrets:z" \
    .
```

#### Cross-Architecture Builds

If you need to build for a different architecture, ensure you have entitlements for that architecture and specify the target platform:

```bash
# Make sure you have ARM64 entitlements first
# Then build for ARM64
podman build \
    --platform "linux/arm64" \
    -f Containerfile \
    -t quay.io/myuser/my-bootc-image:arm64 \
    -v "${HOME}/.rh-entitlements/arm64:/run/secrets:z" \
    .
```

**⚠️ Performance Note:** Cross-architecture builds are significantly slower than native builds due to emulation overhead. Build times can be 5-10x longer depending on the complexity of your image.

### Step 4: Push to Registry

Push your built image to a container registry:

```bash
podman push <YOUR_BOOTC_IMAGE_NAME>
```

---

## Part 2: Create Installable Artifacts

If you want to install this image on bare metal servers or VMs, you'll need to create bootable artifacts using `bootc-image-builder`.

### Step 5: Prepare Build Configuration

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

### Step 6: Create Output Directory

Create a directory to store the generated artifacts:

```bash
mkdir output
```

### Step 7: Pull Image as Root User

The `bootc-image-builder` runs as root and needs access to your bootc image:

```bash
sudo podman pull <YOUR_BOOTC_IMAGE_NAME>
```

### Step 8: Run bootc-image-builder with Entitlements

Run the `bootc-image-builder` container with entitlements mounted:

```bash
sudo podman run \
    --rm \
    --interactive \
    --tty \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    --volume "${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:Z" \
    --volume ./config.toml:/config.toml:ro \
    --volume ./output:/output \
    --volume /var/lib/containers/storage:/var/lib/containers/storage \
    --platform "linux/$ARCH" \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type <IMAGE_TYPE> \
    --target-arch $ARCH \
    <YOUR_BOOTC_IMAGE_NAME>
```

Choose the appropriate `--type` parameter based on your target environment:

| Image Type | Description | Use Case |
|------------|-------------|----------|
| `anaconda-iso` | Bootable ISO installer | Unattended installation on physical hardware |
| `qcow2` **(default)** | QEMU Copy-On-Write format | KVM/QEMU virtualization, OpenStack |
| `ami` | Amazon Machine Image | AWS EC2 instances |
| `vmdk` | Virtual Machine Disk | VMware vSphere, VirtualBox |
| `vhd` | Virtual Hard Disk | Microsoft Hyper-V, Azure |
| `raw` | Raw disk image | Direct disk writing, custom deployments |
| `gce` | Google Compute Engine image | Google Cloud Platform |


---

## Example Complete Workflow

Here's a complete example building a CentOS Stream-based web server with RHEL packages:

```bash
#  Get entitlements

# Create project
mkdir my-web-server && cd my-web-server

# Create Containerfile
cat << 'EOF' > Containerfile
FROM quay.io/centos-bootc/centos-bootc:stream9

# Mount Red Hat entitlements
COPY --from=/run/secrets/etc-pki-entitlement /etc/pki/entitlement
COPY --from=/run/secrets/rhsm /etc/rhsm
COPY --from=/run/secrets/redhat.repo /etc/yum.repos.d/

# Install packages (can now access RHEL repos)
RUN dnf -y install httpd && \
    systemctl enable httpd && \
    dnf clean all

# Clean up entitlements
RUN rm -rf /etc/pki/entitlement /etc/rhsm /etc/yum.repos.d/redhat.repo
EOF

# Create config
cat << 'EOF' > config.toml
[[customizations.user]]
name = "webadmin"
password = "$6$salt$hashedpassword"
key = "ssh-rsa AAAAB3NzaC1yc2E... webadmin@company.com"
groups = ["wheel"]
EOF

# Build with entitlements
podman build \
    --platform "linux/$ARCH" \
    -f Containerfile \
    -t quay.io/myuser/web-server-bootc:latest \
    -v "${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:z" \
    .

# Push image
podman push quay.io/myuser/web-server-bootc:latest

# Generate QEMU image with entitlements
mkdir output
sudo podman pull quay.io/myuser/web-server-bootc:latest
sudo podman run \
    --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    --volume "${ENTITLEMENTS_DIR}/${ARCH}:/run/secrets:Z" \
    --volume ./config.toml:/config.toml:ro \
    --volume ./output:/output \
    --volume /var/lib/containers/storage:/var/lib/containers/storage \
    --platform "linux/$ARCH" \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type qcow2 \
    --target-arch $ARCH \
    quay.io/myuser/web-server-bootc:latest
```

---

## Scripts

To simplify the procedure I created some scripts that you can find under this directory:

### Red Hat Entitlement Manager (`1-install-rh-entitlements.sh`)

#### Purpose
This script obtains Red Hat entitlement files required for non-RHEL builds by creating a temporary RHEL container, subscribing it, extracting entitlements, and cleaning up the subscription automatically.

#### Key Features
- **Automated entitlement extraction**: Creates temporary RHEL container to obtain entitlements
- **Multiple credential sources**: Supports environment variables, credentials files, and interactive input
- **Architecture detection**: Auto-detects system architecture or accepts explicit specification
- **Clean subscription management**: Automatically unsubscribes temporary container
- **Security**: Supports multiple secure credential input methods

#### Usage
```bash
./1-install-rh-entitlements.sh [OPTIONS]

OPTIONS:
  -a ARCH              Architecture: amd64 or arm64. Default: auto-detect from system
  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)
  -u USERNAME          Red Hat username (optional, can use RH_USERNAME env var)
  -p PASSWORD          Red Hat password (optional, can use RH_PASSWORD env var)
  -c CREDENTIALS_FILE  Path to credentials file (optional)
  -h                   Show this help message
```

#### Examples
```bash
# Using environment variables (recommended)
export RH_USERNAME=myuser
export RH_PASSWORD=mypassword
./1-install-rh-entitlements.sh

# Using credentials file
echo 'myuser' > ~/.rh-credentials
echo 'mypassword' >> ~/.rh-credentials
./1-install-rh-entitlements.sh

# For specific architecture
./1-install-rh-entitlements.sh -a arm64
```

---

### Container Image Builder with Entitlements (`2-build-with-entitlements.sh`)

#### Purpose  
This script automates container image building using Podman with Red Hat entitlement files mounted, enabling access to RHEL repositories during builds from non-RHEL base images.

#### Key Features
- **Entitlement mounting**: Automatically mounts entitlement files at `/run/secrets`
- **Architecture handling**: Auto-detects system architecture with cross-build support
- **Validation**: Ensures entitlement files exist before building
- **Registry authentication**: Handles login to base image registries
- **Cross-platform builds**: Supports building for different architectures with binfmt_misc setup

#### Usage
```bash
./2-build-with-entitlements.sh [OPTIONS] -i IMAGE

OPTIONS:
  -i IMAGE             Container image name (required)
  -a ARCH              Architecture (default: system architecture)
  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)
  -f CONTAINERFILE     Path to Containerfile (default: Containerfile)
  -c CONTEXT           Build context directory (default: .)
  -h                   Show this help message
```

#### Examples
```bash
# Basic build (uses system architecture)
./2-build-with-entitlements.sh -i myregistry.com/myimage:latest

# Build for specific architecture
./2-build-with-entitlements.sh -i myregistry.com/myimage:latest -a arm64

# Build with custom Containerfile
./2-build-with-entitlements.sh -i myregistry.com/myimage:latest -f custom.Containerfile -c /path/to/context
```

---

### Bootc Image Exporter with Entitlements (`3-export-with-entitlements.sh`)

#### Purpose
This script exports bootc container images to various disk formats using the bootc-image-builder tool with Red Hat entitlements mounted for repository access during the export process.

#### Key Features
- **Entitlement mounting**: Mounts entitlement files during export process  
- **Multiple output formats**: Supports anaconda-iso, qcow2, ami, vmdk, raw, vhd, gce formats
- **Architecture handling**: Auto-detects system architecture with support for cross-architecture exports
- **Registry management**: Handles authentication for both builder image and target image registries
- **Configuration support**: Uses TOML configuration files for customization
- **Privileged operations**: Manages sudo requirements for container operations

#### Usage
```bash
./3-export-with-entitlements.sh [OPTIONS] -i IMAGE

OPTIONS:
  -i IMAGE             Container image name (required)
  -a ARCH              Architecture (default: system architecture)  
  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)
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

#### Requirements
- **sudo access**: Required for privileged container operations
- **config.toml**: Configuration file must exist (default: ./config.toml)
- **bootc-image-builder**: Uses Red Hat's bootc-image-builder container

#### Examples
```bash
# Export to ISO (default format)
./3-export-with-entitlements.sh -i myregistry.com/myimage:latest

# Export to QCOW2 for virtualization
./3-export-with-entitlements.sh -i myregistry.com/myimage:latest -f qcow2

# Export with custom config and output directory
./3-export-with-entitlements.sh -i myregistry.com/myimage:latest -f ami -t custom-config.toml -o /path/to/exports
```

#### Known Issues
- References GitHub issue #927 in osbuild/bootc-image-builder

# Build bootc Image with GitHub Actions

This directory contains a GitHub Actions workflow (`.github/workflows/build.yml`) that builds a **bootc image** for multiple platforms and exports it in various formats. It is based on [this one](https://github.com/redhat-cop/redhat-image-mode-actions/blob/main/.github/workflows/build_rhel_bootc.yml)

The image is pushed to the **GitHub Container Registry (GHCR)** by default, but can be configured to push to any container registry.

This workflow uses a **subscribed UBI container** approach, which eliminates the need to handle Red Hat subscriptions within your Containerfile. The subscription is managed at the workflow level, making your Containerfile cleaner and more secure.

This is a simple workflow, if you want to take a look to a more advanced one you can check [this repo](https://github.com/luisarizmendi/bootc-images) or [this workflow](https://github.com/luisarizmendi/rhem-demo/blob/main/.github/workflows/build.yml), those automatically build images when there are changes in certain directories and it manages the image automatic versioning depending on the already registered image labels.

---

## How the Workflow Works

![gha_pipeline.png](../../doc/gha_pipeline.png)

1. **Setup**
   - Reads input parameters or defaults.
   - Generates a build matrix for different platforms.
2. **Build**
   - Runs in a subscribed UBI9 container with container tools installed
   - Registers with Red Hat using credentials or activation keys
   - Uses `buildah` to build multi-platform bootc images
   - Automatically unregisters subscription when complete
3. **Multi-Platform Manifest**
   - Creates unified multi-arch container image manifests
   - Supports both x86_64 and ARM64 architectures
4. **Push**
   - Pushes the resulting container images to the configured container registry

**⚠️ Note:** This workflow focuses on building the base bootc container images. For creating installable artifacts with `bootc-image-builder`, you would need custom runners with RHEL subscriptions. You can create installable artifacts from the generated images using the methods mentioned in other scenarios.

---

## Repository Setup

### 1. Place the Workflow File
The workflow file must be located at:

```
.github/workflows/build.yml
```

If it's placed elsewhere, GitHub Actions will **not** detect it.

### 2. Enable Required Workflow Permissions

To allow the workflow to read repository contents and push packages:

1. Go to **Repository Settings** → **Actions** → **General**.
2. Scroll to **Workflow permissions**.
3. Select:
   - ✅ **Read repository contents and packages permissions**
4. Click **Save**.

### 3. Configure Red Hat Credentials

The workflow supports two authentication methods with Red Hat:

#### Option 1: Username/Password (Default)
1. Go to **Repository Settings** → **Secrets and variables** → **Actions**.
2. Add the following **Repository secrets**:
   - `RH_USERNAME`: Your Red Hat username
   - `RH_PASSWORD`: Your Red Hat password

#### Option 2: Organization ID/Activation Key (Optional)
If you prefer to use activation keys:
1. Add these **Repository secrets** instead:
   - `RHT_ORGID`: Your Red Hat organization ID
   - `RHT_ACT_KEY`: Your Red Hat activation key

The workflow will automatically detect which method to use based on available secrets.

### 4. (Optional) Configure Custom Registry Settings

By default, images are pushed to GitHub Container Registry (GHCR). To use a different registry:

1. Go to **Repository Settings** → **Secrets and variables** → **Actions**.
2. Under **Variables**, add any of:
   - `DEST_REGISTRY_HOST`: Custom registry hostname (default: `ghcr.io`)
   - `DEST_REGISTRY_USER`: Custom registry username (default: `github.actor`)
   - `DEST_IMAGE`: Custom image name (default: `{owner}/bootc-example`)
   - `TAGLIST`: Custom tags (default: `latest {sha} {branch}`)
3. Under **Secrets**, add:
   - `DEST_REGISTRY_PASSWORD`: Custom registry password (default: `GITHUB_TOKEN`)

### 5. (Optional) Override Source Registry Credentials

If you need different credentials for pulling from registry.redhat.io:

1. Add these **Repository secrets**:
   - `SOURCE_REGISTRY_USER`: Registry username (defaults to `RH_USERNAME`)
   - `SOURCE_REGISTRY_PASSWORD`: Registry password (defaults to `RH_PASSWORD`)

---

## Usage

### Automatic Triggers
The workflow automatically runs when:
- You push to the `main` branch
- You manually trigger it via the Actions tab

### Manual Trigger with Custom Parameters
1. Go to **Actions** → **Build bootc image with artifacts**
2. Click **Run workflow**
3. Configure:
   - **Platforms**: Comma-separated (default: `linux/amd64,linux/arm64`)
   - **Formats**: Comma-separated (default: `anaconda-iso,qcow2`)

### What Gets Built
The workflow creates:
- **Platform-specific images**: Tagged with architecture suffix (e.g., `latest-amd64`)
- **Multi-platform manifests**: Unified tags that work across architectures
- **Multiple tags**: Including `latest`, commit SHA, and branch name

### Finding Your Images
Built images are available in your repository's **Packages** section, accessible at:
```
https://github.com/{username}/{repository}/pkgs/container/{image-name}
```


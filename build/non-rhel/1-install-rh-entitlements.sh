#!/bin/bash

# Default values
ARCH=""  # Will be detected if not specified
ENTITLEMENTS_DIR="$HOME/.rh-entitlements"
USERNAME=""
PASSWORD=""
CREDENTIALS_FILE=""

SUBS_FROM="registry.redhat.io/rhel9/rhel-bootc:9.6"

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

# Function to prompt for credentials with hidden password input
prompt_for_credentials() {
    echo "No credentials found. Please provide your Red Hat credentials:"
    read -p "Username: " USERNAME
    read -s -p "Password: " PASSWORD
    echo  # Add newline after hidden password input
    
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo "Error: Both username and password are required."
        exit 1
    fi
    
    CREDENTIAL_SOURCE="user input"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -a ARCH              Architecture: amd64 or arm64. Default: auto-detect from system"
    echo "  -e ENTITLEMENTS_DIR  Path to entitlements directory (default: ~/.rh-entitlements)"
    echo "  -u USERNAME          Red Hat username (optional, can use RH_USERNAME env var)"
    echo "  -p PASSWORD          Red Hat password (optional, can use RH_PASSWORD env var)"
    echo "  -c CREDENTIALS_FILE  Path to credentials file (optional)"
    echo "  -h                   Show this help message"
    echo ""
    echo "Credential Priority (first found is used):"
    echo "  1. Command line options (-u/-p)"
    echo "  2. Environment variables (RH_USERNAME/RH_PASSWORD)"
    echo "  3. Credentials file specified with -c"
    echo "  4. Default credentials file (~/.rh-credentials)"
    echo "  5. Interactive user input (if none of the above are set)"
    echo ""
    echo "Examples:"
    echo "  # Using environment variables (recommended)"
    echo "  export RH_USERNAME=myuser"
    echo "  export RH_PASSWORD=mypassword"
    echo "  $0"
    echo ""
    echo "  # Using credentials file"
    echo "  echo 'myuser' > ~/.rh-credentials"
    echo "  echo 'mypassword' >> ~/.rh-credentials"
    echo "  $0"
    echo ""
    echo "  # Using command line (less secure)"
    echo "  $0 -u myuser -p mypassword"
    echo ""
    echo "  # Interactive input (will prompt for credentials)"
    echo "  $0"
    exit 1
}

while getopts "a:s:e:u:p:c:h" opt; do
    case $opt in
        a)
            ARCH="$OPTARG"
            ;;
        e)
            ENTITLEMENTS_DIR="$OPTARG"
            ;;
        u)
            USERNAME="$OPTARG"
            ;;
        p)
            PASSWORD="$OPTARG"
            ;;
        c)
            CREDENTIALS_FILE="$OPTARG"
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

# Auto-detect architecture if not specified
if [ -z "$ARCH" ]; then
    ARCH=$(detect_arch)
    ARCH_SOURCE="auto-detected"
else
    ARCH_SOURCE="specified"
fi

read_credentials_file() {
    local file="$1"
    if [ -f "$file" ]; then
        USERNAME=$(sed -n '1p' "$file" | tr -d '\r\n')
        PASSWORD=$(sed -n '2p' "$file" | tr -d '\r\n')
        return 0
    fi
    return 1
}

CREDENTIAL_SOURCE=""

# Credential priority: 
# 1. Command line > 2. Environment variables > 3. Credentials file > 4. Default credentials file > 5. User input
if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    CREDENTIAL_SOURCE="command line"
elif [ -n "$RH_USERNAME" ] && [ -n "$RH_PASSWORD" ]; then
    USERNAME="$RH_USERNAME"
    PASSWORD="$RH_PASSWORD"
    CREDENTIAL_SOURCE="environment variables"
elif [ -n "$CREDENTIALS_FILE" ] && read_credentials_file "$CREDENTIALS_FILE"; then
    CREDENTIAL_SOURCE="credentials file: $CREDENTIALS_FILE"
elif read_credentials_file "$HOME/.rh-credentials"; then
    CREDENTIAL_SOURCE="default credentials file: $HOME/.rh-credentials"
else
    # If no credentials found through any of the above methods, prompt user
    prompt_for_credentials
fi

# Final validation (this should not be needed anymore, but kept as safeguard)
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Error: Red Hat credentials are required but could not be obtained."
    echo "This should not happen - please check the script logic."
    exit 1
fi

ENTITLEMENTS_DIR="${ENTITLEMENTS_DIR/#\~/$HOME}"

echo "Checking entitlements"
echo "---------------------"
echo "Architecture: $ARCH ($ARCH_SOURCE)"
echo "Entitlements directory for $ARCH: ${ENTITLEMENTS_DIR}/${ARCH}"
echo "Username: $USERNAME"
echo "Using credentials from $CREDENTIAL_SOURCE"
echo "---------------------"
echo ""

if [ ! -d "${ENTITLEMENTS_DIR}/${ARCH}" ]; then
    echo "Creating entitlement directory for ${ARCH}"
    mkdir -p ${ENTITLEMENTS_DIR}/${ARCH}
fi

# Check if entitlements already exist
if [ -d "${ENTITLEMENTS_DIR}/${ARCH}" ] && find "${ENTITLEMENTS_DIR}/${ARCH}" -mindepth 1 -maxdepth 1 -type f | grep -q .; then
    echo "Entitlements already exist for $ARCH."
    
    read -p "Do you want to delete the existing entitlements and continue? (y/N): " choice
    case "$choice" in
        [yY][eE][sS]|[yY])
            echo "Deleting existing entitlements..."
            rm -rf "${ENTITLEMENTS_DIR:?}/${ARCH}"
            ;;
        *)
            echo "Exiting."
            exit 0
            ;;
    esac
fi

# Registry login
if podman login --get-login "${SUBS_FROM%%/*}" &>/dev/null; then
  echo "Already logged in to ${SUBS_FROM%%/*} as $(podman login --get-login "${SUBS_FROM%%/*}")"
else
  echo "Not logged in to ${SUBS_FROM%%/*}. Logging in..."
  podman login -u "$USERNAME" -p "$PASSWORD" "${SUBS_FROM%%/*}"
fi

echo "Enabling binfmt_misc for cross-arch builds..."
podman run --rm --privileged docker.io/multiarch/qemu-user-static --reset -p yes 2>/dev/null \
    || echo "binfmt setup completed (some handlers may have already existed)"

echo "Getting entitlements for $ARCH..."

# Check if the container image already exists and remove it
if podman images --quiet "local-$ARCH" | grep -q .; then
    echo "Container image local-$ARCH already exists, removing it..."
    podman rmi -f "local-$ARCH"
fi

cat <<EOF > Containerfile.subs
FROM $SUBS_FROM
ARG RH_USERNAME=""
ARG RH_PASSWORD=""
RUN if [ -n "\$RH_USERNAME" ] && [ -n "\$RH_PASSWORD" ]; then \
    echo "Registering with Red Hat subscription manager..."  && rm -rf /etc/rhsm-host && subscription-manager register --username "\$RH_USERNAME" --password "\$RH_PASSWORD" | tee /tmp/register_output && echo \$(grep -o 'ID: [a-f0-9-]*' /tmp/register_output | cut -d' ' -f2) > /etc/rhsm/system_id && echo \$(grep -o 'system name is: [a-f0-9-]*' /tmp/register_output | cut -d' ' -f4) > /etc/rhsm/host_id && rm -f /tmp/register_output ; \
    else \
    echo "Red Hat credentials not found; skipping subscription registration."; \
    fi
RUN dnf -y --nogpgcheck install curl jq && dnf clean all
RUN mkdir -p /entitlements/etc-pki-entitlement &&  mkdir -p /entitlements/rhsm && \ 
      cp -a /etc/pki/entitlement/* /entitlements/etc-pki-entitlement &&  cp -a /etc/rhsm/* /entitlements/rhsm && \
      awk '/-appstream-/' RS= ORS="\n\n" /etc/yum.repos.d/redhat.repo >> /entitlements/redhat.repo && awk '/-baseos-/' RS= ORS="\n\n" /etc/yum.repos.d/redhat.repo >> /entitlements/redhat.repo
RUN if [ -n "\$RH_USERNAME" ] && [ -n "\$RH_PASSWORD" ]; then \
    echo "Unregistering from Red Hat Cloud inventory..." && for uuid in \$(curl -s -u "\$RH_USERNAME:\$RH_PASSWORD" "https://cloud.redhat.com/api/inventory/v1/hosts?fqdn=\$(cat /etc/rhsm/host_id)" | grep -o '"id":"[^"]*' | grep -o '[^"]*\$') ; do curl -u "\$RH_USERNAME:\$RH_PASSWORD" -X DELETE "https://cloud.redhat.com/api/inventory/v1/hosts/\$uuid" -H  "accept: */*" ;done && subscription-manager unregister && subscription-manager clean && ln -s /run/secrets/rhsm /etc/rhsm-host; \
    else \
    echo "Red Hat credentials not found; skipping subscription clean-up."; \
    fi
EOF

echo "Building entitlement container for $ARCH..."
mkdir -p entitlements/$ARCH

podman build -f Containerfile.subs \
    --build-arg RH_USERNAME="$USERNAME" \
    --build-arg RH_PASSWORD="$PASSWORD" \
    --platform "linux/$ARCH" \
    --no-cache \
    -t "local-$ARCH" .

CONTAINER_ID=$(podman create "local-$ARCH")
podman cp "${CONTAINER_ID}:/entitlements/." "entitlements/$ARCH/"
podman rm "${CONTAINER_ID}"
podman rmi "local-$ARCH"

mkdir -p "${ENTITLEMENTS_DIR}/${ARCH}"
cp -r "entitlements/$ARCH"/* "${ENTITLEMENTS_DIR}/${ARCH}"

echo "Entitlements gathered for $ARCH:"
ls -la "${ENTITLEMENTS_DIR}/${ARCH}"

# Clean up temporary files
rm -f Containerfile.subs
rm -rf entitlements
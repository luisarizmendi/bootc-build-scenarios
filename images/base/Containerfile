FROM registry.redhat.io/rhel9/rhel-bootc:9.6

## Install base packages
RUN dnf -y install tmux python3-pip && \
    pip3 install podman-compose && \
    dnf clean all

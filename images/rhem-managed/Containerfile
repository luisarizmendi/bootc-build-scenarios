FROM registry.redhat.io/rhel9/rhel-bootc:9.6

RUN dnf -y copr enable @redhat-et/flightctl && \
    dnf -y install flightctl-agent && \
    dnf -y clean all && \
    systemctl enable flightctl-agent.service && \
    systemctl mask bootc-fetch-apply-updates.timer

# Optional: To enable podman-compose application support, uncomment below
 RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
     dnf -y install podman-compose && \
     dnf -y clean all && \
     rm -rf /var/{cache,log} /var/lib/{dnf,rhsm} && \
     systemctl enable podman.service

ADD config.yaml /etc/flightctl/

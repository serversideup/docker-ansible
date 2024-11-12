ARG BUILD_PYTHON_VERSION='3.12'
ARG BUILD_BASE_OS_VERSION='bullseye'

FROM python:${BUILD_PYTHON_VERSION}-${BUILD_BASE_OS_VERSION}

ARG BUILD_ANSIBLE_VARIATION=''
ARG BUILD_ANSIBLE_PATCH_VERSION=''
ARG PACKAGE_DEPENDENCIES=''
ARG PUID='1000'
ARG PGID='1000'
ARG REPOSITORY_BUILD_VERSION='dev'

ENV DEBUG=false \
    ANSIBLE_WORK_DIR=/ansible \
    ANSIBLE_HOME=/etc/ansible \
    ANSIBLE_COLLECTIONS_PATH=/etc/ansible/collections

COPY --chown=root:root --chmod=755 src/rootfs /

# Install dependencies based on OS
RUN serversideup-dep-install-alpine ${PACKAGE_DEPENDENCIES} && \
    serversideup-dep-install-debian ${PACKAGE_DEPENDENCIES} && \
    \
    # Install YQ based on OS and architecture
    ARCH=$(uname -m) && \
    if [ "${ARCH}" = "x86_64" ]; then \
        YQ_BINARY="yq_linux_amd64"; \
    elif [ "${ARCH}" = "aarch64" ]; then \
        YQ_BINARY="yq_linux_arm64"; \
    else \
        echo "Unsupported architecture: ${ARCH}"; \
        exit 1; \
    fi && \
    if [ -f /etc/alpine-release ]; then \
        wget https://github.com/mikefarah/yq/releases/latest/download/${YQ_BINARY} -O /usr/bin/yq && \
        chmod +x /usr/bin/yq; \
    else \
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/${YQ_BINARY} && \
        chmod a+x /usr/local/bin/yq; \
    fi && \
    \
    # Create Ansible user and group
    serversideup-create-unprivileged-user ansible "${PUID}" "${PGID}" && \
    \
    # Create Ansible home directory, Ansible temp directory, and set default hosts file
    mkdir -p "${ANSIBLE_HOME}/tmp" && \
    echo -e '[local]\nlocalhost ansible_host=127.0.0.1' > "${ANSIBLE_HOME}/hosts" && \
    chown -R "${PUID}:${PGID}" "${ANSIBLE_HOME}" && \
    chmod 1777 "${ANSIBLE_HOME}/tmp" && \
    \
    # Create default Ansible working directory and set permissions
    mkdir -p "${ANSIBLE_WORK_DIR}" && \
    chown -R "${PUID}:${PGID}" "${ANSIBLE_WORK_DIR}" && \
    \
    # Create SSH directory for unprivileged user symbolic link target
    mkdir -p /ssh && \
    chmod 700 /ssh && \
    chown "${PUID}:${PGID}" /ssh && \
    ln -s /ssh /home/ansible/.ssh && \
    \
    # Install Ansible and additional dependencies
    echo "🤓 Installing ${BUILD_ANSIBLE_VARIATION}==${BUILD_ANSIBLE_PATCH_VERSION}" && \
    pip3 install --no-cache-dir "${BUILD_ANSIBLE_VARIATION}==${BUILD_ANSIBLE_PATCH_VERSION}" && \
    pip3 install --no-cache-dir ansible-lint passlib requests python-dateutil && \
    \
    # Verify Ansible installation
    ansible --version

LABEL org.opencontainers.image.title="serversideup/${BUILD_ANSIBLE_VARIATION}" \
    org.opencontainers.image.description="Run Ansible anywhere with a lightweight and powerful Docker image" \
    org.opencontainers.image.url="https://github.com/serversideup/docker-ansible" \
    org.opencontainers.image.source="https://github.com/serversideup/docker-ansible" \
    org.opencontainers.image.documentation="https://github.com/serversideup/docker-ansible" \
    org.opencontainers.image.vendor="ServerSideUp" \
    org.opencontainers.image.authors="Jay Rogers (@jaydrogers)" \
    org.opencontainers.image.version="${REPOSITORY_BUILD_VERSION}" \
    org.opencontainers.image.licenses="GPL-3.0-or-later"

ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /ansible

CMD ["ansible-playbook", "--version"]
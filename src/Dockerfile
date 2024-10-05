ARG PYTHON_VERSION='3.12'
ARG BASE_OS_VERSION='bullseye'

FROM python:${PYTHON_VERSION}-${BASE_OS_VERSION}

ARG ANSIBLE_VARIATION=''
ARG ANSIBLE_VERSION=''
ARG PACKAGE_DEPENDENCIES=''
ARG PUID='1000'
ARG PGID='1000'

ENV DEBUG=false \
    ANSIBLE_WORK_DIR=/ansible \
    ANSIBLE_HOME=/etc/ansible \
    ANSIBLE_COLLECTIONS_PATH=/etc/ansible/collections

COPY --chown=root:root --chmod=755 src/rootfs /

# Install dependencies based on OS
RUN serversideup-dep-install-alpine ${PACKAGE_DEPENDENCIES} && \
    serversideup-dep-install-debian ${PACKAGE_DEPENDENCIES} && \
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
    # Install Ansible
    echo "🤓 Installing ${ANSIBLE_VARIATION}==${ANSIBLE_VERSION}" && \
    pip3 install --no-cache-dir "${ANSIBLE_VARIATION}==${ANSIBLE_VERSION}" && \
    \
    # Verify Ansible installation
    ansible --version

ENTRYPOINT ["/entrypoint.sh"]

WORKDIR /ansible

CMD ["ansible-playbook", "--version"]
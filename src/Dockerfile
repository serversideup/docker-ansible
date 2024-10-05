ARG PYTHON_VERSION='3.12'
ARG BASE_OS_VERSION='bullseye'

FROM python:${PYTHON_VERSION}-${BASE_OS_VERSION}

ARG ANSIBLE_VARIATION=''
ARG ANSIBLE_VERSION=''
ARG PACKAGE_DEPENDENCIES=''

ENV DEBUG=false \
    ANSIBLE_WORK_DIR=/ansible \
    ANSIBLE_HOME=/etc/ansible

COPY --chown=root:root --chmod=755 src/rootfs /

# Install dependencies based on OS
RUN /usr/bin/local/serversideup-dep-install-alpine ${PACKAGE_DEPENDENCIES} && \
    /usr/bin/local/serversideup-dep-install-debian ${PACKAGE_DEPENDENCIES} && \
    \
    # Create default Ansible working directory
    mkdir -p "${ANSIBLE_WORK_DIR}" && \
    chmod 1777 "${ANSIBLE_WORK_DIR}" && \
    \
    # Create default default Ansible config directory and tmp directory
    mkdir -p "${ANSIBLE_HOME}/tmp" && \
    chmod 1777 "${ANSIBLE_HOME}" && \
    chmod 1777 "${ANSIBLE_HOME}/tmp" && \
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
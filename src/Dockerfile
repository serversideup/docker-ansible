# First stage to declare global ARGs
ARG PYTHON_VERSION
ARG BASE_OS_VERSION

# Main build stage
FROM python:${PYTHON_VERSION}-${BASE_OS_VERSION}

# Redeclare ARGs after FROM for this stage
ARG PYTHON_VERSION
ARG BASE_OS_VERSION
ARG ANSIBLE_VARIATION
ARG ANSIBLE_VERSION
ARG PACKAGE_DEPENDENCIES

COPY --chown=root:root --chmod=755 src/rootfs /

# Install dependencies based on OS
RUN /usr/bin/local/serversideup-dep-install-alpine ${PACKAGE_DEPENDENCIES} && \
    /usr/bin/local/serversideup-dep-install-debian ${PACKAGE_DEPENDENCIES}

# Install Ansible
RUN pip3 install ${ANSIBLE_VARIATION}==${ANSIBLE_VERSION}

CMD ["ansible-playbook", "--version"]
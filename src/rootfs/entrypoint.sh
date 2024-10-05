#!/bin/sh
set -e
if [ "$DEBUG" = "true" ]; then
    set -x
fi

USER_ID=$(id -u)
GROUP_ID=$(id -g)

debug_print() {
    if [ "$DEBUG" = "true" ]; then
        echo "$1"
    fi
}

debug_print "Running as $USER_ID:$GROUP_ID..."

if [ "$USER_ID" -ne 0 ]; then
    debug_print "Preparing environment for $USER_ID:$GROUP_ID..."
    HOME=/tmp/$USER_ID
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    export HOME
    debug_print "HOME directory set to $HOME"
fi

# Set default inventory file
echo -e '[local]\nlocalhost ansible_host=127.0.0.1' > "${ANSIBLE_HOME}/hosts"

exec "$@"
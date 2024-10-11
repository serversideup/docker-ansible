#!/bin/sh
set -e
default_uid='1000'
default_gid='1000'
default_unprivileged_user='ansible'
run_as_user=${RUN_AS_USER:-"${default_unprivileged_user}"}

if [ "$DEBUG" = "true" ]; then
    set -x
fi

######################################################
# Functions
######################################################

debug_print() {
    if [ "$DEBUG" = "true" ]; then
        echo "$1"
    fi
}

switch_user() {
    if command -v su-exec >/dev/null 2>&1; then
        exec su-exec "$run_as_user" "$@"
    else
        exec gosu "$run_as_user" "$@"
    fi
}

######################################################
# Main
######################################################

# Rename the Ansible user if it doesn't match the default
if [ "$run_as_user" != "$default_unprivileged_user" ]; then

    debug_print "Renaming user \"$default_unprivileged_user\" to \"$run_as_user\"..."

    # Check if we're on Alpine or Debian
    if [ -f /etc/alpine-release ] || [ -f /etc/debian_version ]; then
        # Rename user and group
        usermod -l "$run_as_user" "$default_unprivileged_user" || { echo "Failed to rename user"; exit 1; }
        groupmod -n "$run_as_user" "$default_unprivileged_user" || { echo "Failed to rename group"; exit 1; }
        
        # Update home directory and move contents to new home directory
        usermod -d "/home/$run_as_user" -m "$run_as_user" || { echo "Failed to update home directory"; exit 1; }
        
        if [ -f /etc/debian_version ]; then
            # Update default group for Debian-based systems
            usermod -g "$run_as_user" "$run_as_user" || { echo "Failed to update default group"; exit 1; }
        fi
        
        debug_print "User and group renamed successfully. Home directory updated."
    else
        echo "Unsupported distribution for renaming user."
        exit 1
    fi

    # Create a symbolic link to mimic macOS home folder
    mkdir -p "/Users"
    ln -s "/home/$run_as_user" "/Users/$run_as_user"
fi

# Change the Ansible user and group to the specified UID and GID if they are not the default
if { [ ! -z "${PUID}" ] && [ "${PUID}" != "$default_uid" ]; } || { [ ! -z "${PGID}" ] && [ "${PGID}" != "$default_gid" ]; }; then
    debug_print "Preparing environment for $PUID:$PGID..."
    
    # Handle existing user with the same UID
    if id -u "${PUID}" >/dev/null 2>&1; then
        old_user=$(id -nu "${PUID}")
        debug_print "UID ${PUID} already exists for user ${old_user}. Moving to a new UID."
        usermod -u "999${PUID}" "${old_user}"
    fi

    # Handle existing group with the same GID
    if getent group "${PGID}" >/dev/null 2>&1; then
        old_group=$(getent group "${PGID}" | cut -d: -f1)
        debug_print "GID ${PGID} already exists for group ${old_group}. Moving to a new GID."
        groupmod -g "999${PGID}" "${old_group}"
    fi

    # Change UID and GID of  run_as user and group
    usermod -u "${PUID}" "${run_as_user}" 2>&1 >/dev/null || echo "Error changing user ID."
    groupmod -g "${PGID}" "${run_as_user}" 2>&1 >/dev/null || echo "Error changing group ID."

    debug_print "Changing ownership of all files and directories..."
    chown "${PUID}:${PGID}" "/home/${run_as_user}" "${ANSIBLE_HOME}"

fi

if [ "$SSH_AUTH_SOCK" ]; then
    debug_print "Creating a symbolic link to the SSH Agent socket in the 1Password directory..."
    mkdir -p "/home/${run_as_user}/Library/Group Containers/2BUA8C4S2C.com.1password/t"
    ln -sf "$SSH_AUTH_SOCK" "/home/${run_as_user}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
fi

# Run the command as the unprivileged user if PUID, PGID are set, or if RUN_AS_USER is different from default
if [ ! -z "${PUID}" ] || [ ! -z "${PGID}" ] || [ "$run_as_user" != "$default_unprivileged_user" ]; then
    if [ "$SSH_AUTH_SOCK" ]; then
        debug_print "Ensure the SSH_AUTH_SOCK has the correct permissions..."
        chown "${PUID}:${PGID}" "$SSH_AUTH_SOCK"
    fi
    debug_print "Running command as \"$run_as_user\"..."
    switch_user "$@"
else
    debug_print "Running command as root..."
    exec "$@"
fi
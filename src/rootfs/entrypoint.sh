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

    # Change UID and GID of Ansible user and group
    usermod -u "${PUID}" ansible 2>&1 >/dev/null || echo "Error changing user ID."
    groupmod -g "${PGID}" ansible 2>&1 >/dev/null || echo "Error changing group ID."

    debug_print "Changing ownership of all files and directories..."
    chown "${PUID}:${PGID}" "/home/${default_unprivileged_user}" "/home/${default_unprivileged_user}/.ssh" "${ANSIBLE_HOME}" "/ssh"
    
fi

# Rename the Ansible user if it doesn't match the default
if [ "$run_as_user" != "$default_unprivileged_user" ]; then

    debug_print "Renaming user \"$default_unprivileged_user\" to \"$run_as_user\"..."
    
    # Check if we're on Alpine or Debian
    if [ -f /etc/alpine-release ]; then
        # Alpine Linux
        usermod -l "$run_as_user" "$default_unprivileged_user"
        groupmod -n "$run_as_user" "$default_unprivileged_user"
        
        # Update home directory and move contents to new home directory
        usermod -d "/home/$run_as_user" -m "$run_as_user"
    elif [ -f /etc/debian_version ]; then
        # Debian
        usermod -l "$run_as_user" "$default_unprivileged_user"
        groupmod -n "$run_as_user" "$default_unprivileged_user"
        
        # Update home directory and move contents to new home directory
        usermod -d "/home/$run_as_user" -m "$run_as_user"
        
        # Update default group
        usermod -g "$run_as_user" "$run_as_user"
    else
        echo "Unsupported distribution. User renaming skipped."
    fi

    # Create a symbolic link to mimic macOS home folder
    mkdir -p "/Users"
    ln -s "/home/$run_as_user" "/Users/$run_as_user"

fi

# Run the command as the unprivileged user if PUID, PGID are set, or if RUN_AS_USER is different from default
if [ ! -z "${PUID}" ] || [ ! -z "${PGID}" ] || [ "$run_as_user" != "$default_unprivileged_user" ]; then
    debug_print "Running command as \"$run_as_user\"..."
    switch_user "$@"
else
    debug_print "Running command as root..."
    exec "$@"
fi


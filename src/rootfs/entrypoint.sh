#!/bin/sh
set -e
default_uid='1000'
default_gid='1000'
default_unprivileged_user='ansible'

if [ "$DEBUG" = "true" ]; then
    set -x
fi

debug_print() {
    if [ "$DEBUG" = "true" ]; then
        echo "$1"
    fi
}

switch_user() {
    if command -v su-exec >/dev/null 2>&1; then
        exec su-exec "$default_unprivileged_user" "$@"
    else
        exec gosu "$default_unprivileged_user" "$@"
    fi
}

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
    # Change all files and directories owned by user 1000 or group 1000 to the new user and group
    find / \( -user "$default_uid" -o -group "$default_gid" \) -exec chown -h "${PUID}:${PGID}" {} + 2>/dev/null || echo "Error changing ownership of files and directories."

    # Update user's home directory permissions
    chown -R "${PUID}:${PGID}" "/home/${default_unprivileged_user}"
fi

# Run the command as the unprivileged user if PUID and PGID are set
if [ ! -z "${PUID}" ] || [ ! -z "${PGID}" ]; then
    debug_print "Running command as $default_unprivileged_user..."
    switch_user "$@"
else
    debug_print "Running command as root..."
    exec "$@"
fi
#!/bin/bash

unmount_samba_share() {
    local mount_point="$1"
    echo "Unmounting Samba share..."
    if umount "$mount_point"; then
        echo "Samba share unmounted successfully."
    else
        echo "Failed to unmount Samba share."
    fi
}

call_backup_script() {
    local backup_script="$1"
    local mount_point="$2"
    local backup_script_args=("${@:3}")
    echo "Calling $backup_script..."
    if [ -x "$backup_script" ]; then
        "$backup_script" "$mount_point" "${backup_script_args[@]}"
    else
        echo "Error: $backup_script is not executable or does not exist."
        unmount_samba_share "$mount_point"
        exit 1
    fi
}

mount_samba_share() {
    local samba_server="$1"
    local samba_share="$2"
    local mount_point="$3"
    local creds_file="$4"
    local backup_script="$5"
    local backup_script_args=("${@:6}")

    echo "Mounting Samba share..."
    if mount -t cifs -o credentials="$creds_file",rw,noatime "//""$samba_server"/"$samba_share" "$mount_point"; then
        echo "Samba share mounted successfully."
        call_backup_script "$backup_script" "$mount_point" "${backup_script_args[@]}"
        unmount_samba_share "$mount_point"
    else
        echo "Failed to mount Samba share. Check credentials file, server/share name, and permissions."
    fi
}

if [ $# -lt 3 ]; then
    echo "Usage: $0 <server> <share> <mount point> [<optional arguments for backup script>]"
    exit 1
fi

CREDS_FILE="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.smbcreds"
if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: Credentials file not found at $CREDS_FILE"
    exit 1
fi

mount_samba_share "$1" "$2" "$3" "$CREDS_FILE" "$(dirname "${BASH_SOURCE[0]}")/docker_volume_backup.sh" "${@:4}"
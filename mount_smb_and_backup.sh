#!/bin/bash

usage() {
    echo "Usage: $0 <server> <share> <mount_point> [<optional_backup_args...>]"
    echo
    echo "Mounts a Samba (CIFS) share, runs the Docker volume backup script, and then unmounts it."
    echo
    echo "Arguments:"
    echo "  <server>                   The IP address or hostname of the Samba server."
    echo "  <share>                    The name of the share on the server."
    echo "  <mount_point>              The local directory to mount the share onto."
    echo "  [<optional_backup_args...>] All subsequent arguments are passed directly to the backup script."
    echo
    echo "Credentials:"
    echo "  This script requires a '.smbcreds' file in its directory with the format:"
    echo "  username=your_username"
    echo "  password=your_password"
    echo
    echo "Example:"
    echo "  $0 192.168.1.50 /backups /mnt/smb-backups --encrypt"
}

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
        echo "$backup_script is not executable or does not exist." >&2
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
        echo "Failed to mount Samba share. Check credentials file, server/share name, and permissions." >&2
        exit 1
    fi
}

if [ $# -lt 3 ]; then
    usage
    exit 1
fi

CREDS_FILE="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.smbcreds"
if [ ! -f "$CREDS_FILE" ]; then
    echo "Credentials file not found at $CREDS_FILE" >&2
    usage
    exit 1
fi

mount_samba_share "$1" "$2" "$3" "$CREDS_FILE" "$(dirname "${BASH_SOURCE[0]}")/docker_volume_backup.sh" "${@:4}"
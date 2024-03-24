#!/bin/bash

unmount_nfs_share() {
    local mount_point="$1"

    echo "Unmounting NFS share..."
    if umount "$mount_point"; then
        echo "NFS share unmounted successfully."
    else
        echo "Failed to unmount NFS share."
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
        unmount_nfs_share "$mount_point"
        exit 1
    fi
}

mount_nfs_share() {
    local nfs_server="$1"
    local nfs_share="$2"
    local mount_point="$3"
    local backup_script="$4"
    local backup_script_args=("${@:5}")

    echo "Mounting NFS share..."
    if mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 "$nfs_server:$nfs_share" "$mount_point"; then
        echo "NFS share mounted successfully."
        call_backup_script "$backup_script" "$mount_point" "${backup_script_args[@]}"
        unmount_nfs_share "$mount_point"
    else
        echo "Failed to mount NFS share."
    fi
}

if [ $# -lt 3 ]; then
    echo "Usage: $0 <server> <share> <mount point> [<skip containers>]"
    exit 1
fi

mount_nfs_share "$1" "$2" "$3" "$(dirname "${BASH_SOURCE[0]}")/docker_volume_backup.sh" "${@:4}"

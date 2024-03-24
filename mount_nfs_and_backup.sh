#!/bin/bash

mount_nfs_share() {
    local nfs_server="$1"
    local nfs_share="$2"
    local mount_point="$3"

    echo "Mounting NFS share..."
    if mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 "$nfs_server:$nfs_share" "$mount_point"; then
        echo "NFS share mounted successfully."
        return 0
    else
        echo "Failed to mount NFS share."
        return 1
    fi
}

execute_backup_script() {
    local backup_script="$1"
    local mount_point="$2"
    shift 2
    local backup_script_args=("$@")

    echo "Calling $backup_script..."
    if [ -x "$backup_script" ]; then
        "$backup_script" "$mount_point" "${backup_script_args[@]}"
    else
        echo "Error: $backup_script is not executable or does not exist."
        exit 1
    fi
}

unmount_nfs_share() {
    local mount_point="$1"

    echo "Unmounting NFS share..."
    if umount "$mount_point"; then
        echo "NFS share unmounted successfully."
    else
        echo "Failed to unmount NFS share."
    fi
}

mount_and_backup() {
    local nfs_server="$1"
    local nfs_share="$2"
    local mount_point="$3"
    local backup_script="$4"
    shift 4
    local backup_script_args=("$@")

    if mount_nfs_share "$nfs_server" "$nfs_share" "$mount_point"; then
        execute_backup_script "$backup_script" "$mount_point" "${backup_script_args[@]}"
        unmount_nfs_share "$mount_point"
    fi
}

if [ $# -lt 3 ]; then
    echo "Usage: $0 <server> <share> <mount point> [<skip containers>]"
    exit 1
fi

mount_and_backup "$@"

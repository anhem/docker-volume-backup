#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ $# -ne 3 ]; then
    echo "Usage: $0 <server> <share> <mount point>"
    exit 1
fi

NFS_SERVER="$1"
NFS_SHARE="$2"
MOUNT_POINT="$3"
BACKUP_SCRIPT="$SCRIPT_DIR/docker_volume_backup.sh"

echo "Mounting NFS share..."
if mount -t nfs "$NFS_SERVER:$NFS_SHARE" "$MOUNT_POINT"; then
    echo "NFS share mounted successfully."

    echo "Calling $BACKUP_SCRIPT ..."
    if [ -x "$BACKUP_SCRIPT" ]; then
        "$BACKUP_SCRIPT"
    else
        echo "Error: $BACKUP_SCRIPT is not executable or does not exist."
        exit 1
    fi

    echo "Unmounting NFS share..."
    if umount "$MOUNT_POINT"; then
        echo "NFS share unmounted successfully."
    else
        echo "Failed to unmount NFS share."
    fi
else
    echo "Failed to mount NFS share."
fi

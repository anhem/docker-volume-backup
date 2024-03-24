#!/bin/bash

if [ $# -lt 3 ]; then
    echo "Usage: $0 <server> <share> <mount point> [<skip containers>]"
    exit 1
fi

NFS_SERVER="$1"
NFS_SHARE="$2"
MOUNT_POINT="$3"
shift 3
BACKUP_SCRIPT_ARGS=("$@")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BACKUP_SCRIPT="$SCRIPT_DIR/docker_volume_backup.sh"

echo "Mounting NFS share..."
if mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 "$NFS_SERVER:$NFS_SHARE" "$MOUNT_POINT"; then
    echo "NFS share mounted successfully."

    echo "Calling $BACKUP_SCRIPT ..."
    if [ -x "$BACKUP_SCRIPT" ]; then
        "$BACKUP_SCRIPT" "$MOUNT_POINT" "${BACKUP_SCRIPT_ARGS[@]}"
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

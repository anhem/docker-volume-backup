#!/bin/bash

set -e
trap 'echo "🔥 An error occurred. Aborting."; exit 1' ERR

usage() {
    echo "Usage: $0 <smb|nfs> <notify url> [arguments_for_mount_script...]"
    echo
    echo "This script acts as a controller to run a backup and then call a notify url."
    echo
    echo "Arguments:"
    echo "  <smb|nfs>                  The protocol to use for mounting the backup share."
    echo "  <notify url>               The full URL to call when done."
    echo "  [args...]                  All subsequent arguments are passed directly to the corresponding mount script."
    echo
    echo "Examples:"
    echo "  NFS:"
    echo "    $0 nfs 'http://kuma.example.com/api/push/xyz?status=up&msg=OK' 192.168.1.100 /exports/backups /mnt/backups --skip-volumes=portainer_data"
    echo
    echo "  SMB:"
    echo "    $0 smb 'http://kuma.example.com/api/push/abc?status=up&msg=OK' //fileserver/backups /mnt/smb_backups --use-restic"
}

if [ "$#" -lt 2 ]; then
    echo "Insufficient arguments." >&2
    usage
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MOUNT_NFS_SCRIPT="$SCRIPT_DIR/mount_nfs_and_backup.sh"
MOUNT_SMB_SCRIPT="$SCRIPT_DIR/mount_smb_and_backup.sh"

PROTOCOL=$(echo "$1" | tr '[:upper:]' '[:lower:]')
NOTIFY_URL="$2"

shift 2
MOUNT_SCRIPT_ARGS=("$@")

BACKUP_EXIT_CODE=0

case "$PROTOCOL" in
    smb)
        echo "--- Starting backup via SMB ---"
        if ! "$MOUNT_SMB_SCRIPT" "${MOUNT_SCRIPT_ARGS[@]}"; then
            BACKUP_EXIT_CODE=$?
            echo "🔥 SMB backup script failed with exit code $BACKUP_EXIT_CODE." >&2
        fi
        ;;
    nfs)
        echo "--- Starting backup via NFS ---"
        if ! "$MOUNT_NFS_SCRIPT" "${MOUNT_SCRIPT_ARGS[@]}"; then
            BACKUP_EXIT_CODE=$?
            echo "🔥 NFS backup script failed with exit code $BACKUP_EXIT_CODE." >&2
        fi
        ;;
    *)
        echo "Error: Invalid protocol '$1'. Please use 'smb' or 'nfs'." >&2
        usage
        exit 1
        ;;
esac
echo "--------------------------------------------------"

if [ "$BACKUP_EXIT_CODE" -eq 0 ]; then
    echo "✅ Backup process finished successfully."
    echo "Calling endpoint..."
    if curl -fsS --get "$NOTIFY_URL"; then
        echo "✅ called endpoint successful."
    else
        echo "🔥 Error: Failed to call endpoint." >&2
        exit 2
    fi
else
    echo "🔥 Backup process failed."
fi

exit "$BACKUP_EXIT_CODE"
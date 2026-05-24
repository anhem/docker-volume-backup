#!/bin/bash

usage() {
    echo "Usage: $0 <protocol> <server> <share> <mount_point> <type> [args...]"
    echo
    echo "Performs an integrity check on backups stored on NFS, SMB, or a local directory."
    echo
    echo "Arguments:"
    echo "  <protocol>     'nfs', 'smb', or 'local'"
    echo "  <server>       IP/hostname (use '-' for local)"
    echo "  <share>        Share/Export path (use '-' for local)"
    echo "  <mount_point>  Local directory (where share is mounted or backups are located)"
    echo "  <type>         'restic' or 'gpg'"
    echo "  [args]         Optional arguments:"
    echo "                 - For restic: arguments for 'restic check' (e.g., --read-data)"
    echo "                 - For gpg: the specific filename to check (or leave empty for all .gpg files)"
    echo
    echo "Examples:"
    echo "  $0 nfs 192.168.1.50 /backups /mnt/check restic"
    echo "  $0 smb 192.168.1.50 backups /mnt/check gpg"
    echo "  $0 local - - /home/user/backups restic"
}

if [ "$#" -lt 5 ]; then
    usage
    exit 1
fi

PROTOCOL=$(echo "$1" | tr '[:upper:]' '[:lower:]')
SERVER="$2"
SHARE="$3"
MOUNT_POINT="$4"
CHECK_TYPE=$(echo "$5" | tr '[:upper:]' '[:lower:]')
shift 5
EXTRA_ARGS=("$@")

# Configuration
RESTIC_VERSION="0.18.1"
BUSYBOX_VERSION="1.37.0"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Load environment variables (for BACKUP_PASSWORD)
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
    set +a
fi

unmount_share() {
    if [ "$PROTOCOL" = "local" ]; then
        return 0
    fi

    echo "Unmounting share at $MOUNT_POINT..."
    if umount "$MOUNT_POINT"; then
        echo "Share unmounted successfully."
    else
        echo "Failed to unmount share." >&2
        exit 1
    fi
}

perform_restic_check() {
    echo "Running restic check ${EXTRA_ARGS[*]}..."
    export RESTIC_PASSWORD="$BACKUP_PASSWORD"
    docker run --rm -it \
        -v "$MOUNT_POINT":/repo \
        -e RESTIC_REPOSITORY=/repo \
        -e RESTIC_PASSWORD \
        restic/restic:"$RESTIC_VERSION" check "${EXTRA_ARGS[@]}"
}

perform_gpg_check() {
    local target_file="${EXTRA_ARGS[0]}"
    local overall_success=true
    
    if [ -n "$target_file" ]; then
        if [ ! -f "$MOUNT_POINT/$target_file" ]; then
            echo "Error: File $target_file not found in $MOUNT_POINT" >&2
            return 1
        fi
        echo "Verifying GPG integrity for $target_file..."
        docker run --rm -i \
            -v "$MOUNT_POINT":/backup \
            busybox:"$BUSYBOX_VERSION" \
            sh -c "gpg --decrypt --batch --passphrase-fd 3 /backup/\"$target_file\" | tar -tzf - > /dev/null" 3<<<"$BACKUP_PASSWORD"
    else
        echo "Searching for all .gpg files in $MOUNT_POINT..."
        local found=false
        for f in "$MOUNT_POINT"/*.tar.gz.gpg; do
            [ -e "$f" ] || continue
            found=true
            local filename=$(basename "$f")
            echo "-> Verifying $filename..."
            if docker run --rm -i \
                -v "$MOUNT_POINT":/backup \
                busybox:"$BUSYBOX_VERSION" \
                sh -c "gpg --decrypt --batch --passphrase-fd 3 /backup/\"$filename\" | tar -tzf - > /dev/null" 3<<<"$BACKUP_PASSWORD"; then
                echo "   ✅ $filename is valid."
            else
                echo "   ❌ $filename is CORRUPT or password incorrect." >&2
                overall_success=false
            fi
        done
        
        if [ "$found" = false ]; then
            echo "No .gpg files found."
            return 0
        fi

        if [ "$overall_success" = false ]; then
            return 1
        fi
    fi
}

# Main execution
mount_cmd=""
case "$PROTOCOL" in
    local)
        echo "Using local directory: $MOUNT_POINT"
        mount_cmd="true"
        ;;
    nfs)
        echo "Mounting NFS share..."
        mount_cmd="mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 $SERVER:$SHARE $MOUNT_POINT"
        ;;
    smb)
        CREDS_FILE="$SCRIPT_DIR/.smbcreds"
        if [ ! -f "$CREDS_FILE" ]; then
            echo "Error: Credentials file not found at $CREDS_FILE" >&2
            exit 1
        fi
        echo "Mounting Samba share..."
        mount_cmd="mount -t cifs -o credentials=$CREDS_FILE,rw,noatime //$SERVER/$SHARE $MOUNT_POINT"
        ;;
    *)
        echo "Error: Invalid protocol '$PROTOCOL'. Use 'nfs' or 'smb'." >&2
        usage
        exit 1
        ;;
esac

if $mount_cmd; then
    echo "Share mounted successfully."
    
    case "$CHECK_TYPE" in
        restic)
            perform_restic_check
            ;;
        gpg)
            perform_gpg_check
            ;;
        *)
            echo "Error: Invalid check type '$CHECK_TYPE'. Use 'restic' or 'gpg'." >&2
            unmount_share
            exit 1
            ;;
    esac
    
    unmount_share
else
    echo "Error: Failed to mount share." >&2
    exit 1
fi

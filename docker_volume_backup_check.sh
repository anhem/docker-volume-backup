#!/bin/bash

set -e

# Configuration
RESTIC_VERSION="0.18.1"
BUSYBOX_VERSION="1.37.0"

usage() {
    echo "Usage: $0 <mount_point> [OPTIONS]"

}

cleanup() {
    local exit_code=$?
    if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "local" ] && [ -d "$MOUNT_POINT" ] && mountpoint -q "$MOUNT_POINT"; then
        echo "Unmounting $PROTOCOL share at $MOUNT_POINT..."
        if ! umount "$MOUNT_POINT"; then
            echo "Error: Failed to unmount share. It may be busy." >&2
            if [ "$exit_code" -eq 0 ]; then exit_code=1; fi
        fi
    fi
    exit "$exit_code"
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
        # Decrypt on host, test tar inside container
        if gpg --decrypt --batch --passphrase-fd 3 "$MOUNT_POINT/$target_file" 3<<<"$BACKUP_PASSWORD" | \
            docker run --rm -i busybox:"$BUSYBOX_VERSION" tar -tzf - > /dev/null; then
            echo "   ✅ $target_file is valid."
        else
            echo "   ❌ $target_file is CORRUPT or password incorrect." >&2
            return 1
        fi
    else
        echo "Searching for all .gpg files in $MOUNT_POINT..."
        local found=false
        for f in "$MOUNT_POINT"/*.tar.gz.gpg; do
            [ -e "$f" ] || continue
            found=true
            local filename=$(basename "$f")
            echo "-> Verifying $filename..."
            # Decrypt on host, test tar inside container
            if gpg --decrypt --batch --passphrase-fd 3 "$f" 3<<<"$BACKUP_PASSWORD" | \
                docker run --rm -i busybox:"$BUSYBOX_VERSION" tar -tzf - > /dev/null; then
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

# --- Initialization ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

PROTOCOL="local"
SERVER=""
SHARE=""
MOUNT_POINT=""
CHECK_TYPE=""
EXTRA_ARGS=()

# Parse Arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --protocol=*) PROTOCOL=$(echo "${1#*=}" | tr '[:upper:]' '[:lower:]'); shift 1 ;;
        --protocol) PROTOCOL=$(echo "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
        --type=*) CHECK_TYPE=$(echo "${1#*=}" | tr '[:upper:]' '[:lower:]'); shift 1 ;;
        --type) CHECK_TYPE=$(echo "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
        --server=*) SERVER="${1#*=}"; shift 1 ;;
        --server) SERVER="$2"; shift 2 ;;
        --share=*) SHARE="${1#*=}"; shift 1 ;;
        --share) SHARE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) EXTRA_ARGS+=("$1"); shift 1 ;; # For things like --read-data
        *)
            if [ -z "$MOUNT_POINT" ]; then
                MOUNT_POINT=$1
                shift 1
            else
                EXTRA_ARGS+=("$1") # For things like filename
                shift 1
            fi
            ;;
    esac
done

# Validation
if [ -z "$MOUNT_POINT" ]; then echo "Error: Mount point must be specified." >&2; exit 1; fi
if [ -z "$CHECK_TYPE" ]; then echo "Error: --type <restic|gpg> is required." >&2; exit 1; fi

if [ "$PROTOCOL" != "local" ]; then
    if [ -z "$SERVER" ] || [ -z "$SHARE" ]; then
        echo "Error: Remote protocol '$PROTOCOL' requires --server and --share." >&2; exit 1
    fi
    trap cleanup EXIT
fi

if [ -z "$BACKUP_PASSWORD" ]; then
    echo "Error: BACKUP_PASSWORD must be set." >&2; exit 1
fi

# --- Execution ---

# 1. Mounting
if [ "$PROTOCOL" = "nfs" ]; then
    echo "Mounting NFS share..."
    mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 "$SERVER:$SHARE" "$MOUNT_POINT"
elif [ "$PROTOCOL" = "smb" ]; then
    CREDS_FILE="$SCRIPT_DIR/.smbcreds"
    if [ ! -f "$CREDS_FILE" ]; then echo "Error: .smbcreds file not found." >&2; exit 1; fi
    echo "Mounting SMB share..."
    mount -t cifs -o credentials="$CREDS_FILE",rw,noatime "//$SERVER/$SHARE" "$MOUNT_POINT"
fi

# 2. Check
case "$CHECK_TYPE" in
    restic)
        perform_restic_check
        ;;
    gpg)
        perform_gpg_check
        ;;
    *)
        echo "Error: Invalid check type '$CHECK_TYPE'. Use 'restic' or 'gpg'." >&2
        exit 1
        ;;
esac

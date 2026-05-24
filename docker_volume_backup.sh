#!/bin/bash

set -e

# Configuration
BUSYBOX_VERSION="1.37.0"
RESTIC_VERSION="0.18.1"

usage() {
    echo "Usage: $0 <backup_directory_or_restic_repo> [OPTIONS]"
    echo
    echo "Backs up Docker volumes to tar, encrypted tar using GPG or restic."
    echo "Supports automatic mounting of NFS/SMB shares and success notifications."
    echo
    echo "General Options:"
    echo "  --use-restic                         Back up volumes to a restic repository."
    echo "  --retention-policy \"<policy>\"        Apply a restic forget policy after backup. Requires --use-restic."
    echo "  --encrypt                            Encrypt tar archives using GPG."
    echo "  --include-volumes <vol1,...>         Only back up volumes from this comma-separated list."
    echo "  --skip-volumes <vol1,...>            Do not back up any volumes from this comma-separated list."
    echo "  --include-containers <cont1,...>     Only use containers from this list to perform the backup."
    echo "  --skip-containers <cont1,...>        Do not use these containers to perform the backup."
    echo "  --skip-nfs                           Do not back up volumes mounted via NFS."
    echo "  --notify <url>                       Call this URL (via curl) on successful backup."
    echo "  -h, --help                           Display this help message."
    echo
    echo "Remote Storage Options (optional):"
    echo "  --protocol <nfs|smb>                 Mount a remote share before backing up."
    echo "  --server <host>                      Server IP or hostname for the remote share."
    echo "  --share <name>                       Share name (SMB) or export path (NFS)."
    echo
    echo "Password Management:"
    echo "  Set BACKUP_PASSWORD in a '.env' file or as an environment variable."
    echo "  SMB credentials require a '.smbcreds' file in the script directory."
}

cleanup() {
    local exit_code=$?
    if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "local" ] && [ -d "$BACKUP_DIR" ] && mountpoint -q "$BACKUP_DIR"; then
        echo "Unmounting $PROTOCOL share at $BACKUP_DIR..."
        if ! umount "$BACKUP_DIR"; then
            echo "Error: Failed to unmount share. It may be busy." >&2
            if [ "$exit_code" -eq 0 ]; then exit_code=1; fi
        fi
    fi
    exit "$exit_code"
}

is_in_array() {
    local item_to_find=$1
    shift
    local arr=("$@")
    for element in "${arr[@]}"; do
        if [ "$element" = "$item_to_find" ]; then return 0; fi
    done
    return 1
}

get_docker_volume_names() {
    docker volume ls --format '{{.Name}}'
}

get_containers_for_volume() {
    local volume=$1
    docker ps -a --filter "volume=$volume" --format '{{.Names}}'
}

is_nfs_volume() {
    local volume_name=$1
    local volume_type
    volume_type=$(docker volume inspect --format '{{.Options.type}}' "$volume_name" 2>/dev/null)
    [ "$volume_type" = "nfs" ]
}

backup_volumes() {
    local backup_dir="${BACKUP_DIR%/}/"
    local status_message="Backing up Docker volumes to $backup_dir"
    local conditions=()
    if [ "$USE_RESTIC" = true ]; then conditions+=("using restic"); fi
    if [ "$ENCRYPT" = true ]; then conditions+=("with GPG encryption"); fi
    if [ "$SKIP_NFS" = true ]; then conditions+=("skipping NFS volumes"); fi

    if [ ${#conditions[@]} -gt 0 ]; then
        local joined_conditions
        printf -v joined_conditions ' and %s' "${conditions[@]}"
        status_message+=" (${joined_conditions:5})"
    fi
    echo "$status_message"
    echo "--------------------------------------------------"

    for volume in $(get_docker_volume_names); do
        if [ ${#INCLUDE_VOLUMES[@]} -gt 0 ] && ! is_in_array "$volume" "${INCLUDE_VOLUMES[@]}"; then continue; fi
        if is_in_array "$volume" "${SKIP_VOLUMES[@]}"; then
            echo "-> Skipping volume '$volume' as requested."
            continue
        fi
        if [ "$SKIP_NFS" = true ] && is_nfs_volume "$volume"; then
            echo "-> Skipping NFS volume '$volume' as requested."
            continue
        fi

        local backup_performed_for_volume=false
        for container in $(get_containers_for_volume "$volume"); do
            if [ ${#INCLUDE_CONTAINERS[@]} -gt 0 ] && ! is_in_array "$container" "${INCLUDE_CONTAINERS[@]}"; then continue; fi
            if is_in_array "$container" "${SKIP_CONTAINERS[@]}"; then
                echo "-> Skipping container '$container' for volume '$volume' as requested."
                continue
            fi

            local source
            source=$(docker inspect --format '{{range .Mounts}}{{if eq .Name "'"$volume"'"}}{{.Destination}}{{end}}{{end}}' "$container")

            if [ -z "$source" ]; then
                echo "-> WARN: Could not determine source path for volume '$volume' on container '$container'. Skipping."
                continue
            fi

            if [ "$USE_RESTIC" = true ]; then
                echo "-> Backing up '$volume' (from '$source' on '$container') to restic repository..."
                docker run --rm --volumes-from "$container" \
                    -v "$backup_dir":/repo \
                    -e RESTIC_REPOSITORY=/repo \
                    -e RESTIC_PASSWORD="$BACKUP_PASSWORD" \
                    restic/restic:"$RESTIC_VERSION" backup --tag "$volume" --tag "$container" --host "$(hostname)" "$source"
            else
                local backup_file="$volume.tar.gz"
                if [ "$ENCRYPT" = true ]; then
                    echo "-> Backing up and encrypting '$volume' (from '$source' on '$container') to $backup_dir$backup_file.gpg"
                    docker run --rm --volumes-from "$container" busybox:"$BUSYBOX_VERSION" tar -zcf - "$source" | \
                        gpg --batch --yes --passphrase "$BACKUP_PASSWORD" -c -o "$backup_dir$backup_file.gpg"
                else
                    echo "-> Backing up '$volume' (from '$source' on '$container') to $backup_dir$backup_file"
                    docker run --rm --volumes-from "$container" -v "$backup_dir":/backup busybox:"$BUSYBOX_VERSION" tar -zcvf /backup/"$backup_file" "$source"
                fi
            fi
            backup_performed_for_volume=true
            break
        done

        if [ "$backup_performed_for_volume" = false ]; then
            echo "-> INFO: No suitable container found to back up volume '$volume'."
        fi
    done
    echo "--------------------------------------------------"
    echo "✅ Backup process complete."
}

# --- Initialization ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Default Variables
INCLUDE_VOLUMES=()
SKIP_VOLUMES=()
INCLUDE_CONTAINERS=()
SKIP_CONTAINERS=()
SKIP_NFS=false
ENCRYPT=false
USE_RESTIC=false
RETENTION_POLICY=""
BACKUP_DIR=""
PROTOCOL=""
SERVER=""
SHARE=""
NOTIFY_URL=""

# Parse Arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --include-volumes=*) IFS=',' read -r -a INCLUDE_VOLUMES <<< "${1#*=}"; shift 1 ;;
        --include-volumes) IFS=',' read -r -a INCLUDE_VOLUMES <<< "$2"; shift 2 ;;
        --skip-volumes=*) IFS=',' read -r -a SKIP_VOLUMES <<< "${1#*=}"; shift 1 ;;
        --skip-volumes) IFS=',' read -r -a SKIP_VOLUMES <<< "$2"; shift 2 ;;
        --include-containers=*) IFS=',' read -r -a INCLUDE_CONTAINERS <<< "${1#*=}"; shift 1 ;;
        --include-containers) IFS=',' read -r -a INCLUDE_CONTAINERS <<< "$2"; shift 2 ;;
        --skip-containers=*) IFS=',' read -r -a SKIP_CONTAINERS <<< "${1#*=}"; shift 1 ;;
        --skip-containers) IFS=',' read -r -a SKIP_CONTAINERS <<< "$2"; shift 2 ;;
        --retention-policy=*) RETENTION_POLICY="${1#*=}"; shift 1 ;;
        --retention-policy) RETENTION_POLICY="$2"; shift 2 ;;
        --protocol=*) PROTOCOL=$(echo "${1#*=}" | tr '[:upper:]' '[:lower:]'); shift 1 ;;
        --protocol) PROTOCOL=$(echo "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
        --server=*) SERVER="${1#*=}"; shift 1 ;;
        --server) SERVER="$2"; shift 2 ;;
        --share=*) SHARE="${1#*=}"; shift 1 ;;
        --share) SHARE="$2"; shift 2 ;;
        --notify=*) NOTIFY_URL="${1#*=}"; shift 1 ;;
        --notify) NOTIFY_URL="$2"; shift 2 ;;
        --skip-nfs) SKIP_NFS=true; shift 1 ;;
        --encrypt) ENCRYPT=true; shift 1 ;;
        --use-restic) USE_RESTIC=true; shift 1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            if [ -z "$BACKUP_DIR" ] && [ "${1:0:1}" != "-" ]; then
                BACKUP_DIR=$1
                shift 1
            else
                echo "Unknown argument or error: $1" >&2; usage; exit 1
            fi
            ;;
    esac
done

# Validation
if [ -z "$BACKUP_DIR" ]; then echo "Error: Backup directory must be specified." >&2; exit 1; fi
if [ -n "$PROTOCOL" ] && [ "$PROTOCOL" != "local" ]; then
    if [ -z "$SERVER" ] || [ -z "$SHARE" ]; then
        echo "Error: Remote protocol '$PROTOCOL' requires --server and --share." >&2; exit 1
    fi
    trap cleanup EXIT
fi
if { [ "$ENCRYPT" = true ] || [ "$USE_RESTIC" = true ]; } && [ -z "$BACKUP_PASSWORD" ]; then
    echo "Error: Encryption requires BACKUP_PASSWORD." >&2; exit 1
fi

# --- Execution ---

# 1. Mounting
if [ "$PROTOCOL" = "nfs" ]; then
    echo "Mounting NFS share..."
    mount -t nfs -o rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14,nfsvers=4 "$SERVER:$SHARE" "$BACKUP_DIR"
elif [ "$PROTOCOL" = "smb" ]; then
    CREDS_FILE="$SCRIPT_DIR/.smbcreds"
    if [ ! -f "$CREDS_FILE" ]; then echo "Error: .smbcreds file not found." >&2; exit 1; fi
    echo "Mounting SMB share..."
    mount -t cifs -o credentials="$CREDS_FILE",rw,noatime "//$SERVER/$SHARE" "$BACKUP_DIR"
fi

mkdir -p "$BACKUP_DIR"

# 2. Restic Init
if [ "$USE_RESTIC" = true ] && [ ! -f "${BACKUP_DIR%/}/config" ]; then
    echo "Initializing new Restic repository..."
    docker run --rm -v "$BACKUP_DIR":/repo -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD="$BACKUP_PASSWORD" restic/restic:"$RESTIC_VERSION" init
fi

# 3. Perform Backup
backup_volumes

# 4. Restic Retention
if [ "$USE_RESTIC" = true ] && [ -n "$RETENTION_POLICY" ]; then
    echo "Applying retention policy..."
    docker run --rm -v "$BACKUP_DIR":/repo -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD="$BACKUP_PASSWORD" restic/restic:"$RESTIC_VERSION" forget $RETENTION_POLICY --prune
fi

# 5. Notify
if [ -n "$NOTIFY_URL" ]; then
    echo "Calling notification endpoint..."
    curl -fsS --get "$NOTIFY_URL"
    echo "✅ Notification sent."
fi

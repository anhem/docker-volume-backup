#!/bin/bash

SKIP_CONTAINERS=()
BACKUP_DIR="/path/to/backup/docker_volumes"

mkdir -p "$BACKUP_DIR"

for volume in $(docker volume ls --format '{{.Name}}'); do
    container=$(docker ps -a --filter "volume=$volume" --format '{{.Names}}')
    if [[ " ${SKIP_CONTAINERS[@]} " =~ " ${container} " ]]; then
        continue
    fi
    file="/backup/$volume.tar.gz"
    path=$(docker inspect --format '{{range .Mounts}}{{if eq .Name "'"$volume"'"}}{{.Destination}}{{end}}{{end}}' "$container")
    echo backing up $volume from $path on $container to $file
    docker run --rm --volumes-from "$container" -v "$BACKUP_DIR":/backup busybox tar -zcvf "$file" "$path"
done
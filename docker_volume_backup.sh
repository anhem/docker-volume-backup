#!/bin/bash

get_docker_volume_names() {
    docker volume ls --format '{{.Name}}'
}

get_containers_for_volume() {
    local volume=$1
    docker ps -a --filter "volume=$volume" --format '{{.Names}}'
}

should_skip_container() {
    local container_to_skip=$1
    local skip_containers=("${@:2}")

    for skip_container in "${skip_containers[@]}"; do
        if [ "$skip_container" = "$container_to_skip" ]; then
            return 0
        fi
    done

    return 1
}

backup_volumes() {
    local backup_dir="${1%/}/"
    shift
    local skip_containers=("$@")

    if [ ${#skip_containers[@]} -gt 0 ]; then
        echo "Backing up docker volumes to $backup_dir (skipping ${skip_containers[*]})"
    else
        echo "Backing up docker volumes to $backup_dir"
    fi

    for volume in $(get_docker_volume_names); do
        for container in $(get_containers_for_volume "$volume"); do
            if should_skip_container "$container" "${skip_containers[@]}"; then
                continue
            fi
            backup_file="$volume.tar.gz"
            source=$(docker inspect --format '{{range .Mounts}}{{if eq .Name "'"$volume"'"}}{{.Destination}}{{end}}{{end}}' "$container")
            echo "Backing up $volume ($source) on $container to $backup_dir$backup_file"
            docker run --rm --volumes-from "$container" -v "$backup_dir":/backup busybox tar -zcvf /backup/"$backup_file" "$source"
        done
    done
}

if [ -z "$1" ]; then
    echo "Usage: $0 <backup directory> [<skip containers>]"
    exit 1
fi

backup_volumes "$@"

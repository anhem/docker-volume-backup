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
    local skip_containers=("${@:1}")
    local backup_dir="$1"

    for volume in $(get_docker_volume_names); do
        for container in $(get_containers_for_volume "$volume"); do
            if should_skip_container "$container" "${skip_containers[@]}"; then
                continue
            fi
            file="$backup_dir/$volume.tar.gz"
            path=$(docker inspect --format '{{range .Mounts}}{{if eq .Name "'"$volume"'"}}{{.Destination}}{{end}}{{end}}' "$container")
            echo "Backing up $volume from $path on $container to $file"
            docker run --rm --volumes-from "$container" -v "$backup_dir":/backup busybox tar -zcvf "$file" "$path"
        done
    done
}

if [ -z "$1" ]; then
    echo "Usage: $0 [<skip containers>] <backup_dir>"
    exit 1
fi

backup_volumes "${@:2}"

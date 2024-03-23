FROM ubuntu:latest

COPY docker_volume_backup.sh .

ENTRYPOINT ["./docker_volume_backup.sh"]
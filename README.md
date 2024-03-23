# docker-volume-backup

Backup docker volumes with busybox.

This script detects all existing docker volumes and runs a busybox container to attach to the volume to create backup tar files. 

## Backup

`./docker_volume_backup.sh <backup directory> [<skip containers>]`

Here is an example where we want to skip volumes from the docker containers named mariadb and mongodb:
```
./docker_volume_backup.sh /home/user/backup/ mariadb mongodb 
```

## Restore

To restore run the following command for each volume
```
docker run --rm -v BACKUP_DIR:/backup -v volume_to_restore:/path/to/original/mount busybox tar -xvzf /backup/backup.tar.gz -C /
```
Example
```
docker run --rm -v /data/backup:/backup -v hello_world_volume:/etc/hello/world busybox tar -xvzf /backup/hello_world_volume.tar.gz -C /
```

## Automatic backup

## Cron

Schedule as a cron job to run every night at 01:00 with `crontab -e` and add `0 1 * * * /path/to/dock_volume_backup.sh <backup directory>`

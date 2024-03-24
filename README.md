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

### Cron

Schedule as a cron job to run every night at 01:00 with `crontab -e` and add `0 1 * * * /path/to/dock_volume_backup.sh <backup directory>`

## NFS

This will mount an NFS share before running the backup script and then unmount it when done.

`mount_nfs_and_backup.sh <server> <share> <mount point> [<skip containers>]`

to use an NFS share create a mount point and mark it as immutable to prevent anyone from writing to it

Example:
```
mkdir -p /mnt/docker/
chattr +i /mnt/docker/
mount_nfs_and_backup.sh 192.168.1.2 /path/on/server/ /mnt/docker/ mariadb mongodb 
```



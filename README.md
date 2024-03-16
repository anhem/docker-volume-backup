# docker-volume-backup

Backup docker volumes with busybox.

This script detects all existing docker volumes and runs busybox to attach to the volume to create backup tar files. 

Use SKIP_CONTAINERS to not backup specific volumes by specifying the container name

```
SKIP_CONTAINERS=("mongodb")
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

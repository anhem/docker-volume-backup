# docker-volume-backup

Backup docker volumes with busybox.

This script detects all existing docker volumes and runs busybox to attach to the volume to create backup tar files. 

Use SKIP_CONTAINERS to not backup specific volumes by specifying the container name

```
SKIP_CONTAINERS=("mongodb")
```
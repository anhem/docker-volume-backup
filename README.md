# docker-volume-backup

Backup Docker volumes using BusyBox or Restic.

This script detects all existing Docker volumes and runs a BusyBox or Restic container to attach to the volumes to create backups.

Backups can be created as tar files with or without GPG encryption, or placed in a Restic repository.

This repository also includes scripts for mounting and unmounting NFS or Samba shares to store backups on.

## Backup

For more information and options run:

```bash
./docker_volume_backup.sh --help
```

Here is an example where we want to backup all volumes except for:

* volumes mounted using `nfs`
* all volumes from the containers named `mariadb` and `mongodb`
* the volume named `nginx-proxy-manager_data`:

```bash
./docker_volume_backup.sh /home/user/backup/ --skip-nfs --skip-containers mariadb,mongodb --skip-volumes nginx-proxy-manager_data
```

## Restore

### tar files

To restore tar.gz files, run the following command for each volume:

```bash
docker run --rm \
  -v BACKUP_DIR:/backup \
  -v volume_to_restore:/path/to/original/mount \
  busybox \
  tar -xvzf /backup/backup.tar.gz -C /
```

**Example**

```bash
docker run --rm -v /data/backup:/backup -v hello_world_volume:/etc/hello/world busybox tar -xvzf /backup/hello_world_volume.tar.gz -C /
```

### GPG files

To restore GPG-encrypted files, run the following command for each volume:

```bash
docker run --rm -it \
  -v BACKUP_DIR:/backup \
  -v volume_to_restore:/path/to/original/mount \
  busybox \
  sh -c 'read -sp "Enter backup password: " PWD; echo; gpg --decrypt --batch --passphrase "$PWD" /backup/backup.tar.gz.gpg | tar -xvzf - -C /'
```

### Restic

To restore from a Restic repository, run the following command for each volume:

```bash
docker run --rm -it \
  -v BACKUP_DIR:/repo \
  -v volume_to_restore:/path/to/original/mount \
  restic/restic restore latest --target /path/to/original/mount
```

See the Restic documentation for [restoring from backup](https://restic.readthedocs.io/en/stable/050_restore.html) for more information.

**Restore data from /mnt/restic-repo on a host system to a volume called container_config**:

```bash
sudo docker run --rm -it \
  -v /mnt/restic-repo:/repo -v container_config:/target \
  restic/restic restore latest --repo /repo --tag container_config --target /target
```

**Check snapshots on an NFS share**

```bash
sudo mount -t nfs <ip>:<repo> /mnt/restic-repo && \
sudo docker run --rm -it \
  -v /mnt/restic-repo:/repo \
  restic/restic snapshots --repo /repo
```

## Automatic Backup

### Cron

Schedule as a cron job to run every night at 01:00 with `crontab -e` and add:
`0 1 * * * /path/to/docker_volume_backup.sh <backup directory>`

### Notifications

You can use the `mount_and_backup_and_notify.sh` script to run a backup and then call a notification URL (e.g., Uptime Kuma push URL).

```bash
./mount_and_backup_and_notify.sh <smb|nfs> <notify url> [arguments_for_mount_script...]
```

## NFS

This will mount an NFS share before running the backup script and then unmount it when done.

```bash
./mount_nfs_and_backup.sh <server> <share> <mount point> <backup options>
```

To use an NFS share, create a mount point and mark it as immutable to prevent writing to the host filesystem if the mount fails:

**Example:**

```bash
mkdir -p /mnt/docker/
chattr +i /mnt/docker/
./mount_nfs_and_backup.sh 192.168.1.2 /path/on/server/ /mnt/docker/ --skip-nfs --use-restic --retention-policy="--keep-daily 7"
```

## Samba

This will mount a Samba share before running the backup script and then unmount it when done.

```bash
./mount_smb_and_backup.sh <server> <share> <mount point> <backup options>
```

Requires a `.smbcreds` file in the same directory as the script with the following format:

```
username=<username>
password=<password>
```

To use a Samba share, create a mount point and mark it as immutable:

**Example:**

```bash
mkdir -p /mnt/docker/
chattr +i /mnt/docker/
./mount_smb_and_backup.sh 192.168.1.2 /path/on/server/ /mnt/docker/ --skip-nfs --use-restic --retention-policy="--keep-daily 7"
```

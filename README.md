# docker-volume-backup

Backup docker volumes with busybox or restic.

This script detects all existing docker volumes and runs a busybox or restic container to attach to the volume to create backups.

Backups can be created as tar files with or without GPG encryption, or placed in a restic repository.

This repo also includes scripts for mounting and unmount a nfs or samba share to store backups to.

## Backup

For more information and options run:

```
./docker_volume_backup.sh --help
```

Here is an example where we want backup all volumes except for:

* volumes mounted using `nfs`
* all volumes from the containers named `mariadb` and `mongodb`
* the volume named `nginx-proxy-manager_data`:

```
./docker_volume_backup.sh /home/user/backup/ --skip-nfs --skip-containers mariadb,mongodb --skip-volumes nginx-proxy-manager_data
```

## Restore

### tar files

To restore tar.gz files, run the following command for each volume:

```
docker run --rm \
  -v BACKUP_DIR:/backup \
  -v volume_to_restore:/path/to/original/mount \
  busybox \
  tar -xvzf /backup/backup.tar.gz -C /
```

**Example**

```
docker run --rm -v /data/backup:/backup -v hello_world_volume:/etc/hello/world busybox tar -xvzf /backup/hello_world_volume.tar.gz -C /
```

### gpg files

To restore gpg files, run the following command for each volume:

```
docker run --rm -it \
  -v BACKUP_DIR:/backup \
  -v volume_to_restore:/path/to/original/mount \
  busybox \
  sh -c 'read -sp "Enter backup password: " PWD; echo; gpg --decrypt --batch --passphrase "$PWD" /backup/backup.tar.gz.gpg | tar -xvzf - -C /'
```

### restic

To restore from restic repository, run the following command for each volume:

```
docker run --rm \
  -v BACKUP_DIR:/repo \
  -v volume_to_restore:/path/to/original/mount \
  restic/restic restore latest --target /path/to/original/mount
```

see restic documentation [restoring from backup](https://restic.readthedocs.io/en/stable/050_restore.html) for more information

**Check snapshots on an nfs share**

```
sudo mount -t nfs <ip>:<repo> /mnt/restic-repo && \
sudo docker run --rm -it \
  -v /mnt/restic-repo:/repo \
  -e RESTIC_REPOSITORY=/repo \
  restic/restic snapshots
```

## Automatic backup

### Cron

Schedule as a cron job to run every night at 01:00 with `crontab -e` and add `0 1 * * * /path/to/dock_volume_backup.sh <backup directory>`

## NFS

This will mount an NFS share before running the backup script and then unmount it when done.

`mount_nfs_and_backup.sh <server> <share> <mount point> <backup options>`

to use an NFS share, create a mount point and mark it as immutable to prevent anyone from writing to it when not mounted

**Example:**

```
mkdir -p /mnt/docker/
chattr +i /mnt/docker/
mount_nfs_and_backup.sh 192.168.1.2 /path/on/server/ /mnt/docker/ --skip-nfs --use-restic --retention-policy="--keep-daily 7"
```

## Samba

This will mount a samba share before running the backup script and then unmount it when done.

`mount_smb_and_backup.sh <server> <share> <mount point> <backup options>`

requires a `.smbcreds` file for credentials with:

```
username=<username>
password=<password>
```

to use a samba share, create a mount point and mark it as immutable to prevent anyone from writing to it when not mounted

**Example:**

```
mkdir -p /mnt/docker/
chattr +i /mnt/docker/
mount_smb_and_backup.sh 192.168.1.2 /path/on/server/ /mnt/docker/ --skip-nfs --use-restic --retention-policy="--keep-daily 7"
```



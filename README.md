# docker-volume-backup

Backup Docker volumes using BusyBox or Restic.

This script detects all existing Docker volumes and runs a BusyBox or Restic container to attach to the volumes to create backups.

Backups can be created as tar files with or without GPG encryption, or placed in a Restic repository.

> [!WARNING]
> **Database Backups:** Do not use this script to back up live database data directories (e.g., MySQL, PostgreSQL, MongoDB). Simple file-level backups of running databases can result in corrupted or inconsistent data. Always use the database's native backup tools (like `mysqldump`, `pg_dump`, or `mongodump`) to create a dump file first, and then back up that dump file using this script.

> [!CAUTION]
> **Disclaimer:** This software is provided "as is", without warranty of any kind. Use it at your own risk. Always verify your backups regularly to ensure data integrity.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Password Management](#password-management)
- [Backup](#backup)
  - [Remote Storage (NFS/SMB)](#remote-storage-nfssmb)
  - [Notifications](#notifications)
- [Restore](#restore)
  - [tar files](#tar-files)
  - [GPG files](#gpg-files)
  - [Restic](#restic)
- [Automatic Backup (Cron)](#automatic-backup-cron)
- [Maintenance (Integrity Check)](#maintenance-integrity-check)
  - [Automating Maintenance](#automating-maintenance)

## Prerequisites

For the scripts to work correctly, ensure the following are installed on your host system:

- **Docker**: Must be installed and the current user must have permissions to run containers.
- **GPG**: Required if using the `--encrypt` flag or verifying GPG backups.
- **curl**: Required for sending notifications via the `--notify` flag.
- **mount.nfs**: Required if using the `nfs` protocol.
- **mount.cifs**: Required if using the `smb` protocol (typically part of the `cifs-utils` package).

## Password Management

The scripts require a password for GPG encryption and Restic repositories. You can provide this in two ways:

### 1. .env File (Recommended)
Create a file named `.env` in the same directory as the scripts:
```bash
BACKUP_PASSWORD="your-secure-password"
```

### 2. Environment Variable
Export the variable in your shell or crontab:
```bash
export BACKUP_PASSWORD="your-secure-password"
```

**Security:** Ensure sensitive files are only readable by your user:
```bash
chmod 600 .env .smbcreds
```

For SMB shares, the script requires a `.smbcreds` file in the script directory:
```
username=your_username
password=your_password
```

## Backup

For more information and all options run:

```bash
./docker_volume_backup.sh --help
```

### Basic Local Backup

Backup all volumes to a local directory:

```bash
./docker_volume_backup.sh /path/to/backup/dir
```

### GPG Encrypted Backup

Backup and encrypt all volumes using GPG (requires `BACKUP_PASSWORD` to be set):

```bash
./docker_volume_backup.sh /path/to/backup/dir --encrypt
```

### Remote Storage (NFS/SMB)

The script can automatically mount an NFS or SMB share before starting the backup and unmount it when finished.

**NFS Example:**
```bash
./docker_volume_backup.sh /mnt/backup \
  --protocol nfs \
  --server 192.168.1.50 \
  --share /exports/backups \
  --use-restic
```

**SMB Example:**
(Requires a `.smbcreds` file with `username=` and `password=` in the script directory)
```bash
./docker_volume_backup.sh /mnt/backup \
  --protocol smb \
  --server 192.168.1.50 \
  --share backups \
  --encrypt
```

### Notifications

You can call a notification URL (e.g., Uptime Kuma, Healthchecks.io) on success:

```bash
./docker_volume_backup.sh /mnt/backup --notify "https://hc-ping.com/your-uuid"
```

## Restore

### tar files
```bash
docker run --rm -v /data/backup:/backup -v my_volume:/target busybox tar -xvzf /backup/my_volume.tar.gz -C /
```

### GPG files
```bash
docker run --rm -it -v /data/backup:/backup -v my_volume:/target busybox \
  sh -c 'read -sp "Pass: " P; gpg --decrypt --batch --passphrase "$P" /backup/my_volume.tar.gz.gpg | tar -xvzf - -C /'
```

### Restic
```bash
docker run --rm -it -v /data/backup:/repo -v my_volume:/target restic/restic \
  restore latest --repo /repo --tag my_volume --target /target
```

## Automatic Backup (Cron)

Schedule as a cron job to run every night at 01:00:

```cron
0 1 * * * /path/to/docker_volume_backup.sh /mnt/backup --protocol nfs --server 192.168.1.50 --share /backups --notify "https://ping-url" >> /var/log/backup.log 2>&1
```

## Maintenance (Integrity Check)

To verify the integrity of your backups, use the unified check script. This supports both Restic repositories and GPG-encrypted tar files.

```bash
./docker_volume_backup_check.sh <mount_point> --type <restic|gpg> [OPTIONS]
```

**Examples:**
```bash
# Verify a Restic repository (NFS)
./docker_volume_backup_check.sh /mnt/check --protocol nfs --server 192.168.1.50 --share /exports/backups --type restic --read-data-subset=10%

# Verify all GPG backups (Local)
./docker_volume_backup_check.sh /home/user/backups --type gpg
```

### Automating Maintenance

It is recommended to run a basic integrity check weekly and a more thorough data check monthly.

#### Cron Example

Add these to your `crontab -e` to automate verification:

```cron
# Every Sunday at 02:00: Check metadata and 10% of data
0 2 * * 0 /path/to/docker_volume_backup_check.sh /mnt/check --protocol nfs --server 192.168.1.50 --share /share --type restic --read-data-subset=10% >> /var/log/backup_check.log 2>&1
```

#### Monitoring & Notifications

You can combine maintenance with notifications by using the main backup script's notification logic if you wrap it, but for simple health checks, the absence of a cron success log or a manual ping is your signal. 

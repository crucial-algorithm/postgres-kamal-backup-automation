# PostgreSQL Backup Automation

Automated backup solution for PostgreSQL instances running on Kamal with Hetzner Cloud Volumes and AWS S3.

## Features

✅ **Automated daily backups** to local Hetzner volumes  
✅ **Off-site S3 sync** for disaster recovery  
✅ **Multi-instance support** - manage multiple PostgreSQL databases on one server  
✅ **Staggered cron jobs** - prevent I/O contention  
✅ **Health monitoring** - daily checks with alerts  
✅ **Easy restore** - simple scripts for disaster recovery  
✅ **One-command installation** - automated setup

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/postgres-backup-automation.git
cd postgres-backup-automation
```

### 2. Configure Your Apps

```bash
# Copy example configs
cp config/apps.conf.example config/apps.conf
cp config/aws.conf.example config/aws.conf

# Edit configurations
nano config/apps.conf    # Define your PostgreSQL instances
nano config/aws.conf     # Add AWS credentials
```

### 3. Install on Server

SSH to your database server and run:

```bash
# As root
sudo su

# Run installer
./install.sh
```

The installer will:
- Install AWS CLI
- Configure AWS credentials
- Generate backup/restore scripts for each app
- Set up cron jobs (staggered timing)
- Install unified health check script

## Configuration

### Apps Configuration (`config/apps.conf`)

Define each PostgreSQL instance:

```bash
POSTGRES_APPS=(
    "nutrix|/mnt/HC_Volume_105109388|nutrix-postgres|nutrix|nutrix|nutrix/postgres-backups"
    "verva|/mnt/HC_Volume_XXXXXXX|verva-postgres|verva|verva_production|verva/postgres-backups"
)
```

Format: `"app_name|volume_path|container_name|db_user|db_name|s3_prefix"`

**Fields:**
- `app_name`: Unique identifier (used in script names)
- `volume_path`: Hetzner volume mount point
- `container_name`: Docker container name
- `db_user`: PostgreSQL username
- `db_name`: PostgreSQL database name
- `s3_prefix`: S3 path prefix (e.g., `app-name/postgres-backups`)

### AWS Configuration (`config/aws.conf`)

```bash
AWS_ACCESS_KEY_ID="your-access-key"
AWS_SECRET_ACCESS_KEY="your-secret-key"
AWS_REGION="us-east-1"
AWS_S3_BUCKET="your-bucket-name"
```

**⚠️ Keep this file private!** Add to `.gitignore`.

## Usage

### Manual Backup

```bash
/usr/local/bin/postgres-backup-nutrix.sh
```

### Restore from Backup

```bash
# From local
/usr/local/bin/postgres-restore-nutrix.sh /mnt/HC_Volume_105109388/backups/latest.sql.gz

# From S3
/usr/local/bin/postgres-restore-nutrix.sh s3://verva-prod/nutrix/postgres-backups/backup_20260314_020000.sql.gz
```

### Health Check

```bash
/usr/local/bin/check-all-backups.sh
```

## Disaster Recovery

See [README.md](README.md) for detailed recovery procedures.

## Support

See [docs/CLAUDE.md](docs/CLAUDE.md) for AI assistant context.

## License

MIT License

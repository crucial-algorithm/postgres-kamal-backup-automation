# CLAUDE.md - AI Assistant Context

This document provides context for AI assistants (like Claude) to understand and help with this PostgreSQL backup automation system.

---

## Project Purpose

This repository automates PostgreSQL backups for applications deployed with Kamal on Hetzner Cloud infrastructure, with off-site backup to AWS S3.

## Architecture Overview

### Infrastructure Stack

```
Hetzner Cloud Server(s)
├── Multiple PostgreSQL Containers (via Kamal)
│   ├── App 1: nutrix-postgres (port 5432)
│   ├── App 2: verva-postgres (port 5433)
│   └── App N: app-postgres (port 543N)
│
├── Hetzner Cloud Volumes (one per app)
│   ├── /mnt/HC_Volume_XXXXXX → App 1 data
│   ├── /mnt/HC_Volume_YYYYYY → App 2 data
│   └── Persist across container restarts
│
└── Local Backups on Volumes
    ├── /mnt/HC_Volume_XXXXXX/backups/
    ├── 7-day retention
    └── Fast restore (2-5 min)

AWS S3 Bucket
└── Off-site Backups
    ├── app1/postgres-backups/
    ├── app2/postgres-backups/
    ├── 30-90 day retention (via lifecycle)
    └── Disaster recovery (15-30 min)
```

### Backup Strategy (3-Tier)

1. **Tier 1: Local Backups** (Hetzner Volume)
   - Daily pg_dump backups
   - 7-day retention
   - Recovery: 2-5 minutes
   - Cost: Included in volume

2. **Tier 2: S3 Backups** (Off-site)
   - Synced after each local backup
   - 30-90 day retention
   - Recovery: 15-30 minutes
   - Cost: ~$0.60/month per 50GB

3. **Tier 3: Volume Snapshots** (Optional)
   - Manual or monthly Hetzner snapshots
   - Point-in-time recovery
   - Recovery: 30-60 minutes

## Installation Process

### What the Installer Does

```bash
./install.sh
```

1. **Preflight Checks**
   - Verifies root access
   - Checks config files exist

2. **AWS CLI Setup**
   - Installs awscli if not present
   - Configures credentials from `config/aws.conf`

3. **Script Generation**
   - Reads app definitions from `config/apps.conf`
   - For each app, generates from templates:
     - `/usr/local/bin/postgres-backup-<app>.sh`
     - `/usr/local/bin/postgres-restore-<app>.sh`
   - Generates unified health check script

4. **Cron Setup**
   - Creates staggered backup jobs
   - Example: App1 at 2:00, App2 at 2:15, App3 at 2:30
   - Adds daily health check

5. **Testing** (optional)
   - Runs each backup script
   - Verifies S3 uploads

## Configuration Files

### `config/apps.conf`

**Format:**
```bash
POSTGRES_APPS=(
    "app_name|volume_path|container_name|db_user|db_name|s3_prefix"
)
```

**Example:**
```bash
POSTGRES_APPS=(
    "nutrix|/mnt/HC_Volume_105109388|nutrix-postgres|nutrix|nutrix|nutrix/postgres-backups"
    "verva|/mnt/HC_Volume_234567|verva-postgres|verva|verva_production|verva/postgres-backups"
)
```

**Fields Explained:**
- `app_name`: Used in script naming (e.g., `postgres-backup-nutrix.sh`)
- `volume_path`: Where Hetzner volume is mounted
- `container_name`: Docker container running PostgreSQL
- `db_user`: PostgreSQL username
- `db_name`: Database name to backup
- `s3_prefix`: S3 path (e.g., `nutrix/postgres-backups/`)

### `config/aws.conf`

**Required Variables:**
```bash
AWS_ACCESS_KEY_ID="AKIA..."
AWS_SECRET_ACCESS_KEY="..."
AWS_REGION="us-east-1"
AWS_S3_BUCKET="your-bucket"
```

**Security:** This file is gitignored and should never be committed.

## Template System

### How Templates Work

Templates use placeholder substitution:

```bash
# Template file
APP_NAME="{{APP_NAME}}"

# After processing
APP_NAME="nutrix"
```

**Placeholders:**
- `{{APP_NAME}}` - Application identifier
- `{{VOLUME_PATH}}` - Hetzner volume mount point
- `{{CONTAINER_NAME}}` - Docker container name
- `{{DB_USER}}` - PostgreSQL username
- `{{DB_NAME}}` - Database name
- `{{S3_BUCKET}}` - S3 bucket name
- `{{S3_PREFIX}}` - S3 path prefix
- `{{AWS_REGION}}` - AWS region
- `{{RETENTION_DAYS}}` - Local backup retention
- `{{MAX_AGE_HOURS}}` - Health check threshold

### Template Files

1. **`templates/backup-script.sh.template`**
   - Generates per-app backup scripts
   - Process: pg_dump → compress → save local → upload S3 → cleanup old

2. **`templates/restore-script.sh.template`**
   - Generates per-app restore scripts
   - Supports both local and S3 sources
   - Includes safety prompts

3. **`templates/check-all-backups.sh.template`**
   - Unified health monitoring
   - Checks all apps defined in config
   - Reports: container status, local backup age, S3 backup count

## Backup Script Flow

### Backup Process (per app)

```
1. Create backup directory if needed
2. Run pg_dump | gzip → backup_YYYYMMDD_HHMMSS.sql.gz
3. Create symlink → latest.sql.gz
4. Upload to S3 (async, non-blocking)
5. Delete local backups > 7 days old
6. Log summary
```

**Staggering:** Each app runs 15 minutes apart to avoid:
- CPU contention (pg_dump is CPU-intensive)
- Network saturation (S3 uploads)
- Disk I/O bottlenecks

### Restore Process

```
1. Accept file path (local or s3://)
2. If S3, download to /tmp/
3. Prompt user confirmation (prevents accidents)
4. Drop existing connections
5. Drop and recreate database
6. Restore via: gunzip -c | psql
7. Recreate extensions (e.g., pgvector)
8. Cleanup temp files
```

## Health Check System

### What It Checks

For each app:
- ✅ Container is running
- ✅ Local backup exists
- ✅ Local backup age < 26 hours
- ✅ S3 backups exist
- ✅ S3 has recent backups

### Exit Codes

- `0` - All checks passed (OK)
- `1` - Critical failure (FAILED)
- `2` - Warning condition (WARNING)

### Cron Integration

```cron
0 8 * * * /usr/local/bin/check-all-backups.sh >> /var/log/backup-health.log 2>&1
```

Runs daily at 8 AM, logs to `/var/log/backup-health.log`.

## Common Use Cases

### Adding a New App

1. **Update config:**
```bash
nano config/apps.conf
# Add new entry to POSTGRES_APPS array
```

2. **Re-run installer:**
```bash
./install.sh
```

Installer detects new app and generates scripts automatically.

### Migrating to New Server

1. **On old server:**
```bash
# Backup configs (not in git)
cp config/apps.conf ~/apps.conf.backup
cp config/aws.conf ~/aws.conf.backup
```

2. **On new server:**
```bash
git clone <repo>
cd postgres-backup-automation
cp ~/apps.conf.backup config/apps.conf
cp ~/aws.conf.backup config/aws.conf
./install.sh
```

3. **Restore databases from S3:**
```bash
/usr/local/bin/postgres-restore-nutrix.sh s3://bucket/nutrix/postgres-backups/backup_YYYYMMDD_HHMMSS.sql.gz
```

### Server Swap (Active-Standby)

**Scenario:** Primary server fails, need to activate standby

1. **Detach Hetzner volumes from failed server:**
```bash
hcloud volume detach postgres-nutrix
hcloud volume detach postgres-verva
```

2. **Attach to standby server:**
```bash
hcloud volume attach postgres-nutrix --server standby-server --automount
hcloud volume attach postgres-verva --server standby-server --automount
```

3. **Update Kamal configs** to point to new server IPs

4. **Re-run installer on standby server:**
```bash
./install.sh
```

5. **Boot PostgreSQL accessories:**
```bash
kamal accessory boot postgres -d htz
```

Data is intact on volumes, no restore needed!

## Troubleshooting Guide

### Backup Fails

**Check:** Disk space
```bash
df -h /mnt/HC_Volume_*
```

**Check:** Container running
```bash
docker ps | grep postgres
```

**Check:** PostgreSQL accessible
```bash
docker exec nutrix-postgres pg_isready -U nutrix
```

**Check:** Logs
```bash
tail -50 /var/log/postgres-backup-nutrix.log
```

### S3 Upload Fails

**Check:** AWS credentials
```bash
aws s3 ls
```

**Check:** Network connectivity
```bash
ping s3.amazonaws.com
```

**Check:** IAM permissions
- Needs `s3:PutObject` on bucket
- Needs `s3:ListBucket` for verification

**Manual test:**
```bash
echo "test" | aws s3 cp - s3://bucket/test.txt
```

### Health Check Reports Old Backup

**Possible causes:**
1. Cron job not running → Check: `crontab -l`
2. Backup script failing → Check logs
3. Time drift → Check: `date` and NTP sync

**Fix:**
```bash
# Run backup manually
/usr/local/bin/postgres-backup-nutrix.sh

# Verify
/usr/local/bin/check-all-backups.sh
```

## Security Considerations

### Secrets Management

**Never commit:**
- `config/apps.conf` - Contains volume paths, DB names
- `config/aws.conf` - Contains AWS credentials

**Gitignored:** These files are in `.gitignore`

**Best practice:**
1. Keep encrypted backups of configs
2. Use secure password manager for storage
3. Rotate AWS keys quarterly
4. Use IAM roles when possible (instead of hardcoded keys)

### S3 Security

**Recommended S3 settings:**
- Enable versioning (recover from accidental delete)
- Enable encryption at rest (SSE-S3 or SSE-KMS)
- Restrict bucket policy to specific IAM user
- Enable access logging
- Use lifecycle rules for cost optimization

### PostgreSQL Security

**Backup considerations:**
- Backups contain full database dumps
- Compress to reduce storage/transfer
- Consider encrypting backups before S3 upload
- Limit access to backup scripts (root only)

## Cost Analysis

### Per 50GB Database

**Hetzner:**
- Volume (50GB): €2.20/month
- Snapshots (optional): €0.55/month (50GB)

**AWS S3:**
- Storage (Standard-IA): $0.60/month (50GB)
- Retrieval: $0.50 per restore
- Transfer: Free to same-region EC2

**Total:** ~€2.80/month per app

### For 3 Apps (150GB total)

- Hetzner volumes: €6.60/month
- S3 storage: $1.80/month
- **Total: ~€8.40/month**

### Cost Optimization

1. **S3 Lifecycle:** Move to Glacier after 30 days
2. **Intelligent-Tiering:** Auto-optimize based on access
3. **Local retention:** Reduce from 7 to 3 days
4. **Compress better:** Use `pg_dump -Fc` (custom format)

## Extending the System

### Adding Email Alerts

**Modify health check script:**
```bash
# At end of check-all-backups.sh
if [ "$OVERALL_STATUS" == "FAILED" ]; then
    echo "Backup check failed" | mail -s "Alert: Backup Failed" admin@example.com
fi
```

### Adding Slack Notifications

**Install webhook:**
```bash
apt-get install curl jq
```

**Add to backup script:**
```bash
if [ $? -eq 0 ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"Backup completed: '$APP_NAME'"}' \
        $SLACK_WEBHOOK_URL
fi
```

### Supporting Additional Databases

**MySQL/MariaDB:**
- Replace `pg_dump` with `mysqldump`
- Adjust template accordingly

**MongoDB:**
- Replace with `mongodump`
- Different restore process

## Development Workflow

### Testing Changes Locally

```bash
# Create test environment
docker run -d --name test-postgres \
    -e POSTGRES_USER=test \
    -e POSTGRES_DB=test \
    -e POSTGRES_PASSWORD=test \
    postgres:16

# Test backup script
./templates/backup-script.sh.template  # (after manual variable substitution)
```

### Contributing

1. Fork repository
2. Create feature branch
3. Test on staging server
4. Update documentation
5. Submit pull request

## Kamal Integration

### How This Works with Kamal

**Kamal deploys PostgreSQL:**
```yaml
# deploy.yml
accessories:
  postgres:
    image: postgres:16
    host: 5.161.176.161
    volumes:
      - "/mnt/HC_Volume_105109388/postgresql/data:/var/lib/postgresql/data"
```

**This repo provides:**
- Backup automation for those PostgreSQL instances
- Independent of Kamal deployment
- Can be installed on any server (even non-Kamal)

### Deployment Flow

```
1. Deploy app with Kamal → PostgreSQL running
2. Clone this repo on server
3. Configure apps.conf (match Kamal setup)
4. Run ./install.sh → Backups automated
5. Update Kamal config → Redeploy app
6. Backups continue working automatically
```

## Version History

This automation system evolved from:
1. Manual backup scripts per app
2. Unified backup approach (didn't work - wrong assumption)
3. Multi-instance approach (current)

**Key insight:** Each app needs isolation for:
- Independent failures
- Clear debugging
- Flexible scheduling
- Organizational clarity

## Future Enhancements

**Possible additions:**
- [ ] Support for read replicas
- [ ] Point-in-time recovery (WAL archiving)
- [ ] Backup encryption before S3
- [ ] Metrics/monitoring integration (Prometheus)
- [ ] Backup verification (restore test automation)
- [ ] Multi-cloud support (Backblaze B2, Cloudflare R2)
- [ ] Differential/incremental backups
- [ ] Backup compression levels

## FAQ for AI Assistants

### Q: User wants to add a new app
**A:** Guide them to:
1. Edit `config/apps.conf`
2. Add new entry to `POSTGRES_APPS` array
3. Re-run `./install.sh`

### Q: User reports backup failing
**A:** Debug checklist:
1. Check container running: `docker ps | grep postgres`
2. Check disk space: `df -h`
3. Check logs: `tail /var/log/postgres-backup-<app>.log`
4. Test manually: `/usr/local/bin/postgres-backup-<app>.sh`

### Q: User wants to change backup time
**A:** Guide them to:
1. Edit `config/apps.conf`
2. Change `BACKUP_CRON_HOUR`
3. Re-run `./install.sh` to update cron

### Q: User needs to restore database
**A:** Provide restore command:
```bash
# From local
/usr/local/bin/postgres-restore-<app>.sh /mnt/HC_Volume_*/backups/latest.sql.gz

# From S3
/usr/local/bin/postgres-restore-<app>.sh s3://bucket/app/postgres-backups/backup_*.sql.gz
```

### Q: User setting up new server
**A:** Full migration guide:
1. Clone repo
2. Copy configs from old server
3. Run installer
4. Restore databases from S3 if needed

---

**This document should provide complete context for AI assistants to effectively help users with this backup automation system.**

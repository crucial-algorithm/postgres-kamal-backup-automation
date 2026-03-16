# CLAUDE.md - AI Assistant Documentation

This file helps Claude AI (or other AI assistants) understand and work with this repository.

---

## 🎯 Repository Purpose

This repository automates PostgreSQL backup setup for servers running Kamal deployments on Hetzner Cloud with:
- Local backups on Hetzner Cloud Volumes
- Off-site sync to AWS S3
- Per-application isolation
- Automated scheduling and monitoring

---

## 🏗️ Architecture

### Multi-Instance Design

The system supports multiple PostgreSQL instances on a single server:

```
Server (e.g., 5.161.176.161)
├── App1 PostgreSQL (port 5432)
│   ├── Container: app1-postgres
│   ├── Volume: /mnt/HC_Volume_XXXXX
│   └── S3: s3://bucket/app1/postgres-backups/
├── App2 PostgreSQL (port 5433)
│   ├── Container: app2-postgres  
│   ├── Volume: /mnt/HC_Volume_YYYYY
│   └── S3: s3://bucket/app2/postgres-backups/
└── App3 PostgreSQL (port 5434)
    └── ...
```

### Key Design Decisions

1. **One script per app**: Each application gets dedicated backup/restore scripts for isolation
2. **Staggered cron times**: Backups run at different times (2:00, 2:15, 2:30) to avoid I/O contention
3. **Template-based generation**: Scripts are generated from templates with variable substitution
4. **Unified monitoring**: Single health check script monitors all apps
5. **S3 prefix per app**: Each app has its own S3 prefix for organization

---

## 📁 File Structure

```
.
├── README.md                    # User-facing documentation
├── CLAUDE.md                    # This file - AI assistant guide
├── install.sh                   # Main installer script
├── uninstall.sh                 # Cleanup/removal script
├── config.example.sh            # Example configuration
├── .gitignore                   # Excludes config.sh, logs
│
├── scripts/
│   ├── backup-template.sh      # Template for backup scripts
│   ├── restore-template.sh     # Template for restore scripts
│   └── health-check-template.sh # Template for health monitoring
│
└── utils/
    ├── install-aws-cli.sh      # AWS CLI installation
    ├── configure-aws.sh        # AWS credentials setup
    └── setup-cron.sh           # Cron job configuration
```

---

## 🔧 Configuration Format

### config.sh Structure

```bash
# AWS Configuration
AWS_ACCESS_KEY_ID="AKIA..."
AWS_SECRET_ACCESS_KEY="secret..."
AWS_REGION="us-east-1"
S3_BUCKET="my-bucket"

# Apps Configuration
# Format: "name:volume_id:container:db_user:db_name:cron_hour:cron_minute"
APPS=(
    "nutrix:105109388:nutrix-postgres:nutrix:nutrix:2:0"
    "verva:123456789:verva-postgres:verva:verva_production:2:15"
)

# Backup Settings
RETENTION_DAYS=7
STORAGE_CLASS="STANDARD_IA"
```

### App Configuration Fields

1. **name**: App identifier (used in filenames, logs)
2. **volume_id**: Hetzner volume ID from `df -h | grep HC_Volume`
3. **container**: Docker container name (from `docker ps`)
4. **db_user**: PostgreSQL username
5. **db_name**: PostgreSQL database name
6. **cron_hour**: Hour for backup (0-23)
7. **cron_minute**: Minute for backup (0-59)

---

## 🛠️ How Installation Works

### install.sh Flow

1. **Validation**
   - Check if running as root
   - Verify config.sh exists
   - Source configuration

2. **AWS Setup**
   - Install AWS CLI if missing
   - Configure credentials
   - Test S3 access

3. **Per-App Setup** (loops through APPS array)
   - Generate backup script from template
   - Generate restore script from template
   - Create log file
   - Add cron job

4. **Global Setup**
   - Generate unified health check script
   - Schedule daily health check
   - Display summary

### Template Variable Substitution

Templates use `{{VAR}}` placeholders replaced during generation:

```bash
# Template
DOCKER_CONTAINER="{{CONTAINER_NAME}}"

# After substitution
DOCKER_CONTAINER="nutrix-postgres"
```

---

## 📝 Script Templates

### Backup Script (backup-template.sh)

**Purpose**: Create local backup + sync to S3

**Variables**:
- `{{APP_NAME}}` - Application name
- `{{VOLUME_PATH}}` - Volume mount path
- `{{CONTAINER_NAME}}` - Docker container
- `{{DB_USER}}` - Database user
- `{{DB_NAME}}` - Database name
- `{{S3_BUCKET}}` - S3 bucket
- `{{S3_PREFIX}}` - S3 prefix
- `{{AWS_REGION}}` - AWS region
- `{{RETENTION_DAYS}}` - Local retention
- `{{STORAGE_CLASS}}` - S3 storage class

**Output**: `/usr/local/bin/postgres-backup-{app}.sh`

### Restore Script (restore-template.sh)

**Purpose**: Restore database from local or S3 backup

**Features**:
- Accepts local file path or S3 URL
- Downloads from S3 if needed
- Confirms before overwriting
- Recreates extensions (vector, etc.)

**Output**: `/usr/local/bin/postgres-restore-{app}.sh`

### Health Check (health-check-template.sh)

**Purpose**: Monitor all PostgreSQL backups

**Checks**:
- Container running status
- Local backup age (<26 hours)
- S3 backup existence
- Overall health status

**Output**: `/usr/local/bin/check-all-backups.sh`

---

## 🔄 Adding New Apps

### Method 1: Via Config + Reinstall

```bash
# 1. Edit config.sh
nano config.sh

# 2. Add new app to APPS array
APPS+=(
    "newapp:999999999:newapp-postgres:newapp:newapp_db:2:45"
)

# 3. Run installer
./install.sh
# Installer detects existing apps and only sets up new one
```

### Method 2: Single App Setup

```bash
# Export variables
export APP_NAME="newapp"
export VOLUME_ID="999999999"
# ... etc

# Generate scripts
./utils/generate-single-app.sh
```

---

## 🧹 Cleanup/Uninstall

### uninstall.sh Flow

1. **Discovery**
   - Find all postgres-backup-*.sh scripts
   - Find all postgres-restore-*.sh scripts
   - Identify related cron jobs

2. **Removal** (with confirmation)
   - Remove backup scripts
   - Remove restore scripts
   - Remove health check
   - Remove cron jobs
   - Optionally remove logs
   - Optionally remove AWS config

3. **Verification**
   - List remaining PostgreSQL containers
   - Note: Does NOT remove data or containers

---

## 🐛 Common Issues & Solutions

### Issue: "Container not found"

**Cause**: Container name mismatch in config

**Debug**:
```bash
# List actual container names
docker ps --format '{{.Names}}' | grep postgres

# Compare with config
cat config.sh | grep APPS
```

**Fix**: Update container name in config.sh

### Issue: "Volume path not found"

**Cause**: Wrong volume ID in config

**Debug**:
```bash
# Find actual volume paths
df -h | grep HC_Volume
```

**Fix**: Update volume_id in config.sh

### Issue: "S3 upload fails"

**Cause**: AWS credentials or permissions

**Debug**:
```bash
# Test AWS access
aws s3 ls s3://your-bucket/

# Check credentials
cat /root/.aws/credentials
```

**Fix**: Re-run `./utils/configure-aws.sh`

### Issue: "Backup not running"

**Cause**: Cron not configured correctly

**Debug**:
```bash
# Check crontab
crontab -l | grep postgres

# Check cron logs
grep CRON /var/log/syslog | grep postgres
```

**Fix**: Manually add cron job or re-run installer

---

## 🧪 Testing Checklist

After installation, verify:

- [ ] AWS CLI installed: `aws --version`
- [ ] AWS configured: `aws s3 ls`
- [ ] Backup scripts exist: `ls /usr/local/bin/postgres-backup-*.sh`
- [ ] Restore scripts exist: `ls /usr/local/bin/postgres-restore-*.sh`
- [ ] Health check exists: `ls /usr/local/bin/check-all-backups.sh`
- [ ] Cron jobs added: `crontab -l`
- [ ] Manual backup works: `/usr/local/bin/postgres-backup-nutrix.sh`
- [ ] S3 upload verified: `aws s3 ls s3://bucket/app/postgres-backups/`
- [ ] Health check passes: `/usr/local/bin/check-all-backups.sh`

---

## 🤖 AI Assistant Guidelines

### When Helping Users

1. **Always ask about their setup**:
   - How many PostgreSQL instances?
   - Container names?
   - Volume IDs?
   - S3 bucket details?

2. **Guide through config.sh creation**:
   - Start with config.example.sh
   - Fill in AWS credentials
   - Build APPS array correctly

3. **Test step-by-step**:
   - Install AWS CLI first
   - Test one app before all
   - Verify S3 upload works

### When Modifying Code

1. **Preserve template structure**:
   - Keep `{{VAR}}` placeholders
   - Don't hardcode values
   - Maintain idempotency

2. **Update all related files**:
   - If changing backup script, update template
   - If adding features, update README
   - If changing config format, update example

3. **Test multi-app scenarios**:
   - Verify with 1, 2, and 3+ apps
   - Test staggered cron times
   - Confirm S3 prefix separation

---

## 📊 Key Metrics

### Backup Success Criteria

- Local backup created: `ls /mnt/HC_Volume_*/backups/`
- S3 upload confirmed: `aws s3 ls s3://bucket/app/postgres-backups/`
- Backup size reasonable: `du -h /mnt/HC_Volume_*/backups/latest.sql.gz`
- Health check passes: `/usr/local/bin/check-all-backups.sh` exit 0

### Performance Expectations

- Backup time: ~1-5 minutes for 1GB database
- S3 upload: Depends on bandwidth (1-10 minutes for 1GB)
- Restore time: ~5-30 minutes total
- Cron overhead: Negligible (staggered runs)

---

## 🔐 Security Considerations

### Credentials Storage

- **config.sh**: Contains plaintext AWS credentials
  - Must be excluded from git (.gitignore)
  - Should have 600 permissions
  - Store encrypted backup externally

- **/root/.aws/credentials**: AWS config
  - Created by installer
  - Should have 600 permissions
  - Shared by all backup scripts

### S3 Permissions

Minimum required IAM policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::bucket-name/*",
                "arn:aws:s3:::bucket-name"
            ]
        }
    ]
}
```

### Server Access

- Scripts run as root (required for cron)
- No external network access needed (except S3)
- No inbound ports opened
- Uses existing Docker socket

---

## 🚀 Future Enhancements

Potential improvements (not yet implemented):

1. **Multi-cloud support**: Backblaze B2, Cloudflare R2
2. **Encryption**: Encrypt backups before S3 upload
3. **Notifications**: Slack/Discord/email alerts
4. **Web dashboard**: Monitor backups via web UI
5. **Backup verification**: Automated restore testing
6. **Metrics export**: Prometheus integration
7. **Multi-region**: Cross-region S3 replication

---

## 📞 Support for AI Assistants

When a user asks for help:

1. **Gather context**:
   - Current server setup
   - Number of PostgreSQL instances
   - Existing backup solution (if any)

2. **Provide step-by-step guidance**:
   - Start with config.example.sh
   - Walk through each APPS entry
   - Test incrementally

3. **Troubleshoot systematically**:
   - Check logs first
   - Verify container names
   - Test AWS access
   - Confirm cron syntax

4. **Security awareness**:
   - Remind about .gitignore
   - Warn about plaintext credentials
   - Suggest password managers

---

**This repository is designed to be used by both humans and AI assistants. All scripts are idempotent and can be safely re-run.**

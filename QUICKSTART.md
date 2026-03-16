# Quick Start Guide

Get PostgreSQL backups with S3 sync running in under 10 minutes.

---

## 🚀 Installation

### On Your Server

```bash
# 1. Download the repository
cd /root
wget https://github.com/YOUR-USERNAME/postgres-backup-automation/archive/main.tar.gz
tar -xzf main.tar.gz
cd postgres-backup-automation-main

# 2. Copy and edit configuration
cp config.example.sh config.sh
nano config.sh

# 3. Fill in these required values:
#    - AWS_ACCESS_KEY_ID
#    - AWS_SECRET_ACCESS_KEY
#    - AWS_REGION (e.g., us-east-1)
#    - S3_BUCKET (your bucket name)
#    - APPS array (see below)

# 4. Run installer
chmod +x install.sh
./install.sh
```

---

## ⚙️ Configuration Example

### Finding Your Values

**1. Get volume IDs:**
```bash
df -h | grep HC_Volume
```

Output:
```
/dev/sdb    50G  5.2G   45G  11% /mnt/HC_Volume_105109388
/dev/sdc    50G  3.1G   47G   7% /mnt/HC_Volume_123456789
```

Use: `105109388` and `123456789`

**2. Get container names:**
```bash
docker ps --format '{{.Names}}' | grep postgres
```

Output:
```
nutrix-postgres
verva-postgres
```

**3. Get database info from your Kamal config:**
```bash
cat config/deploy.htz.yml | grep -A 10 "accessories:"
```

### Edit config.sh

```bash
# AWS Configuration
AWS_ACCESS_KEY_ID="AKIA..."
AWS_SECRET_ACCESS_KEY="secret..."
AWS_REGION="us-east-1"
S3_BUCKET="my-backups"

# Apps Configuration
APPS=(
    "nutrix:105109388:nutrix-postgres:nutrix:nutrix:2:0"
    "verva:123456789:verva-postgres:verva:verva_production:2:15"
)

# Backup Settings
RETENTION_DAYS=7
STORAGE_CLASS="STANDARD_IA"
```

---

## ✅ Verification

After installation:

```bash
# 1. Check scripts were created
ls -l /usr/local/bin/postgres-backup-*.sh
ls -l /usr/local/bin/postgres-restore-*.sh

# 2. Test a backup
/usr/local/bin/postgres-backup-nutrix.sh

# 3. Verify S3 upload
aws s3 ls s3://my-backups/nutrix/postgres-backups/

# 4. Check health
/usr/local/bin/check-all-backups.sh

# 5. View cron jobs
crontab -l
```

---

## 🔄 Server Migration

### Scenario: Moving from Server A to Server B

**On Server B:**

```bash
# 1. Download and extract
cd /root
wget https://github.com/YOUR-USERNAME/postgres-backup-automation/archive/main.tar.gz
tar -xzf main.tar.gz
cd postgres-backup-automation-main

# 2. Copy your config.sh from secure storage
# (password manager, encrypted backup, etc.)

# 3. Update volume IDs in config.sh if they changed
nano config.sh
# Check: df -h | grep HC_Volume

# 4. Run installer
./install.sh

# Done! Backups will run automatically
```

---

## 📊 Daily Operations

```bash
# Check status
/usr/local/bin/check-all-backups.sh

# Manual backup
/usr/local/bin/postgres-backup-nutrix.sh

# View recent backups
aws s3 ls s3://my-backups/nutrix/postgres-backups/ | tail -5

# Restore from S3
/usr/local/bin/postgres-restore-nutrix.sh s3://my-backups/nutrix/postgres-backups/backup_20260314_020000.sql.gz
```

---

## 🆘 Troubleshooting

### Backup script fails

```bash
# Check logs
tail -50 /var/log/postgres-backup-nutrix.log

# Test AWS access
aws s3 ls s3://my-backups/

# Check container is running
docker ps | grep nutrix-postgres
```

### S3 upload fails

```bash
# Re-configure AWS
nano config.sh
# Update AWS credentials

# Re-run installer
./install.sh
```

---

## 🔐 Security Checklist

- [ ] `config.sh` is in .gitignore
- [ ] `config.sh` is stored securely (password manager)
- [ ] AWS IAM user has minimal S3 permissions
- [ ] Credentials rotated every 90 days

---

**That's it! Your backups are now automated.** 🎉

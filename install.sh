#!/bin/bash

# ========================================
# PostgreSQL Backup Automation Installer
# ========================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ========================================
# Helper Functions
# ========================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ========================================
# Validation
# ========================================

log_info "Starting PostgreSQL Backup Automation Setup..."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    log_info "Please run: sudo ./install.sh"
    exit 1
fi

# Check if config.sh exists
if [ ! -f "$SCRIPT_DIR/config.sh" ]; then
    log_error "config.sh not found!"
    log_info "Please copy config.example.sh to config.sh and fill in your values:"
    log_info "  cp config.example.sh config.sh"
    log_info "  vi config.sh"
    exit 1
fi

# Source configuration
log_info "Loading configuration..."
source "$SCRIPT_DIR/config.sh"

# Validate required variables
REQUIRED_VARS=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "S3_BUCKET" "APPS")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        log_error "Required variable $var is not set in config.sh"
        exit 1
    fi
done

log_success "Configuration loaded"
echo ""

# ========================================
# AWS CLI Installation
# ========================================

log_info "Checking AWS CLI..."

if ! command -v aws &> /dev/null; then
    log_warning "AWS CLI not found, installing..."
    apt-get update -qq
    apt-get install -y unzip curl
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    log_success "AWS CLI installed"
else
    log_success "AWS CLI already installed ($(aws --version))"
fi

echo ""

# ========================================
# AWS Configuration
# ========================================

log_info "Configuring AWS credentials..."

mkdir -p /root/.aws

cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

chmod 600 /root/.aws/credentials

cat > /root/.aws/config << EOF
[default]
region = ${AWS_REGION}
output = json
EOF

# Test AWS access
log_info "Testing S3 access..."
if aws s3 ls s3://${S3_BUCKET} --region ${AWS_REGION} > /dev/null 2>&1; then
    log_success "S3 access confirmed"
else
    log_error "Cannot access S3 bucket: ${S3_BUCKET}"
    log_info "Please verify:"
    log_info "  1. Bucket exists: aws s3 ls"
    log_info "  2. Credentials are correct"
    log_info "  3. Region is correct: ${AWS_REGION}"
    exit 1
fi

echo ""

# ========================================
# Setup Each App
# ========================================

log_info "Setting up backup scripts for ${#APPS[@]} app(s)..."
echo ""

INSTALLED_APPS=()

for app_config in "${APPS[@]}"; do
    # Parse app configuration
    IFS=':' read -r APP_NAME VOLUME_ID CONTAINER_NAME DB_USER DB_NAME CRON_HOUR CRON_MINUTE <<< "$app_config"
    
    log_info "Configuring app: $APP_NAME"
    
    # Validate container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warning "Container '${CONTAINER_NAME}' not found (docker ps)"
        log_warning "Skipping $APP_NAME - ensure PostgreSQL is running first"
        echo ""
        continue
    fi
    
    # Validate volume exists
    VOLUME_PATH="/mnt/HC_Volume_${VOLUME_ID}"
    if [ ! -d "$VOLUME_PATH" ]; then
        log_warning "Volume path not found: $VOLUME_PATH"
        log_warning "Skipping $APP_NAME - check volume ID"
        echo ""
        continue
    fi
    
    # Create backup directory
    mkdir -p "${VOLUME_PATH}/backups"
    
    # Generate backup script
    BACKUP_SCRIPT="/usr/local/bin/postgres-backup-${APP_NAME}.sh"
    cat "$SCRIPT_DIR/scripts/backup-template.sh" | \
        sed "s/{{APP_NAME}}/${APP_NAME}/g" | \
        sed "s/{{VOLUME_ID}}/${VOLUME_ID}/g" | \
        sed "s/{{CONTAINER_NAME}}/${CONTAINER_NAME}/g" | \
        sed "s/{{DB_USER}}/${DB_USER}/g" | \
        sed "s/{{DB_NAME}}/${DB_NAME}/g" | \
        sed "s/{{S3_BUCKET}}/${S3_BUCKET}/g" | \
        sed "s/{{AWS_REGION}}/${AWS_REGION}/g" | \
        sed "s/{{RETENTION_DAYS}}/${RETENTION_DAYS}/g" | \
        sed "s/{{STORAGE_CLASS}}/${STORAGE_CLASS}/g" \
        > "$BACKUP_SCRIPT"
    
    chmod +x "$BACKUP_SCRIPT"
    log_success "Created backup script: $BACKUP_SCRIPT"
    
    # Generate restore script
    RESTORE_SCRIPT="/usr/local/bin/postgres-restore-${APP_NAME}.sh"
    cat "$SCRIPT_DIR/scripts/restore-template.sh" | \
        sed "s/{{APP_NAME}}/${APP_NAME}/g" | \
        sed "s/{{VOLUME_ID}}/${VOLUME_ID}/g" | \
        sed "s/{{CONTAINER_NAME}}/${CONTAINER_NAME}/g" | \
        sed "s/{{DB_USER}}/${DB_USER}/g" | \
        sed "s/{{DB_NAME}}/${DB_NAME}/g" | \
        sed "s/{{S3_BUCKET}}/${S3_BUCKET}/g" | \
        sed "s/{{AWS_REGION}}/${AWS_REGION}/g" \
        > "$RESTORE_SCRIPT"
    
    chmod +x "$RESTORE_SCRIPT"
    log_success "Created restore script: $RESTORE_SCRIPT"
    
    # Create log file
    touch "/var/log/postgres-backup-${APP_NAME}.log"
    
    # Add cron job (if not already exists)
    CRON_CMD="${CRON_MINUTE} ${CRON_HOUR} * * * ${BACKUP_SCRIPT} >> /var/log/postgres-backup-${APP_NAME}.log 2>&1"
    
    if crontab -l 2>/dev/null | grep -qF "$BACKUP_SCRIPT"; then
        log_warning "Cron job already exists for $APP_NAME"
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        log_success "Added cron job: ${CRON_HOUR}:$(printf "%02d" $CRON_MINUTE) UTC"
    fi
    
    INSTALLED_APPS+=("$app_config")
    echo ""
done

# ========================================
# Generate Health Check Script
# ========================================

log_info "Generating unified health check script..."

HEALTH_CHECK_SCRIPT="/usr/local/bin/check-all-backups.sh"

# Build the apps check block
APPS_CHECK=""
for app_config in "${INSTALLED_APPS[@]}"; do
    IFS=':' read -r APP_NAME VOLUME_ID CONTAINER_NAME DB_USER DB_NAME CRON_HOUR CRON_MINUTE <<< "$app_config"
    
    APPS_CHECK+="# Check $APP_NAME
APP=\"$APP_NAME\"
VOLUME=\"/mnt/HC_Volume_${VOLUME_ID}\"
CONTAINER=\"$CONTAINER_NAME\"
S3_PREFIX=\"${APP_NAME}/postgres-backups\"

echo \"[\$APP]\"

# Check container
if ! docker ps --format '{{.Names}}' | grep -q \"^\${CONTAINER}\$\"; then
    echo \"  ❌ Container not running!\"
    OVERALL_STATUS=\"FAILED\"
else
    # Check local backup
    BACKUP_DIR=\"\$VOLUME/backups\"
    LATEST_LOCAL=\$(find \$BACKUP_DIR -name \"backup_*.sql.gz\" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
    
    if [ -z \"\$LATEST_LOCAL\" ]; then
        echo \"  ❌ No local backups found!\"
        OVERALL_STATUS=\"FAILED\"
    else
        LOCAL_FILE=\$(echo \$LATEST_LOCAL | cut -d' ' -f2)
        LOCAL_AGE_SECONDS=\$(( \$(date +%s) - \$(echo \$LATEST_LOCAL | cut -d' ' -f1 | cut -d'.' -f1) ))
        LOCAL_AGE_HOURS=\$(( LOCAL_AGE_SECONDS / 3600 ))
        LOCAL_SIZE=\$(du -h \$LOCAL_FILE 2>/dev/null | cut -f1)
        
        echo \"  Local Backup:\"
        echo \"    File: \$(basename \$LOCAL_FILE)\"
        echo \"    Age: \$LOCAL_AGE_HOURS hours\"
        echo \"    Size: \$LOCAL_SIZE\"
        
        if [ \$LOCAL_AGE_HOURS -gt \$MAX_AGE_HOURS ]; then
            echo \"    ⚠️  WARNING: Backup older than \$MAX_AGE_HOURS hours!\"
            [ \"\$OVERALL_STATUS\" == \"OK\" ] && OVERALL_STATUS=\"WARNING\"
        else
            echo \"    ✅ OK\"
        fi
    fi
    
    # Check S3 backup
    S3_COUNT=\$(aws s3 ls s3://\${S3_BUCKET}/\${S3_PREFIX}/ 2>/dev/null | grep \"backup_\" | wc -l)
    
    echo \"  S3 Backups:\"
    if [ \$S3_COUNT -eq 0 ]; then
        echo \"    ❌ No S3 backups found!\"
        OVERALL_STATUS=\"FAILED\"
    else
        S3_LATEST=\$(aws s3 ls s3://\${S3_BUCKET}/\${S3_PREFIX}/ 2>/dev/null | grep \"backup_\" | tail -1 | awk '{print \$4}')
        echo \"    Total: \$S3_COUNT backups\"
        echo \"    Latest: \$S3_LATEST\"
        echo \"    ✅ OK\"
    fi
fi

echo \"\"

"
done

# Generate final health check script
cat "$SCRIPT_DIR/scripts/health-check-template.sh" | \
    sed "s/{{MAX_BACKUP_AGE_HOURS}}/${MAX_BACKUP_AGE_HOURS:-26}/g" | \
    sed "/{{APPS_CHECK_BLOCK}}/r /dev/stdin" | \
    sed "/{{APPS_CHECK_BLOCK}}/d" \
    <<< "$APPS_CHECK" \
    > "$HEALTH_CHECK_SCRIPT"

# Add S3_BUCKET variable to health check
sed -i "2a S3_BUCKET=\"${S3_BUCKET}\"" "$HEALTH_CHECK_SCRIPT"

chmod +x "$HEALTH_CHECK_SCRIPT"
log_success "Created health check script: $HEALTH_CHECK_SCRIPT"

# Add health check to cron (daily at 8 AM)
HEALTH_CRON="0 8 * * * $HEALTH_CHECK_SCRIPT >> /var/log/backup-health.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "$HEALTH_CHECK_SCRIPT"; then
    log_warning "Health check cron job already exists"
else
    (crontab -l 2>/dev/null; echo "$HEALTH_CRON") | crontab -
    log_success "Added health check cron job: 8:00 UTC daily"
fi

echo ""

# ========================================
# Summary
# ========================================

echo "========================================"
log_success "Installation Complete!"
echo "========================================"
echo ""
echo "Installed apps: ${#INSTALLED_APPS[@]}"
for app_config in "${INSTALLED_APPS[@]}"; do
    IFS=':' read -r APP_NAME _ _ _ _ CRON_HOUR CRON_MINUTE <<< "$app_config"
    echo "  - $APP_NAME (backups at ${CRON_HOUR}:$(printf "%02d" $CRON_MINUTE) UTC)"
done
echo ""
echo "Scripts installed:"
echo "  Backup scripts:  /usr/local/bin/postgres-backup-*.sh"
echo "  Restore scripts: /usr/local/bin/postgres-restore-*.sh"
echo "  Health check:    $HEALTH_CHECK_SCRIPT"
echo ""
echo "Logs:"
echo "  Backup logs:     /var/log/postgres-backup-*.log"
echo "  Health log:      /var/log/backup-health.log"
echo ""
echo "Next steps:"
echo "  1. Test a backup:  /usr/local/bin/postgres-backup-${INSTALLED_APPS[0]%%:*}.sh"
echo "  2. Check S3:       aws s3 ls s3://${S3_BUCKET}/"
echo "  3. Verify health:  $HEALTH_CHECK_SCRIPT"
echo "  4. View cron jobs: crontab -l"
echo ""
echo "========================================"

#!/bin/bash

# ========================================
# PostgreSQL Backup Configuration
# ========================================
# 
# IMPORTANT: Copy this file to config.sh and fill in your actual values
# 
# cp config.example.sh config.sh
# nano config.sh
#
# DO NOT commit config.sh to version control!
# ========================================

# ========================================
# AWS Configuration
# ========================================

# Your AWS Access Key ID
# Get from AWS Console → IAM → Users → Security Credentials
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"

# Your AWS Secret Access Key  
# Get from AWS Console → IAM → Users → Security Credentials
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# AWS Region where your S3 bucket is located
# Examples: us-east-1, eu-west-1, ap-southeast-1
AWS_REGION="us-east-1"

# S3 Bucket name for storing backups
# Must already exist - create via AWS Console or:
#   aws s3 mb s3://my-backup-bucket --region us-east-1
S3_BUCKET="my-backup-bucket"

# ========================================
# Apps Configuration
# ========================================
#
# Define your PostgreSQL instances as an array
#
# Format per app (colon-separated):
#   "app_name:volume_id:container_name:db_user:db_name:cron_hour:cron_minute"
#
# Fields explained:
#   app_name       - Unique identifier for the app (used in filenames, logs)
#   volume_id      - Hetzner volume ID (get from: df -h | grep HC_Volume)
#   container_name - Docker container name (get from: docker ps)
#   db_user        - PostgreSQL username
#   db_name        - PostgreSQL database name
#   cron_hour      - Hour to run backup (0-23, UTC)
#   cron_minute    - Minute to run backup (0-59)
#
# Stagger cron times to avoid I/O contention!
# Example: App1 at 2:00, App2 at 2:15, App3 at 2:30
#
APPS=(
    "nutrix:105109388:nutrix-postgres:nutrix:nutrix:2:0"
    "verva:123456789:verva-postgres:verva:verva_production:2:15"
    # "app3:987654321:app3-postgres:app3:app3_db:2:30"
)

# ========================================
# Backup Settings
# ========================================

# How many days to keep local backups before deletion
# S3 backups are retained longer (see S3 lifecycle rules)
RETENTION_DAYS=7

# S3 Storage Class
# Options:
#   STANDARD_IA  - Standard Infrequent Access (~$0.0125/GB/month)
#   GLACIER_IR   - Glacier Instant Retrieval (~$0.004/GB/month)
#   STANDARD     - Standard storage (~$0.023/GB/month)
# Recommended: STANDARD_IA for daily backups
STORAGE_CLASS="STANDARD_IA"

# ========================================
# Advanced Settings (optional)
# ========================================

# Enable verbose logging (true/false)
VERBOSE=false

# Compress backups with gzip (true/false)
# Always leave as true unless you have specific reasons
COMPRESS=true

# Health check max age (hours)
# Backup is considered stale if older than this
MAX_BACKUP_AGE_HOURS=26

# ========================================
# How to Find Your Values
# ========================================
#
# volume_id:
#   SSH to server and run:
#     df -h | grep HC_Volume
#   Example output:
#     /dev/sdb    50G  5.2G   45G  11% /mnt/HC_Volume_105109388
#   Use: 105109388
#
# container_name:
#   SSH to server and run:
#     docker ps --format '{{.Names}}' | grep postgres
#   Example output:
#     nutrix-postgres
#     verva-postgres
#   Use the exact name shown
#
# db_user and db_name:
#   Check your Kamal deploy.yml or deploy.htz.yml:
#     accessories:
#       postgres:
#         env:
#           clear:
#             POSTGRES_USER: nutrix    # This is db_user
#             POSTGRES_DB: nutrix      # This is db_name
#
# cron_hour and cron_minute:
#   Choose times in UTC (not your local timezone!)
#   Stagger by 15 minutes per app to avoid I/O contention
#   Examples:
#     - First app:  2:00 (hour=2, minute=0)
#     - Second app: 2:15 (hour=2, minute=15)  
#     - Third app:  2:30 (hour=2, minute=30)
#
# ========================================
# Example Configuration
# ========================================
#
# For a server with 2 apps:
#
# APPS=(
#     "nutrix:105109388:nutrix-postgres:nutrix:nutrix:2:0"
#     "verva:123456789:verva-postgres:verva:verva_production:2:15"
# )
#
# This will:
#   - Backup nutrix at 2:00 AM UTC daily
#   - Backup verva at 2:15 AM UTC daily
#   - Store locally on respective volumes
#   - Upload to s3://my-backup-bucket/nutrix/postgres-backups/
#   - Upload to s3://my-backup-bucket/verva/postgres-backups/
#
# ========================================

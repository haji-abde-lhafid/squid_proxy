#!/bin/bash

# setup_log_cron.sh
# Sets up an automatic log cleanup cron job for Squid and Dante

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run as root${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Setting up automatic proxy log cleanup...${NC}"

# Define the local script path
LOCAL_BIN="/usr/local/bin/clear_proxy_logs.sh"
REPO_URL="https://raw.githubusercontent.com/haji-abde-lhafid/squid_proxy/main/clear_logs.sh"

# Download or copy clear_logs.sh
if [ -f "./clear_logs.sh" ]; then
    echo -e "${BLUE}[INFO] Copying local clear_logs.sh to $LOCAL_BIN${NC}"
    cp ./clear_logs.sh "$LOCAL_BIN"
else
    echo -e "${BLUE}[INFO] Downloading clear_logs.sh from repository...${NC}"
    curl -s -o "$LOCAL_BIN" "$REPO_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Failed to download clear_logs.sh. Check your internet connection.${NC}"
        exit 1
    fi
fi

chmod +x "$LOCAL_BIN"

# Set up cron job (every 2 hours)
CRON_CMD="0 */2 * * * $LOCAL_BIN >/dev/null 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$LOCAL_BIN"; then
    echo -e "${GREEN}[SUCCESS] Cron job is already set up to clear logs automatically.${NC}"
else
    # Append the new cron job
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo -e "${GREEN}[SUCCESS] Cron job added! Proxy logs will be cleared every 2 hours automatically.${NC}"
fi

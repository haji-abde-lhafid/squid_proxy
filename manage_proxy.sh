#!/bin/bash

# manage_proxy.sh
# Central management menu for Squid Proxy scripts

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Repository Base URL
REPO_URL="https://raw.githubusercontent.com/haji-abde-lhafid/squid_proxy/main"

# List of scripts to manage
SCRIPTS=(
    "install_squid_dante.sh"
    "install_squid_proxy.sh"
    "uninstall_squid_dante.sh"
    "uninstall_squid_proxy.sh"
    "add_user.sh"
    "fix_squid.sh"
    "check_proxy_services.sh"
    "monitor.sh"
)

# Function to print the menu header
print_header() {
    clear
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}       Squid & Dante Proxy Management Menu          ${NC}"
    echo -e "${BLUE}====================================================${NC}"
}

# Function to pause and wait for user input
pause() {
    echo ""
    read -p "Press [Enter] key to continue..."
}

# Function to check and run a script
run_script() {
    local script_name=$1
    if [ -f "$script_name" ]; then
        echo -e "${GREEN}Starting $script_name...${NC}"
        chmod +x "$script_name"
        ./"$script_name"
    else
        echo -e "${RED}Error: Script $script_name not found!${NC}"
        read -p "Do you want to download it now? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            download_file "$script_name"
            if [ -f "$script_name" ]; then
                chmod +x "$script_name"
                ./"$script_name"
            fi
        fi
    fi
    pause
}

# Function to download a single file
download_file() {
    local file_name=$1
    echo -e "${YELLOW}Downloading $file_name...${NC}"
    if curl -s -O "$REPO_URL/$file_name"; then
        chmod +x "$file_name"
        echo -e "${GREEN}Download complete: $file_name${NC}"
    else
        echo -e "${RED}Failed to download $file_name${NC}"
    fi
}

# Function to download all scripts
download_all_scripts() {
    print_header
    echo -e "${YELLOW}Downloading all scripts from repository...${NC}"
    echo ""
    for script in "${SCRIPTS[@]}"; do
        download_file "$script"
    done
    echo ""
    echo -e "${GREEN}All downloads completed.${NC}"
    pause
}

# Main Loop
while true; do
    print_header
    echo "1. Install Squid & Dante (with Auth)"
    echo "2. Install Squid Proxy (Simple)"
    echo "3. Uninstall Squid & Dante"
    echo "4. Uninstall Squid Proxy"
    echo "5. Add Proxy User"
    echo "6. Fix Squid Permissions"
    echo "7. Check Proxy Services (Auto-Restart)"
    echo "8. Monitor Proxy Usage"
    echo "9. Download / Update All Scripts"
    echo "0. Exit"
    echo -e "${BLUE}====================================================${NC}"
    read -p "Enter your choice [0-9]: " choice

    case $choice in
        1)
            run_script "install_squid_dante.sh"
            ;;
        2)
            run_script "install_squid_proxy.sh"
            ;;
        3)
            run_script "uninstall_squid_dante.sh"
            ;;
        4)
            run_script "uninstall_squid_proxy.sh"
            ;;
        5)
            run_script "add_user.sh"
            ;;
        6)
            run_script "fix_squid.sh"
            ;;
        7)
            run_script "check_proxy_services.sh"
            ;;
        8)
            run_script "monitor.sh"
            ;;
        9)
            download_all_scripts
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            pause
            ;;
    esac
done

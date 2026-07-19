#!/usr/bin/env bash

# ==============================================================================
# User Management Utilities
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

ensure_htpasswd() {
    if ! command -v htpasswd &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get install -y apache2-utils >/dev/null 2>&1
        else
            yum install -y httpd-tools >/dev/null 2>&1 || dnf install -y httpd-tools >/dev/null 2>&1
        fi
    fi
}

init_passwd_file() {
    if [[ ! -d "$SQUID_DIR" ]]; then
        mkdir -p "$SQUID_DIR"
    fi
    if [[ ! -f "$PASSWD_FILE" ]]; then
        touch "$PASSWD_FILE"
        chmod 644 "$PASSWD_FILE"
    fi
}

is_squid_installed() {
    systemctl list-unit-files | grep -q "^squid"
}

is_dante_installed() {
    systemctl list-unit-files | grep -Eq "^(dante-server|danted)"
}

add_user() {
    local username="$1"
    local password="$2"
    
    if [[ -z "$username" || -z "$password" ]]; then
        read -r -p "Enter username: " username
        read -r -s -p "Enter password: " password
        echo ""
    fi
    
    if [[ -z "$username" || -z "$password" ]]; then
        print_error "Username and password cannot be empty."
        return 1
    fi
    
    local success=0
    
    # Squid htpasswd
    if is_squid_installed; then
        ensure_htpasswd
        init_passwd_file
        if grep -q "^${username}:" "$PASSWD_FILE" 2>/dev/null; then
            print_warning "User $username already exists in Squid."
        else
            if htpasswd -b "$PASSWD_FILE" "$username" "$password" >/dev/null 2>&1; then
                print_success "User $username added to Squid."
                systemctl reload squid 2>/dev/null || true
                success=1
            else
                print_error "Failed to add user $username to Squid."
            fi
        fi
    fi
    
    # Dante system user
    if is_dante_installed; then
        if id "$username" &>/dev/null; then
            print_warning "System user $username already exists (Dante)."
        else
            if useradd -M -s /usr/sbin/nologin "$username" >/dev/null 2>&1; then
                echo "$username:$password" | chpasswd >/dev/null 2>&1
                print_success "User $username added to Dante."
                success=1
            else
                print_error "Failed to add user $username to Dante."
            fi
        fi
    fi
    
    if [[ $success -eq 1 ]]; then
        log_msg "USER_MGMT" "Added user $username"
    fi
}

delete_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        read -r -p "Enter username to delete: " username
    fi
    
    local success=0
    
    # Squid htpasswd
    if is_squid_installed; then
        init_passwd_file
        if grep -q "^${username}:" "$PASSWD_FILE" 2>/dev/null; then
            if htpasswd -D "$PASSWD_FILE" "$username" >/dev/null 2>&1; then
                print_success "User $username deleted from Squid."
                systemctl reload squid 2>/dev/null || true
                success=1
            fi
        fi
    fi
    
    # Dante system user
    if is_dante_installed; then
        if id "$username" &>/dev/null; then
            if userdel -f "$username" >/dev/null 2>&1; then
                print_success "User $username deleted from Dante."
                success=1
            fi
        fi
    fi
    
    if [[ $success -eq 1 ]]; then
        log_msg "USER_MGMT" "Deleted user $username"
    fi
}

change_password() {
    local username="$1"
    local password="$2"
    
    if [[ -z "$username" ]]; then
        read -r -p "Enter username: " username
    fi
    
    if [[ -z "$password" ]]; then
        read -r -s -p "Enter new password: " password
        echo ""
    fi
    
    local success=0
    
    if is_squid_installed; then
        ensure_htpasswd
        init_passwd_file
        if grep -q "^${username}:" "$PASSWD_FILE" 2>/dev/null; then
            if htpasswd -b "$PASSWD_FILE" "$username" "$password" >/dev/null 2>&1; then
                print_success "Password changed for Squid user $username."
                systemctl reload squid 2>/dev/null || true
                success=1
            fi
        fi
    fi
    
    if is_dante_installed; then
        if id "$username" &>/dev/null; then
            if echo "$username:$password" | chpasswd >/dev/null 2>&1; then
                print_success "Password changed for Dante user $username."
                success=1
            fi
        fi
    fi
    
    if [[ $success -eq 1 ]]; then
        log_msg "USER_MGMT" "Changed password for $username"
    fi
}

disable_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        read -r -p "Enter username to disable: " username
    fi
    
    # Squid: just append 'DISABLED' to hash
    if is_squid_installed; then
        if grep -q "^${username}:" "$PASSWD_FILE" 2>/dev/null; then
            sed -i "s/^${username}:/${username}:DISABLED_/g" "$PASSWD_FILE"
            print_success "User $username disabled in Squid."
            systemctl reload squid 2>/dev/null || true
        fi
    fi
    
    # Dante: lock user
    if is_dante_installed; then
        if id "$username" &>/dev/null; then
            usermod -L "$username" >/dev/null 2>&1
            print_success "User $username disabled in Dante."
        fi
    fi
}

enable_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        read -r -p "Enter username to enable: " username
    fi
    
    if is_squid_installed; then
        if grep -q "^${username}:DISABLED_" "$PASSWD_FILE" 2>/dev/null; then
            sed -i "s/^${username}:DISABLED_/${username}:/g" "$PASSWD_FILE"
            print_success "User $username enabled in Squid."
            systemctl reload squid 2>/dev/null || true
        fi
    fi
    
    if is_dante_installed; then
        if id "$username" &>/dev/null; then
            usermod -U "$username" >/dev/null 2>&1
            print_success "User $username enabled in Dante."
        fi
    fi
}

list_users() {
    echo -e "${CYAN}--- Registered Users (Squid) ---${NC}"
    if [[ -s "$PASSWD_FILE" ]]; then
        awk -F':' '{
            if ($2 ~ /^DISABLED_/) {
                print "- " $1 " (Disabled)"
            } else {
                print "- " $1 " (Active)"
            }
        }' "$PASSWD_FILE"
        echo -e "${GREEN}Total Squid users: $(wc -l < "$PASSWD_FILE")${NC}"
    else
        echo "No users found in Squid."
    fi
    
    echo -e "\n${CYAN}--- Registered Users (Dante) ---${NC}"
    # Find users with /usr/sbin/nologin or /bin/false that aren't system defaults
    local dante_users=$(awk -F':' '($3 >= 1000) && ($7 == "/usr/sbin/nologin" || $7 == "/sbin/nologin") {print $1}' /etc/passwd)
    if [[ -n "$dante_users" ]]; then
        for u in $dante_users; do
            # Check if locked
            if passwd -S "$u" 2>/dev/null | grep -q " L "; then
                echo "- $u (Disabled)"
            else
                echo "- $u (Active)"
            fi
        done
        echo -e "${GREEN}Total Dante users: $(echo "$dante_users" | wc -w)${NC}"
    else
        echo "No users found in Dante."
    fi
}

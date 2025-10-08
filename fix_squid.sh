#!/bin/bash

# Squid Fix Script
set -e

echo "🔧 Troubleshooting Squid Installation..."

# Check Squid status and logs
echo "📋 Checking Squid status..."
systemctl status squid --no-pager -l | head -20

echo "📖 Checking Squid logs..."
journalctl -u squid --no-pager -n 20

# Check configuration syntax
echo "🔍 Checking configuration syntax..."
squid -k parse

# Common fixes
echo "🛠️  Applying common fixes..."

# 1. Fix password file path in config
echo "Fixing password file path..."
if grep -q "/usr/lib64/squid/basic_ncsa_auth" /etc/squid/squid.conf; then
    # Test which path exists
    if [ -f "/usr/lib64/squid/basic_ncsa_auth" ]; then
        echo "Using /usr/lib64/squid/basic_ncsa_auth"
    elif [ -f "/usr/lib/squid/basic_ncsa_auth" ]; then
        sed -i 's|/usr/lib64/squid/basic_ncsa_auth|/usr/lib/squid/basic_ncsa_auth|g' /etc/squid/squid.conf
        echo "Updated to /usr/lib/squid/basic_ncsa_auth"
    else
        echo "❌ basic_ncsa_auth not found, installing required packages..."
        # Install required packages
        if command -v dnf &> /dev/null; then
            dnf install -y squid-helpers
        elif command -v yum &> /dev/null; then
            yum install -y squid-helpers
        fi
    fi
fi

# 2. Fix permissions
echo "🔐 Fixing permissions..."
chown squid:squid /etc/squid/passwords
chmod 600 /etc/squid/passwords
chown squid:squid /var/spool/squid
chmod 755 /var/spool/squid

# 3. Create minimal working config as backup
echo "📝 Creating minimal configuration..."
cp /etc/squid/squid.conf /etc/squid/squid.conf.backup2

cat > /etc/squid/squid_minimal.conf << 'EOF'
http_port 8888
visible_hostname squid-proxy

# Minimal auth config
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm "Squid Proxy"
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# Basic settings
forwarded_for delete
via off
dns_v4_first on
EOF

# 4. Test with minimal config first
echo "🧪 Testing with minimal configuration..."
cp /etc/squid/squid_minimal.conf /etc/squid/squid.conf

# 5. Reinitialize cache
echo "🗂️  Reinitializing cache..."
squid -z

# 6. Start Squid
echo "🚀 Starting Squid..."
systemctl start squid

if systemctl is-active --quiet squid; then
    echo "✅ Squid started successfully!"
    
    # Test the proxy
    echo "🧪 Testing proxy..."
    curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" --max-time 10 \
         -x http://rooot:aaaa5555@localhost:8888 http://httpbin.org/ip
else
    echo "❌ Squid still failed to start"
    echo "📖 Latest logs:"
    journalctl -u squid --no-pager -n 10
    exit 1
fi
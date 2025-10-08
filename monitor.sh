#!/bin/bash
echo "Squid Status:"
systemctl status squid --no-pager -l | head -10
echo -e "\nActive Connections:"
netstat -tlnp | grep :8888 || ss -tlnp | grep :8888
echo -e "\nRecent Logs:"
tail -10 /var/log/squid/access.log 2>/dev/null || echo "Logs not available"
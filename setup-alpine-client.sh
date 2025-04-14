#!/bin/sh
# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Install bc using apk (Alpine package manager)
if ! apk info -e bc > /dev/null 2>&1; then
    apk add bc
fi

# Stop existing service if running (OpenRC)
rc-service ak_client stop 2>/dev/null

# Function to detect main network interface
get_main_interface() {
    interfaces=$(ip -o link show | \
        awk -F': ' '$2 !~ /^((lo|docker|veth|br-|virbr|tun|vnet|wg|vmbr|dummy|gre|sit|vlan|lxc|lxd|warp|tap))/{print $2}' | \
        grep -v '@')
    
    interface_count=$(echo "$interfaces" | wc -l)
    
    # Format traffic size function
    format_bytes() {
        bytes=$1
        if [ "$bytes" -lt 1024 ]; then
            echo "${bytes} B"
        elif [ "$bytes" -lt 1048576 ]; then # 1024*1024
            echo "$(echo "scale=2; $bytes/1024" | bc) KB"
        elif [ "$bytes" -lt 1073741824 ]; then # 1024*1024*1024
            echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
        elif [ "$bytes" -lt 1099511627776 ]; then # 1024*1024*1024*1024
            echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
        else
            echo "$(echo "scale=2; $bytes/1099511627776" | bc) TB"
        fi
    }
    
    # Show interface traffic function
    show_interface_traffic() {
        interface=$1
        if [ -d "/sys/class/net/$interface" ]; then
            rx_bytes=$(cat /sys/class/net/"$interface"/statistics/rx_bytes)
            tx_bytes=$(cat /sys/class/net/"$interface"/statistics/tx_bytes)
            echo "   ↓ Received: $(format_bytes "$rx_bytes")"
            echo "   ↑ Sent: $(format_bytes "$tx_bytes")"
        else
            echo "   无法读取流量信息"
        fi
    }
    
    # Display all available interfaces
    echo "所有可用的网卡接口:" >&2
    echo "------------------------" >&2
    i=1
    ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}' | while read -r interface; do
        echo "$i) $interface" >&2
        show_interface_traffic "$interface" >&2
        i=$((i+1))
    done
    echo "------------------------" >&2
    
    while true; do
        printf "请选择网卡，如上方显示异常或没有需要的网卡，请直接填入网卡名: " >&2
        read selection
        
        # Check if selection is a number
        if echo "$selection" | grep -q '^[0-9]\+$'; then
            selected_interface=$(ip -o link show | grep -v "lo:" | sed -n "${selection}p" | awk -F': ' '{print $2}')
            if [ -n "$selected_interface" ]; then
                echo "已选择网卡: $selected_interface" >&2
                echo "$selected_interface"
                break
            else
                echo "无效的选择，请重新输入" >&2
                continue
            fi
        else
            # Use the input as interface name directly
            echo "已选择网卡: $selection" >&2
            echo "$selection"
            break
        fi
    done
}

# Check if all arguments are provided
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <auth_secret> <url> <name> [disk_devices] [proxy_enabled] [proxy_type] [proxy_address]"
    echo "Example 1 (without proxy): $0 your_secret wss://api.123.321 HK-Akile"
    echo "Example 2 (with disk devices): $0 your_secret wss://api.123.321 HK-Akile \"sda,sdb\""
    echo "Example 3 (with proxy): $0 your_secret wss://api.123.321 HK-Akile \"\" true socks5 127.0.0.1:40000"
    echo "Example 4 (with disk devices and proxy): $0 your_secret wss://api.123.321 HK-Akile \"sda,sdb\" true socks5 127.0.0.1:40000"
    exit 1
fi

# Get system architecture
ARCH=$(uname -m)
CLIENT_FILE="akile_client-linux-amd64"

# Set appropriate client file based on architecture
if [ "$ARCH" = "x86_64" ]; then
    CLIENT_FILE="akile_client-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    CLIENT_FILE="akile_client-linux-arm64"
elif [ "$ARCH" = "x86_64" ] && [ "$(uname -s)" = "Darwin" ]; then
    CLIENT_FILE="akile_client-darwin-amd64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Assign command line arguments to variables
auth_secret="$1"
url="$2"
monitor_name="$3"

# Disk devices (default to empty)
disk_devices="[]"
if [ "$#" -ge 4 ] && [ -n "$4" ]; then
    IFS=',' read -ra devices <<< "$4"
    disk_devices="["
    for device in "${devices[@]}"; do
        disk_devices+="\"$device\","
    done
    disk_devices=${disk_devices%,}
    disk_devices+="]"
fi

# Proxy settings (default to disabled)
proxy_enabled="false"
proxy_type=""
proxy_address=""
if [ "$#" -ge 7 ]; then
    proxy_enabled="$5"
    proxy_type="$6"
    proxy_address="$7"
elif [ "$#" -ge 5 ] && [ "$4" = "true" ] || [ "$4" = "false" ]; then
    # Backward compatibility for old proxy format
    proxy_enabled="$4"
    proxy_type="$5"
    proxy_address="$6"
fi

# Get network interface
net_name=$(get_main_interface)
echo "Using network interface: $net_name"

# Create directory and change to it
mkdir -p /etc/ak_monitor/
cd /etc/ak_monitor/

# Download client
if [ -n "$proxy_type" ] && [ -n "$proxy_address" ]; then
    apk add curl
    curl -Lo client "https://github.com/Heather-Mont/akile_monitor/releases/latest/download/$CLIENT_FILE" --proxy "${proxy_type}://${proxy_address}"
else
    apk add wget
    wget -O client "https://github.com/Heather-Mont/akile_monitor/releases/latest/download/$CLIENT_FILE"
fi
chmod +x client

# Create OpenRC service file
cat > /etc/init.d/ak_client << 'EOF'
#!/sbin/openrc-run

description="AkileCloud Monitor Service"
command="/etc/ak_monitor/client"
command_background="yes"
pidfile="/run/ak_client.pid"
directory="/etc/ak_monitor/"
start_stop_daemon_args="--user root --group root"

depend() {
    need net
    after net
}
EOF

# Create client configuration with disk and proxy settings
cat > /etc/ak_monitor/client.json << EOF
{
    "auth_secret": "${auth_secret}",
    "url": "${url}",
    "net_name": "${net_name}",
    "name": "${monitor_name}",
    "disk_devices": ${disk_devices},
    "proxy": {
        "enabled": ${proxy_enabled},
        "type": "${proxy_type}",
        "address": "${proxy_address}"
    }
}
EOF

# Set proper permissions
chmod 644 /etc/ak_monitor/client.json
chmod 755 /etc/init.d/ak_client

# Enable and start the service with OpenRC
rc-update add ak_client default
rc-service ak_client start

echo "Installation complete! Service status:"
rc-service ak_client status

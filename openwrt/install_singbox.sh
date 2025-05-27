#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

if command -v sing-box &> /dev/null; then
    echo -e "${CYAN}sing-box 已安装，跳过安装步骤${NC}"
else
    echo "正在更新包列表并安装 sing-box,请稍候..."
    opkg update >/dev/null 2>&1
    opkg install kmod-nft-tproxy >/dev/null 2>&1
    opkg install sing-box >/dev/null 2>&1

    if command -v sing-box &> /dev/null; then
        echo -e "${CYAN}sing-box 安装成功${NC}"
    else
        echo -e "${RED}sing-box 安装失败，请检查日志或网络配置${NC}"
        exit 1
    fi
fi

# 清空原有sing-box服务脚本
if [ -f /etc/init.d/sing-box ]; then
    > /etc/init.d/sing-box
fi

cat << 'EOF' >> /etc/init.d/sing-box
#!/bin/sh /etc/rc.common

# OpenWrt init.d script for sing-box
START=99
STOP=10
USE_PROCD=1

NAME=sing-box
PROG=/usr/bin/sing-box
CONFIG_FILE=/etc/sing-box/config.json

start_service() {
    procd_open_instance
    procd_set_param command "$PROG" run -c "$CONFIG_FILE"
    procd_set_param respawn
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_set_param file "$CONFIG_FILE"  # Reload on config change
    procd_set_param netdev "eth0"        # Depend on eth0 interface
    procd_close_instance
    
    # Post-startup configuration
    (
        # Wait for service to be ready
        local timeout=10
        local count=0
        
        while [ $count -lt $timeout ]; do
            if pgrep -f "$PROG" > /dev/null 2>&1; then
                configure_network_mode
                exit 0
            fi
            sleep 1
            count=$((count + 1))
        done
        
        logger -t "$NAME" "Service failed to start within timeout"
        exit 1
    ) &
}

service_triggers() {
    procd_add_config_trigger "config.change" "sing-box" /etc/init.d/sing-box reload
    
    # Add trigger for eth0 interface changes
    procd_add_interface_trigger "interface.*.up" "eth0" /etc/init.d/sing-box restart
}

configure_network_mode() {
    # Configure networking based on mode - called after service starts
    if [ -f /etc/sing-box/mode.conf ]; then
        local MODE
        MODE=$(grep -oE '^MODE=.*' /etc/sing-box/mode.conf | cut -d'=' -f2)
        case "$MODE" in
            "TProxy")
                logger -t "$NAME" "Applying TProxy firewall rules"
                if ! /etc/sing-box/scripts/configure_tproxy.sh; then
                    logger -t "$NAME" "ERROR: TProxy firewall rules failed - stopping service"
                    /etc/init.d/sing-box stop
                    return 1
                fi
                logger -t "$NAME" "TProxy firewall rules applied successfully"
                ;;
            "TUN")
                logger -t "$NAME" "Applying TUN firewall rules"
                if ! /etc/sing-box/scripts/configure_tun.sh; then
                    logger -t "$NAME" "ERROR: TUN firewall rules failed - stopping service"
                    /etc/init.d/sing-box stop
                    return 1
                fi
                logger -t "$NAME" "TUN firewall rules applied successfully"
                ;;
        esac
    fi
}

stop_service() {
    # Cleanup nftables rules when stopping
    cleanup_firewall_rules
    logger -t "$NAME" "Service stopped"
}

cleanup_firewall_rules() {
    # Clean up all nftables rules
    logger -t "$NAME" "Cleaning up nftables rules"
    /etc/sing-box/scripts/clean_nft.sh
}

reload_service() {
    # Custom reload logic if needed
    stop
    start
}
EOF

chmod +x /etc/init.d/sing-box

/etc/init.d/sing-box enable
/etc/init.d/sing-box start

echo -e "${CYAN}sing-box 服务已启用并启动${NC}"

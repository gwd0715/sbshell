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
MODE_FILE=/etc/sing-box/mode.conf
TPROXY_SCRIPT=/etc/sing-box/scripts/configure_tproxy.sh

# Define physical interfaces for procd_set_param netdev
PHYSICAL_INTERFACES="eth0 eth2 sta1"
# Define logical interfaces for triggers and availability check
LOGICAL_INTERFACES="wan wwan tethering"

start_service() {
    sleep 6
    # Check if at least one required logical interface is up before starting
    if ! check_interface_availability; then
        logger -t "$NAME" "No required logical interfaces available (wan, wwan, tethering) - delaying start"
        return 1
    fi
    
    # Check if TProxy mode is enabled and configure if needed BEFORE starting service
    if ! configure_tproxy_if_needed; then
        logger -t "$NAME" "TProxy configuration failed - aborting service start"
        return 1
    fi
    
    procd_open_instance
    procd_set_param user root
    procd_set_param command "$PROG" run -c "$CONFIG_FILE"
    procd_set_param respawn
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_set_param file "$CONFIG_FILE"  # Reload on config change
    
    # Add netdev param with physical device names to make procd track interface changes
    # This enables procd to restart the service when physical interfaces change
    procd_set_param netdev $PHYSICAL_INTERFACES
    
    procd_close_instance
    
    logger -t "$NAME" "Service started successfully"
}

check_interface_availability() {
    # Check if at least one logical interface has IP and connectivity
    for iface in $LOGICAL_INTERFACES; do
        if ubus call network.interface."$iface" status >/dev/null 2>&1; then
            if ubus call network.interface."$iface" status | grep -q '"up": true' && \
               ubus call network.interface."$iface" status | grep -q '"ipv4-address"'; then
                # Also verify default route exists
                if ip route | grep -q "^default"; then
                    logger -t "$NAME" "Interface $iface is ready with IP and route"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

configure_tproxy_if_needed() {
    # Check if mode file contains MODE=TProxy
    if [ -f "$MODE_FILE" ]; then
        if grep -q "^MODE=TProxy$" "$MODE_FILE"; then
            logger -t "$NAME" "TProxy mode detected - executing configuration script"
            if "$TPROXY_SCRIPT"; then
                logger -t "$NAME" "TProxy configuration completed successfully"
                return 0
            else
                logger -t "$NAME" "TProxy configuration failed - script returned error"
                return 1
            fi
        fi
    fi
    return 0  # No TProxy mode or no mode file - continue normally
}

service_triggers() {
    procd_add_config_trigger "config.change" "sing-box" /etc/init.d/sing-box reload
    procd_open_trigger   
    # Add triggers for all required logical interfaces
    for iface in $LOGICAL_INTERFACES; do
        procd_add_interface_trigger "interface.*.up" "$iface" /etc/init.d/sing-box restart
    done  
    procd_close_trigger
}

stop_service() {
    logger -t "$NAME" "Service stopped"
    # Note: We don't remove TProxy rules on stop as they might be needed by other services
    # or the rules might be persistent across reboots
}

reload_service() {
    logger -t "$NAME" "Service reload triggered"
    # Custom reload logic if needed
    stop
    start
}

# Custom restart function to add logging
restart() {
    logger -t "$NAME" "Interface change detected - restarting service"
    stop
    start
}
EOF

chmod +x /etc/init.d/sing-box

/etc/init.d/sing-box enable
/etc/init.d/sing-box start

echo -e "${CYAN}sing-box 服务已启用并启动${NC}"

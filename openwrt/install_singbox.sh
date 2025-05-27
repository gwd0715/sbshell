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

# Define required interfaces
REQUIRED_INTERFACES="eth0 eth2 sta1"

start_service() {
    # Check if at least one required interface is up before starting

    procd_open_instance
    procd_set_param command "$PROG" run -c "$CONFIG_FILE"
    procd_set_param respawn
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_set_param file "$CONFIG_FILE"  # Reload on config change
    
    # Add netdev params to make procd track interface changes
    # This enables procd to restart the service when interfaces change
    for iface in $REQUIRED_INTERFACES; do
        procd_set_param netdev "$iface"
    done
    
    procd_close_instance
    
    logger -t "$NAME" "Service started successfully"
}

service_triggers() {
    procd_add_config_trigger "config.change" "sing-box" /etc/init.d/sing-box reload
    
    # Add triggers for all required interfaces
    # Now that we use procd_set_param netdev, these triggers will work properly
    for iface in $REQUIRED_INTERFACES; do
        procd_add_interface_trigger "interface.*.up" "$iface" /etc/init.d/sing-box restart
    done
}

stop_service() {
    logger -t "$NAME" "Service stopped"
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

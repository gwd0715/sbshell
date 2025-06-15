#!/bin/bash

# 配置参数
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5}')

# 读取当前模式
MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf | sed 's/^MODE=//')

# 清理 TProxy 模式的防火墙规则
clearTProxyRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null
    ip route del local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE 2>/dev/null
    echo "清理 TProxy 模式的防火墙规则"
}

if [ "$MODE" = "TUN" ]; then
    echo "应用 TUN 模式下的防火墙规则..."

    # 清理 TProxy 模式的防火墙规则
    clearTProxyRules

    # 等待 sing-box 自动创建 nftables 表
    RETRY=10
    while ! nft list tables | grep -q 'inet sing-box'; do
        echo "等待 inet sing-box 表创建..."
        sleep 1
        RETRY=$((RETRY - 1))
        [ "$RETRY" -le 0 ] && echo "超时退出，sing-box 的表未创建。" && exit 1
    done

    # 创建白名单集合（如果尚未存在）
    nft list table inet sing-box | grep -q 'whitelist_host_ipv4' || \
    nft add set inet sing-box whitelist_host_ipv4 { type ipv4_addr\; }

    # 添加白名单 IP（避免重复添加）
    nft add element inet sing-box whitelist_host_ipv4 { 192.168.3.3, 192.168.3.4 } 2>/dev/null

    # 插入规则
    nft insert rule inet sing-box output ip saddr @whitelist_host_ipv4 return
    nft insert rule inet sing-box output_udp_icmp ip saddr @whitelist_host_ipv4 return
    nft insert rule inet sing-box prerouting ip saddr @whitelist_host_ipv4 return

    echo "TUN 模式的防火墙规则已应用。"
else
    echo "当前模式不是 TUN 模式，跳过防火墙规则配置。" >/dev/null 2>&1
fi

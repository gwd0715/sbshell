#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # 无颜色

# 配置文件路径
CONFIG_FILE="/etc/sing-box/config.json"
MANUAL_FILE="/etc/sing-box/manual.conf"
DEFAULTS_FILE="/etc/sing-box/defaults.conf"

# 检查现有配置文件是否有效
check_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${CYAN}检测到现有配置文件: $CONFIG_FILE${NC}"
        if sing-box check -c "$CONFIG_FILE" &>/dev/null; then
            echo -e "${GREEN}当前配置文件验证通过${NC}"
            read -rp "是否使用当前配置文件？(y/n): " use_existing
            if [[ "$use_existing" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}将使用现有配置文件，不进行更新${NC}"
                exit 0
            else
                echo -e "${CYAN}将继续更新配置文件...${NC}"
            fi
        else
            echo -e "${RED}当前配置文件验证失败，将进行更新${NC}"
        fi
    else
        echo -e "${CYAN}未找到现有配置文件，将进行创建${NC}"
    fi
}

# 获取当前模式
MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf | sed 's/^MODE=//')

prompt_user_input() {
    read -rp "请输入后端地址(回车使用默认值可留空): " BACKEND_URL
    if [ -z "$BACKEND_URL" ]; then
        BACKEND_URL=$(grep BACKEND_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
        echo -e "${CYAN}使用默认后端地址: $BACKEND_URL${NC}"
    fi

    read -rp "请输入订阅地址(回车使用默认值可留空): " SUBSCRIPTION_URL
    if [ -z "$SUBSCRIPTION_URL" ]; then
        SUBSCRIPTION_URL=$(grep SUBSCRIPTION_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
        echo -e "${CYAN}使用默认订阅地址: $SUBSCRIPTION_URL${NC}"
    fi

    read -rp "请输入配置文件地址(回车使用默认值可留空): " TEMPLATE_URL
    if [ -z "$TEMPLATE_URL" ]; then
        if [ "$MODE" = "TProxy" ]; then
            TEMPLATE_URL=$(grep TPROXY_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            echo -e "${CYAN}使用默认 TProxy 配置文件地址: $TEMPLATE_URL${NC}"
        elif [ "$MODE" = "TUN" ]; then
            TEMPLATE_URL=$(grep TUN_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            echo -e "${CYAN}使用默认 TUN 配置文件地址: $TEMPLATE_URL${NC}"
        else
            echo -e "${RED}未知的模式: $MODE${NC}"
            exit 1
        fi
    fi
}

# 主程序
check_existing_config

while true; do
    prompt_user_input

    echo -e "${CYAN}你输入的配置信息如下:${NC}"
    echo "后端地址: $BACKEND_URL"
    echo "订阅地址: $SUBSCRIPTION_URL"
    echo "配置文件地址: $TEMPLATE_URL"
    read -rp "确认输入的配置信息？(y/n): " confirm_choice
    if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
        # 更新手动输入的配置文件
        cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF

        echo "手动输入的配置已更新"

        # 构建完整的配置文件URL
        if [ -n "$BACKEND_URL" ] && [ -n "$SUBSCRIPTION_URL" ]; then
            FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"
        else
            FULL_URL="${TEMPLATE_URL}"
        fi
        echo "生成完整订阅链接: $FULL_URL"

        while true; do
            # 下载并验证配置文件
            if curl -L --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE"; then
                echo "配置文件下载完成"
                if sing-box check -c "$CONFIG_FILE"; then
                    echo -e "${GREEN}配置文件验证成功！${NC}"
                    break
                else
                    echo -e "${RED}配置文件验证失败${NC}"
                    read -rp "是否重试下载？(y/n): " retry_choice
                    if [[ "$retry_choice" =~ ^[Nn]$ ]]; then
                        exit 1
                    fi
                fi
            else
                echo "配置文件下载失败"
                read -rp "下载失败，是否重试？(y/n): " retry_choice
                if [[ "$retry_choice" =~ ^[Nn]$ ]]; then
                    exit 1
                fi
            fi
        done

        break
    else
        echo -e "${RED}请重新输入配置信息。${NC}"
    fi
done
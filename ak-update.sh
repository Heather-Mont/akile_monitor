#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 判断系统架构
ARCH=$(uname -m)
MONITOR_FILE="akile_monitor-linux-amd64"
CLIENT_FILE="akile_client-linux-amd64"

if [ "$ARCH" = "x86_64" ]; then
    MONITOR_FILE="akile_monitor-linux-amd64"
    CLIENT_FILE="akile_client-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    MONITOR_FILE="akile_monitor-linux-arm64"
    CLIENT_FILE="akile_client-linux-arm64"
elif [ "$ARCH" = "x86_64" ] && [ "$(uname -s)" = "Darwin" ]; then
    MONITOR_FILE="akile_monitor-darwin-amd64"
    CLIENT_FILE="akile_client-darwin-amd64"
else
    echo "不支持的系统架构: $ARCH"
    exit 1
fi

function update_monitor_fe() {
    echo "正在更新主控前端..."
    
    # 检查是否安装了主控前端
    if [ ! -d "/etc/ak_monitor/frontend" ]; then
        echo "未检测到主控前端安装，请先安装主控前端"
        return
    fi
    
    cd /etc/ak_monitor/frontend
    
    # 创建临时目录
    echo "创建临时目录..."
    TEMP_DIR=$(mktemp -d)
    
    # 下载到临时目录
    echo "下载新版本..."
    cd "$TEMP_DIR"
    wget -O frontend.zip https://github.com/akile-network/akile_monitor_fe/releases/download/v.0.0.2/akile_monitor_fe.zip
    
    # 备份当前版本
    echo "备份当前版本..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p /etc/ak_monitor/backup
    cd /etc/ak_monitor/frontend
    tar -czf "/etc/ak_monitor/backup/frontend_${timestamp}.tar.gz" ./*
    
    # 在临时目录解压并处理
    echo "解压新版本..."
    cd "$TEMP_DIR"
    unzip -o frontend.zip
    rm frontend.zip
    
    # 如果存在 config.json，删除它
    if [ -f "$TEMP_DIR/config.json" ]; then
        echo "移除新版本中的配置文件..."
        rm "$TEMP_DIR/config.json"
    fi
    
    # 复制新文件到目标目录，排除 config.json
    echo "更新文件..."
    cp -rf "$TEMP_DIR"/* /etc/ak_monitor/frontend/
    
    # 清理临时目录
    echo "清理临时文件..."
    rm -rf "$TEMP_DIR"
    
    # 重启 Caddy 服务
    echo "重启 Caddy 服务..."
    systemctl restart caddy
    
    echo "主控前端更新完成！"
}

function update_monitor() {
    echo "正在更新主控后端..."
    
    # 检查是否安装了主控后端
    if [ ! -f "/etc/ak_monitor/config.json" ]; then
        echo "未检测到主控后端安装，请先安装主控后端"
        return
    fi
    
    # 停止服务
    systemctl stop ak_monitor
    
    cd /etc/ak_monitor/
    
    # 备份当前版本
    echo "备份当前版本..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp ak_monitor "ak_monitor.backup.${timestamp}"
    
    # 下载新版本
    echo "下载新版本..."
    wget -O ak_monitor https://github.com/akile-network/akile_monitor/releases/latest/download/$MONITOR_FILE
    chmod 777 ak_monitor
    
    # 重启服务
    systemctl start ak_monitor
    
    echo "主控后端更新完成！"
}

function update_client() {
    echo "正在更新被控..."
    
    # 检查是否安装了被控
    if [ ! -f "/etc/ak_monitor/client.json" ]; then
        echo "未检测到被控安装，请先安装被控"
        return
    fi
    
    # 停止服务
    systemctl stop ak_client
    
    cd /etc/ak_monitor/
    
    # 备份当前版本
    echo "备份当前版本..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp client "client.backup.${timestamp}"
    
    # 下载新版本
    echo "下载新版本..."
    wget -O client https://github.com/akile-network/akile_monitor/releases/latest/download/$CLIENT_FILE
    chmod 777 client
    
    # 重启服务
    systemctl start ak_client
    
    echo "被控更新完成！"
}

# 主菜单
while true; do
    clear
    echo "=================================================="
    echo "AkileCloud Monitor 更新脚本"
    echo "=================================================="
    echo "1. 更新主控前端"
    echo "2. 更新主控后端"
    echo "3. 更新被控"
    echo "4. 退出"
    echo "=================================================="

    read -p "请选择要执行的操作 (1-4): " choice

    case $choice in
        1)
            update_monitor_fe
            ;;
        2)
            update_monitor
            ;;
        3)
            update_client
            ;;
        4)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效的选项，请重新选择"
            ;;
    esac

    echo
    read -p "按回车键继续..."
done

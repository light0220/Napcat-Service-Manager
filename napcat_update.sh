#!/bin/bash
# napcat_update.sh - 自动更新Napcat（采用官方最新安装脚本）

# 配置
NAPCAT_DIR="/root/Napcat"
UPDATE_LOG="/var/log/napcat_update.log"
INSTALL_SCRIPT="napcat.sh"
INSTALL_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数（同时输出到控制台和日志文件）
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] $1" | tee -a "$UPDATE_LOG"
}

# 检查Napcat是否运行
check_running() {
    if systemctl is-active --quiet napcat; then
        return 0  # 运行中
    else
        return 1  # 未运行
    fi
}

# 备份当前版本（防止更新失败）
backup_current_version() {
    if [ -d "$NAPCAT_DIR" ]; then
        local backup_dir="${NAPCAT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        log "备份当前版本到 $backup_dir..."
        cp -r "$NAPCAT_DIR" "$backup_dir" || log "${YELLOW}警告：部分文件备份失败${NC}"
    fi
}

# 主更新流程
main() {
    log "======================================"
    log "开始Napcat自动更新检查"
    
    # 检查安装目录是否存在
    if [ ! -d "$NAPCAT_DIR" ]; then
        log "${RED}错误：未找到Napcat安装目录 $NAPCAT_DIR${NC}"
        exit 1
    fi
    
    # 记录更新前状态
    check_running
    local was_running=$?  # 0=运行中，1=未运行
    
    # 备份当前版本
    # backup_current_version
    
    # 下载最新安装脚本
    log "下载最新安装脚本..."
    if ! curl -sSL -o "$INSTALL_SCRIPT" "$INSTALL_URL"; then
        log "${RED}错误：下载安装脚本失败${NC}"
        exit 1
    fi
    
    # 赋予执行权限
    chmod +x "$INSTALL_SCRIPT"
    
    # 运行安装脚本（使用指定参数）
    log "开始执行更新..."
    if sudo bash "$INSTALL_SCRIPT" --docker n --cli n --force; then
        log "${GREEN}安装脚本执行成功${NC}"
    else
        log "${RED}错误：安装脚本执行失败${NC}"
        exit 1
    fi
    
    # 清理临时脚本
    rm -f "$INSTALL_SCRIPT"
    
    # 重启服务确保更新生效
    log "重启Napcat服务..."
    if systemctl restart napcat; then
        log "${GREEN}Napcat服务重启成功${NC}"
    else
        log "${RED}错误：Napcat服务重启失败${NC}"
        exit 1
    fi
    
    log "${GREEN}自动更新完成${NC}"
    log "======================================"
}

# 执行主流程
main
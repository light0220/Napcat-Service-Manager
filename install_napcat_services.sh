#!/bin/bash
# install_napcat_services.sh - 安装Napcat开机自启动和自动更新服务

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] ${1}"
}

# 检查是否以root用户运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "${RED}错误: 此脚本需要以root用户运行${NC}"
        exit 1
    fi
}

# 检查Napcat安装目录
check_napcat_installation() {
    INSTALL_BASE_DIR="/root/Napcat"
    QQ_BASE_PATH="${INSTALL_BASE_DIR}/opt/QQ"
    
    log "检查Napcat安装..."
    
    if [ ! -d "${INSTALL_BASE_DIR}" ]; then
        log "${RED}错误: 未找到Napcat安装目录 ${INSTALL_BASE_DIR}${NC}"
        exit 1
    fi
    
    if [ ! -f "${QQ_BASE_PATH}/qq" ]; then
        log "${RED}错误: QQ可执行文件不存在${NC}"
        exit 1
    fi
    
    log "${GREEN}Napcat安装检查通过${NC}"
}

# 安装systemd服务
install_systemd_service() {
    log "安装systemd服务..."
    
    # 复制服务文件到系统目录
    cp napcat.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/napcat.service
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用并启动服务
    systemctl enable napcat
    systemctl start napcat
    
    # 检查服务状态
    if systemctl is-active --quiet napcat; then
        log "${GREEN}Napcat服务启动成功${NC}"
    else
        log "${YELLOW}Napcat服务启动失败，状态如下:${NC}"
        systemctl status napcat --no-pager
    fi
}

# 安装自动更新脚本
install_update_script() {
    log "安装自动更新脚本..."
    
    # 复制更新脚本到系统可执行目录
    cp napcat_update.sh /usr/local/bin/
    chmod +x /usr/local/bin/napcat_update.sh
    
    # 创建日志文件
    # touch /var/log/napcat_update.log
    # chmod 644 /var/log/napcat_update.log
}

# 配置定时任务
configure_crontab() {
    log "配置定时任务..."
    
    # 检查是否已有定时任务
    if crontab -l 2>/dev/null | grep -q "napcat_update.sh"; then
        log "${YELLOW}已存在自动更新定时任务，跳过配置${NC}"
        return
    fi
    
    # 添加每天凌晨3点执行的任务
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/napcat_update.sh") | crontab -
}

# 显示安装完成信息
show_completion_info() {
    log "======================================"
    log "所有服务安装完成！"
    log "======================================"
    log "服务管理命令:"
    log "  启动: systemctl start napcat"
    log "  停止: systemctl stop napcat"
    log "  重启: systemctl restart napcat"
    log "  状态: systemctl status napcat"
    log ""
    log "更新相关:"
    log "  手动更新: /usr/local/bin/napcat_update.sh"
    log "  更新日志目录: /var/log/napcat_update/"
    log "  自动更新时间: 每天凌晨3点"
    log "======================================"
}

# 主函数
main() {
    log "开始安装Napcat服务组件..."
    check_root
    check_napcat_installation
    install_systemd_service
    install_update_script
    configure_crontab
    show_completion_info
    log "${GREEN}部署完成！${NC}"
}

# 执行主函数
main "$@"
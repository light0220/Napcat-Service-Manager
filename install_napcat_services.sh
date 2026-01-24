#!/bin/bash

###
 # @作    者 : 北极星光 light22@126.com
 # @创建时间 : 2025-10-30 15:46:31
 # @最后修改 : 2026-01-24 16:48:42
 # @修 改 者 : 北极星光
### 

# 日志配置
LOG_DIR="/var/log/napcat_update"
LOG_FILE="${LOG_DIR}/install_napcat_services.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 确保日志目录存在并设置权限
init_log() {
    # 创建日志目录（不存在则创建）
    if [ ! -d "${LOG_DIR}" ]; then
        mkdir -p "${LOG_DIR}"
        chmod 755 "${LOG_DIR}" # 只读权限，避免篡改
    fi
    # 创建日志文件（不存在则创建）
    if [ ! -f "${LOG_FILE}" ]; then
        touch "${LOG_FILE}"
        chmod 644 "${LOG_FILE}" # 读写权限
    fi
}

# 日志函数：同时输出到终端和日志文件（保留颜色）
log() {
    local timestamp="[$(date +"%Y-%m-%d %H:%M:%S")]"
    local message="${timestamp} ${1}"
    # 输出到终端（保留颜色）
    echo -e "${message}"
    # 输出到日志文件（去除颜色码，避免日志乱码）
    echo -e "${message}" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g' >> "${LOG_FILE}"
}

# 检查是否以root用户运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "${RED}错误: 此脚本需要以root用户运行${NC}"
        exit 1
    fi
}

# 自动安装Napcat
install_napcat() {
    log "${YELLOW}未检测到Napcat，开始自动安装...${NC}"
    
    # 优化curl检测逻辑：多种方式确认curl是否存在
    check_curl() {
        # 方式1：command -v（标准检测）
        if command -v curl &> /dev/null; then
            log "${GREEN}已检测到curl（路径：$(command -v curl)）${NC}"
            return 0
        fi
        # 方式2：which检测（兼容部分特殊环境）
        if which curl &> /dev/null; then
            log "${GREEN}已检测到curl（路径：$(which curl)）${NC}"
            return 0
        fi
        # 方式3：直接检查常见路径（改用字符串列表，兼容所有Shell）
        local curl_paths="/usr/bin/curl /usr/local/bin/curl /bin/curl"
        for path in $curl_paths; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                log "${GREEN}已检测到curl（路径：$path）${NC}"
                export PATH="$PATH:$(dirname "$path")" # 确保路径在PATH中
                return 0
            fi
        done
        # 所有方式都未检测到
        return 1
    }

    # 执行curl检测
    if ! check_curl; then
        log "${YELLOW}未安装curl，正在安装...${NC}"
        
        # 兼容Debian/Ubuntu系（apt），若为CentOS可替换为yum
        if command -v apt &> /dev/null; then
            # 增加--fix-missing修复依赖，-qq减少输出
            apt update -qq &> /dev/null || log "${YELLOW}apt更新缓存失败，尝试直接安装curl${NC}"
            apt install -y -qq curl --fix-missing &> /dev/null
        elif command -v yum &> /dev/null; then
            yum install -y curl &> /dev/null
        else
            log "${RED}错误: 未识别到包管理器（apt/yum），无法安装curl${NC}"
            exit 1
        fi

        # 安装后再次检测，避免假失败
        if ! check_curl; then
            log "${RED}错误: 安装curl失败，无法下载Napcat安装脚本${NC}"
            exit 1
        fi
    fi

    # 定义安装脚本下载路径
    INSTALL_SCRIPT="/tmp/install.sh"
    # 下载Napcat安装脚本（增加超时时间和重试机制）
    log "下载Napcat安装脚本..."
    if ! curl -fsSL --connect-timeout 10 --retry 3 https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh -o "${INSTALL_SCRIPT}"; then
        log "${RED}错误: 下载Napcat安装脚本失败（请检查网络连接）${NC}"
        exit 1
    fi

    # 赋予执行权限并执行安装命令
    chmod +x "${INSTALL_SCRIPT}"
    log "执行Napcat安装脚本: bash install.sh --docker n --cli n --force"
    # 安装过程的输出也写入日志（保留详细信息）
    if ! bash "${INSTALL_SCRIPT}" --docker n --cli n --force 2>&1 | tee -a "${LOG_FILE}"; then
        log "${RED}错误: Napcat安装执行失败${NC}"
        rm -f "${INSTALL_SCRIPT}" # 清理临时脚本
        exit 1
    fi

    # 清理临时安装脚本
    rm -f "${INSTALL_SCRIPT}"
    log "${GREEN}Napcat自动安装完成${NC}"
}

# 检查Napcat安装目录（未安装则自动安装）
check_napcat_installation() {
    INSTALL_BASE_DIR="/root/Napcat"
    QQ_BASE_PATH="${INSTALL_BASE_DIR}/opt/QQ"
    
    log "检查Napcat安装..."
    
    # 检查核心文件是否存在
    if [ ! -d "${INSTALL_BASE_DIR}" ] || [ ! -f "${QQ_BASE_PATH}/qq" ]; then
        log "${YELLOW}Napcat安装目录或核心文件不存在${NC}"
        # 调用自动安装函数
        install_napcat
        
        # 安装完成后重新检查
        log "重新检查Napcat安装状态..."
        if [ ! -d "${INSTALL_BASE_DIR}" ] || [ ! -f "${QQ_BASE_PATH}/qq" ]; then
            log "${RED}错误: Napcat安装后仍未检测到核心文件${NC}"
            exit 1
        fi
    fi
    
    log "${GREEN}Napcat安装检查通过${NC}"
}

# 安装systemd服务
install_systemd_service() {
    log "安装systemd服务..."
    
    # 复制服务文件到系统目录
    if ! cp napcat.service /etc/systemd/system/; then
        log "${RED}错误: 复制napcat.service文件失败${NC}"
        exit 1
    fi
    chmod 644 /etc/systemd/system/napcat.service
    
    # 重新加载systemd配置
    systemctl daemon-reload &> /dev/null
    
    # 启用并启动服务
    systemctl enable napcat &> /dev/null
    systemctl start napcat &> /dev/null
    
    # 检查服务状态
    if systemctl is-active --quiet napcat; then
        log "${GREEN}Napcat服务启动成功${NC}"
    else
        log "${YELLOW}Napcat服务启动失败，状态如下:${NC}"
        # 服务状态输出也写入日志
        systemctl status napcat --no-pager 2>&1 | tee -a "${LOG_FILE}"
    fi
}

# 安装自动更新脚本
install_update_script() {
    log "安装自动更新脚本..."
    
    # 复制更新脚本到系统可执行目录
    if ! cp napcat_update.sh /usr/local/bin/; then
        log "${RED}错误: 复制napcat_update.sh文件失败${NC}"
        exit 1
    fi
    chmod +x /usr/local/bin/napcat_update.sh
}

# 配置定时任务
configure_crontab() {
    log "配置定时任务..."
    
    # 检查是否已有定时任务
    if crontab -l 2>/dev/null | grep -q "napcat_update.sh"; then
        log "${YELLOW}已存在自动更新定时任务，跳过配置${NC}"
        return
    fi
    
    # 添加每天凌晨3点执行的任务（输出日志到文件）
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/napcat_update.sh >> ${LOG_DIR}/napcat_update.log 2>&1") | crontab -
    if [ $? -eq 0 ]; then
        log "${GREEN}定时任务配置成功${NC}"
    else
        log "${RED}错误: 定时任务配置失败${NC}"
        exit 1
    fi
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
    log "  安装日志文件: ${LOG_FILE}"
    log "  更新日志目录: ${LOG_DIR}"
    log "  自动更新时间: 每天凌晨3点"
    log "======================================"
}

# 主函数
main() {
    # 初始化日志目录和文件
    init_log
    # 输出启动信息（同时写入日志）
    log "======================================"
    log "开始安装Napcat服务组件"
    log "======================================"
    
    check_root
    check_napcat_installation
    install_systemd_service
    install_update_script
    configure_crontab
    show_completion_info
    log "${GREEN}部署完成！所有执行日志已保存到 ${LOG_FILE}${NC}"
}

# 执行主函数（确保所有输出都被日志函数捕获）
main "$@"
#!/bin/bash
# napcat_update.sh - 自动更新Napcat（带详细日志和重试机制）

# 配置
NAPCAT_DIR="/root/Napcat"
UPDATE_LOG="/var/log/napcat_update.log"
INSTALL_SCRIPT="napcat.sh"
INSTALL_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"
# 版本检查API配置
LATEST_VERSION_URL="https://github.com/NapNeko/NapCatQQ/releases/latest"  # 修正仓库地址
LOCAL_API_URL="http://localhost:7777/get_version_info"
RETRY_DELAY=10  # 重试间隔（秒）
MAX_RETRIES=3   # 新增最大重试次数定义

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数（同时输出到控制台和日志文件，带颜色标记）
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

# 更新：使用curl POST请求获取当前版本（通过本地API）
get_current_version() {
    local retries=$MAX_RETRIES
    local version="unknown"
    
    while [ $retries -gt 0 ]; do
        # 使用curl发送POST请求，带Content-Type头和空JSON数据
        response=$(curl -sSL --location --request POST "$LOCAL_API_URL" \
            --header "Content-Type: application/json" \
            --data-raw "{}" 2>>"$UPDATE_LOG")
        
        # 检查响应是否有效并解析JSON
        if [ -n "$response" ]; then
            # 修正解析路径，从data对象中提取app_version
            version=$(echo "$response" | grep -o '"app_version":"[^"]*' | sed 's/"app_version":"//')
            if [ -n "$version" ]; then
                echo "$version"
                return 0
            fi
        fi
        
        log "${YELLOW}获取当前版本失败，重试中（剩余$((retries-1))次）${NC}"
        retries=$((retries - 1))
        sleep $RETRY_DELAY
    done
    
    echo "unknown"
    return 1
}

# 获取最新版本（通过GitHub最新发布页面重定向）
get_latest_version() {
    local retries=$MAX_RETRIES
    local version="unknown"
    
    while [ $retries -gt 0 ]; do
        # 通过跟随重定向获取最新版本标签
        # -I 只获取响应头，-L 跟随重定向
        response=$(curl -sSL -I -L "$LATEST_VERSION_URL" 2>>"$UPDATE_LOG")
        
        if [ -n "$response" ]; then
            # 从Location头中提取版本号（GitHub最新发布会重定向到具体版本页面）
            version=$(echo "$response" | grep -i 'Location:' | awk -F '/' '{print $NF}' | tr -d '\r')
            if [ -n "$version" ] && [ "$version" != "latest" ]; then
                echo "$version"
                return 0
            fi
        fi
        
        log "${YELLOW}获取最新版本失败，重试中（剩余$((retries-1))次）${NC}"
        retries=$((retries - 1))
        sleep $RETRY_DELAY
    done
    
    echo "unknown"
    return 1
}

# 比较版本号（简单比较，适用于vX.Y.Z格式）
version_gt() {
    # 移除版本号中的v前缀进行比较
    local ver1=$(echo "$1" | sed 's/^v//')
    local ver2=$(echo "$2" | sed 's/^v//')
    [ "$(printf "%s\n" "$ver1" "$ver2" | sort -V | tail -n1)" = "$ver1" ] && [ "$ver1" != "$ver2" ]
}

# 带重试的下载函数
download_with_retry() {
    local url=$1
    local output=$2
    local retries=$MAX_RETRIES
    
    log "开始下载: $url"
    
    while [ $retries -gt 0 ]; do
        if curl -sSL -w "HTTP状态码: %{http_code}\n" -o "$output" "$url" 2>>"$UPDATE_LOG"; then
            if [ -s "$output" ]; then
                log "${GREEN}下载成功${NC}"
                return 0
            else
                log "${YELLOW}下载文件为空，重试中（剩余$((retries-1))次）${NC}"
            fi
        else
            log "${YELLOW}下载失败，重试中（剩余$((retries-1))次）${NC}"
        fi
        
        retries=$((retries - 1))
        sleep $RETRY_DELAY
    done
    
    log "${RED}达到最大重试次数，下载失败${NC}"
    return 1
}

# 带重试的安装执行函数
execute_install_with_retry() {
    local script=$1
    local retries=$MAX_RETRIES
    
    log "开始执行安装脚本..."
    
    while [ $retries -gt 0 ]; do
        if bash "$script" --docker n --cli n --force > >(tee -a "$UPDATE_LOG") 2> >(tee -a "$UPDATE_LOG" >&2); then
            log "${GREEN}安装脚本执行成功${NC}"
            return 0
        else
            log "${YELLOW}安装脚本执行失败，重试中（剩余$((retries-1))次）${NC}"
        fi
        
        retries=$((retries - 1))
        sleep $RETRY_DELAY
    done
    
    log "${RED}达到最大重试次数，安装失败${NC}"
    return 1
}

# 主更新流程
main() {
    > "$UPDATE_LOG"
    log "======================================"
    log "开始Napcat自动更新检查"
    log "最大重试次数: $MAX_RETRIES 次，间隔: $RETRY_DELAY 秒"
    
    if [ ! -d "$NAPCAT_DIR" ]; then
        log "${RED}错误：未找到Napcat安装目录 $NAPCAT_DIR${NC}"
        exit 1
    fi
    
    # 获取当前版本和最新版本
    log "检查当前版本..."
    local current_version=$(get_current_version)
    log "当前版本: $current_version"
    
    log "检查最新版本..."
    local latest_version=$(get_latest_version)
    log "最新版本: $latest_version"
    
    # 版本检查与比较
    if [ "$current_version" = "unknown" ] || [ "$latest_version" = "unknown" ]; then
        log "${YELLOW}版本信息获取不完整，无法判断是否需要更新${NC}"
        exit 1
    fi
    
    if ! version_gt "$latest_version" "$current_version"; then
        log "${GREEN}当前已是最新版本（$current_version），无需更新${NC}"
        exit 0
    fi
    
    log "${YELLOW}发现新版本（$latest_version），开始更新...${NC}"
    
    # 记录运行状态并下载安装脚本
    check_running
    local was_running=$?  # 0=运行中，1=未运行
    
    # 下载最新安装脚本
    if ! download_with_retry "$INSTALL_URL" "$INSTALL_SCRIPT"; then
        log "${RED}错误：安装脚本下载失败，更新终止${NC}"
        exit 1
    fi
    
    # 赋予执行权限
    chmod +x "$INSTALL_SCRIPT"
    
    # 执行安装脚本
    if ! execute_install_with_retry "$INSTALL_SCRIPT"; then
        log "${RED}错误：安装脚本执行失败，更新终止${NC}"
        exit 1
    fi
    
    # 清理临时脚本
    rm -f "$INSTALL_SCRIPT"
    
    # 重启服务
    log "重启Napcat服务..."
    if systemctl restart napcat; then
        log "${GREEN}Napcat服务重启成功${NC}"
    else
        log "${RED}错误：Napcat服务重启失败，请手动检查${NC}"
        exit 1
    fi
    
    log "${GREEN}更新完成，已升级至版本 $latest_version${NC}"
    log "======================================"
}

main
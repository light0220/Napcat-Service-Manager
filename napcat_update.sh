#!/bin/bash
# napcat_update.sh - 自动更新Napcat（带详细日志和重试机制）

# 配置
NAPCAT_DIR="/root/Napcat"
UPDATE_LOG="/var/log/napcat_update.log"
INSTALL_SCRIPT="napcat.sh"
INSTALL_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"
# 新增API配置
LOCAL_API_URL="http://localhost:6099/api/base/GetNapCatVersion"
API_KEY="eyJEYXRhIjp7IkNyZWF0ZWRUaW1lIjoxNzYzNjA2MzE2NTIzLCJIYXNoRW5jb2RlZCI6ImM3YmEyNmJmMTZkZjBkZGIzNGRkNWI4ZWI1YTIzNmFlMmZiMDc1MTk3ZGJlYjliZGQyZDk4M2RiOWQxMzFjYjgifSwiSG1hYyI6IjdjMTM2YTMxMjE5N2ZiNGQ3YTU2NzdlOTA1YjUwYTY3MjEzYjMwYTM2OWE1YjIwNzBjOTFmYjQ1OWJlMTgyODUifQ=="
MAX_RETRIES=3  # 最大重试次数
RETRY_DELAY=10  # 重试间隔（秒）

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

# 新增：使用curl获取当前版本（通过本地API）
get_current_version() {
    local retries=$MAX_RETRIES
    local version="unknown"
    
    while [ $retries -gt 0 ]; do
        # 使用curl发送请求，带Authorization头
        response=$(curl -sSL -H "Authorization: Bearer $API_KEY" "$LOCAL_API_URL" 2>>"$UPDATE_LOG")
        
        # 检查响应是否有效并解析JSON
        if [ -n "$response" ]; then
            # 使用grep和sed提取version字段（简单JSON解析）
            version=$(echo "$response" | grep -o '"version":"[^"]*' | sed 's/"version":"//')
            if [ -n "$version" ]; then
                echo "$version"
                return 0
            fi
        fi
        
        log "${YELLOW}获取版本失败，重试中（剩余$((retries-1))次）${NC}"
        retries=$((retries - 1))
        sleep $RETRY_DELAY
    done
    
    echo "unknown"
    return 1
}

# 带重试的下载函数
download_with_retry() {
    local url=$1
    local output=$2
    local retries=$MAX_RETRIES
    
    log "开始下载: $url"
    
    while [ $retries -gt 0 ]; do
        # 使用curl详细输出（包括HTTP状态码），并记录到日志
        if curl -sSL -w "HTTP状态码: %{http_code}\n" -o "$output" "$url" 2>>"$UPDATE_LOG"; then
            # 检查文件大小（排除空文件）
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
    
    log "开始执行安装脚本（带详细日志）..."
    
    while [ $retries -gt 0 ]; do
        # 执行安装脚本，并将完整输出记录到日志
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
    # 清空临时日志（保留历史日志，只清空本次执行的临时输出）
    > "$UPDATE_LOG"
    log "======================================"
    log "开始Napcat自动更新检查（带重试机制）"
    log "最大重试次数: $MAX_RETRIES 次，间隔: $RETRY_DELAY 秒"
    
    # 检查安装目录是否存在
    if [ ! -d "$NAPCAT_DIR" ]; then
        log "${RED}错误：未找到Napcat安装目录 $NAPCAT_DIR${NC}"
        exit 1
    fi
    
    # 获取当前版本
    log "检查当前版本..."
    local current_version=$(get_current_version)
    log "当前版本: $current_version"
    
    # 记录更新前状态
    check_running
    local was_running=$?  # 0=运行中，1=未运行
    
    # 下载最新安装脚本（带重试）
    if ! download_with_retry "$INSTALL_URL" "$INSTALL_SCRIPT"; then
        log "${RED}错误：安装脚本下载失败，更新终止${NC}"
        exit 1
    fi
    
    # 赋予执行权限
    chmod +x "$INSTALL_SCRIPT"
    
    # 执行安装脚本（带重试和完整日志）
    if ! execute_install_with_retry "$INSTALL_SCRIPT"; then
        log "${RED}错误：安装脚本执行失败，更新终止${NC}"
        exit 1
    fi
    
    # 清理临时脚本
    rm -f "$INSTALL_SCRIPT"
    
    # 重启服务确保更新生效
    log "重启Napcat服务..."
    if systemctl restart napcat; then
        log "${GREEN}Napcat服务重启成功${NC}"
    else
        log "${RED}错误：Napcat服务重启失败，请手动检查${NC}"
        exit 1
    fi
    
    # 输出更新后的版本（如果需要）
    log "检查更新后版本..."
    local new_version=$(get_current_version)
    log "更新后版本: $new_version"
    
    log "${GREEN}自动更新完成${NC}"
    log "======================================"
}

# 执行主流程
main
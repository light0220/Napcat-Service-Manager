#!/bin/bash
# napcat_update.sh - 自动更新Napcat（带版本检查、详细日志和重试机制）

# 配置
NAPCAT_DIR="/root/Napcat"
UPDATE_LOG="/var/log/napcat_update.log"
INSTALL_SCRIPT="napcat.sh"
INSTALL_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"
GITHUB_REPO="NapNeko/NapCatQQ"  # GitHub仓库地址
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

# 获取当前安装的版本
get_current_version() {
    # 从本地安装目录的package.json获取版本（NapCatQQ的版本通常记录在这里）
    local version_file="$NAPCAT_DIR/package.json"
    if [ -f "$version_file" ]; then
        # 使用jq解析JSON（如果没有jq可安装：apt install jq 或 yum install jq）
        if command -v jq &> /dev/null; then
            jq -r '.version' "$version_file" 2>/dev/null | tr -d '[:space:]'
        else
            # 不依赖jq的简易解析
            grep -oP '"version": "\K[^"]+' "$version_file" 2>/dev/null | tr -d '[:space:]'
        fi
    else
        # 备选：从启动日志获取版本
        if [ -f "$NAPCAT_DIR/logs/latest.log" ]; then
            grep -oP 'NapCatQQ v\K[\d.]+' "$NAPCAT_DIR/logs/latest.log" 2>/dev/null | head -n1 | tr -d '[:space:]'
        else
            echo "unknown"
        fi
    fi
}

# 获取GitHub最新版本
get_latest_version() {
    local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    local temp_file=$(mktemp)
    
    if download_with_retry "$api_url" "$temp_file"; then
        # 解析GitHub API返回的最新版本号（去除v前缀）
        if command -v jq &> /dev/null; then
            local version=$(jq -r '.tag_name' "$temp_file" 2>/dev/null | sed 's/^v//')
        else
            local version=$(grep -oP '"tag_name": "\Kv?[^"]+' "$temp_file" 2>/dev/null | sed 's/^v//')
        fi
        rm -f "$temp_file"
        echo "$version" | tr -d '[:space:]'
        return 0
    else
        rm -f "$temp_file"
        echo "unknown"
        return 1
    fi
}

# 比较版本号（支持x.y.z格式）
version_gt() {
    # 将版本号转换为数组
    IFS='.' read -ra curr <<< "$1"
    IFS='.' read -ra latest <<< "$2"
    
    # 比较每个部分
    for i in "${!curr[@]}"; do
        if [ "${latest[$i]}" -gt "${curr[$i]}" ]; then
            return 0  # 最新版本更高
        elif [ "${latest[$i]}" -lt "${curr[$i]}" ]; then
            return 1  # 当前版本更高
        fi
    done
    
    # 如果当前版本部分比最新版本少，说明最新版本更高（如1.2 < 1.2.1）
    if [ ${#latest[@]} -gt ${#curr[@]} ]; then
        return 0
    fi
    
    return 1  # 版本相同
}

# 带重试的下载函数
download_with_retry() {
    local url=$1
    local output=$2
    local retries=$MAX_RETRIES
    
    log "开始下载: $url"
    
    while [ $retries -gt 0 ]; do
        # GitHub API需要User-Agent头，否则可能返回403
        if curl -sSL -H "User-Agent: curl/7.68.0" -w "HTTP状态码: %{http_code}\n" -o "$output" "$url" 2>>"$UPDATE_LOG"; then
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

    # 获取版本信息
    log "检查版本信息..."
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    log "当前版本: $current_version"
    log "最新版本: $latest_version"
    
    # 版本检查逻辑
    if [ "$current_version" = "unknown" ] || [ "$latest_version" = "unknown" ]; then
        log "${YELLOW}无法获取完整版本信息，将继续执行更新流程${NC}"
    elif ! version_gt "$current_version" "$latest_version"; then
        log "${GREEN}当前已是最新版本，无需更新${NC}"
        log "======================================"
        exit 0
    else
        log "发现新版本，开始执行更新..."
    fi
    
    # 记录更新前状态
    check_running
    local was_running=$?  # 0=运行中，1=未运行
    
    # 备份当前版本（如需启用可取消注释）
    # backup_current_version
    
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
    
    log "${GREEN}自动更新完成${NC}"
    log "======================================"
}

# 执行主流程
main
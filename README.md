# Napcat-Service-Manager

Napcat的systemd服务管理工具，提供开机自启、自动更新、状态监控等功能，简化Napcat QQ机器人的运维流程。

## 功能特性

- 🚀 开机自动启动Napcat服务，确保机器人持续运行
- 🔄 每日定时（默认凌晨3点）自动检查并更新至最新版本
- 📊 完善的日志记录（服务运行日志+按日期分类的更新日志）
- 🛠️ 便捷的服务管理命令（启动/停止/重启/状态查询）

## 适配系统

- 支持系统：Linux发行版（需搭载systemd服务管理器，如Ubuntu 16.04+、CentOS 7+、Debian 9+等）
- 依赖工具：`systemd`、`curl`、`crontab`、`bash`（建议4.0+）

## 文件结构

```
.
├── install_napcat_services.sh      # 一键安装脚本
├── napcat_update.sh                # 自动更新脚本
├── napcat.service                  # systemd服务配置文件
└── README.md                       # 项目说明文档
```

## 一键安装

1. 确保已安装Napcat，且安装路径为 `/root/Napcat`（如果未安装，脚本会自动下载并安装Napcat）
2. 执行安装命令：
   ```bash
   sudo chmod +x install_napcat_services.sh napcat_update.sh
   sudo ./install_napcat_services.sh
   ```

## 服务管理

```bash
# 启动服务
sudo systemctl start napcat

# 停止服务 
sudo systemctl stop napcat

# 查看状态
sudo systemctl status napcat

# 查看日志
sudo journalctl -u napcat -f
```

## 更新管理

### 版本检测配置

自动更新依赖 Napcat 的本地 API 获取当前版本，需确保：

- Napcat 已配置 HTTP 服务器（默认地址 `http://localhost:7777`）
- 若修改服务器地址，需同步更新 `/usr/local/bin/napcat_update.sh`中的 `LOCAL_API_URL`参数

```bash
# 如需手动触发更新可执行
sudo /usr/local/bin/napcat_update.sh

# 查看更新日志（按日期查询）
ls /var/log/napcat_update/  # 列出所有日志文件
tail -f /var/log/napcat_update/napcat_update_20250520.log  # 查看指定日期日志
```

## 注意事项

- 需要以root权限运行
- 首次安装前请确认 Napcat 已正常运行（/root/Napcat/opt/QQ/qq文件存在）
- 自动更新需要网络连接

## 卸载

1. 停止并禁用服务：

   ```bash
   sudo systemctl stop napcat
   sudo systemctl disable napcat
   ```
2. 删除服务文件与更新脚本：

   ```bash
   sudo rm /etc/systemd/system/napcat.service
   sudo rm /usr/local/bin/napcat_update.sh
   ```
3. 移除定时任务：

   ```bash
   sudo crontab -l | grep -v "napcat_update.sh" | sudo crontab -
   ```
4. 删除更新日志目录（可选）：

   ```bash
   sudo rm -rf /var/log/napcat_update/
   ```

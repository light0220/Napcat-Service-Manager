# NapcatQQ 守护服务

## 功能特性

- 开机自动启动NapCat QQ机器人
- 定期（默认每天3点）自动检查并更新最新版本
- 完善的日志记录和状态监控
- 需配合NapCat使用

## 一键安装

```bash
sudo ./install_napcat_services.sh
```

安装脚本会自动完成：

1. 安装systemd服务
2. 配置自动更新脚本
3. 设置定时任务(每天凌晨3点检查更新)

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

为方便脚本检测本地当前版本，需在NapCat配置相应HTTP服务器，默认为http://localhost:7777。可以自行修改但要保证napcat_update.sh中LOCAL_API_URL="http://localhost:7777/get_version_info"的服务器地址与你修改的地址相同。

```bash
# 手动更新
sudo /usr/local/bin/napcat_update.sh

# 查看更新日志
tail -f /var/log/napcat_update.log
```

## 注意事项

- 需要以root权限运行
- 确保已正确安装Napcat QQ
- 自动更新需要网络连接

## 卸载

1. 停止服务：

   ```bash
   sudo systemctl stop napcat
   sudo systemctl disable napcat
   ```
2. 删除服务文件：

   ```bash
   sudo rm /etc/systemd/system/napcat.service
   ```
3. 删除更新脚本：

   ```bash
   sudo rm /usr/local/bin/napcat_update.sh
   ```
4. 移除定时任务：

   ```bash
   sudo crontab -l | grep -v "napcat_update.sh" | sudo crontab -
   ```

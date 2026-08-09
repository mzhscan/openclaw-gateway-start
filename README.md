# 🐾 OpenClaw Gateway 启动监控

自动监控 OpenClaw Gateway 状态，挂了自动拉起 + Bark 推送告警。

---

## ✨ 特性

- 🔄 **本机监控**：检测 Gateway 进程，挂了自动执行 `openclaw gateway start` 拉起
- 🌐 **远程监控**：通过 SSH 远程检测另一台机器的 Gateway 状态
- 📱 **Bark 推送**：支持自定义分组、标题、内容、图标
- ⚙️ **systemd 服务**：常驻后台、开机自启、崩溃自动重启
- 🎯 **去重推送**：用 ALERT 标志位防止刷屏，死→活只推一次

---

> ⚠️ **重要**：请勿使用 `sudo bash <(curl ...)`，这是 `sudo` + 进程替换的经典坑，会报 `/dev/fd/63: No such file or directory`。请先下载到本地再 sudo 执行。

## 🚀 一键部署

### 本机监控

由于 `sudo` + 进程替换 (`bash <(...)`) 存在兼容性问题，请分两步执行：

```bash
# 第一步：下载脚本到本地
curl -Ls https://raw.githubusercontent.com/mzhscan/openclaw-gateway-start/main/install.sh -o /tmp/install.sh

# 第二步：sudo 执行
sudo bash /tmp/install.sh
```

或者一行版（自动跳转）：
```bash
curl -Ls https://raw.githubusercontent.com/mzhscan/openclaw-gateway-start/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

选择 `1`（本机监控），按提示配置 Bark 推送。

### 远程监控

同样分两步：

```bash
curl -Ls https://raw.githubusercontent.com/mzhscan/openclaw-gateway-start/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

选择 `2`（远程监控），按提示填写：
- Bark 配置（可选）
- 目标机器 IP/域名
- SSH 用户名、密码、端口

部署过程中会自动检测并安装 `sshpass`。

---

## 📋 部署流程

1. 选择模式（**1** 本机 / **2** 远程）
2. 选择是否配置 Bark 推送
3. 如果配置 Bark，按提示填写：
   - **Bark 服务地址**（如 `https://bark.doogeee.cn:3210`）
   - **设备 Key**
   - **分组**（可选）
   - **标题**（必填）
   - **通知内容**（必填）
   - **图标 URL**（可选，必须以 `http://` 或 `https://` 开头）
4. 远程模式额外填写：目标机器 IP/域名、SSH 用户名、密码、端口
5. 自动下载脚本、生成配置、注册 systemd 服务、启动

---

## 🔧 服务管理

部署完成后，会创建一个 systemd 服务：

| 模式 | 服务名 |
|------|--------|
| 本机 | `monitor-gateway-local.service` |
| 远程 | `monitor-gateway-remote.service` |

### 常用命令

```bash
# 查看状态
sudo systemctl status monitor-gateway-local
sudo systemctl status monitor-gateway-remote

# 查看实时日志
sudo journalctl -u monitor-gateway-local -f

# 重启服务
sudo systemctl restart monitor-gateway-local

# 停止服务
sudo systemctl stop monitor-gateway-local

# 开机自启管理
sudo systemctl enable monitor-gateway-local
sudo systemctl disable monitor-gateway-local

# 卸载服务
sudo systemctl disable --now monitor-gateway-local
sudo rm /etc/systemd/system/monitor-gateway-local.service
```

---

## 📍 文件路径

| 文件 | 路径 |
|------|------|
| 部署脚本 | `/opt/scripts/install.sh` |
| 本机监控 | `/opt/scripts/monitor-gateway-local.sh` |
| 远程监控 | `/opt/scripts/monitor-gateway-remote.sh` |
| 配置文件 | `/opt/scripts/monitor-gateway-{local,remote}.conf` |
| systemd 服务 | `/etc/systemd/system/monitor-gateway-{local,remote}.service` |
| 运行日志 | `/var/log/monitor/gateway-{local,remote}.log` |

---

## 🔔 Bark URL 格式

```
{BARK_BASE}/{KEY}/{分组}/{标题}/{内容}?icon={图标}
```

示例：
```
https://bark.doogeee.cn:3210/skVvGbREvs6VL9RRyYi24L/星黎好消息/OpenClaw%20Gateway/OpenClaw%20Gateway%20已启动?icon=https://tu.doogeee.cn:3210/i/2026/08/10/c5sow.png
```

脚本会根据你的配置自动拼接：
- **不填分组** → URL 省略分组段
- **不填图标** → URL 不带 `?icon=` 参数

---

## 📊 推送规则

### 本机监控（monitor-gateway-local）

| 场景 | 推送标题 | 推送内容 |
|------|---------|---------|
| 开机检测到 Gateway 在跑 | 用户自定义 | 用户自定义 |
| Gateway 死 → 自动拉起成功 | 用户自定义 | 用户自定义 |

**去重**：用 `ALERT` 标志位，同一异常只推一次，恢复后再推一次。

### 远程监控（monitor-gateway-remote）

| 场景 | 推送标题 | 推送内容 |
|------|---------|---------|
| SSH 连不上 | `无法连接到 OpenClaw 所在服务器` | `无法 SSH 到 {IP}:{端口}` |
| SSH 连上但 Gateway 死了 | `OpenClaw Gateway 已停止` | `{IP} 上的 Gateway 已停止运行` |
| Gateway 恢复 | **不推送** | - |

---

## ❓ 常见问题

### Q: 部署后 Gateway 还是没拉起来？
A: 检查 `/var/log/monitor/gateway-local.log`，确认 `openclaw` 命令是否在 PATH 中。

### Q: Bark 推送没收到？
A:
1. 检查 Bark 服务地址 + Key 是否正确
2. 测试 `curl "你的Bark URL"`
3. 查看 Bark 服务端日志

### Q: 远程模式 SSH 连接失败？
A:
1. 确认目标机器 SSH 服务正常
2. 确认用户名密码正确
3. 确认防火墙放行了 SSH 端口
4. 检查 `sshpass` 是否安装

### Q: 想修改 Bark 配置？
A: 直接编辑配置文件，重启服务：
```bash
sudo vim /opt/scripts/monitor-gateway-local.conf
sudo systemctl restart monitor-gateway-local
```

---

## 📜 仓库

- GitHub: <https://github.com/mzhscan/openclaw-gateway-start>
- 作者: [mzhscan](https://github.com/mzhscan)

---

## 📄 License

MIT
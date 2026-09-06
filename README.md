# QQ Runtime

QQ 官方机器人运行时框架（企业级聚合发行版）。基于 Python 3.12 + FastAPI + SQLite，
内置管理台、授权体系、插件沙箱与积分/支付/媒体等全套能力。

> 💡 **提示**：本仓库为公开文档与发行仓库，用于发布**一键部署脚本**、**客户端安装包**、**部署教程**与**更新日志**。
> 框架核心以加固镜像分发，不在此处提供私有后端源码。

---

## ⚡ 极速部署（推荐 Docker）

在任何 Linux 服务器上只需运行一行命令，即可全自动完成硬件架构自检、Docker 状态监控与自启、国内高速镜像加速源选择及一键集群拉起：

```bash
# 官方公网源安装
curl -fsSL https://raw.githubusercontent.com/Chinachani/Runtime-doc/main/install.sh | bash

# 国内高速加速安装（推荐中国大陆服务器，支持 GitHub 加速通道）
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Chinachani/Runtime-doc/main/install.sh | bash
```

### 内置国内 Docker 镜像加速源
- `ghcr.1ms.run/chinachani/qq-runtime:latest`（国内毫秒级高速分发，推荐）
- `ghcr.nju.edu.cn/chinachani/qq-runtime:latest`（南京大学开源镜像站）
- `ghcr.milu.moe/chinachani/qq-runtime:latest`（麋鹿社区开源加速）
- `docker.m.daocloud.io/ghcr.io/chinachani/qq-runtime:latest`（DaoCloud 镜像）
- `ghcr.io/chinachani/qq-runtime:latest`（GitHub 官方全球源）

---

## 💻 桌面端与移动客户端下载

QQ Runtime 支持多端原生直连（自带节点管理与断网秒开切换）：

- **Windows 桌面一体化版**（`.exe`，集成免 Docker 本地运行时）：可在本仓库 [Releases 最新发行页](../../releases/latest) 直接下载。
- **macOS 桌面一体化版**（`.dmg`）：可在本仓库 [Releases 最新发行页](../../releases/latest) 直接下载。
- **Android 移动客户端**（`.apk`，支持前台保活与掉线提醒）：可在本仓库 [Releases 最新发行页](../../releases/latest) 直接下载。

---

## 📚 开发者文档与生态

| 文档 | 说明 |
| --- | --- |
| [docs/部署教程.md](docs/部署教程.md) | 从零部署一个机器人实例 |
| [docs/插件开发指南.md](docs/插件开发指南.md) | 插件结构、权限、卡片、网页面板、发布签名 |
| [docs/授权协议.md](docs/授权协议.md) | 软件许可与授权协议 |
| [examples/plugin.demo.guide/](examples/plugin.demo.guide/) | 示例插件（对应开发指南的完整演示） |

## 授权与版本

- 框架按授权级别开放功能；未授权实例仅可执行诊断指令。
- 管理台「关于/更新」会自动检查本仓库的 Release 获取新版本与更新日志。
- 商业插件按 `[license]` 授权块与厂商签名发放。

## 联系

通过授权渠道联系发行方获取授权。

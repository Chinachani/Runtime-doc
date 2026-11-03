# QQ Runtime

[![Version](https://img.shields.io/badge/version-1.7.11-blue)](CHANGELOG.md)

QQ 官方机器人运行时框架，提供 WebSocket/Webhook 接入、Web 管理台、插件市场、音视频与文件处理、积分支付和配套部署工具。

本仓库是 Runtime 的公开文档与发行入口：包含安装脚本、用户指南、插件生态资料、版本日志和可下载的发行附件。框架源码与构建流程由发行方在主仓库维护；请勿把内部运维资料复制到此处。

## 1.7.11 更新

修复管理台和 APK 构建时 Google Fonts 地址解析导致的偶发编译失败，固定使用包含上游修复的 Next.js 稳定版 `16.4.4`。发布附件见 [v1.7.11 Release](https://github.com/Chinachani/Runtime-doc/releases/tag/v1.7.11)，详细内容见 [CHANGELOG](CHANGELOG.md)。

## 1.7.10 更新

修复插件菜单按钮重复回调应答、正常回复丢失的问题。菜单过期时会明确提示重新打开；点击后不再等待插件处理完成才应答。发布附件见 [v1.7.10 Release](https://github.com/Chinachani/Runtime-doc/releases/tag/v1.7.10)，详细内容见 [CHANGELOG](CHANGELOG.md)。

## 1.7.9 更新重点

- 完善中心积分账本、历史余额核对和支付幂等，修复重复入账及退款并发问题。
- 优化插件管理、批量操作和参数配置，区分后台权限与插件能力，敏感凭据不再明文回显。
- 改进 Bili/Dy 视频与音频压缩、文件兜底和手机封面比例；修复 Bili 时长判断与提示顺序，补齐 Steam 命令。
- 提供可选 bwrap 强沙箱配置，兼容管理员安装的 Python 库与 FFmpeg 工具，明确报告插件启动恢复失败。
- 取消旧商业在线授权依赖，继续保留登录、管理员权限、插件能力批准及完整性校验。

详细变更见 [CHANGELOG](CHANGELOG.md)，可下载附件以 [v1.7.9 Release](https://github.com/Chinachani/Runtime-doc/releases/tag/v1.7.9) 的实际发布结果为准。

## 快速部署

推荐在受支持的 Linux 主机上使用交互式安装脚本。脚本会检查 Docker 环境、可用端口和硬件，并引导选择附加服务及初始管理员账户。

```bash
curl -fsSL https://raw.githubusercontent.com/Chinachani/Runtime-doc/main/install.sh | bash
```

国内网络可使用加速地址：

```bash
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Chinachani/Runtime-doc/main/install.sh | bash
```

首次部署、升级、备份与排错见[部署教程](docs/部署教程.md)。安装前也可以先从本仓库下载 `install.sh` 检查脚本内容，再执行。

## 首次配置与升级

1. 使用安装脚本生成的管理员账户登录 Web 管理台，在「QQ 接入」填写机器人凭据并启动网关。
2. 在「插件管理」选择插件。外部插件需开启开发者模式、按声明批准所需能力，再启用；新增能力不会在更新时自动获批。
3. 通过插件管理页进入各插件设置，填写它们自己的上游接口与 Key。Runtime 启动不再需要旧商业授权服务，QQ 官方凭据和各上游认证仍需配置。

从旧版升级前请备份部署配置、业务数据和插件配置。语音/视频余额迁入中心账本时，冲突账户会暂停扣费并等待管理员核对；需要充值的插件还须批准新增的支付能力。完整说明见[部署教程](docs/部署教程.md)。

外部插件默认在独立进程中运行；需要文件系统与命名空间隔离时，应显式部署 bwrap。Docker 默认安全配置可能阻止其启动，安装了 bubblewrap 也不代表已生效，须核对插件管理页实际沙箱状态。进程后端与强沙箱的区别及部署入口见[部署教程](docs/部署教程.md#强沙箱)。

## 文档

| 内容 | 适合读者 |
| --- | --- |
| [全部公开文档索引](docs/README.md) | 所有用户 |
| [部署教程](docs/部署教程.md) | Runtime 管理员 |
| [插件开发指南](docs/插件开发指南.md) | 插件作者 |
| [插件市场上架指南](docs/插件上架指南.md) | 插件作者与审核提交者 |
| [插件 Demo](examples/plugin.demo.guide/) | 插件作者 |
| [版本更新日志](CHANGELOG.md) | Runtime 用户与管理员 |

## 版本与下载

- 最新框架镜像、客户端和插件附件以 [Releases](https://github.com/Chinachani/Runtime-doc/releases) 中实际提供的资产为准；不同版本可能包含不同附件。
- 管理台会检查本仓库的 Release 并显示对应版本说明。
- Docker 镜像源与更新方式见[部署教程](docs/部署教程.md)。

## 支持

遇到部署、插件或权限问题，请先查看文档索引和常见问题，再通过项目支持渠道反馈。请附上 Runtime/插件版本、操作步骤及错误提示，并移除日志中的密码、Token、Cookie、API Key 和用户隐私。

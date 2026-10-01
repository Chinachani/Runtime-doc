# QQ Runtime

QQ 官方机器人运行时框架。提供统一的机器人接入、Web 管理台、插件系统和配套部署工具。

本仓库是 Runtime 的公开文档与发行入口：包含安装脚本、用户指南、插件生态资料、版本日志和可下载的发行附件。框架源码与构建流程由发行方在主仓库维护；请勿把内部运维资料复制到此处。

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

## 文档

| 内容 | 适合读者 |
| --- | --- |
| [全部公开文档索引](docs/README.md) | 所有用户 |
| [部署教程](docs/部署教程.md) | Runtime 管理员 |
| [插件开发指南](docs/插件开发指南.md) | 插件作者 |
| [插件市场上架指南](docs/插件上架指南.md) | 插件作者与审核提交者 |
| [软件许可协议模板](docs/授权协议.md) | 需起草授权协议的发行方；模板须经法律审阅 |
| [插件 Demo](examples/plugin.demo.guide/) | 插件作者 |
| [版本更新日志](CHANGELOG.md) | Runtime 用户与管理员 |

## 版本与下载

- 最新框架镜像、客户端和插件附件以 [Releases](https://github.com/Chinachani/Runtime-doc/releases) 中实际提供的资产为准；不同版本可能包含不同附件。
- 管理台会检查本仓库的 Release 并显示对应版本说明。
- Docker 镜像源与更新方式见[部署教程](docs/部署教程.md)。

## 支持

遇到部署或授权问题，请先查看文档索引和常见问题，再通过随授权提供的支持渠道联系发行方。提交问题时请先移除日志中的密码、Token、Cookie、API Key、IP 白名单等敏感信息。

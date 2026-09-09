# 更新日志

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；
版本号遵循语义化版本。买家通过管理台「更新检查」或本页获取新版本信息。

## [0.6.8] - 2026-09-09

### Steam 监控插件补全（对齐 AstrBot 1.28 版）

- **完整目标解析**：`/sw` 全部目标参数现在支持 `steamid64`、`好友码`（9 位 CS:GO 好友码）、`steamcommunity.com/profiles/...` 资料链接、`/id/自定义ID` 链接（经 ResolveVanityURL 解析）、`me`、`@绑定用户` 与 `@昵称` 反查；`resolve` 指令同时输出好友码。
- **info 详细查询**：`/sw info <目标>` 输出状态（离线/在线/忙碌等 7 态中文）、实名、主页、注册时间、地区，游戏中时追加该游戏总时长与成就进度（`IPlayerService/GetOwnedGames` + `GetPlayerAchievements`）。
- **分组订阅**：`/sw sub|unsub <分组>` 将当前会话订阅到指定分组；`/sw add|remove <目标> <分组>` 管理 SteamID 与分组的归属（同一账号可入多组，remove 仅移出该分组、无剩余分组才移出号池）；推送按分组扇出去重，分组模式启用时不回退全局订阅；`/sw groupinfo|grouplist` 分页查看，`/sw subclean` 同时清理无效全局与分组订阅。
- **监控列表分页**：`/sw list [页码]` 每页 8 条，显示绑定用户（优先昵称）与所属分组。
- **停止游戏推送增强**：开启 `notify_on_stop` 后推送"已停止游戏+本次游玩时长"，`show_stop_playtime_comment`（默认开）附加阶梯评价；`/sw comment on|off`、`/sw notify_on_stop on|off` 运行时开关。
- **API 请求重试**：查询 Steam API 按配置的次数与间隔自动重试。
- **模块化菜单**：`/sw manage|notify|query|bind|net` 输出各模块命令清单，`/sw` 卡片菜单新增详细资料/解析/完整菜单按钮。
- **清除绑定键平台前缀**：绑定键从 `qq_official:<openid>:<steamid>` 迁移为 `<openid>:<steamid>`（与 drawimg 的清理方向一致），存量带前缀行读取时自动剥除、用户重新绑定后即写入新格式；管理台绑定列表同步归一化显示。
- **查询本地化游戏名**：开启 `use_localized_game_name` 后按 `game_name_language` 经商店 API 换取中文名（带 TTL 缓存）。

## [0.6.6] - 2026-09-09

### 水印清理文件元数据清理与服务状态人性化

- **文件元数据水印清理**：新增 `/wm file` 指令——把图片/文件与指令一起发送，服务端下载附件后调用 watermarks-remover 清理 EXIF、C2PA、XMP 等元数据标记，并将清理后的文件回传到当前会话。默认先弹确认卡片（`require_confirm` 可关），受 `max_file_size_mb` 大小限制。
- **服务状态人性化**：`/wm status` 不再直接输出上游 JSON，改为可读描述——在线版本、文件处理能力（EXIF/C2PA/PDF/音视频工具）、文本改写（Layer B）是否配置、文本水印检测可用性。
- 主菜单与帮助文案同步补充文件清理用法。

## [0.6.5] - 2026-09-09

### 修复客户端登录 500（users 表无 role_id 列）

- **根因**：`POST /api/auth/token` 的响应体引用了 `user["role_id"]`，而 `authenticate()` 返回的是 `users` 表原始行——该表自 v0.1 起就没有 `role_id` 列（角色经 `user_roles` 关联表映射）。凭据校验成功后在序列化响应时抛出 `KeyError`，登录一律 500。浏览器端登录走 `/api/auth/login`（不引用 role_id）所以从未暴露；打包客户端上线 Bearer 登录后必现。
- **修复**：响应体移除 `role_id` 字段；`test_api_tokens` 的 mock 用户改为真实表结构作回归防护（修改前该测试因 mock 带 role_id 而无法复现 500）。
- 与 0.6.4 的 PNA 预检修复叠加后，客户端"Failed to fetch"链路的两个服务端阻断点全部消除。

## [0.6.4] - 2026-09-09

### 修复安卓客户端登录 Failed to fetch（Private Network Access）

- **根因**：安卓 13+ WebView 强制执行 Private Network Access（PNA）——从 App 的 `http://localhost` 源向局域网地址（如 `192.168.1.219`）发起的跨源请求会先发送携带 `Access-Control-Request-Private-Network: true` 的预检；Runtime 的 CORS 中间件默认拒绝该扩展预检（HTTP 400），WebView 直接以 `Failed to fetch` 终止请求。因此健康探测（简单 GET，无预检）能通、延迟显示正常，而登录的 `POST /api/auth/token` 必然失败。
- **修复**：CORS 中间件启用 `allow_private_network=True`，对 PNA 预检正确响应 `Access-Control-Allow-Private-Network: true`。仅影响打包客户端（本地源→私网）这一合法调用场景；浏览器直连管理台不受影响。
- **APK versionCode 递增**：CI 由发版 tag 自动推导 versionCode（major×10⁶+minor×10³+patch），修复 versionCode 恒为 1 导致 Android 拒绝覆盖安装的问题。

## [0.6.3] - 2026-09-09

### 水印清理接入上游 watermarks-remover 服务

- **客户端适配上游 API 契约**：上游 [guillaumemeyer/watermarks-remover](https://github.com/guillaumemeyer/watermarks-remover) 的 `/inspect`、`/clean` 接收 base64 文件负载（`{"file": ..., "name": "input.txt"}`），文本清理结果以 base64 `file` 字段回传；旧版内置 sidecar 的 `{"kind":"text","text":...}` 与 `{"text":...}` 契约继续兼容，两种响应形状均支持。
- **一键部署接入官方镜像**：`install.sh` 与参考 compose 的 `watermarks-remover` 服务改用上游官方镜像 `ghcr.io/guillaumemeyer/watermarks-remover`（内置 exiftool/qpdf/Ghostscript/ffmpeg 文件元数据清理），凭 `WATERMARKS_SERVICE_TOKEN` 启用 Bearer 认证，与 Runtime 水印插件共用同一 Token。文本 Layer B 智能改写为可选能力，需另行配置 `WATERMARKS_REWRITE_*` LLM 后端。

## [0.6.2] - 2026-09-09

### 客户端启动直落登录页与发布流程修正

- **APK 启动不再跳过登录**：客户端构建的根路径此前固定重定向到 `/dashboard`，而静态导出的认证门禁无法在预渲染阶段运行，未登录用户直接进入只有壳子的首页（数据请求全部失败）。客户端构建根路径现在重定向到 `/auth/runtime-login`，服务端构建行为不变。
- **发布流程说明**：`create_doc_release.py` 要求 tag 版本必须存在对应 CHANGELOG 段落，重构建标签也需同步补段；自本版本起恢复正常语义化发版。

## 重构建标签 v0.6.1-rebuild2 - 2026-09-10

> CI 重构建标签：内容与 [0.6.1] 完全一致，用于在配置固定签名密钥后重新产出可安装的 APK。该版本 APK 已验证为 v2 固定签名，可正常安装；其发布流程中发行注记步骤失败仅影响 Release 描述文本，不影响 APK 附件。

## [0.6.1] - 2026-09-09

### 手机客户端连接修复与 APK 固定签名

- **修复手机客户端"测试并保存节点"报 Failed to fetch**：打包客户端此前以 `https://localhost` 作为 WebView 源，而自建节点均为 `http://` 局域网地址，属混合内容（Mixed Content）被 WebView 静默拦截。客户端源改为 `http` scheme，节点探测与账密绑定 Token 请求恢复正常（服务端 CORS 已验证对 http 源完全放行）。
- **修复手机端无法删除节点**：节点切换器与登录页节点列表的删除按钮此前仅在鼠标悬停时显示（触屏设备没有悬停，按钮永远不可见），且当前选中节点只显示对勾不显示删除。现删除按钮常显、选中节点亦可删除，并加大触控目标。
- **APK 固定签名密钥**：CI 此前使用 runner 临时生成的 debug keystore，每次构建签名都不同，覆盖安装必然提示"签名不同"。构建流程改为 `assembleRelease` 并通过 GitHub Secrets 注入固定签名密钥（未配置时自动回退调试签名并给出警告）。**注意：旧版本 APK 首次升级到固定签名版本仍需卸载重装一次，此后即可正常覆盖升级。**

## [0.6.0] - 2026-09-09

### 手机客户端可用性修复与部署链路闭环

- **修复手机端插件页"此页面无法加载"**：APK 采用 Next.js 静态导出，动态插件页路由只能预渲染构建期已知的固定组合，外部 ZIP 插件与 `community`、`pay` 等页面的侧栏链接在客户端内全部 404。新增 `/dashboard/runtime/plugin-view` 查询参数路由：打包客户端（`NEXT_PUBLIC_CLIENT_BUILD=true`）将插件页链接解析到该单一预渲染路由、运行时按查询参数渲染任意插件页；服务端部署保持原有语义化路径完全不变。
- **手机客户端登录页节点选择器与 Bearer Token 鉴权**：打包客户端运行于 `capacitor://` 源，`SameSite=lax` 会话 Cookie 无法跨源携带，此前 APK 既不能切换服务器节点也无法完成登录。登录页新增节点选择器（仅客户端构建渲染），登录改走 `POST /api/auth/token` 换取长期 Bearer Token（设计上豁免 CSRF）并持久化到节点条目，后续请求统一以 `Authorization: Bearer` 鉴权。
- **消除健康检查高延迟**：`/api/health` 每次轮询都对整个 SQLite 数据库执行 `PRAGMA quick_check` 全量完整性扫描（92MB 库约 300ms），导致节点延迟探测恒为扫描耗时而非真实网络延迟。改为 5 分钟 TTL 缓存 + 过期后台无阻塞刷新；管理台运行概览仍强制真实扫描，保留权威完整性结论；`close()` 取消后台刷新任务，避免对已关闭连接执行语句。
- **表情包模板"自动预览"开关（默认关闭）**：模板列表页原本对全部数百个模板批量加载预览图，网络压力过大。新增 `auto_preview` 配置项：默认关闭时目录接口不下发 `preview_url`、列表以"预览"文字按钮呈现，点击弹窗仍可按需加载单张预览（服务端磁盘持久缓存）；开启后恢复缩略图批量加载。
- **一键部署脚本接入新版控制台**：`install.sh` 此前生成的 `compose.yaml` 缺少 `dashboard` 服务，`RUNTIME_DASHBOARD_URL` 未设置导致全新安装静默回退旧版 legacy 控制台。现自动推导与所选镜像源配套的 dashboard 镜像、生成 `dashboard` 服务（同源代理 + `RUNTIME_API_ORIGIN` 回连）；在 dashboard 镜像尚未发布的过渡期自动降级 legacy 控制台并提示后续一键切换命令，不中断安装。
- **CI 发布 dashboard 镜像**：发布流程新增 `ghcr.io/chinachani/qq-runtime-dashboard` 的构建（Node 22 + standalone 产物）与版本/`latest` 双标签推送，补齐"打 tag → 双镜像发布 → 一键安装拉取"完整链路。
- **修复绘图插件积分结算残留死代码**：清理 `drawimg` 配置导出与积分结算路径中的无用 `users` 字典与未定义 `cs` 引用（后者在 `except` 块内触发 `NameError`，会把已吞掉的业务异常升级为 500）。

## [0.4.0] - 2026-09-06

### 新增功能与架构演进

- **Linux 服务器 Docker 智能一键部署脚本 (`install.sh`)**：支持无代码环境下一键智能部署，具备操作系统架构自检、Docker 与 Docker Compose 守护进程运行检测与自启/安装引导；内置 4 大国内高速加速源（`ghcr.1ms.run`、`ghcr.nju.edu.cn`、`ghcr.milu.moe`、`docker.m.daocloud.io`）及官方源交互切换；自动生成强随机主密钥、高强度安全初始管理员凭证、生产级 `compose.yaml` 与 `.env`；集成容器健康检查轮询与精美控制台高亮卡片。
- **全端原生接入底座与 API Token 鉴权体系**：
  - 新增 `api_tokens` 数据表与持久化方法，支持长期与限期 API Token 的安全哈希存储（SHA-256）；
  - `current_user` 认证机制升级：支持 `Authorization: Bearer <TOKEN>` 头部鉴权，无缝适配 Tauri 桌面端与 Capacitor 移动端原生直连；
  - Bearer Token 认证自动豁免 CSRF 检查，确保客户端跨源调用的合规与安全；
  - 提供 `POST /api/auth/token` 账密换取 Token 开放接口，以及管理台 Token 签发、查看与撤销路由（`/api/system/tokens`）；
  - 引入 `CORSMiddleware` 跨源访问支持，打通桌面端（`tauri://*`）与移动端（`capacitor://*`）跨域调用。

## [0.3.4] - 2026-09-06

### 修复与控制台优化

- **一键更新伴生服务连接与重启容错优化**：重构伴生服务下发逻辑，区分网络连接与拉取等待阶段；将伴生服务在执行拉取或重启时引起的读取超时（`ReadTimeout`）和容器销毁连接关闭正确识别为“已成功受理并正在重启”，杜绝误报“无法连接更新伴生服务”；新增 45 秒防抖和近期重启状态感知。
- **更新日志弹窗宽度与高度滚动条优化**：弹窗宽度加宽至 `max-w-3xl`，日志内容区明确限定高度（`max-h-[55vh]`）并提供纵向平滑滚动条，长日志排版更舒展。
- **系统与管理卡片加宽布局**：调整桌面端布局为 12 列网格，将【版本与更新】卡片宽度增加至 5 栏（加宽约 25%），镜像加速源选择、拉取命令复制与日志预览更加宽敞。

## [0.3.3] - 2026-09-06

### 插件系统与服务优化

- **绘图服务风格预设表格化呈现**：将 `/dg style` 预设列表重构为工整紧凑的 Markdown 表格展示（包含预设名称、提示词预览、选中状态三列）；彻底过滤换行符与表格分割符，提示词预览截取前 40 字符并加省略号，消除数百字提示词刷屏困扰。
- **预设详情独立查看指令**：新增 `/dg style view <预设名>` 指令，支持随时以富文本卡片查看长文本预设的完整提示词内容。
- **插件数据目录严格隔离**：彻底修复绘图插件持久化路径，严禁向插件代码安装根目录（`./data/plugins/`）写入运行期文件，统一重定向至 `data/plugin-data`，启动时自动清理历史遗留数据，彻底解决由此引起的包指纹 SHA256 校验失败问题。
- **插件指纹校验白名单增强**：`_directory_digest` 在校验包完整性时，自动跳过运行期生成的 `data/`、`config/`、`logs/`、`cache/` 目录以及临时文件（`*.log`、`*.tmp`、`*.sqlite*` 等），杜绝动态数据破坏代码包校验。
- **启动恢复容错与重试保障**：在开机启动恢复（`restore_enabled`）阶段遭遇瞬态超时或异常时，仅在内存中标记错误，**绝不在 SQLite 数据库中覆盖为 `load_failed`**，保留用户的 `enabled` 启动意图；并增加 1 秒延迟自动重试机制。
- **沙箱 Worker 启动握手超时放宽**：将 Worker 进程初始化握手超时上限从 10 秒放宽至 30 秒（`startup_timeout_seconds`），杜绝低功耗小主机重启并发拉起多个插件时因 CPU 瞬时高负载导致启动超时误报。

## [0.3.2] - 2026-09-06

### 修复与运维

- 修复 Watchtower 一键更新中断 Bug：修复伴生更新服务默认扫描全部容器、在拉取私有本地构建的 Dashboard 容器时遭遇权限拒绝导致更新流程中断的问题。
- 引入容器精准更新隔离标签：在 Compose 配置中为 Runtime 容器添加专属更新标签（`com.centurylinklabs.watchtower.enable=true`），并在 Watchtower 启用 `WATCHTOWER_LABEL_ENABLE: "true"`，杜绝误更新与权限拒绝异常。
- 确保自动更新平滑闭环：容器镜像目标规范绑定为 `latest` 标签，实现管理台点击一键更新后自动拉取新版本并重启服务。

## [0.3.1] - 2026-09-06

### 管理台与系统

- 版本发布日志体验优化：当系统处于最新版本时，自动展示本次版本的发布与更新日志，不再展示“暂无待更新日志”。
- 本地日志回退保障：增加内置 `CHANGELOG.md` 提取机制，在 GitHub API 响应超时或受限时自动回退读取本地日志，确保离线与弱网环境下的日志完整可见。
- GHCR 国内镜像源加速：新增 4 大常用国内镜像加速源（`ghcr.1ms.run`、`ghcr.nju.edu.cn`、`ghcr.milu.moe`、`docker.m.daocloud.io`），在管理台版本卡片与更新弹窗中支持一键切换与拉取命令联动复制。
- 镜像打包与环境变量优化：Docker 镜像打包内置 `CHANGELOG.md`，Compose 配置支持灵活切换镜像加速 Registry。

## [0.3.0] - 2026-09-06

### 管理台与系统

- 版本与更新模块重构：移除 SQ 授权中心干扰，统一采用公开仓库 Runtime-doc 的 GitHub Releases 作为权威版本源。
- 版本日志 Markdown 结构化美化：引入富文本渲染，卡片内设限制高度（`max-h-24`）与底部渐隐遮罩。
- 完整更新日志 Dialog 弹窗：支持弹窗浏览完整日志记录、镜像拉取命令一键复制以及 GitHub Releases 快速入口。
- 一键自动更新机制（Watchtower 伴生服务）：支持通过前端管理台直接下发更新指令，平滑拉取新镜像并重启服务，配合前端自动轮询健康状态与重载页面。

### 插件与服务

- word2ppt：计费前置校验修复，积分不足时提前拦截任务创建，避免产生无效执行记录。
- word2ppt：优化反代大模型接口异常处理与状态反馈。

## [0.2.1] - 2026-09-05

### 安全与发行

- 发行镜像执法链 Cython 编译（二进制分发）+ 完整性自检；厂商公钥与网关公钥构建期烧录。
- 授权响应网关 Ed25519 签名：编译客户端强制验签（默认开启，环境变量仅可轮换）。
- 商业插件厂商签名强制：`[license]` 插件必须厂商签名方可激活，开发者模式与环境变量均不可绕过。
- 版本检测与更新日志迁移至公开仓库 Runtime-doc；GitHub Actions 构建发行镜像并推送 GHCR。

### 插件

- word2ppt：管理面板增强、Python 依赖管理与模型列表接口。
- 官方插件前端 SDK（RuntimePluginBridge）。
- 沙箱与插件生命周期行为调整。

## [0.2.0] - 2026-09-06

### 框架

- 商业授权体系：机器人绑定授权、功能位（权益包）、3 天离线宽限、心跳续期。
- 未授权实例受限模式：仅允许身份与授权诊断指令。
- 管理台 v2：极简主题、插件/媒体分页筛选、会话备注与预览、审计与版本更新检查。
- 插件系统：ZIP 包安装/升级/卸载、进程级沙箱（bubblewrap/seccomp）、
  权限与依赖白名单、网页面板桥接。
- 积分与支付桥（内置 runtime.pay）：订单创建/查询/退款/兑换。
- 内置插件：社区管理、权限管理、MD 卡片、绘图、表情包、水印、NA 等。

### 安全与发行

- 授权响应 Ed25519 签名（网关加签，客户端烧录公钥验签）。
- 商业插件厂商签名强制：`[license]` 插件必须厂商签名方可激活，
  开发者模式与环境变量均不可绕过。
- 发行镜像执法链 Cython 编译（二进制分发）+ 完整性自检。

### 已知限制

- word2ppt 的单页重做与 AI 配图为降级实现，待后续版本补全。
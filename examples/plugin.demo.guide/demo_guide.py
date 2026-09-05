"""插件开发指南演示插件（plugin.demo.guide）。

演示 Runtime 外部插件的全部常用能力，与 docs/plugin-dev-guide.md 一一对应：

- 命令注册与子命令分发（/guide）
- 返回文本与 Markdown 卡片（Card/Button，见 runtime.models）
- 主动发送（context.qq.send_text / send_card）
- 积分读写（context.points，operation_id 幂等；需要 points.manage 能力）
- 网络请求（httpx，需要 network 能力）
- 事件监听（context.register_event_handler("*")）
- 周期任务与管理页数据快照（data_dir/page_overview.json）
- 内置插件桥（context.builtin("runtime.pay")，声明见 plugin.toml）

测试命令：
  /guide                主菜单卡片
  /guide me             查询我的积分（chat.read/points 演示）
  /guide give 10        给自己加 10 积分（演示 debit/credit 幂等）
  /guide pay 100        通过 runtime.pay 创建 100 积分充值订单
  /guide rate           用 network 能力拉取一个公开 JSON API
  /guide stats          内部状态（事件计数、任务执行次数）
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import httpx

from runtime.models import Button, Card

logger = logging.getLogger("plugin.demo.guide")

PLUGIN_ID = "plugin.demo.guide"
GUIDE_TEXT = (
    "**插件开发指南演示**\n\n"
    "本插件演示 Runtime 外部插件的常用能力：\n"
    "/guide me —— 查询我的积分余额\n"
    "/guide give <数量> —— 幂等地给自己加积分\n"
    "/guide pay <积分> —— 通过 runtime.pay 创建充值订单\n"
    "/guide rate —— 用 network 能力拉取公开汇率 API\n"
    "/guide stats —— 事件/任务运行统计\n"
    "管理台 → 插件页面 → 演示插件面板 查看网页端数据。"
)


class DemoGuidePlugin:
    def __init__(self, context: Any) -> None:
        self.context = context
        self.data_dir = Path(getattr(context, "data_dir", "./data"))
        self.config_dir = Path(getattr(context, "config_dir", "./config"))
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.config_dir.mkdir(parents=True, exist_ok=True)

        self.state_path = self.data_dir / "state.json"
        self.state: dict[str, Any] = self._load_json(self.state_path, {"events": 0, "tasks": 0, "greeted": {}})
        self._write_page_snapshot()

    # ---------- 管理页动作处理 ----------
    async def on_page_action(self, action: str, payload: dict[str, Any]) -> Any:
        """接收管理页面通过 RuntimePluginBridge.callAction 派发的动作。"""
        if action == "ping":
            import time
            return {
                "message": f"来自 demo_guide worker 的响应！时间: {int(time.time())}",
                "events_seen": self.state.get("events", 0),
                "tasks_run": self.state.get("tasks", 0),
                "echo_payload": payload or {},
            }
        if action == "reset_stats":
            self.state["events"] = 0
            self.state["tasks"] = 0
            self._save_state()
            self._write_page_snapshot()
            return {"message": "运行统计已重置为 0"}
        raise ValueError(f"未知的管理页动作: {action}")

    # ---------- 存储小工具 ----------
    @staticmethod
    def _load_json(path: Path, default: Any) -> Any:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default

    def _save_state(self) -> None:
        self.state_path.write_text(json.dumps(self.state, ensure_ascii=False, indent=1), encoding="utf-8")

    def _write_page_snapshot(self, extra: dict[str, Any] | None = None) -> None:
        """把面板数据写到 data_dir，供 Runtime 管理页端点（web.py）读取。"""
        snapshot = {
            "plugin_id": PLUGIN_ID,
            "events_seen": self.state.get("events", 0),
            "tasks_run": self.state.get("tasks", 0),
            "greetings": len(self.state.get("greeted", {})),
            **(extra or {}),
        }
        (self.data_dir / "page_overview.json").write_text(
            json.dumps(snapshot, ensure_ascii=False, indent=1), encoding="utf-8"
        )

    # ---------- 命令入口 ----------
    async def handle_guide(self, ctx: Any, args: list[str]) -> str | Card:
        sub = args[0].lower() if args else "menu"

        if sub in {"menu", "帮助", "help"}:
            return self._menu_card(ctx)

        if sub == "me":
            points = getattr(self.context, "points", None)
            balance = await points.balance(ctx.sender_id) if points else None
            return Card(
                title="我的信息",
                markdown=(
                    f"发送者：{ctx.sender_id}\n"
                    f"场景：{ctx.scene}\n"
                    f"积分余额：{balance if balance is not None else '（积分服务未接入）'}"
                ),
                rows=[[Button(label="主菜单", command="/guide")]],
            )

        if sub == "give":
            points = getattr(self.context, "points", None)
            if points is None:
                return "当前环境未接入积分服务。"
            amount = max(1, min(1000, int(args[1]) if len(args) > 1 and args[1].isdigit() else 10))
            operation_id = f"demo.guide:{ctx.sender_id}:{amount}:daily"
            # operation_id 幂等：同一键重复执行 PointsService 会静默跳过
            # （不报错也不加钱），所以用前后余额对比给出如实提示。
            before = await points.balance(ctx.sender_id)
            await points.credit(
                ctx.sender_id, str(amount),
                reason="demo.guide.reward", actor=PLUGIN_ID, operation_id=operation_id,
            )
            after = await points.balance(ctx.sender_id)
            if after == before:
                return f"今日 {amount} 积分奖励已经领取过啦，当前余额 {after}，明天再来～"
            return f"已到账 {amount} 积分，当前余额 {after}。"

        if sub == "pay":
            return await self._create_recharge(ctx, args)

        if sub == "check":
            # /guide check <订单号>：查询支付状态（支付成功后 runtime.pay
            # 已自动把积分入账到 owner_key，无需插件重复入账）
            pay = self._pay_api()
            if pay is None or not hasattr(pay, "query_payment"):
                return "当前环境未启用内置插件桥。"
            if len(args) < 2:
                return "用法：/guide check <订单号>"
            order = await pay.query_payment(args[1])
            status = str(order.get("local_status") or order.get("status") or "unknown")
            mark = {"paid": "✅ 已支付，积分已自动到账", "pending": "⏳ 待支付"}.get(status, status)
            return f"订单 {args[1]}：{mark}\n/guide me 查询余额。"

        if sub == "qr" and len(args) > 1:
            return await self._send_pay_qr(ctx, args[1])

        if sub == "rate":
            # network 能力演示：拉取公开 API（无需 API Key）
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get("https://open.er-api.com/v6/latest/USD")
                response.raise_for_status()
                rates = response.json().get("rates", {})
            cny = rates.get("CNY")
            return f"1 USD ≈ {cny} CNY（数据源 open.er-api.com）。"

        if sub == "stats":
            return (
                f"事件已收到：{self.state.get('events', 0)} 条\n"
                f"周期任务执行：{self.state.get('tasks', 0)} 次\n"
                f"问候过的用户：{len(self.state.get('greeted', {}))} 个"
            )

        if sub == "ping":
            return await self.cmd_ping(ctx, args[1:])

        if sub == "echo":
            return await self.cmd_echo(ctx, args[1:])

        if sub == "card":
            return await self.cmd_card(ctx, args[1:])

        if sub == "id":
            return await self.cmd_id(ctx, args[1:])

        if sub == "pip":
            return await self.cmd_pip(ctx, args[1:])

        return self._menu_card(ctx)

    async def _send_pay_qr(self, ctx: Any, order_id: str) -> str:
        """把订单支付链接渲染成二维码图片并发送（需要 qrcode 库）。"""
        orders = self._load_json(self.data_dir / "pending_orders.json", {})
        order = orders.get(order_id)
        if not order or not order.get("pay_url"):
            return "订单不存在或已过期（仅保留最近 50 笔）。"
        try:
            import qrcode
        except ImportError:
            return "运行环境缺少 qrcode 库（pip install qrcode），请联系管理员安装。"
        media = getattr(self.context, "media", None)
        qq = getattr(self.context, "qq", None)
        if media is None or qq is None:
            return "当前环境不支持图片发送。"
        qr_path = self.data_dir / f"pay_qr_{order_id[:16]}.png"
        qrcode.make(order["pay_url"]).save(str(qr_path))
        try:
            if ctx.scene not in {"c2c", "group"}:
                return f"当前场景（{ctx.scene}）不支持文件/图片发送。"
            # 正确链路：prepare（元数据）→ upload_media_file（分片上传拿 file_info）→ send_media
            request = await media.prepare(ctx.scene, ctx.conversation_id, 1, qr_path)
            uploaded = await qq.upload_media_file(request, qr_path)
            file_info = uploaded.get("file_info") if isinstance(uploaded, dict) else None
            if not file_info:
                return f"上传媒体接口未返回 file_info: {uploaded}"
            await qq.send_media(ctx.conversation_id, ctx.scene, str(file_info))
            return f"二维码已发送（{order.get('points')} 积分，请微信/支付宝扫码）。"
        except Exception as error:
            return f"二维码发送失败：{str(error)[:200]}"
        finally:
            qr_path.unlink(missing_ok=True)

    def _pay_api(self):
        try:
            return self.context.builtin("runtime.pay")
        except Exception:
            return None

    async def _create_recharge(self, ctx: Any, args: list[str]) -> str | Card:
        """创建充值订单并返回带跳转按钮的订单卡。

        关键点（与 plugin.drawimg.service 一致）：
        - owner_key 必须是积分身份（支付成功后 runtime.pay 自动 credit 到它）
        - 订单结果里的 pay_url/qrcode 用来构建跳转按钮与扫码入口
        - 支付完成由 runtime.pay 的轮询任务自动入账，插件不要重复 credit
        """
        pay = self._pay_api()
        if pay is None or not hasattr(pay, "create_payment"):
            return "当前环境未启用内置插件桥。"
        points_amount = max(1, min(100000, int(args[1]) if len(args) > 1 and args[1].isdigit() else 100))
        identity = ctx.sender_id
        try:
            order = await pay.create_payment(
                source_plugin=PLUGIN_ID,
                external_id=f"demo:{identity}:{points_amount}:{int(__import__('time').time())}",
                owner_key=identity,
                subject=f"演示充值 {points_amount} 积分",
                amount=f"{points_amount / 100:.2f}", points=str(points_amount),
            )
        except Exception as error:
            message = str(error)
            if "active payment limit" in message:
                return "你有未支付订单达到上限，请先完成或等待超时关闭后重试。"
            return f"创建订单失败：{message[:200]}"

        order_id = str(order.get("order_id") or order.get("id") or order.get("reference") or "-")
        pay_url = str(order.get("pay_url") or order.get("url") or order.get("pay_info") or "")
        amount_yuan = order.get("amount") or f"{points_amount / 100:.2f}"
        self._remember_order(order_id, pay_url, points_amount, ctx.sender_id)

        markdown = (
            f"# 💳 演示充值订单\n\n"
            f"> 30 分钟内有效，支持微信/支付宝扫码。\n\n"
            f"* 充值数量：`{points_amount}` 积分\n"
            f"* 应付金额：**￥{amount_yuan}**\n"
            f"* 订单号：`{order_id}`\n"
            f"* 状态：⏳ 待支付\n\n"
            f"✨ 支付成功后积分自动到账，无需手动确认。"
        )
        row1 = []
        if pay_url.startswith(("http://", "https://")):
            # action_type=0：链接按钮，点击直接打开收银台（跳转不限定用户）
            row1.append(Button(label="💳 立即跳转付款", command=pay_url, action_type=0, style="primary"))
        row1.append(self._btn(ctx, "🔍 查询订单", f"/guide check {order_id}"))
        rows = [
            row1,
            [self._btn(ctx, "🖼️ 获取二维码", f"/guide qr {order_id}"),
             self._btn(ctx, "💰 查余额", "/guide me")],
            [self._btn(ctx, "主菜单", "/guide")],
        ]
        return Card(title="积分充值", markdown=markdown, rows=rows)

    def _remember_order(self, order_id: str, pay_url: str, points: int, identity: str) -> None:
        orders = self._load_json(self.data_dir / "pending_orders.json", {})
        orders[order_id] = {
            "pay_url": pay_url, "points": points, "identity": identity, "time": __import__("time").time(),
        }
        # 只保留最近 50 笔
        for old_id in list(orders)[:-50]:
            orders.pop(old_id, None)
        path = self.data_dir / "pending_orders.json"
        path.write_text(json.dumps(orders, ensure_ascii=False, indent=1), encoding="utf-8")

    @staticmethod
    def _btn(ctx: Any, label: str, command: str, style: str = "normal") -> Button:
        """仅触发者本人可点的按钮（permission=0 + specify_user_ids）。

        群聊里可以避免他人误触/代触你的按钮。
        """
        return Button(
            label=label, command=command, style=style,
            permission=0, specify_user_ids=(str(ctx.sender_id),),
        )

    def _menu_card(self, ctx: Any) -> Card:
        return Card(
            title="插件开发指南演示",
            markdown=(
                "**可用演示命令**\n"
                "/guide me —— 我的积分\n"
                "/guide give 10 —— 幂等加积分\n"
                "/guide pay 100 —— 创建充值订单\n"
                "/guide rate —— 汇率查询（network）\n"
                "/guide stats —— 运行统计\n"
                "/ping —— 机器人响应测试（pong）\n"
                "/card —— Markdown 卡片交互测试\n"
                "/id —— 用户稳定 ID 查询"
            ),
            rows=[
                [self._btn(ctx, "我的积分", "/guide me"),
                 self._btn(ctx, "加 10 积分", "/guide give 10", "primary")],
                [self._btn(ctx, "测试 Ping", "/ping"),
                 self._btn(ctx, "测试 Card", "/card")],
                [self._btn(ctx, "查询 ID", "/id"),
                 self._btn(ctx, "运行统计", "/guide stats")],
            ],
        )

    # ---------- 诊断与演示指令 ----------
    async def cmd_ping(self, ctx: Any, args: list[str]) -> str:
        return "pong"

    async def cmd_echo(self, ctx: Any, args: list[str]) -> str:
        return " ".join(args) if args else "用法：/echo 文本"

    async def cmd_card(self, ctx: Any, args: list[str]) -> Card:
        return Card(
            title="Markdown 卡片演示",
            markdown="### 🎴 Markdown 卡片与交互组件\n\n本卡片由 `plugin.demo.guide` 渲染生成，支持按钮回调与快捷交互。",
            rows=[
                [self._btn(ctx, "测试 Ping", "/ping", "primary"), self._btn(ctx, "回显测试", "/echo 欢迎体验 QQ Runtime")],
                [self._btn(ctx, "查询 ID", "/id"), self._btn(ctx, "指南主菜单", "/guide")],
            ],
        )

    async def cmd_id(self, ctx: Any, args: list[str]) -> str:
        openid = getattr(ctx, "member_openid", None) or getattr(ctx, "sender_id", "") or "未知"
        conv_id = getattr(ctx, "group_id", None) or getattr(ctx, "conversation_id", "-")
        return f"你的稳定 ID：{openid}\n会话 ID：{conv_id}\n场景：{getattr(ctx, 'scene', 'unknown')}"

    async def cmd_pip(self, ctx: Any, args: list[str]) -> str | Card:
        import importlib.metadata
        if not args:
            pkgs = []
            for dist in importlib.metadata.distributions():
                name = dist.metadata.get("Name") or dist.name
                pkgs.append(f"`{name}` == **{dist.version}**")
            pkgs.sort()
            summary = "\n".join(f"- {p}" for p in pkgs[:15])
            return Card(
                title="Python 依赖管理",
                markdown=f"### 📦 已安装 Python 依赖（共 {len(pkgs)} 个）\n\n{summary}\n\n💡 发送 `/pip check <包名>` 检查版本，完整管理请登录 Web 管理台。",
                rows=[[self._btn(ctx, "测试 Ping", "/ping"), self._btn(ctx, "指南主菜单", "/guide")]],
            )
        if args[0] in {"check", "info"} and len(args) > 1:
            pkg = args[1].strip()
            try:
                dist = importlib.metadata.distribution(pkg)
                return f"✅ `{pkg}` 已安装，版本为 **{dist.version}**。\n简介：{dist.metadata.get('Summary', '')}"
            except importlib.metadata.PackageNotFoundError:
                return f"⚠️ 未找到 `{pkg}`，当前尚未安装。\n请在 Web 管理台【系统管理 → Python 依赖包】中一键安装。"
        return "用法：/pip 或 /pip check <包名>"

    # ---------- 事件与任务 ----------
    async def on_event(self, ctx: Any) -> None:
        self.state["events"] = int(self.state.get("events", 0)) + 1
        # 首次见到的用户写入问候记录（真实项目请谨慎：全量事件频率很高）
        key = f"{getattr(ctx, 'platform', '')}:{getattr(ctx, 'sender_id', '')}"
        greeted = self.state.setdefault("greeted", {})
        if key not in greeted:
            greeted[key] = int(__import__("time").time())
            if len(greeted) > 500:  # 防止无限膨胀
                oldest = sorted(greeted.items(), key=lambda kv: kv[1])[:100]
                for old_key, _ in oldest:
                    greeted.pop(old_key, None)
        self._save_state()
        if self.state["events"] % 20 == 0:
            self._write_page_snapshot()

    async def snapshot_task(self) -> None:
        self.state["tasks"] = int(self.state.get("tasks", 0)) + 1
        self._save_state()
        self._write_page_snapshot()

    def close(self) -> None:
        self._save_state()
        self._write_page_snapshot()
        logger.info("demo.guide 已关闭")


def setup(context: Any) -> DemoGuidePlugin:
    plugin = DemoGuidePlugin(context)
    context.register_command("guide", plugin.handle_guide, category="demo", description="插件开发指南演示主入口")
    context.register_command("ping", plugin.cmd_ping, category="diagnostic", description="检查机器人响应（pong）")
    context.register_command("echo", plugin.cmd_echo, category="diagnostic", description="回显输入文本")
    context.register_command("card", plugin.cmd_card, category="card", description="测试 Markdown 卡片与按钮交互")
    context.register_command("id", plugin.cmd_id, category="identity", description="查询用户稳定 ID 与会话信息")
    context.register_command("pip", plugin.cmd_pip, category="system", description="查询 Python 依赖包")
    context.register_event_handler("*", plugin.on_event)
    context.register_task("snapshot", 60, plugin.snapshot_task)
    return plugin

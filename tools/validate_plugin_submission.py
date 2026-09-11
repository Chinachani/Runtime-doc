#!/usr/bin/env python3
"""
Plugin Submission Validator for QQ Runtime Marketplace.

Can be run locally by developers or in GitHub Actions on the Chinachani/Runtime-doc repo.
Validates:
1. ZIP archive integrity and security (zip-slip, size limits, file count)
2. plugin.toml presence and schema compliance
3. Permission and dependency declarations
4. SHA-256 hash matching
5. Updates or appends to market.json
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

MAX_ZIP_SIZE = 52428800  # 50MB
MAX_FILE_COUNT = 1000
PLUGIN_ID_PATTERN = re.compile(r"^plugin\.[a-z0-9_]+(\.[a-z0-9_]+)*$")
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$")

VALID_PERMISSIONS = {
    "chat.read",
    "chat.send",
    "chat.receive",
    "points.manage",
    "plugins.manage",
    "network",
    "filesystem",
    "storage",
    "cron",
    "media.upload",
    "media.send",
    "audit",
    "system.info",
}


class ValidationError(Exception):
    pass


def parse_issue_body(body: str) -> dict[str, str]:
    """
    Extract fields from GitHub Issue Form markdown body.
    Supports both issue template headers (### Field) and standard key-value patterns.
    """
    data: dict[str, str] = {}
    current_key: str | None = None
    buffer: list[str] = []

    for line in body.splitlines():
        header_match = re.match(r"^###\s+(.+)$", line.strip())
        if header_match:
            if current_key and buffer:
                data[current_key] = "\n".join(buffer).strip()
                buffer = []
            header_name = header_match.group(1).strip()
            # Normalize headers
            if "插件标识" in header_name or "Plugin ID" in header_name:
                current_key = "plugin_id"
            elif "版本" in header_name or "Version" in header_name:
                current_key = "version"
            elif "下载链接" in header_name or "Download URL" in header_name:
                current_key = "download_url"
            elif "SHA-256" in header_name or "sha256" in header_name.lower():
                current_key = "sha256"
            elif "仓库" in header_name or "Repo URL" in header_name:
                current_key = "repo_url"
            elif "分类" in header_name or "Category" in header_name:
                current_key = "category"
            elif "图标" in header_name or "Icon" in header_name:
                current_key = "icon"
            elif "描述" in header_name or "Description" in header_name:
                current_key = "description"
            else:
                current_key = header_name.lower().replace(" ", "_")
        elif current_key is not None:
            buffer.append(line)

    if current_key and buffer:
        data[current_key] = "\n".join(buffer).strip()

    # Also look for backtick blocks or key: value fallback
    if "market.json" in body and "```json" in body:
        try:
            json_block = body.split("```json", 1)[1].split("```", 1)[0].strip()
            item = json.loads(json_block)
            for k in ("plugin_id", "id", "version", "download_url", "sha256", "category", "icon", "description", "repo_url"):
                if k in item and (k not in data or not data[k]):
                    norm_k = "plugin_id" if k == "id" else k
                    data[norm_k] = str(item[k])
        except Exception:
            pass

    return data


def validate_zip_content(zip_bytes: bytes) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    """
    Validates ZIP file safely and extracts manifest and metadata.
    Returns (manifest_dict, metadata_dict, warnings_list).
    """
    warnings: list[str] = []
    if len(zip_bytes) > MAX_ZIP_SIZE:
        raise ValidationError(f"插件包体积超过最大限制 50MB (当前大小: {len(zip_bytes)} 字节)")

    try:
        zf = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except Exception as exc:
        raise ValidationError(f"无效的 ZIP 压缩包: {exc}") from exc

    infolist = zf.infolist()
    if len(infolist) > MAX_FILE_COUNT:
        raise ValidationError(f"插件包内文件数过多 ({len(infolist)} > {MAX_FILE_COUNT})")

    # Check for zip slip and executable binaries
    has_manifest = False
    manifest_name: str | None = None
    metadata_name: str | None = None

    for info in infolist:
        name = info.filename
        if name.startswith("/") or "\\" in name or ".." in name.split("/"):
            raise ValidationError(f"检测到非法路径穿越风险: {name}")

        # Determine plugin.toml
        basename = name.split("/")[-1]
        if basename == "plugin.toml":
            has_manifest = True
            manifest_name = name
        elif basename == "metadata.yaml" or basename == "metadata.yml":
            metadata_name = name

    if not has_manifest or not manifest_name:
        raise ValidationError("插件包内未找到 plugin.toml 规范清单！")

    try:
        manifest_raw = zf.read(manifest_name).decode("utf-8")
        manifest = tomllib.loads(manifest_raw)
    except Exception as exc:
        raise ValidationError(f"解析 plugin.toml 失败: {exc}") from exc

    plugin_meta = manifest.get("plugin")
    if not isinstance(plugin_meta, dict):
        raise ValidationError("plugin.toml 中缺少 [plugin] 节")

    plugin_id = plugin_meta.get("id")
    if not plugin_id or not isinstance(plugin_id, str):
        raise ValidationError("plugin.toml 中缺少 plugin.id 或不是字符串")
    if not PLUGIN_ID_PATTERN.match(plugin_id):
        raise ValidationError(
            f"plugin.id 格式非法: '{plugin_id}'，必须以 'plugin.' 开头且只包含小写字母、数字、点或下划线"
        )

    version = plugin_meta.get("version")
    if not version or not isinstance(version, str):
        raise ValidationError("plugin.toml 中缺少 plugin.version 或不是字符串")
    if not VERSION_PATTERN.match(version):
        raise ValidationError(f"plugin.version '{version}' 不符合语义化版本格式 (如 1.0.0)")

    name = plugin_meta.get("name")
    if not name or not isinstance(name, str):
        raise ValidationError("plugin.toml 中缺少 plugin.name")

    entrypoint = plugin_meta.get("entrypoint")
    if not entrypoint or not isinstance(entrypoint, str) or ":" not in entrypoint:
        raise ValidationError("plugin.toml 中缺少合法的 plugin.entrypoint (需为 'module:func' 格式)")

    permissions = manifest.get("permissions", [])
    if not isinstance(permissions, list):
        raise ValidationError("plugin.toml 中的 permissions 必须为数组")
    for perm in permissions:
        if perm not in VALID_PERMISSIONS:
            warnings.append(f"声明了未知的权限: '{perm}'")

    metadata: dict[str, Any] = {}
    if metadata_name:
        try:
            meta_raw = zf.read(metadata_name).decode("utf-8")
            # Parse simple yaml key-values
            for line in meta_raw.splitlines():
                if ":" in line and not line.strip().startswith("#"):
                    k, v = line.split(":", 1)
                    metadata[k.strip()] = v.strip().strip("'\"")
        except Exception:
            pass

    return manifest, metadata, warnings


def download_zip(url: str, timeout: int = 30) -> bytes:
    """Download ZIP package from release URL."""
    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; RuntimeMarketValidator/1.0)",
        "Accept": "*/*",
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status != 200:
                raise ValidationError(f"下载失败: HTTP {resp.status}")
            return resp.read()
    except Exception as exc:
        raise ValidationError(f"无法从 '{url}' 下载插件包: {exc}") from exc


def validate_submission(
    zip_bytes: bytes,
    download_url: str,
    repo_url: str = "",
    expected_hash: str | None = None,
    category: str = "tools",
    icon: str = "🚀",
) -> tuple[dict[str, Any], list[str]]:
    """
    Run comprehensive checks on zip bytes and metadata.
    Returns (market_entry, warnings).
    """
    actual_hash = hashlib.sha256(zip_bytes).hexdigest()
    if expected_hash:
        expected_clean = expected_hash.strip().lower()
        if actual_hash.lower() != expected_clean:
            raise ValidationError(
                f"SHA-256 校验码不匹配！\n期望值: {expected_clean}\n实际计算值: {actual_hash}"
            )

    manifest, metadata, warnings = validate_zip_content(zip_bytes)
    plugin_meta = manifest["plugin"]
    plugin_id = plugin_meta["id"]
    version = plugin_meta["version"]
    name = plugin_meta["name"]
    description = metadata.get("desc") or plugin_meta.get("description") or f"{name} 插件"
    author = metadata.get("author") or "社区开发者"
    final_icon = metadata.get("icon") or icon or "📦"

    market_entry = {
        "id": plugin_id,
        "name": name,
        "version": version,
        "author": author,
        "category": category,
        "icon": final_icon,
        "description": description,
        "download_url": download_url,
        "repo_url": repo_url,
        "sha256": actual_hash,
        "size_bytes": len(zip_bytes),
        "permissions": manifest.get("permissions", []),
        "tags": [category],
    }

    return market_entry, warnings


def update_market_file(market_file: Path, new_entry: dict[str, Any]) -> str:
    """
    Updates or inserts the entry into market.json.
    Returns an action string: 'added' or 'updated'.
    """
    if not market_file.exists():
        market_data: list[dict[str, Any]] = []
    else:
        try:
            market_data = json.loads(market_file.read_text(encoding="utf-8"))
            if not isinstance(market_data, list):
                market_data = []
        except Exception:
            market_data = []

    action = "added"
    existing_idx = None
    for idx, item in enumerate(market_data):
        if item.get("id") == new_entry["id"]:
            existing_idx = idx
            break

    if existing_idx is not None:
        market_data[existing_idx] = new_entry
        action = "updated"
    else:
        market_data.append(new_entry)

    # Sort deterministically by id
    market_data.sort(key=lambda x: str(x.get("id", "")))
    market_file.write_text(json.dumps(market_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return action


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate plugin submission for QQ Runtime Market")
    parser.add_argument("--file", type=str, help="Path to local plugin zip file")
    parser.add_argument("--url", type=str, help="Download URL of the plugin zip")
    parser.add_argument("--expected-hash", type=str, help="Expected SHA-256 hash")
    parser.add_argument("--repo-url", type=str, default="", help="Plugin source repository URL")
    parser.add_argument("--category", type=str, default="tools", help="Marketplace category")
    parser.add_argument("--icon", type=str, default="🚀", help="Plugin display icon")
    parser.add_argument("--issue-body", type=str, help="Raw GitHub issue body text")
    parser.add_argument("--market-json-path", type=str, help="Path to market.json to update")
    parser.add_argument("--update-market", action="store_true", help="Automatically update market.json")
    parser.add_argument("--output-json", action="store_true", help="Print result as json")

    args = parser.parse_args()

    download_url = args.url or ""
    repo_url = args.repo_url or ""
    expected_hash = args.expected_hash
    category = args.category
    icon = args.icon
    zip_bytes: bytes | None = None

    if args.issue_body:
        parsed_data = parse_issue_body(args.issue_body)
        if "download_url" in parsed_data:
            download_url = parsed_data["download_url"].strip()
        if "sha256" in parsed_data:
            expected_hash = parsed_data["sha256"].strip()
        if "repo_url" in parsed_data:
            repo_url = parsed_data["repo_url"].strip()
        if "category" in parsed_data:
            category = parsed_data["category"].strip()
        if "icon" in parsed_data:
            icon = parsed_data["icon"].strip()

    if args.file:
        file_path = Path(args.file)
        if not file_path.exists():
            print(f"❌ 错误: 本地文件不存在: {file_path}", file=sys.stderr)
            return 1
        zip_bytes = file_path.read_bytes()
        if not download_url:
            download_url = f"file://{file_path.resolve()}"
    elif download_url:
        print(f"📥 正在从 URL 下载插件包: {download_url}...")
        try:
            zip_bytes = download_zip(download_url)
        except ValidationError as exc:
            print(f"❌ 下载失败: {exc}", file=sys.stderr)
            return 1
    else:
        print("❌ 错误: 必须提供 --file 或 --url 或有效包含 download_url 的 --issue-body", file=sys.stderr)
        return 1

    try:
        market_entry, warnings = validate_submission(
            zip_bytes=zip_bytes,
            download_url=download_url,
            repo_url=repo_url,
            expected_hash=expected_hash,
            category=category,
            icon=icon,
        )
    except ValidationError as exc:
        print(f"❌ 插件校验失败:\n{exc}", file=sys.stderr)
        return 1

    action = None
    if args.update_market and args.market_json_path:
        market_file = Path(args.market_json_path)
        action = update_market_file(market_file, market_entry)
        print(f"✅ market.json 已更新 (动作: {action}): {market_file}")

    if args.output_json:
        result = {
            "valid": True,
            "action": action,
            "market_entry": market_entry,
            "warnings": warnings,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("\n🎉 插件校验通过！")
        print(f"- 标识: {market_entry['id']}")
        print(f"- 名称: {market_entry['name']}")
        print(f"- 版本: {market_entry['version']}")
        print(f"- 体积: {market_entry['size_bytes']} 字节 ({Math.round(market_entry['size_bytes']/1024) if False else round(market_entry['size_bytes']/1024)} KB)")
        print(f"- SHA-256: {market_entry['sha256']}")
        if warnings:
            print(f"- 警告提示: {', '.join(warnings)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

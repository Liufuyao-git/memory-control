#!/usr/bin/env python3
"""
audit.py — 系统配置文件 token 审计脚本
职责：token 计数 + 文件元数据 + 凭据标记，不做内容分析（内容交 AI）
"""

import os
import json
import re
import sys
from datetime import datetime
from pathlib import Path

# ── 默认审计文件列表 ──────────────────────────────────────────
DEFAULT_FILES = [
    "MEMORY.md",
    "SOUL.md",
    "TOOLS.md",
    "AGENTS.md",
    "USER.md",
    "IDENTITY.md",
    "HEARTBEAT.md",
]

# 凭据关键词
# 注意：去掉了裸 "key"（过于宽泛，在 markdown 中误报率极高）
# 保留 "api_key" / "access_token" 等精确形式
CREDENTIAL_KEYWORDS = [
    "token", "secret", "password", "credential",
    "PRIVATE-TOKEN", "access_token", "api_key", "Authorization",
]

# 真实凭据判定：连续字母数字串最短长度（过短的串多为说明性文字）
CRED_MIN_ALNUM_RUN = 6

# CW 定价（$/M tok，Anthropic Cache Write）
CW_PRICE_PER_M = 3.75

# 中文字符占比阈值（超过则加 cjk_warning，提示 token 估算误差可达 ±25%）
CJK_RATIO_THRESHOLD = 0.30


def count_tokens(text: str) -> tuple[int, str]:
    """
    token 计数：优先 tiktoken，fallback 字符÷3.5 估算
    返回 (token数, 精度标注)
    """
    try:
        import tiktoken
        enc = tiktoken.get_encoding("cl100k_base")
        return len(enc.encode(text)), "tiktoken(cl100k)"
    except Exception:
        estimated = int(len(text) / 3.5)
        return estimated, "estimate(char÷3.5, ±15%)"


def _is_likely_real_credential(line: str) -> bool:
    """
    判断某行是否为真实凭据（而非说明性文字）。
    条件（同时满足）：
      1. 含赋值符号（= : ` ' "）
      2. 含连续字母数字串，长度 >= CRED_MIN_ALNUM_RUN
    降低误报的关键：说明性文字（如「token 消耗」「api_key 说明」）
    不含长连续字母数字串，会被过滤掉。
    """
    has_assign = any(c in line for c in ['=', '`', "'", '"', ':'])
    # 找连续字母数字串，长度阈值由 CRED_MIN_ALNUM_RUN 控制
    alnum_runs = re.findall(rf'[A-Za-z0-9_\-]{{{CRED_MIN_ALNUM_RUN},}}', line)
    has_long_alnum = len(alnum_runs) > 0
    return has_assign and has_long_alnum


def find_credential_lines(text: str) -> tuple[list[dict], list[dict]]:
    """
    精确到行的凭据检测。
    返回两个列表：
      - credential_lines: likely_credential=True 的行（AI 必须保护）
      - credential_lines_noise: likely_credential=False 的行（仅供参考，AI 不处理）
    """
    confirmed = []
    noise = []
    kw_lower_list = [kw.lower() for kw in CREDENTIAL_KEYWORDS]

    for i, line in enumerate(text.splitlines(), start=1):
        line_lower = line.lower()
        matched_kw = None
        for kw, kw_lower in zip(CREDENTIAL_KEYWORDS, kw_lower_list):
            if kw_lower in line_lower:
                matched_kw = kw
                break
        if matched_kw is None:
            continue

        entry = {
            "line": i,
            "preview": line.strip()[:60],
            "keyword": matched_kw,
        }
        if _is_likely_real_credential(line):
            confirmed.append(entry)
        else:
            noise.append(entry)

    return confirmed, noise


def detect_cjk_ratio(text: str) -> float:
    """计算文本中 CJK 字符占比"""
    if not text:
        return 0.0
    cjk_count = sum(1 for c in text if '\u4e00' <= c <= '\u9fff')
    return cjk_count / len(text)


def extract_read_when(text: str) -> str:
    """从 frontmatter 提取 read_when 字段"""
    match = re.search(r'read_when:\s*\n((?:\s+-[^\n]+\n?)+)', text)
    if match:
        items = re.findall(r'-\s*(.+)', match.group(1))
        return ", ".join(items)
    return ""


def validate_user_md(workspace: Path) -> dict:
    """
    校验 USER.md 是否存在且内容足够建立场景基线。
    返回 {"valid": bool, "reason": str}
    """
    user_md = workspace / "USER.md"
    if not user_md.exists():
        return {"valid": False, "reason": "USER.md 不存在，无法建立用户场景基线"}
    try:
        text = user_md.read_text(encoding="utf-8").strip()
    except Exception as e:
        return {"valid": False, "reason": f"USER.md 读取失败：{e}"}
    if len(text) < 50:
        return {"valid": False, "reason": f"USER.md 内容过少（{len(text)} 字符），无法建立有效场景基线"}
    return {"valid": True, "reason": "ok"}


def audit_file(workspace: Path, filename: str) -> dict:
    filepath = workspace / filename
    if not filepath.exists():
        return {
            "file": filename,
            "exists": False,
            "tokens": 0,
            "token_source": "-",
            "lines": 0,
            "size_bytes": 0,
            "has_credentials": False,
            "credential_lines": [],
            "credential_lines_noise": [],
            "cjk_warning": False,
            "read_when": "",
            "cw_cost_per_turn": 0.0,
            "savings_per_10k_turns": 0.0,
            "note": "文件不存在，跳过"
        }

    try:
        text = filepath.read_text(encoding="utf-8")
    except Exception as e:
        return {
            "file": filename,
            "exists": True,
            "error": str(e),
            "tokens": 0,
            "token_source": "-",
            "lines": 0,
            "size_bytes": 0,
            "has_credentials": False,
            "credential_lines": [],
            "credential_lines_noise": [],
            "cjk_warning": False,
            "read_when": "",
            "cw_cost_per_turn": 0.0,
            "savings_per_10k_turns": 0.0,
            "note": f"文件读取失败：{e}"
        }

    tokens, token_source = count_tokens(text)
    lines = text.count('\n') + 1
    size = filepath.stat().st_size
    confirmed_creds, noise_creds = find_credential_lines(text)
    read_when = extract_read_when(text)
    cjk_ratio = detect_cjk_ratio(text)
    cjk_warning = cjk_ratio > CJK_RATIO_THRESHOLD

    # 费用估算
    cw_cost_per_turn = tokens * CW_PRICE_PER_M / 1_000_000
    savings_per_10k = cw_cost_per_turn * 10_000

    severity = _calc_severity(filename, text, lines, tokens)

    result = {
        "file": filename,
        "exists": True,
        "tokens": tokens,
        "token_source": token_source,
        "lines": lines,
        "size_bytes": size,
        "has_credentials": len(confirmed_creds) > 0,
        # AI 只保护 credential_lines 里的行，noise 仅供参考不处理
        "credential_lines": confirmed_creds,
        "credential_lines_noise": noise_creds,
        "cjk_warning": cjk_warning,
        "read_when": read_when,
        "severity": severity,
        "cw_cost_per_turn": round(cw_cost_per_turn, 6),
        "savings_per_10k_turns": round(savings_per_10k, 4),
    }
    if cjk_warning:
        result["cjk_warning_msg"] = (
            f"CJK 字符占比 {cjk_ratio:.0%}，token 估算误差可达 ±25%，"
            "节省数字仅供参考，实际以 Phase 2 执行后重跑 audit.py 为准"
        )
    return result


def _calc_severity(filename: str, text: str, lines: int, tokens: int) -> str:
    """
    Severity 评级
    High   → 立即处理，每轮影响 >500 tok
    Medium → 本轮处理，每轮影响 200~500 tok
    Low    → 下次处理，影响 <200 tok
    """
    name = filename.upper()

    if "MEMORY" in name and lines > 200:
        return "High"

    code_block_count = text.count("```")
    if code_block_count >= 6:  # 3 个完整代码块（开+闭 × 2 = 6）
        return "High"

    if "HEARTBEAT" in name and lines > 60:
        return "Medium"

    table_count = text.count("|")
    if tokens > 500 and table_count >= 10:
        return "Medium"

    if tokens > 400:
        return "Medium"

    return "Low"


def load_config(workspace: Path) -> list[str]:
    """读取 config.yaml 中的 files 列表，不存在则用默认列表。
    查找顺序：工作区根 config.yaml → skills/context-slim/config.yaml（兼容旧布局）
    """
    candidates = [
        workspace / "config.yaml",
        workspace / "skills" / "context-slim" / "config.yaml",
    ]
    config_path = next((p for p in candidates if p.exists()), None)
    if config_path is not None:
        try:
            import yaml
            with open(config_path) as f:
                cfg = yaml.safe_load(f)
            if cfg and cfg.get("files"):
                print(f"[audit] 使用 {config_path.name}（{config_path}）文件列表：{cfg['files']}", file=sys.stderr)
                return cfg["files"]
            else:
                print(f"[audit] 警告：{config_path} 中 files 为空，使用默认列表", file=sys.stderr)
        except ImportError:
            print("[audit] 警告：未安装 PyYAML，config.yaml 未生效，使用默认文件列表", file=sys.stderr)
        except Exception as e:
            print(f"[audit] 警告：读取 {config_path} 失败（{e}），使用默认文件列表", file=sys.stderr)
    return DEFAULT_FILES


def main():
    import argparse
    parser = argparse.ArgumentParser(description="context-slim audit script")
    parser.add_argument("--config", type=str, default=None,
                        help="指定 config.yaml 路径（绝对路径或相对于 workspace 的路径）")
    args = parser.parse_args()

    workspace = Path(os.environ.get("OPENCLAW_WORKSPACE", Path.home() / ".openclaw" / "workspace"))

    # ── USER.md 校验（Phase 0 前置条件）──────────────────────
    user_baseline = validate_user_md(workspace)
    if not user_baseline["valid"]:
        print(f"[audit] ⚠️  USER.md 校验失败：{user_baseline['reason']}", file=sys.stderr)
        print("[audit] Phase 0 中止。请先确保 USER.md 存在且包含用户场景信息，再运行审计。", file=sys.stderr)
        # 仍然输出 JSON，但带 abort 标记，供 AI 感知
        print(json.dumps({
            "abort": True,
            "abort_reason": user_baseline["reason"],
            "generated_at": datetime.now().isoformat(),
            "workspace": str(workspace),
        }, ensure_ascii=False))
        sys.exit(1)

    # ── 读取文件列表 ─────────────────────────────────────────
    if args.config:
        config_path = Path(args.config)
        if not config_path.is_absolute():
            config_path = workspace / args.config
        files = DEFAULT_FILES
        try:
            import yaml
            with open(config_path) as f:
                cfg = yaml.safe_load(f)
            if cfg and cfg.get("files"):
                files = cfg["files"]
                print(f"[audit] 使用指定 config：{config_path} → {files}", file=sys.stderr)
            else:
                print(f"[audit] 警告：{config_path} 无有效 files 列表，使用默认", file=sys.stderr)
        except ImportError:
            print("[audit] 警告：未安装 PyYAML，--config 参数无效，使用默认文件列表", file=sys.stderr)
        except Exception as e:
            print(f"[audit] 警告：读取 {config_path} 失败（{e}），使用默认文件列表", file=sys.stderr)
    else:
        files = load_config(workspace)

    results = [audit_file(workspace, f) for f in files]

    total_tokens = sum(r["tokens"] for r in results if r.get("exists") and not r.get("error"))
    total_cw_per_turn = sum(r["cw_cost_per_turn"] for r in results if r.get("exists") and not r.get("error"))
    total_savings_10k = sum(r["savings_per_10k_turns"] for r in results if r.get("exists") and not r.get("error"))
    has_cjk_warning = any(r.get("cjk_warning") for r in results)

    output = {
        "abort": False,
        "generated_at": datetime.now().isoformat(),
        "workspace": str(workspace),
        "cw_price_per_m_tok": CW_PRICE_PER_M,
        "user_baseline_status": user_baseline,
        "summary": {
            "total_files": len([r for r in results if r.get("exists")]),
            "total_tokens": total_tokens,
            "total_cw_cost_per_turn": round(total_cw_per_turn, 6),
            "total_savings_per_10k_turns": round(total_savings_10k, 4),
            "cjk_warning": has_cjk_warning,
            "savings_note": (
                "含中文文件，token 估算误差可达 ±25%，节省数字仅供参考"
                if has_cjk_warning else
                "token 估算误差 ±15%，节省数字仅供参考，以 Phase 2 执行后重测为准"
            ),
        },
        "files": results,
    }

    if len([r for r in results if r.get("exists")]) == 0:
        print("[audit] 错误：所有文件均不存在，请检查 workspace 路径", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

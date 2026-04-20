#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# backup.sh — context-slim Phase 2 强制备份脚本
#
# 用法：bash skills/context-slim/scripts/backup.sh [file1 file2 ...]
#   不传参数：备份 DEFAULT_FILES（7 个标准配置文件）
#   传参数：只备份指定文件（相对于 workspace 根目录）
#
# 成功：打印 BACKUP_OK <备份目录路径>，exit 0
# 失败：打印 BACKUP_FAILED <原因>，exit 1
#
# AI 必须看到 "BACKUP_OK" 才能继续 Phase 2，否则立即中止。
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
BACKUP_BASE="$WORKSPACE/.backup"
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="$BACKUP_BASE/$DATE"
MANIFEST="$BACKUP_DIR/backup_manifest.json"

# 默认备份文件列表
DEFAULT_FILES=(
    "MEMORY.md"
    "SOUL.md"
    "TOOLS.md"
    "AGENTS.md"
    "USER.md"
    "IDENTITY.md"
    "HEARTBEAT.md"
)

# ── 确定备份文件列表 ──────────────────────────────────────────
if [ $# -gt 0 ]; then
    FILES=("$@")
else
    FILES=("${DEFAULT_FILES[@]}")
fi

# ── 创建备份目录 ──────────────────────────────────────────────
mkdir -p "$BACKUP_DIR" || {
    echo "BACKUP_FAILED 无法创建备份目录：$BACKUP_DIR"
    exit 1
}

# ── 逐文件备份 ────────────────────────────────────────────────
BACKED_UP=()
SKIPPED=()
FAILED=()

for f in "${FILES[@]}"; do
    src="$WORKSPACE/$f"
    # 保留子目录结构（如 memory/2026-04-13.md）
    dst_dir="$BACKUP_DIR/$(dirname "$f")"
    mkdir -p "$dst_dir"
    dst="$BACKUP_DIR/$f"

    if [ ! -f "$src" ]; then
        SKIPPED+=("$f")
        continue
    fi

    if cp "$src" "$dst" 2>/dev/null; then
        BACKED_UP+=("$f")
    else
        FAILED+=("$f")
    fi
done

# ── 失败检查 ──────────────────────────────────────────────────
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "BACKUP_FAILED 以下文件备份失败：${FAILED[*]}"
    exit 1
fi

if [ ${#BACKED_UP[@]} -eq 0 ]; then
    echo "BACKUP_FAILED 没有任何文件被备份（所有文件均不存在）"
    exit 1
fi

# ── 写 manifest ───────────────────────────────────────────────
# 构造 JSON array（逐元素加引号，不用 shell 展开拼接可执行命令，避免空格问题）
BACKED_JSON=$(printf '"%s",' "${BACKED_UP[@]}" | sed 's/,$//')
if [ ${#SKIPPED[@]} -gt 0 ]; then
    SKIPPED_JSON=$(printf '"%s",' "${SKIPPED[@]}" | sed 's/,$//')
else
    SKIPPED_JSON=""
fi

cat > "$MANIFEST" <<EOF
{
  "backup_time": "$(date -Iseconds)",
  "workspace": "$WORKSPACE",
  "backup_dir": "$BACKUP_DIR",
  "backed_up": [$BACKED_JSON],
  "skipped_not_exist": [$SKIPPED_JSON],
  "restore_note": "逐文件恢复：cp <backup_dir>/<file> <workspace>/<file>，例如：cp $BACKUP_DIR/SOUL.md $WORKSPACE/SOUL.md"
}
EOF

# ── 成功输出 ──────────────────────────────────────────────────
echo "BACKUP_OK $BACKUP_DIR"
echo "  已备份：${#BACKED_UP[@]} 个文件 → $BACKUP_DIR"
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo "  跳过（不存在）：${SKIPPED[*]}"
fi
echo "  恢复：cp $BACKUP_DIR/<file> $WORKSPACE/<file>"

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# context-slim · 效果验证测试套件
# 用法：bash tests/run_test.sh
#        从 workspace 根目录执行（OPENCLAW_WORKSPACE 指向该根目录）
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
# 确保子进程（python3 audit.py）与 bash 使用同一工作区根路径
export OPENCLAW_WORKSPACE="$WORKSPACE"
# 本仓库布局：脚本与测试位于工作区根目录下 scripts/、tests/
TEST_DIR="$WORKSPACE/tests"
AUDIT_PY="$WORKSPACE/scripts/audit.py"
TEST_CONFIG="$TEST_DIR/config.yaml"
EXPECTED="$TEST_DIR/expected.json"
RESULT_JSON="/tmp/context_slim_test_result.json"
TOKEN_TOLERANCE=0.20   # ±20%

# ── 颜色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0; WARN=0

# bash: ((expr)) 当 expr=0 时返回 exit code 1，触发 set -e；|| true 规避此行为
pass() { echo -e "  ${GREEN}✓${RESET} $1"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}✗${RESET} $1"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; ((WARN++)) || true; }
info() { echo -e "  ${CYAN}→${RESET} $1"; }

# ── 前置检查 ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ context-slim 效果验证 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

echo -e "${BOLD}[前置检查]${RESET}"

[ -f "$AUDIT_PY" ]    && pass "audit.py 存在" || { fail "audit.py 不存在：$AUDIT_PY"; exit 1; }
[ -f "$TEST_CONFIG" ] && pass "tests/config.yaml 存在" || { fail "tests/config.yaml 不存在"; exit 1; }
[ -f "$EXPECTED" ]    && pass "tests/expected.json 存在" || { fail "tests/expected.json 不存在"; exit 1; }

# 检查 mock 文件是否存在
for mock in mock_AGENTS.md mock_MEMORY.md mock_TOOLS.md mock_SOUL.md mock_BOOTSTRAP.md; do
  [ -f "$TEST_DIR/$mock" ] && pass "mock 文件存在：$mock" || fail "mock 文件缺失：$mock"
done

echo ""

# ── 运行 audit.py ─────────────────────────────────────────────────────────────
echo -e "${BOLD}[运行 audit.py]${RESET}"
info "python3 $AUDIT_PY --config $TEST_CONFIG"
echo ""

cd "$WORKSPACE"
python3 "$AUDIT_PY" --config "$TEST_CONFIG" > "$RESULT_JSON" 2>/tmp/audit_stderr.txt
AUDIT_EXIT=$?

if [ $AUDIT_EXIT -ne 0 ]; then
  fail "audit.py 异常退出 (exit $AUDIT_EXIT)"
  cat /tmp/audit_stderr.txt
  exit 1
fi
pass "audit.py 正常退出"

# 打印 stderr（info 级别日志）
if [ -s /tmp/audit_stderr.txt ]; then
  while IFS= read -r line; do info "$line"; done < /tmp/audit_stderr.txt
fi
echo ""

# ── 解析结果 ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}[T1 · 汇总校验]${RESET}"

total_files=$(python3 -c "import json; d=json.load(open('$RESULT_JSON')); print(d['summary']['total_files'])")
total_tokens=$(python3 -c "import json; d=json.load(open('$RESULT_JSON')); print(d['summary']['total_tokens'])")
expected_files=$(python3 -c "import json; d=json.load(open('$EXPECTED')); print(d['summary']['total_files_expect'])")
cred_files=$(python3 -c "import json; d=json.load(open('$RESULT_JSON')); print(sum(1 for f in d['files'] if f.get('has_credentials')))")

info "审计文件数: $total_files (期望 $expected_files)"
info "总 token 数: $total_tokens"
info "含凭据文件数: $cred_files"

[ "$total_files" -eq "$expected_files" ] \
  && pass "文件数正确 ($total_files)" \
  || fail "文件数不符: 实际=$total_files 期望=$expected_files"

[ "$total_tokens" -gt 500 ] \
  && pass "总 token 数合理 ($total_tokens > 500)" \
  || fail "总 token 数异常偏低 ($total_tokens), mock 文件可能未被正确读取"

echo ""

# ── 逐文件校验 ────────────────────────────────────────────────────────────────
echo -e "${BOLD}[T2 · 逐文件校验]${RESET}"

python3 - <<'PYEOF'
import json, sys, os

result_path = "/tmp/context_slim_test_result.json"
_workspace = os.environ.get("OPENCLAW_WORKSPACE", os.path.expanduser("~/.openclaw/workspace"))
expected_path = os.path.join(_workspace, "tests", "expected.json")

result = json.load(open(result_path))
expected = json.load(open(expected_path))

PASS = 0; FAIL = 0; WARN = 0
TOL = expected["_tolerance"]["token_pct"]

def p(msg): print(f"  \033[0;32m✓\033[0m {msg}"); global PASS; PASS += 1
def f(msg): print(f"  \033[0;31m✗\033[0m {msg}"); global FAIL; FAIL += 1
def w(msg): print(f"  \033[1;33m⚠\033[0m {msg}"); global WARN; WARN += 1
def i(msg): print(f"  \033[0;36m→\033[0m {msg}")

result_map = {r["file"]: r for r in result["files"]}

for exp in expected["files"]:
    fname = exp["file"]
    short = fname.split("/")[-1]
    print(f"\n  \033[1m{short}\033[0m")

    r = result_map.get(fname)
    if r is None:
        f(f"文件未出现在 audit 结果中：{fname}")
        FAIL += 1
        continue

    # exists
    if r.get("exists"):
        p("exists=true")
    else:
        f("exists=false，文件未被读取")
        continue

    # token 范围
    tok = r.get("tokens", 0)
    tmin, tmax = exp["token_min"], exp["token_max"]
    # 扩展容差
    tmin_tol = int(tmin * (1 - TOL))
    tmax_tol = int(tmax * (1 + TOL))
    if tmin_tol <= tok <= tmax_tol:
        p(f"token 数在范围内：{tok}（期望 {tmin}~{tmax}，±{int(TOL*100)}% 容差）")
    else:
        f(f"token 数超出范围：{tok}（期望 {tmin}~{tmax}，±{int(TOL*100)}% 容差）")

    # severity
    sev = r.get("severity", "")
    sev_expect = exp["severity_expect"]
    if sev in sev_expect:
        p(f"severity 正确：{sev}（期望之一：{sev_expect}）")
    else:
        f(f"severity 不符：实际={sev}，期望之一={sev_expect}")
        i(exp.get("_severity_reason", ""))

    # has_credentials
    hc = r.get("has_credentials", False)
    hc_exp = exp["has_credentials"]
    if hc == hc_exp:
        p(f"has_credentials 正确：{hc}")
    else:
        f(f"has_credentials 不符：实际={hc}，期望={hc_exp}")

    # credential_lines 数量（仅 mock_TOOLS.md）
    if "credential_lines_min" in exp:
        cl = len(r.get("credential_lines", []))
        cmin = exp["credential_lines_min"]
        if cl >= cmin:
            p(f"credential_lines 数量满足：{cl} >= {cmin}")
        else:
            f(f"credential_lines 数量不足：{cl} < {cmin}（期望至少检测到 {cmin} 处真实凭据）")

    # credential_lines_noise 上限（验证误报过滤有效）
    if "credential_lines_noise_max" in exp:
        noise = len(r.get("credential_lines_noise", []))
        nmax = exp["credential_lines_noise_max"]
        if noise <= nmax:
            p(f"credential_lines_noise 在容忍范围内：{noise} <= {nmax}（误报过滤有效）")
        else:
            f(f"credential_lines_noise 过多：{noise} > {nmax}（误报过滤可能失效）")

    # 冗余块提示（informational，不判 PASS/FAIL）
    redundant = exp.get("redundant_sections", [])
    if redundant:
        i(f"期望识别的冗余块（{len(redundant)} 个，Phase 1 人工核对）：")
        for s in redundant:
            print(f"      - {s}")

# 汇总 severity 统计
print(f"\n  \033[1m[汇总 severity 分布]\033[0m")
sev_counts = {}
for r in result["files"]:
    if r.get("exists"):
        s = r.get("severity","?")
        sev_counts[s] = sev_counts.get(s, 0) + 1
for s, c in sorted(sev_counts.items()):
    print(f"  → {s}: {c} 个文件")

exp_sum = expected["summary"]
med_high = sev_counts.get("High", 0) + sev_counts.get("Medium", 0)
if med_high >= exp_sum["medium_or_high_severity_files_min"]:
    p(f"Medium/High 文件数满足：{med_high} >= {exp_sum['medium_or_high_severity_files_min']}")
else:
    f(f"Medium/High 文件数不足：{med_high} < {exp_sum['medium_or_high_severity_files_min']}")

print(f"\n__RESULT__ PASS={PASS} FAIL={FAIL} WARN={WARN}")
PYEOF

echo ""

# ── T3: 输出格式校验 ──────────────────────────────────────────────────────────
echo -e "${BOLD}[T3 · JSON 输出格式校验]${RESET}"

python3 -c "
import json
d = json.load(open('$RESULT_JSON'))
required_top = ['generated_at','workspace','summary','files']
required_file = ['file','exists','tokens','severity','has_credentials','credential_lines','cw_cost_per_turn']
ok = True
for k in required_top:
    if k not in d:
        print(f'  \033[0;31m✗\033[0m 顶层字段缺失：{k}'); ok = False
    else:
        print(f'  \033[0;32m✓\033[0m 顶层字段存在：{k}')
for f in d['files']:
    if not f.get('exists'): continue
    for k in required_file:
        if k not in f:
            print(f'  \033[0;31m✗\033[0m {f[\"file\"].split(\"/\")[-1]} 缺少字段：{k}'); ok = False
print('  \033[0;32m✓\033[0m 所有存在文件的必要字段齐全' if ok else '')
"

echo ""

# ── 最终结果 ──────────────────────────────────────────────────────────────────
RESULT_LINE=$(grep "__RESULT__" /tmp/audit_stderr.txt 2>/dev/null || true)
PY_PASS=$(python3 -c "
import subprocess, sys
result = open('/tmp/context_slim_test_result.json').read()
" 2>/dev/null || echo "")

# 从 Python 输出里提取最终计数
FINAL=$(python3 - <<'PYEOF2'
import re, subprocess, sys

# re-run summary extraction from T2 output (captured above via tee)
# 由于 bash heredoc 已经打印了，这里只输出最终判断
import json, os

r = json.load(open("/tmp/context_slim_test_result.json"))
_ws = os.environ.get("OPENCLAW_WORKSPACE", os.path.expanduser("~/.openclaw/workspace"))
e = json.load(open(os.path.join(_ws, "tests", "expected.json")))

checks = []
# T1: file count
checks.append(r["summary"]["total_files"] == e["summary"]["total_files_expect"])
# T1: total tokens > 500
checks.append(r["summary"]["total_tokens"] > 500)

result_map = {f["file"]: f for f in r["files"]}
for exp in e["files"]:
    rv = result_map.get(exp["file"])
    if not rv or not rv.get("exists"): checks.append(False); continue
    # token range
    tok = rv["tokens"]
    tol = e["_tolerance"]["token_pct"]
    checks.append(int(exp["token_min"]*(1-tol)) <= tok <= int(exp["token_max"]*(1+tol)))
    # severity
    checks.append(rv.get("severity") in exp["severity_expect"])
    # credentials
    checks.append(rv.get("has_credentials") == exp["has_credentials"])

total = len(checks); passed = sum(checks); failed = total - passed
print(f"TOTAL={total} PASSED={passed} FAILED={failed}")
PYEOF2
)

TOTAL=$(echo "$FINAL" | grep -o 'TOTAL=[0-9]*' | cut -d= -f2)
PASSED=$(echo "$FINAL" | grep -o 'PASSED=[0-9]*' | cut -d= -f2)
FAILED=$(echo "$FINAL" | grep -o 'FAILED=[0-9]*' | cut -d= -f2)

echo -e "${BOLD}━━━ 测试结果 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  检查项总计：${BOLD}$TOTAL${RESET}  通过：${GREEN}${BOLD}$PASSED${RESET}  失败：${RED}${BOLD}$FAILED${RESET}"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}✅ ALL PASSED${RESET} — context-slim skill 效果验证通过"
  echo ""
  echo -e "  ${CYAN}下一步 (人工): 触发 skill Phase 1，核对冗余块识别是否与 expected.json 一致${RESET}"
else
  echo -e "  ${RED}${BOLD}❌ FAILED ($FAILED/$TOTAL)${RESET} — 请检查上方失败项"
fi

echo ""
echo -e "  完整 audit 结果：${CYAN}$RESULT_JSON${RESET}"
echo ""

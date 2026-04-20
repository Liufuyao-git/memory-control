---
name: context-slim
version: 1.0.0
updated_at: "2026-04-13"
description: >
  智能体工作区系统配置文件瘦身 Skill。当用户说「帮我瘦身系统配置」「审计 bootstrap 文件」
  「context audit」「系统文件太大了」「配置文件占太多 token」时触发。
  专门针对每轮必须写入上下文的系统配置文件（MEMORY.md / SOUL.md / TOOLS.md /
  AGENTS.md / USER.md / IDENTITY.md / HEARTBEAT.md），分析上下文负担，
  识别冗余，给出精简建议，等用户确认后执行。不处理 skills/ 目录下的 SKILL.md 文件。
---

# context-slim — 系统配置文件瘦身

## 功能概述

审计工作区（workspace）中每轮必须加载的系统配置文件，识别冗余内容（无关场景、跨文件重复、死代码、过期文件、冗余表述），输出量化的瘦身建议，等用户确认后执行。

**核心价值**：系统配置文件每轮写入 Cache Write，是最大的固定成本来源。上周实战案例：5 个文件精简后每轮节省 3,679 tok，固定成本↓79%，万轮节省 ≈$138。

## 触发词

**瘦身审计：**
- 「帮我瘦身系统配置文件」
- 「审计 bootstrap 文件」
- 「context audit」
- 「系统文件太大了」
- 「配置文件占太多 token」

**效果验证（测试模式）：**
- 「跑一下 context-slim 的测试」
- 「验证 skill 效果」
- 「context-slim test」
- 「run test」

## SOP

详见 `docs/sop.md`。三个阶段：

- **Phase 0（自动）**：运行 `scripts/audit.py` 采集数据，读取 USER.md 建立用户场景基线，读取各配置文件全文和 `docs/techniques.md`
- **Phase 1（输出审计报告）**：逐文件分析，输出优先级表和冗余块清单，等用户确认
- **Phase 2（等「执行」）**：备份 → 修改 → 写变更记录
- **Phase T（测试模式）**：说出测试触发词后执行，运行 `bash tests/run_test.sh`（在工作区根目录），输出通过/失败摘要，不影响真实配置文件

## 文件目录

```
<工作区根>/
├── SKILL.md              # 本文件，入口
├── scripts/
│   └── audit.py          # token 计数 + 文件元数据采集（不做内容分析）
├── docs/
│   ├── sop.md            # 三阶段 SOP 步骤文档
│   └── techniques.md   # 审计视角 + 案例
└── tests/                # 效果验证（mock 与 run_test.sh）
```

## 注意事项

1. **Phase 0 自身成本**：读取所有文件约消耗 ~3,000 tok，属正常开销，提前告知用户
2. **凭据保护**：只保护 `credential_lines[]`（`likely_credential=true`）里的行；`credential_lines_noise[]` 是低置信度误报，正常处理
3. **MEMORY.md 特殊处理**：历史事件记录不动，只删与 SOUL.md 语义重复的行为规范类内容
4. **备份强制**：Phase 2 第一步必须调用 `scripts/backup.sh`，看到 `BACKUP_OK` 才继续，`BACKUP_FAILED` 则立即中止
5. **执行授权**：Phase 1 报告输出后，必须等用户明确说「执行」才进入 Phase 2；Phase 1 末尾必须显式输出授权提示
6. **审计范围**：默认审计列表见 `scripts/audit.py` 的 `DEFAULT_FILES`，可通过工作区根目录 `config.yaml`（若存在）或 `skills/context-slim/config.yaml`（兼容旧布局）的 `files` 字段覆盖
7. **USER.md 前置校验**：audit.py 启动时自动校验 USER.md，不存在或内容过少时 exit(1) 并中止 Phase 0，需先补充 USER.md
8. **PyYAML 依赖（可选）**：config.yaml 自定义文件列表需要 PyYAML（`pip install pyyaml`），未安装则自动回退到默认列表，stderr 有警告
9. **WORKSPACE 路径**：默认 `~/.openclaw/workspace`，可通过环境变量 `OPENCLAW_WORKSPACE` 覆盖（如 `export OPENCLAW_WORKSPACE=/custom/path`）
10. **节省 tok 均为估算**：中文文件误差 ±25%，英文 ±15%，实际以 Phase 2 执行后重跑 audit.py 为准

## 可配置项（config.yaml，可选）

```yaml
# 工作区根目录 config.yaml（不存在则用 audit.py 内建默认列表）
files:
  - MEMORY.md
  - SOUL.md
  - TOOLS.md
  - AGENTS.md
  - USER.md
  - IDENTITY.md
  - HEARTBEAT.md
```

# MEMORY.md - 我的长期记忆（mock 测试版）

## 用户速览
数据库内核方向工程师，专注关系型数据库与内部运维平台。
风格要求：正直敢说不谄媚，先出方案再执行，直接精准不废话。

## 代码仓库约定
涉及代码开发任务时：
1. 先检查 workspace 下是否已有对应仓库，避免重复 clone
2. clone 新仓库必须放到持久化目录，防止被清理后续复用
3. 已知持久仓库：示例内核项目（`workspace/example-kernel`，永远不清理）

## 踩过的坑
- 任务边界不清时擅自扩展范围——没有「执行」绝对不动
- config.patch 触发热重载时子 Agent announce 可能丢失

## 报告生成设计准则

HTML 报告必须由 AI 凭完整上下文生成，禁止用 Python 字符串拼接 HTML 或 Jinja 模板渲染。
脚本职责：读数据 → 构造 prompt → 调 LLM → 写文件 → 上传 CDN，不写任何 HTML。
风格基准：#0d0f14 背景、#13161f 卡片、#6366f1 强调色、14px 圆角、fadeUp 动画。

## SKILL.md 行数规范

SKILL.md 超过 150 行，或出现具体字段名/SQL/HTML 片段时必须拆分。
规范细节、字段映射、报告结构全部下沉到 `docs/` 或 `references/` 独立文件。
违反 = SKILL.md 继续膨胀，导致上下文爆炸。

## OKR 2026 Q1

### 目标 1：数据库运维平台稳定性提升
- KR1：MySQL 慢查询告警 P99 延迟降低 30%
- KR2：主从延迟 > 10s 告警数量减少 50%
- KR3：Binlog 积压告警 MTTR < 30 分钟

### 目标 2：内核分支迭代
- KR1：完成 3 个内核 Feature 的代码 Review 和合并
- KR2：输出 2 篇技术设计文档
- KR3：内核 Bug 修复 SLA < 48 小时

### 目标 3：AI Skill 建设
- KR1：发布 3 个团队内可用的 AgentSkill
- KR2：context-slim skill 通过完整测试
- KR3：每周借助本助手完成 ≥ 5 个技术任务

## 词汇表 / 术语对照

| 术语 | 含义 |
|------|------|
| CW | Cache Write，Anthropic 的缓存写入计费项 |
| CR | Cache Read，缓存读取，比 CW 便宜 75% |
| Bootstrap 文件 | 每轮必须加载的系统配置文件（MEMORY.md 等） |
| memoryres/ | 冷存储层，按需加载不占常驻上下文 |
| severity | audit.py 的评级：High / Medium / Low |
| DB-Ops | 内部数据库运维与管控平台（示例名） |
| ExampleKernel | 基于上游 MySQL 的定制内核分支（示例名） |
| MTTR | Mean Time To Recovery，平均恢复时间 |

<!-- _test_hints
报告生成设计准则 → 单一职责违反（行为规范混入记忆文件）→ 移到 SOUL.md
SKILL.md 行数规范 → 单一职责违反（行为规范混入记忆文件）→ 移到 SOUL.md
OKR 2026 Q1 → 视角六冷存储候选（低频引用）→ 迁移到 memoryres/okr.md
词汇表 / 术语对照 → 视角六冷存储候选（低频引用）→ 迁移到 memoryres/glossary.md
-->

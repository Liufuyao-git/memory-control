# memory-control

一个用于审计系统配置文件上下文体积的 skill 项目。

它通过 `scripts/audit.py` 统计 token、标记疑似凭据位置，并配合 `docs/` 中的 SOP 与技巧文档，帮助 AI 在修改前先完成审计，再按授权执行瘦身。

## 适用场景

- 审计 `MEMORY.md`、`SOUL.md`、`TOOLS.md`、`AGENTS.md` 等系统文件
- 识别冗余内容、重复规则、低频配置与高成本上下文
- 在修改前先生成建议，避免直接改动真实配置

## 目录

```text
.
├── SKILL.md              # skill 入口说明
├── USER.md               # 用户场景基线示例
├── docs/
│   ├── sop.md            # 审计/执行流程
│   └── techniques.md     # 审计技巧与案例
├── scripts/
│   └── audit.py          # token 审计脚本
└── tests/
    ├── run_test.sh       # 测试入口
    ├── config.yaml       # 测试配置
    └── mock_*.md         # mock 数据
```

## 快速开始

```bash
python scripts/audit.py
```

如需指定工作区根目录：

```bash
export OPENCLAW_WORKSPACE=/your/workspace
python scripts/audit.py
```

如需使用测试配置：

```bash
python scripts/audit.py --config tests/config.yaml
```

## 运行测试

```bash
bash tests/run_test.sh
```

## 说明

- 默认审计文件列表内置在 `scripts/audit.py`
- `config.yaml` 可覆盖审计文件列表（需安装 `PyYAML`）
- 测试使用 `tests/mock_*.md`，不会改动真实系统文件

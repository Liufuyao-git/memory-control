---
read_when:
  - 会话启动
summary: 工具和环境配置备注（mock 测试版）
---

# TOOLS.md - 本地备注（mock）

## 全局必需配置（保留）

- workspace: `/home/node/.openclaw/workspace`
- 登录态存于 `{workspace}/.session-store`（示例路径）
- SSO token 路径：`/home/node/.token/sso_token.json`
- GitLab base: `https://gitlab.example.com`
- Personal Access Token: `MOCK_TOKEN_abc123xyz`
- 用法: `curl -H "PRIVATE-TOKEN: MOCK_TOKEN_abc123xyz" https://gitlab.example.com/api/v4/...`

## 数据库平台 API 调用规范

API 基础地址：`https://dms-api.example.com/api/v1`
鉴权方式：请求头加 `X-SSO-Token: <token>`，token 从 `/home/node/.token/sso_token.json` 读取。

常用接口：
- `GET /cluster/list` — 获取集群列表，参数 `type=mysql|redis|cache`
- `GET /cluster/{name}/metrics` — 获取集群监控指标，参数 `metric=cpu|qps|latency`
- `GET /cluster/{name}/slow-sql` — 获取慢查询列表，参数 `start_time` / `end_time`
- `POST /ticket/create` — 创建工单，body 见各工单类型文档
- `GET /ticket/{id}/status` — 查询工单状态

返回格式统一为 `{ "code": 0, "data": {...}, "msg": "ok" }`，code 非 0 时抛错。

限流策略：每个 API 1000 QPS，超过会返回 429，需要指数退避重试。

## 消息服务发送规范

消息发送端点：`https://messenger.example.com/api/open/message/send`
鉴权：`Authorization: Bearer <access_token>`，token 从 `~/.token/messenger_token.json` 读取。

消息类型：
- `text`：纯文本，`content` 字段传字符串
- `markdown`：富文本，支持标题/列表/代码块
- `card`：卡片消息，需要提供 `card_id` 和 `variables`
- `file`：文件消息，先调用上传接口获取 `file_key`，再发送

群聊发送：`chat_id` 传群 ID；私聊发送：`user_id` 传用户 ID，二选一。
消息长度限制：text ≤ 4096 字符，markdown ≤ 8192 字符。
撤回消息：`DELETE /api/open/message/{message_id}`，仅支持 24 小时内的消息。

## CDN 上传规范

CDN 上传使用 `scripts/upload_to_cdn.py`，内部调用 Node 脚本完成实际上传。
固定 `appName=demo-static`，每次生成随机路径 `demo-static/随机串`，不会覆盖历史文件。
文本文件自动带 `charset=utf-8`，避免浏览器乱码。
线上环境：不加参数；内网环境：加 `--internal`。
上传前必须运行 `pnpm install` 安装依赖。

## 文档平台创建规范

创建文档 API：`POST https://docs-api.example.com/cv/api/openapi/codebase/doc/write`
必填字段：`content`（markdown 字符串）、`parentShortcutId`（父文档 ID）、`accessToken`。
默认父文档 ID：`4c6d8e61c16e518e00f3962160e71a29`（「代码 review」文档，示例 ID）。
注意：一次只能创建一个文档，不要循环调用；返回 `docUrl` 即可访问链接。

<!-- _test_hints
数据库平台 API 调用规范 → 视角二（Skill 专属规范，非全局必需）→ 移到 db-monitor SKILL.md
消息服务发送规范 → 视角二（Skill 专属规范，非全局必需）→ 移到 messenger SKILL.md
CDN 上传规范 → 视角二（Skill 专属规范，非全局必需）→ 移到 cdn-upload SKILL.md
文档平台创建规范 → 视角二（Skill 专属规范，非全局必需）→ 移到 doc-platform SKILL.md
-->

# OpenClaw Agent REST API 文档

> **基础 URL:** `http://<host>:5180/api`
> **局域网可访问:** 监听 `0.0.0.0:5180`

---

## 1. GET /api/agents

列出所有已配置的 Agent。

### 请求

```
GET /api/agents
```

无请求参数。

### 请求示例 (curl)

```bash
# 列出所有 Agent
curl http://localhost:5180/api/agents

# 从局域网其他机器访问
curl http://192.168.3.161:5180/api/agents
```

### 响应

**成功 (200)**

```json
{
  "success": true,
  "data": [
    {
      "id": "main",
      "identity": {
        "name": "经理",
        "emoji": "🧊",
        "theme": "manager"
      },
      "workspace": "/home/moston/.openclaw/workspace",
      "agentDir": "/home/moston/.openclaw/agents/main/agent",
      "model": "minimax/MiniMax-M2-7",
      "routing": "default"
    }
  ]
}
```

**失败 (500)**

```json
{
  "success": false,
  "error": "Command failed: ...",
  "output": ""
}
```

---

## 2. POST /api/agents

添加新 Agent 或更新已有 Agent。

### 请求

```
POST /api/agents
Content-Type: application/json
```

### 请求参数 (JSON Body)

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | ✅ | Agent 名字（用于生成 ID） |
| `emoji` | string | ❌ | 表情符号，默认 🤖 |
| `role` | string | ❌ | 职位/角色描述 |
| `vibe` | string | ❌ | 风格/氛围描述 |
| `specialties` | string | ❌ | 专长（逗号分隔或列表） |
| `model` | string | ❌ | 模型 ID |
| `bind` | string/array | ❌ | 渠道绑定，如 `feishu` |
| `workspace` | string | ❌ | 自定义工作目录路径 |

### 请求示例 (curl)

```bash
# 添加前端工程师 Agent
curl -X POST http://localhost:5180/api/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "前端工程师",
    "emoji": "🧑‍💻",
    "role": "前端开发专家",
    "vibe": "高效、专业、注重细节",
    "specialties": "Vue3, React, TypeScript, CSS动画, 响应式设计"
  }'

# 添加时指定模型
curl -X POST http://localhost:5180/api/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Python后端",
    "emoji": "🐍",
    "role": "后端工程师",
    "specialties": "Python, FastAPI, PostgreSQL, Redis, Docker",
    "model": "minimax/MiniMax-M2-7"
  }'

# 添加时绑定渠道
curl -X POST http://localhost:5180/api/agents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "飞书助手",
    "emoji": "📮",
    "bind": "feishu"
  }'
```

### 响应

**成功 (200)**

```json
{
  "success": true,
  "message": "Agent '前端工程师' created",
  "data": {
    "id": "前端工程师",
    "name": "前端工程师",
    "emoji": "🧑‍💻",
    "role": "前端开发专家",
    "specialties": "Vue3, React, TypeScript, CSS动画, 响应式设计",
    "workspace": "/home/moston/.openclaw/workspace/agent-api/data/前端工程师/workspace",
    "identityPath": "/home/moston/.openclaw/workspace/agent-api/data/前端工程师/workspace/IDENTITY.md"
  }
}
```

**失败 (400/500)**

```json
{
  "success": false,
  "error": "Field \"name\" is required"
}
```

---

## 3. GET /api/agents/:id

查看单个 Agent 详情。

### 请求

```
GET /api/agents/:id
```

### 路径参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | string | Agent ID（如 `main`、`前端工程师`） |

### 请求示例 (curl)

```bash
# 查看 main Agent
curl http://localhost:5180/api/agents/main

# 查看指定 Agent
curl http://localhost:5180/api/agents/前端工程师
```

### 响应

**成功 (200)**

```json
{
  "success": true,
  "data": {
    "id": "main",
    "identity": {
      "name": "经理",
      "emoji": "🧊",
      "theme": "manager"
    },
    "workspace": "/home/moston/.openclaw/workspace",
    "model": "minimax/MiniMax-M2-7"
  }
}
```

**失败 (404)**

```json
{
  "success": false,
  "error": "Agent 'xxx' not found"
}
```

---

## 4. DELETE /api/agents/:id

删除指定 Agent。

### 请求

```
DELETE /api/agents/:id[?force=true]
```

### 路径参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | string | Agent ID |

### 查询参数

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `force` | boolean | false | `true` 跳过确认直接删除 |

### 请求示例 (curl)

```bash
# 删除 Agent（需确认）
curl -X DELETE http://localhost:5180/api/agents/前端工程师

# 强制删除（跳过确认）
curl -X DELETE "http://localhost:5180/api/agents/前端工程师?force=true"

# 删除并查看输出
curl -v -X DELETE "http://localhost:5180/api/agents/前端工程师?force=true"
```

### 响应

**成功 (200)**

```json
{
  "success": true,
  "message": "Agent '前端工程师' deleted",
  "data": {
    "deleted": true
  }
}
```

**失败 (404)**

```json
{
  "success": false,
  "error": "Agent 'xxx' not found"
}
```

**失败 (400 - 需确认)**

```json
{
  "success": false,
  "error": "Confirmation required, use ?force=true to skip",
  "output": "..."
}
```

---

## 5. GET /api/health

健康检查接口。

### 请求示例 (curl)

```bash
curl http://localhost:5180/api/health
```

### 响应

```json
{
  "status": "ok",
  "timestamp": "2026-03-22T21:30:00.000Z"
}
```

---

## 错误响应格式

所有接口错误响应统一格式：

```json
{
  "success": false,
  "error": "错误描述信息",
  "output": "（可选）CLI 原始输出"
}
```

---

## HTTP 状态码

| 状态码 | 说明 |
|--------|------|
| 200 | 成功 |
| 400 | 请求参数错误（如缺少 name 字段） |
| 404 | Agent 不存在 |
| 500 | 服务器/CLI 执行错误 |

---

## Web 界面

启动后直接访问根路径 `/` 可打开 Web 管理界面（HTML），无需任何认证，适合局域网内浏览器直接管理 Agent。

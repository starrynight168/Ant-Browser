const docsApiDetails = <String, String>{
  'api-profiles-launch': r'''
## GET /api/profiles — 实例列表

列出当前全部实例。

读取当前实例目录中的全部实例配置，适合做实例选择器或管理后台列表。

### 请求参数

无参数。

### 请求示例

```bash
curl http://127.0.0.1:19900/api/profiles \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回实例列表。
- 503：实例目录当前不可用。

### 成功响应示例

```json
{
  "ok": true,
  "count": 1,
  "items": [
    {
      "profileId": "550e8400-e29b-41d4-a716-446655440000",
      "profileName": "buyer-001",
      "launchCode": "BUYER_001",
      "keywords": ["buyer-001"],
      "tags": ["电商"],
      "proxyId": "proxy-us",
      "running": false,
      "debugReady": false
    }
  ]
}
```

## POST /api/profiles — 创建实例

创建一个新实例，可选创建后立即启动。

写入实例配置，必要时同时申请 launchCode，并支持通过 autoLaunch 在创建后直接启动浏览器。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profile | Body | object | 是 | 实例配置主体。 |
| launchCode | Body | string | 否 | 指定实例 launchCode。 |
| autoLaunch | Body | boolean | 否 | 是否在创建后立即启动。 |
| start | Body | object | 否 | 仅本次自动启动时附加的启动参数。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/profiles \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "profile": {
      "profileName": "buyer-001",
      "proxyId": "proxy-us",
      "keywords": ["buyer-001"],
      "tags": ["电商"]
    },
    "launchCode": "BUYER_001"
  }'
```

### 状态码

- 201：实例创建成功。
- 400：请求体非法或 profile 缺失。
- 409：launchCode 冲突或实例数超限。

### 成功响应示例

```json
{
  "ok": true,
  "created": true,
  "updated": false,
  "launched": false,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "profile": {
    "profileId": "550e8400-e29b-41d4-a716-446655440000",
    "profileName": "buyer-001",
    "keywords": ["buyer-001"],
    "proxyId": "proxy-us"
  }
}
```

### 注意事项

- autoLaunch=true 时，响应会附带启动结果字段。
- profile.proxyId 与 profile.proxyConfig 同时传时，优先使用 proxyId 对应的代理池节点。
- 若 proxyId 无效：提供 proxyConfig 则按自定义代理保存；未提供 proxyConfig 则返回 400。

## GET /api/profiles/{profileId} — 单个实例

查询单个实例配置。

读取指定实例的完整配置快照，适合进入实例详情页或编辑页前预加载数据。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profileId | Path | string | 是 | 实例 ID。 |

### 请求示例

```bash
curl http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000 \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回实例详情。
- 404：实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "profile": {
    "profileId": "550e8400-e29b-41d4-a716-446655440000",
    "profileName": "buyer-001",
    "keywords": ["buyer-001"],
    "tags": ["电商"],
    "proxyId": "proxy-us"
  }
}
```

## PUT /api/profiles/{profileId} — 更新实例

更新指定实例配置。

用整份 profile 配置覆盖更新实例，可选顺带更新 launchCode，并支持更新后立即启动。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profileId | Path | string | 是 | 实例 ID。 |
| profile | Body | object | 是 | 更新后的实例配置。 |
| launchCode | Body | string | 否 | 需要覆盖时传新的 launchCode。 |
| autoLaunch | Body | boolean | 否 | 更新后是否直接启动。 |

### 请求示例

```bash
curl -X PUT http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000 \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "profile": {
      "profileName": "buyer-001-updated",
      "proxyId": "proxy-us",
      "keywords": ["buyer-001", "checkout"]
    }
  }'
```

### 状态码

- 200：更新成功。
- 400：请求体非法。
- 404：实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "created": false,
  "updated": true,
  "launched": false,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001-updated",
  "launchCode": "BUYER_001"
}
```

### 注意事项

- 整份更新，不是 patch。
- profile.proxyId 与 profile.proxyConfig 同时传时，优先使用 proxyId 对应的代理池节点。
- 若 proxyId 无效：提供 proxyConfig 则按自定义代理保存；未提供 proxyConfig 则返回 400。

## DELETE /api/profiles/{profileId} — 删除实例

删除一个未运行中的实例。

删除实例配置并移除关联 launchCode；运行中的实例会被直接拒绝删除。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profileId | Path | string | 是 | 实例 ID。 |

### 请求示例

```bash
curl -X DELETE http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000 \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：删除成功。
- 404：实例不存在。
- 409：实例仍在运行，不能直接删除。

### 成功响应示例

```json
{
  "ok": true,
  "deleted": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001"
}
```

### 注意事项

- 运行中的实例先 stop，再 delete。

## GET /api/profiles/{profileId}/status — 实例状态

查询单个实例的实时运行态。

返回运行中、debugReady、cdpUrl 等运行态字段，适合精确观察单个实例当前状态。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profileId | Path | string | 是 | 实例 ID。 |

### 请求示例

```bash
curl http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000/status \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回实例运行态。
- 404：实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "running": true,
  "debugPort": 9333,
  "debugReady": true,
  "active": true,
  "cdpUrl": "http://127.0.0.1:19876",
  "directDebugUrl": "http://127.0.0.1:9333"
}
```

## POST /api/profiles/{profileId}/stop — 停止实例

精确停止一个指定实例。

按 profileId 停止实例，适合任务完成后的精确回收。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| profileId | Path | string | 是 | 实例 ID。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000/stop \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：停止成功。
- 404：实例不存在。
- 503：当前环境不支持运行态控制。

### 成功响应示例

```json
{
  "ok": true,
  "stopped": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "running": false,
  "debugReady": false,
  "active": false
}
```

## GET /api/launch/{code} — 按 Code 启动

按唯一 launchCode 启动实例。

最短路径的启动接口，适合外部系统已经拿到唯一 launchCode 的场景。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| code | Path | string | 是 | 实例 launchCode。 |

### 请求示例

```bash
curl http://127.0.0.1:19900/api/launch/BUYER_001 \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：启动成功。
- 404：launchCode 不存在。

### 成功响应示例

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "pid": 10240,
  "debugPort": 9333,
  "debugReady": true,
  "cdpPort": 19876,
  "cdpUrl": "http://127.0.0.1:19876"
}
```

## POST /api/launch — 按 selector 启动

按 selector 或兼容顶层字段启动实例。

更灵活的启动入口，支持 selector、兼容顶层选择字段、launchArgs、startUrls 和 skipDefaultStartUrls 等临时参数。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| selector | Body | object | 否 | 目标实例选择条件；新接入推荐使用。 |
| code | Body | string | 否 | 兼容写法：等价于 selector.code。 |
| profileId | Body | string | 否 | 兼容写法：等价于 selector.profileId。 |
| profileName | Body | string | 否 | 兼容写法：等价于 selector.profileName。 |
| keyword / keywords | Body | string / string[] | 否 | 兼容写法：等价于 selector.keyword / selector.keywords。 |
| tag / tags | Body | string / string[] | 否 | 兼容写法：等价于 selector.tag / selector.tags。 |
| groupId | Body | string | 否 | 兼容写法：等价于 selector.groupId。 |
| matchMode | Body | unique \| first \| all | 否 | 兼容写法：等价于 selector.matchMode。 |
| launchArgs | Body | string[] | 否 | 本次启动的临时附加参数。 |
| startUrls | Body | string[] | 否 | 本次启动后额外打开的网址。 |
| skipDefaultStartUrls | Body | boolean | 否 | 是否跳过实例默认启动 URL。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/launch \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "selector": {
      "keyword": "checkout",
      "tags": ["电商", "北美"],
      "matchMode": "unique"
    },
    "skipDefaultStartUrls": true
  }'
```

### 状态码

- 200：启动成功。
- 400：selector 缺失或请求体非法。
- 409：selector 命中多个实例。

### 成功响应示例

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "debugReady": true,
  "cdpUrl": "http://127.0.0.1:19876"
}
```

### 注意事项

- selector 为空且没有任何兼容顶层选择字段时返回 400。
- matchMode=all 只在这个接口可用。
- proxyId / proxyConfig 只影响本次启动，不覆盖实例原代理。
''',
  'api-runtime': r'''
## GET /api/runtime/active — 当前活动实例

查看当前统一 CDP 入口挂着哪个实例。

当外部系统只知道 LaunchServer 端口、不知道当前 active target 时，先查这个接口最直接。

### 请求参数

无参数。

### 请求示例

```bash
curl http://127.0.0.1:19900/api/runtime/active \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回当前 active target 状态。

### 成功响应示例

```json
{
  "ok": true,
  "active": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "profileName": "buyer-001",
  "launchCode": "BUYER_001",
  "running": true,
  "debugReady": true,
  "cdpUrl": "http://127.0.0.1:19876",
  "directDebugUrl": "http://127.0.0.1:9333"
}
```

### 注意事项

- active=false 表示当前没有活动实例。

## POST /api/runtime/session — 准备可接管会话

准备一个可 attach 的运行时会话。

按 selector 命中实例，必要时自动启动，并在给定超时时间内等待 debugReady=true。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| selector | Body | object | 否 | 目标实例选择条件；新接入推荐使用。 |
| code | Body | string | 否 | 兼容写法：等价于 selector.code。 |
| profileId | Body | string | 否 | 兼容写法：等价于 selector.profileId。 |
| profileName | Body | string | 否 | 兼容写法：等价于 selector.profileName。 |
| keyword / keywords | Body | string / string[] | 否 | 兼容写法：等价于 selector.keyword / selector.keywords。 |
| tag / tags | Body | string / string[] | 否 | 兼容写法：等价于 selector.tag / selector.tags。 |
| groupId | Body | string | 否 | 兼容写法：等价于 selector.groupId。 |
| matchMode | Body | unique \| first | 否 | 兼容写法：等价于 selector.matchMode。 |
| timeoutMs | Body | integer | 否 | 等待 debugReady 的超时时间。 |
| startUrls | Body | string[] | 否 | 本次启动时额外打开的网址。 |
| skipDefaultStartUrls | Body | boolean | 否 | 是否跳过实例默认启动 URL。 |
| launchArgs | Body | string[] | 否 | 本次启动时临时附加的启动参数。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/session \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "selector": { "code": "BUYER_001" },
    "timeoutMs": 45000,
    "skipDefaultStartUrls": true
  }'
```

### 状态码

- 200：实例已 ready，可直接 attach。
- 202：实例已处理但暂未 ready，可稍后重试。
- 400：selector 缺失或 matchMode 非法。
- 404：目标实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "ready": true,
  "waitTimedOut": false,
  "retryable": false,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "running": true,
  "debugReady": true,
  "active": true,
  "cdpUrl": "http://127.0.0.1:19876",
  "directDebugUrl": "http://127.0.0.1:9333",
  "timeoutMs": 45000
}
```

### 注意事项

- selector 为空且没有任何兼容顶层选择字段时返回 400。
- 200 表示 ready，可直接接管。
- 202 表示未 ready，需要重试。

## POST /api/runtime/status — 按 selector 查状态

按 selector 查询实例当前运行态。

不启动新实例，不等待 ready，只看当前 selector 命中的实例状态。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| selector | Body | object | 否 | 目标实例选择条件；新接入推荐使用。 |
| code / profileId / profileName | Body | string | 否 | 兼容顶层选择字段。 |
| keyword / keywords | Body | string / string[] | 否 | 兼容顶层选择字段。 |
| tag / tags / groupId | Body | string / string[] | 否 | 兼容顶层选择字段。 |
| matchMode | Body | unique \| first | 否 | 运行态控制不支持 all。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/status \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "selector": { "keyword": "checkout", "matchMode": "first" }
  }'
```

### 状态码

- 200：返回运行态。
- 400：selector 缺失或 matchMode 非法。
- 404：目标实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "running": true,
  "debugReady": false,
  "active": false,
  "cdpUrl": ""
}
```

### 注意事项

- 不会启动实例。
- selector 为空且没有任何兼容顶层选择字段时返回 400。

## POST /api/runtime/stop — 按 selector 停止

按 selector 停止实例。

和 runtime/status 一样使用 selector，但动作改为停止实例，适合编排侧做统一回收。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| selector | Body | object | 否 | 目标实例选择条件；新接入推荐使用。 |
| code / profileId / profileName | Body | string | 否 | 兼容顶层选择字段。 |
| keyword / keywords | Body | string / string[] | 否 | 兼容顶层选择字段。 |
| tag / tags / groupId | Body | string / string[] | 否 | 兼容顶层选择字段。 |
| matchMode | Body | unique \| first | 否 | 运行态控制不支持 all。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/stop \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "selector": { "code": "BUYER_001" }
  }'
```

### 状态码

- 200：停止成功。
- 400：selector 缺失或 matchMode 非法。
- 404：目标实例不存在。

### 成功响应示例

```json
{
  "ok": true,
  "stopped": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "running": false,
  "debugReady": false,
  "active": false
}
```

### 注意事项

- selector 为空且没有任何兼容顶层选择字段时返回 400。
- 不支持 matchMode=all。

## GET /json/version — CDP 版本信息

读取统一 CDP 入口的版本信息。

这个接口透传当前 active target 的 CDP 版本信息，适合 attach 前探测调试入口是否可用。

### 请求参数

无参数。

### 请求示例

```bash
curl http://127.0.0.1:19900/json/version \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回当前 active target 的版本信息。
- 503：当前没有可透传的 active target。

### 成功响应示例

```json
{
  "Browser": "Chrome/<version>",
  "Protocol-Version": "1.3",
  "User-Agent": "Mozilla/5.0",
  "webSocketDebuggerUrl": "ws://127.0.0.1:19876/devtools/browser/active"
}
```

### 注意事项

- 无 active target 时返回 503。

## GET /json/list — CDP Target 列表

读取统一 CDP 入口当前暴露的 target 列表。

给 Playwright、Puppeteer 或诊断工具查看当前活动 target 时使用。

### 请求参数

无参数。

### 请求示例

```bash
curl http://127.0.0.1:19900/json/list \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回当前活动实例的 target 列表。
- 503：当前没有可透传的 active target。

### 成功响应示例

```json
[
  {
    "id": "page-1",
    "type": "page",
    "title": "Checkout",
    "url": "https://example.com/checkout",
    "webSocketDebuggerUrl": "ws://127.0.0.1:19876/devtools/page/page-1"
  }
]
```

### 注意事项

- 无 active target 时返回 503。

## WS /devtools/... — CDP WebSocket

通过统一 WebSocket 入口接管当前活动实例。

实际 attach 时使用的就是这个 WebSocket 入口。外部工具通常先拿 /json/version 或 /json/list，再连对应 websocketDebuggerUrl。

### 请求参数

无参数。

### 请求示例

```javascript
const browser = await chromium.connectOverCDP("ws://127.0.0.1:19900");
// 或按 /json/list 返回的 webSocketDebuggerUrl 连接具体 page target
```

### 状态码

- 101：WebSocket 升级成功。
- 503：当前没有可透传的 active target。

### 成功响应示例

```text
WebSocket 握手成功后进入标准 Chrome DevTools Protocol 消息流。
```

### 注意事项

- 先调 runtime/session，再连 WS。
''',
  'api-automation': r'''
## GET /api/automation/scripts — 脚本列表

查询可执行脚本清单。

返回脚本元数据，用于拿 scriptId、默认 selector / params 和脚本类型。

### 请求参数

无参数。

### 请求示例

```bash
curl http://127.0.0.1:19900/api/automation/scripts \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回脚本列表。
- 503：自动化脚本能力未启用。

### 成功响应示例

```json
{
  "ok": true,
  "status": "success",
  "data": {
    "count": 1,
    "items": [
      {
        "id": "news-query-txt",
        "name": "查询新闻并写 TXT",
        "type": "playwright-cdp",
        "status": "ready",
        "entryFile": "index.cjs",
        "selector": { "code": "BUYER_001" },
        "params": { "keyword": "OpenAI", "limit": 10 }
      }
    ]
  }
}
```

### 注意事项

- 不返回 scriptText。

## GET /api/automation/scripts/{scriptId} — 脚本详情

按 scriptId 查询单个脚本详情。

标准单资源读取接口，用于从脚本列表进入某个脚本时补充其来源和包格式等元数据。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| scriptId | Path | string | 是 | 脚本唯一 ID。 |

### 请求示例

```bash
curl http://127.0.0.1:19900/api/automation/scripts/news-query-txt \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回脚本详情。
- 404：脚本不存在。
- 503：自动化脚本能力未启用。

### 成功响应示例

```json
{
  "ok": true,
  "status": "success",
  "data": {
    "item": {
      "id": "news-query-txt",
      "name": "查询新闻并写 TXT",
      "type": "playwright-cdp",
      "status": "ready",
      "entryFile": "index.cjs",
      "selector": { "code": "BUYER_001" },
      "params": { "keyword": "OpenAI", "limit": 10 },
      "packageFormat": "ant-automation-script",
      "manifestVersion": 1,
      "source": {
        "type": "git",
        "uri": "https://example.com/repo.git",
        "ref": "main"
      }
    }
  }
}
```

### 注意事项

- 不返回 scriptText。

## POST /api/automation/scripts/run — 执行脚本

按 scriptId 执行脚本。

外部调用方只需传入脚本 ID 和对象形态的 selector / params。推荐优先传 selector.code；如果脚本已在 UI 中绑定目标实例，也可以只传 scriptId 直接执行。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| scriptId | Body | string | 是 | 要执行的脚本 ID。 |
| selector | Body | object | 否 | 覆盖脚本默认 selector。 |
| params | Body | object | 否 | 覆盖脚本默认 params。 |
| useScriptSelector | Body | boolean | 否 | 显式指定是否沿用脚本默认 selector。 |
| useScriptParams | Body | boolean | 否 | 显式指定是否沿用脚本默认 params。 |
| timeoutMs | Body | integer | 否 | 本次脚本执行超时时间，范围 1000 到 1800000。 |

### 请求示例

```bash
curl -X POST http://127.0.0.1:19900/api/automation/scripts/run \
  -H "Content-Type: application/json" \
  -H "X-Ant-Api-Key: <your-api-key>" \
  -d '{
    "scriptId": "news-query-txt",
    "selector": { "code": "BUYER_001" },
    "params": { "keyword": "OpenAI", "limit": 10 }
  }'
```

### 状态码

- 200：执行成功。
- 400：scriptId 缺失、selector / params 不是对象，或 timeoutMs 超出范围。
- 500：脚本执行失败。

### 成功响应示例

```json
{
  "ok": true,
  "status": "success",
  "data": {
    "run": {
      "id": "run-1",
      "scriptId": "news-query-txt",
      "scriptName": "查询新闻并写 TXT",
      "scriptType": "playwright-cdp",
      "status": "success",
      "summary": "已抓取 10 条新闻并写入 TXT",
      "durationMs": 12034
    },
    "summary": "已抓取 10 条新闻并写入 TXT"
  }
}
```

### 注意事项

- selector / params 必须是 object。
- 不传时沿用脚本默认配置。

## GET /api/automation/scripts/runs?limit=20 — 运行记录

查询最近脚本运行记录。

返回最近 N 次脚本执行记录，适合调试、审计和任务结果回看。

### 请求参数

| 字段 | 位置 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| limit | Query | integer | 否 | 返回记录条数，默认 20，最小 1，最大 200。 |

### 请求示例

```bash
curl "http://127.0.0.1:19900/api/automation/scripts/runs?limit=20" \
  -H "X-Ant-Api-Key: <your-api-key>"
```

### 状态码

- 200：返回运行记录。
- 503：自动化脚本能力未启用。

### 成功响应示例

```json
{
  "ok": true,
  "status": "success",
  "data": {
    "count": 1,
    "limit": 20,
    "items": [
      {
        "id": "run-1",
        "scriptId": "news-query-txt",
        "status": "success",
        "summary": "已抓取 10 条新闻并写入 TXT",
        "durationMs": 12034
      }
    ]
  }
}
```
''',
};

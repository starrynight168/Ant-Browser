const docsContent = <String, String>{
  'tutorial-basic': r'''
# 使用教程

## 应用内路径

- 内核：`指纹浏览器 -> 内核管理 -> 下载内核 / 识别本地内核`
- 代理：`指纹浏览器 -> 代理池配置 -> 导入代理`
- 插件：`指纹浏览器 -> 插件包管理 -> 安装 / 导入插件`
- 实例：`指纹浏览器 -> 实例列表 -> 新建配置 -> 启动`
- 迁移：`实例列表 -> 导入实例 / 勾选实例 -> 导出`

## 最小上手顺序

1. 打开 `指纹浏览器 > 内核管理`
2. 准备一个可用内核
3. 打开 `指纹浏览器 > 代理池配置`，导入代理或确认直连
4. 需要固定插件时，打开 `指纹浏览器 > 插件包管理` 安装插件
5. 打开 `指纹浏览器 > 实例列表`，点 `新建配置`
6. 选择内核、代理、插件后保存并启动

## 实例迁移

- 批量导出：`实例列表 -> 勾选实例 -> 导出`
- 单个导出：`实例列表 -> 更多 -> 导出`
- 导入实例：`实例列表 -> 导入实例 -> 选择 ZIP`

- 导出前先停止实例，避免浏览器数据文件被占用
- 导出包包含实例配置和完整浏览器用户数据目录
- 导入时会生成新实例，不覆盖当前已有实例
- 代理只按名称适配本地同名代理，未匹配时自动清空代理

## 最小 HTTP 对接

只想启动实例，用 `POST /api/launch`；需要等待实例和 CDP 都可用，用 `POST /api/runtime/session`。

```bash
curl http://127.0.0.1:19900/api/health

curl -X POST http://127.0.0.1:19900/api/launch \
  -H "Content-Type: application/json" \
  -d '{
    "code": "BUYER_001",
    "skipDefaultStartUrls": true
  }'
```

## 返回里主要看这几个字段

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "debugReady": true,
  "cdpUrl": "http://127.0.0.1:19900"
}
```

## Playwright 接管

```javascript
import { chromium } from "playwright";

const res = await fetch("http://127.0.0.1:19900/api/launch", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    code: "BUYER_001",
    skipDefaultStartUrls: true
  })
});

const data = await res.json();
const browser = await chromium.connectOverCDP(data.cdpUrl);
```

需要稳定接管时，不要自己轮询，直接用 `POST /api/runtime/session`。
''',
  'tutorial-skill': r'''
# SKILL 使用说明

## 先准备好 3 个前提

1. Ant Browser 和 OpenClaw 在同一台机器上
2. Ant Browser 的 LaunchServer 可访问，默认是 `http://127.0.0.1:19900`
3. OpenClaw 已安装 `ant-chrome-openclaw` skill，并且已有指向 Ant Browser 的远程 CDP 浏览器配置

## 安装 Skill

如果你不知道项目根目录在哪，先点上面的 `打开根目录`。

### Windows

直接安装：

```powershell
pwsh -File skills/ant-chrome-openclaw/scripts/install_ant_chrome_openclaw.ps1 -SetDefaultProfile
```

如果没探测到 OpenClaw 路径，再用：

```powershell
pwsh -File skills/ant-chrome-openclaw/scripts/install_ant_chrome_openclaw.ps1 -TargetSkillsDir "C:\path\to\openclaw\skills" -ConfigFile "C:\path\to\openclaw\openclaw.json" -SetDefaultProfile
```

### Linux

直接安装：

```bash
bash skills/ant-chrome-openclaw/scripts/install_ant_chrome_openclaw.sh \
  --set-default-profile
```

如果没探测到 OpenClaw 路径，再用：

```bash
bash skills/ant-chrome-openclaw/scripts/install_ant_chrome_openclaw.sh \
  --target-skills-dir /path/to/openclaw/skills \
  --config-file /path/to/openclaw/openclaw.json \
  --set-default-profile
```

如果 Ant Browser 开了 API Key，安装时补上对应参数即可。

## 在对话里怎么触发

每次提问开头都明确写：

```text
使用 ant-chrome-openclaw skill。
```

然后直接写你的目标，不要只说“帮我打开浏览器”。

## 推荐提问模板

### 启动并接管

```text
使用 ant-chrome-openclaw skill。
先检查 LaunchServer。
如果实例 BUYER_001 没有运行，就启动它。
确认 debugReady=true 后接管浏览器，并打开 https://example.com
```

### 只接管当前活动实例

```text
使用 ant-chrome-openclaw skill。
先检查当前 active 实例。
如果当前活动实例已经是 BUYER_001，就直接接管，不要切换到别的实例。
```

### 按条件匹配实例

```text
使用 ant-chrome-openclaw skill。
按 keyword=buyer-001 查实例状态。
如果唯一命中，就接管。
如果多命中，不要自动切换，先告诉我。
```

### 停止实例

```text
使用 ant-chrome-openclaw skill。
停止 launchCode=BUYER_001 对应的实例。
```

## 稳定使用规则

- 先在 Ant Browser 前端里把实例、代理、标签和内核配置好
- 优先提供精确标识，推荐顺序是 `launchCode`、`profileId`、`profileName`
- 只有在 `debugReady=true` 且 `cdpUrl` 非空时才接管
- 如果 selector 命中多个实例，不要自动选，先返回结果给用户确认
- `browser stop` 只是断开 OpenClaw 接管，不等于关闭 Ant Browser 实例
- 当前统一 CDP 入口一次只指向一个活动实例，切换前先看 `GET /api/runtime/active`

## 最小排查顺序

```text
1. GET /api/health
2. GET /api/runtime/active
3. 按 code 或 selector 调 launch / runtime/session
4. 如果失败，再看 GET /api/launch/logs?limit=20
```
''',
  'tutorial-flow': r'''
# 操作流程

## 首次配置

```text
1. 内核管理：准备 Chrome 内核
2. 代理池配置：导入或录入代理
3. 插件包管理：安装插件，设置默认安装或指定实例
4. 实例列表：创建实例并选择内核、代理、分组
5. 启动实例：确认 debugReady 后再接管
6. 迁移实例：停止实例后导出 ZIP，新环境中导入为新实例
```

## 插件接入流程

```text
插件包管理 -> 输入商店链接 / 插件 ID -> 安装
插件包管理 -> 默认安装 / 设置实例 -> 按分组选择实例 -> 保存
实例列表 -> 单个实例 -> 插件 -> 手动设置本实例（可选）
```

## 分组限制怎么用

- 在实例列表或分组管理里先维护实例分组
- 在插件包管理里点插件卡片的 `设置实例`
- 弹窗会按分组展示实例，并显示每组已选数量
- 点 `选择本组` 可以快速让整组实例写入该插件
- 点 `取消本组` 可以快速让整组实例排除此插件

## 启动前检查

```text
1. 实例有可用内核
2. 代理可连通，或确认不需要代理
3. 必要插件已安装，并且该实例在插件限制范围内
4. 启动后 debugReady=true
```
''',
  'changelog-versions': r'''
# 更新日志

## 1.8.0 - 2026-09-03

- 备份渠道：支持本地、OpenList 和 S3（含兼容服务）三种备份位置。
- 备份范围：支持全量备份和按实例选择性备份；远程历史支持扫描、下载和恢复。
- OpenList 定时备份：支持每日执行时间、最近执行状态和失败反馈；实例仍在运行时跳过本次任务。
- 凭据保护：OpenList Token 和 S3 访问凭据仅保存到本地敏感配置，界面默认脱敏并支持按需显示。
- 恢复安全：增加备份清单校验、路径校验和解压限制，并按当前机器重新映射实例与外部内核路径。
- 代理连接栈：明确区分 xray + sing-box 组合栈与独立 mihomo 栈，完善代理运行时下载和连通性流程。
- 设置维护：新增系统设置重置，并增加定时备份配置保护。

## 1.7.0 - 2026-08-17

- 实例窗口标识：Windows 运行实例使用独立窗口图标，右上角显示 1-10 / A-Z 角标，窗口标题左侧同步显示运行码。
- 实例窗口标识：任务栏图标使用白色圆角指纹底图，数字角标使用系统字体抗锯齿渲染并放大，小图标提升到 32px 高清绘制。
- 应用图标：桌面快捷方式、应用窗口与侧边栏 Logo 统一使用白色背景、蓝色指纹线稿标识。
- 全局备份与恢复：重构全量备份流程，覆盖应用配置、数据库和浏览器数据，支持合并导入，并展示阶段进度、当前组件和导出日志。
- 备份安全校验：备份清单增加文件数量、大小和 SHA-256 校验，导入时校验归档路径、条目类型和解压限制，降低损坏或异常备份包的导入风险。
- 备份数据一致性：恢复 SQLite 时保留代理指定内核、实例代理绑定、内存限制、回收站状态等迁移字段，兼容旧版本缺失列；实例和内核路径按当前机器归一化，外部内核优先按稳定 coreId 映射。
- 维护失败保护：浏览器进程停止或初始化清理失败时中止导入/重置，不再把未完成的维护操作报告为成功。
- 通知中心：新增通知中心，支持按全部、未读、错误和警告筛选，可批量标记已读、清空通知，并从通知直接跳转到相关页面。
- 交互反馈：优化 Toast、Modal 和确认操作的进出场过渡，异步操作期间锁定重复提交，关闭应用时按动画完成后再执行最小化或退出。
- 生命周期稳定性：统一浏览器运行事件和应用退出流程，改善浏览器异常退出、停止状态、托盘操作和启动关闭阶段的状态反馈，避免退出期间继续发送运行事件。
- 退出诊断：新增应用生命周期日志、Wails 日志和 Windows 只读诊断监视器，在安装包中自动注册并在卸载时移除，用于记录进程退出、文件状态、进程树和相关日志。
- 代理兼容：修复 Clash 配置中出现 null 值时的导入解析失败问题。

## 1.6.0 - 2026-08-11

- 插件持久化：支持保存插件安装包、安装记录和实例插件配置，实例启动时自动恢复已配置插件。
- 插件迁移：实例备份导入后自动修复插件安装目录、安装包和运行备份路径。
- 指纹处理：跨平台画像使用宿主真实字体避免中日韩文字缺失，删除实例时同步清理指纹检测缓存。
- 窗口启动：保留配置的启动窗口尺寸，仅在超出桌面工作区时收缩。
- 设置与文档：优化启动服务端口保存按钮、应用内教程路径和 Launch API 使用说明。
- 开发资料：新增代理协议支持审计报告和 Automa 导入、读取、点击、循环及 JavaScript 导出示例。
- 应用版本升级到 1.6.0。

## 1.5.0 - 2026-07-25

- 代理增强：支持 HTTPS 代理桥接，完善代理导入、测速和连接可用性处理。
- 实例安全：增加实例删除数据审计，避免误删用户数据目录时缺少确认依据。
- 会话恢复：新增实例最近会话恢复配置，创建、复制、更新和启动流程保持一致。
- 启动服务：补充启动 API 服务端口设置，设置页可查看当前地址并保存偏好端口。
- 界面优化：精简代理池导入流程，新增代理池使用说明入口，减少页面信息堆叠。
- 应用版本升级到 1.5.0。

## 1.4.0 - 2026-07-15

- 指纹检测页默认中文，Linux / macOS 指纹环境自动切换英文，避免中文字体缺失导致方块字。
- 移除控制台栏目，启动页直接进入实例列表。
- 应用版本升级到 1.4.0。

## 1.3.0 - 2026-06-23

- 自动化增强：完善自动化脚本导入、运行、目标实例选择和执行记录管理。
- 插件管理：支持插件安装、导入、启停、删除、实例限制和单实例插件配置。
- VPN 优化：优化 Xray、sing-box、Mihomo 等连接栈的启动、测速、检测和预热能力。
- 实例迁移：支持实例导入导出，可将实例配置和完整浏览器用户数据目录打包迁移到新环境。
- 代理适配：实例导入时按代理名称匹配本地同名代理，匹配不到或同名不唯一时自动清空代理。
- 界面优化：优化实例列表、关键字展示、操作菜单和导入导出入口。

## 1.2.0 - 2026-05-09

- 接口调用：Launch API 补齐实例增删改查、按 code / selector 启动、runtime session / status / stop 和统一 CDP 入口。
- 自动化接口：脚本执行支持 selector / params 覆盖和 timeoutMs 超时控制，双实例 runtime 流程支持超时取消与错误返回。
- 代理池增强：新增链式代理导入、编辑和预览能力，支持 HTTP / SOCKS5 两层链路，并优化直连代理批量导入。
- 代理检测：新增测速目标、IP 健康检测目标和桥接启动超时配置，链式代理也可以参与测速与健康检测。
- 实例启动：代理异常时支持本次直连启动，不修改实例原有代理配置；默认代理池只保留直连节点。
- 书签能力：新增 IP 检测站点默认书签，支持设置启动时自动打开，并可同步到已有未运行实例。

## 1.1.0 - 2026-03-19

- Linux 支持：补齐 Linux 环境下的开发、打包、安装、启动与运行链路，并修复安装版启动与退出稳定性问题。
- macOS unsigned 内测：支持原生 macOS 主机打包 app / zip，用户状态目录迁移到 Application Support。
- SOCKS 代理测试：SOCKS 代理能力进入测试阶段，继续验证稳定性与兼容性。
- 接口触发浏览器：实验性支持通过接口启动浏览器实例，为自动化流程接入做准备。

## 1.0.0

- 实例隔离管理：支持创建、编辑、启动、停止、重启、克隆和删除浏览器实例。
- 代理池配置：支持统一维护代理节点，将代理绑定到具体实例，并导入 Clash 配置。
- 内核管理：支持维护多个 Chrome 内核，设置默认内核，并在实例中选择使用。
- 快捷启动：支持通过实例 Code 和快捷入口打开目标实例。
- 标签与检索：支持按标签、关键字、状态、代理、内核、分组筛选实例。
- 本地化存储：配置和实例数据保存在本地，适合长期使用和备份。
''',
  'core-management': r'''
# 内核介绍

## 推荐目录

```text
chrome/
  chrome-<version>/
    chrome.exe
    ...
```

## 两种准备方式

```text
方式 A：应用内下载
指纹浏览器 -> 内核管理 -> 下载内核

方式 B：手动下载
下载 ZIP -> 解压到 chrome/<version>/ -> 回到内核管理确认识别
```

## 下载渠道

- [fingerprint-chromium](https://github.com/adryfish/fingerprint-chromium)
- [Releases](https://github.com/adryfish/fingerprint-chromium/releases)

## 在应用里怎么用

```text
内核管理 -> 设默认内核
实例编辑页 -> 选择内核
```

## 全局设置

```text
内核管理 -> 全局设置 -> 编辑
```

- 用户数据根目录决定实例数据保存位置
- 默认启动参数会追加到实例启动参数里
- 默认指纹参数会追加到指纹内核启动参数里
- 默认启动页面为空时，不会额外打开页面
- 轻启动模式用于减少启动阶段的额外等待

## 自检

```text
1. 目录下能看到 chrome.exe
2. 内核管理页能识别到该目录
3. 实例绑定的是正确版本
```
''',
  'proxy-usage': r'''
# 代理介绍

## 直接录入示例

```text
<proxy-url>
<proxy-url>
<proxy-url>
```

## Clash YAML 导入示例

```yaml
proxies:
  - name: hk-vless
    type: vless
    server: example.com
    port: 443
    uuid: your-uuid
    tls: true
    servername: example.com
```

## 批量 DNS 示例

```yaml
dns:
  enable: true
  nameserver:
    - 119.29.29.29
    - 223.5.5.5
```

## 应用内路径

```text
代理池配置 -> 导入 Clash YAML / 录入 HTTP(S) / SOCKS5
实例编辑页 -> 选择代理池节点
```

## 在实例接口里绑定代理

```json
{
  "profile": {
    "profileName": "buyer-001",
    "proxyId": "proxy-us",
    "keywords": ["buyer-001"]
  },
  "launchCode": "BUYER_001"
}
```

不需要代理时，`proxyId` 留空即可。
`proxyId` 与 `proxyConfig` 同时传时，优先使用 `proxyId` 对应的代理池节点。
如果 `proxyId` 无效但传了 `proxyConfig`，会自动改为使用该 `proxyConfig`。
如果 `proxyId` 无效且 `proxyConfig` 也为空，请求会直接报错。
''',
  'extension-usage': r'''
# 插件包管理

## 入口

```text
指纹浏览器 -> 插件包管理
```

## 安装方式

- 输入 Chrome Web Store 链接或 32 位插件 ID 后安装
- 本地已有 `.crx` / `.zip` 时，用手动安装导入文件
- 已解压的插件目录可直接导入目录
- 安装完成后，勾选 `默认安装` 才会写入未手动设置的实例

## 设置实例

```text
插件包管理 -> 插件卡片 -> 设置实例
```

- 勾选的实例会写入该插件
- 未勾选的实例会排除该插件
- 弹窗按实例分组展示，未设置分组的实例进入 `未分组`
- 每个分组支持 `选择本组` 和 `取消本组`
- 分组标题会显示该组 `已选 / 总数`

## 单实例插件配置

```text
实例列表 -> 实例行 -> 插件
```

- 默认情况下，实例继承已勾选 `默认安装` 的插件
- 打开手动设置后，该实例只写入弹窗内勾选的插件
- 手动设置适合少量特殊实例

## 推荐用法

```text
同一批业务实例 -> 放入同一分组
同一批业务需要的插件 -> 在设置实例里选择对应分组
个别实例例外 -> 再用单实例插件配置微调
```
''',
  'api-overview': r'''
# 接口总览

## 基础地址

```text
http://127.0.0.1:19900
```

## 认证示例

```bash
curl -H "X-Ant-Api-Key: <your-api-key>" http://127.0.0.1:19900/api/health
```

没开认证时，去掉这个请求头即可。

## 全部接口

| 分类 | 方法 | 路径 |
|------|------|------|
| 健康检查 | `GET` | `/api/health` |
| 实例管理 | `GET` | `/api/profiles` |
| 实例管理 | `POST` | `/api/profiles` |
| 实例管理 | `GET` | `/api/profiles/{profileId}` |
| 实例管理 | `PUT` | `/api/profiles/{profileId}` |
| 实例管理 | `DELETE` | `/api/profiles/{profileId}` |
| 实例管理 | `GET` | `/api/profiles/{profileId}/status` |
| 实例管理 | `POST` | `/api/profiles/{profileId}/stop` |
| 启动 | `GET` | `/api/launch/{code}` |
| 启动 | `POST` | `/api/launch` |
| 运行态 | `GET` | `/api/runtime/active` |
| 运行态 | `POST` | `/api/runtime/session` |
| 运行态 | `POST` | `/api/runtime/status` |
| 运行态 | `POST` | `/api/runtime/stop` |
| 自动化脚本 | `GET` | `/api/automation/scripts` |
| 自动化脚本 | `GET` | `/api/automation/scripts/{scriptId}` |
| 自动化脚本 | `POST` | `/api/automation/scripts/run` |
| 自动化脚本 | `GET` | `/api/automation/scripts/runs` |
| 调用日志 | `GET` | `/api/launch/logs` |
| CDP 统一入口 | `GET` | `/json/version` |
| CDP 统一入口 | `GET` | `/json/list` |
| CDP 统一入口 | `WS` | `/devtools/...` |

## selector 最小写法

```json
{
  "selector": {
    "code": "BUYER_001",
    "matchMode": "unique"
  }
}
```

也可以把 `code / profileId / profileName / keyword / tags / groupId / matchMode` 放在请求体顶层；新接入建议统一放进 `selector`。

## 怎么选接口

| 场景 | 用哪个 |
|------|--------|
| 已知唯一 Code | `GET /api/launch/{code}` |
| 需要参数 / selector | `POST /api/launch` |
| 需要 ready 后再接管 | `POST /api/runtime/session` |
| 只有 selector，想查状态 | `POST /api/runtime/status` |
| 只有 selector，想停止 | `POST /api/runtime/stop` |
''',
  'api-profiles-launch': r'''
# 实例与启动

## 实例接口

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/api/profiles` | 列实例 |
| `POST` | `/api/profiles` | 创建实例 |
| `GET` | `/api/profiles/{profileId}` | 查单个实例 |
| `PUT` | `/api/profiles/{profileId}` | 更新实例 |
| `DELETE` | `/api/profiles/{profileId}` | 删除实例 |
| `GET` | `/api/profiles/{profileId}/status` | 查实例运行态 |
| `POST` | `/api/profiles/{profileId}/stop` | 停止实例 |

## 创建实例

```bash
curl -X POST http://127.0.0.1:19900/api/profiles \
  -H "Content-Type: application/json" \
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

## 创建并立即启动

```bash
curl -X POST http://127.0.0.1:19900/api/profiles \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {
      "profileName": "buyer-002",
      "keywords": ["buyer-002"]
    },
    "autoLaunch": true,
    "start": {
      "skipDefaultStartUrls": true
    }
  }'
```

## 创建实例（自定义代理配置）

```bash
curl -X POST http://127.0.0.1:19900/api/profiles \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {
      "profileName": "buyer-003",
      "proxyConfig": "http://127.0.0.1:18080",
      "keywords": ["buyer-003"]
    }
  }'
```

## 查询 / 更新 / 删除

```bash
curl http://127.0.0.1:19900/api/profiles
curl http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000
curl -X PUT http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000 -H "Content-Type: application/json" -d '{ ... }'
curl -X DELETE http://127.0.0.1:19900/api/profiles/550e8400-e29b-41d4-a716-446655440000
```

## 启动接口

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/api/launch/{code}` | 按唯一 Code 启动 |
| `POST` | `/api/launch` | 按 code / selector 参数化启动 |

### 按 Code 启动

```bash
curl http://127.0.0.1:19900/api/launch/A3F9K2
```

### 按 selector 启动

```bash
curl -X POST http://127.0.0.1:19900/api/launch \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {
      "keyword": "checkout",
      "tags": ["电商", "北美"],
      "groupId": "group-sales-us",
      "matchMode": "unique"
    },
    "skipDefaultStartUrls": true
  }'
```

## 启动成功响应

```json
{
  "ok": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "debugReady": true,
  "cdpUrl": "http://127.0.0.1:19900"
}
```

## 单实例状态 / 停止

| 方法 | 路径 | 示例用途 |
|------|------|----------|
| `GET` | `/api/profiles/{profileId}/status` | 查实例是否运行、是否 ready |
| `POST` | `/api/profiles/{profileId}/stop` | 任务完成后精确停止 |

## 记住这几个规则

```text
launchCode 冲突 -> 409
PUT 是整份更新
运行中的实例不能直接 DELETE
matchMode=all 只在 POST /api/launch 可用
proxyId 和 proxyConfig 同时传 -> 优先 proxyId
proxyId 无效 + proxyConfig 非空 -> 使用 proxyConfig
proxyId 无效 + proxyConfig 为空 -> 400
```
''',
  'api-runtime': r'''
# 运行态与接管

## 接口

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/api/runtime/active` | 查当前活动实例 |
| `POST` | `/api/runtime/session` | 准备可接管会话 |
| `POST` | `/api/runtime/status` | 按 selector 查运行态 |
| `POST` | `/api/runtime/stop` | 按 selector 停止实例 |
| `GET` | `/json/version` | 统一 CDP 入口 |
| `GET` | `/json/list` | 统一 CDP 入口 |
| `WS` | `/devtools/...` | CDP WebSocket 接管 |

## 查询当前活动实例

```bash
curl http://127.0.0.1:19900/api/runtime/active
```

```json
{
  "ok": true,
  "active": true,
  "profileId": "550e8400-e29b-41d4-a716-446655440000",
  "launchCode": "BUYER_001",
  "debugReady": true,
  "cdpUrl": "http://127.0.0.1:19900"
}
```

## 准备可接管会话

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/session \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {
      "code": "BUYER_001"
    },
    "timeoutMs": 45000,
    "skipDefaultStartUrls": true
  }'
```

| 返回 | 含义 |
|------|------|
| `200 + ready=true` | 可以直接 attach |
| `202 + ready=false` | 已处理，但还没 ready |

## 按 selector 查状态

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/status \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {
      "keyword": "shop",
      "matchMode": "first"
    }
  }'
```

## 按 selector 停止

```bash
curl -X POST http://127.0.0.1:19900/api/runtime/stop \
  -H "Content-Type: application/json" \
  -d '{
    "code": "BUYER_001"
  }'
```

## 接管示例

```javascript
import { chromium } from "playwright";

const res = await fetch("http://127.0.0.1:19900/api/runtime/session", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    selector: { code: "BUYER_001" },
    skipDefaultStartUrls: true
  })
});

const data = await res.json();
const browser = await chromium.connectOverCDP(data.cdpUrl);
```

## 记住这几个规则

```text
runtime/status 和 runtime/stop 不支持 matchMode=all
attach 前先看 active / debugReady / cdpUrl
统一入口只指向一个活动实例
```
''',
  'api-automation': r'''
# 脚本自动化

## 接口

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/api/automation/scripts` | 查脚本列表 |
| `GET` | `/api/automation/scripts/{scriptId}` | 查单个脚本详情 |
| `POST` | `/api/automation/scripts/run` | 执行脚本 |
| `GET` | `/api/automation/scripts/runs` | 查运行记录 |

## 列脚本

```bash
curl http://127.0.0.1:19900/api/automation/scripts
```

```json
{
  "ok": true,
  "items": [
    {
      "id": "news-query-txt",
      "name": "查询新闻并写 TXT",
      "type": "playwright-cdp",
      "status": "ready"
    }
  ]
}
```

## 执行脚本

```bash
curl -X POST http://127.0.0.1:19900/api/automation/scripts/run \
  -H "Content-Type: application/json" \
  -d '{
    "scriptId": "news-query-txt",
    "selector": { "code": "BUYER_001" },
    "params": { "keyword": "OpenAI", "limit": 10 }
  }'
```

```json
{
  "ok": true,
  "run": {
    "id": "run-1",
    "status": "success",
    "summary": "已抓取 10 条新闻并写入 TXT"
  }
}
```

如果脚本已经在界面里配置成 `使用已有实例` 或 `按模板新建实例`，也可以只传：

```bash
curl -X POST http://127.0.0.1:19900/api/automation/scripts/run \
  -H "Content-Type: application/json" \
  -d '{
    "scriptId": "news-query-txt"
  }'
```

## 查运行记录

```bash
curl http://127.0.0.1:19900/api/automation/scripts/runs?limit=20
```

## 记住这几个规则

```text
scriptId 必填
推荐优先使用 selector.code，而不是 profileId
selector / params 必须是 JSON object
不传 selector / params 时，默认沿用脚本内配置
```
''',
  'api-support': r'''
# 排障与日志

## 先查这 4 个接口

| 接口 | 用途 |
|------|------|
| `GET /api/health` | 先确认服务是否在线 |
| `GET /api/launch/logs?limit=20` | 查看最近接口调用和错误 |
| `GET /api/runtime/active` | 看统一 CDP 当前指向哪个实例 |
| `GET /api/profiles/{profileId}/status` | 精确确认某个实例是否在运行、是否 ready |

## 日志接口

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/api/launch/logs?limit=50` | 查看最近接口调用和错误 |

## 日志里主要看

```text
method
path
code
selector
profileId
status
error
durationMs
```

## 错误码速查

| 状态码 | 一般代表什么 | 先做什么 |
|--------|--------------|----------|
| `400` | 请求体不对 / selector 缺失 | 先对照示例 JSON |
| `401` | API Key 错误 | 检查 `X-Ant-Api-Key` |
| `403` | 不是 localhost | 改成本机请求 |
| `404` | Code 或 selector 没命中 | 检查 `code / keywords / tags / groupId` |
| `405` | 方法不对 | 检查 GET / POST |
| `409` | 多命中 / launchCode 冲突 | 收窄 selector 或换 launchCode |
| `500` | 启动或脚本执行失败 | 看 `/api/launch/logs` 和应用日志 |
| `503` | 当前没有活动实例或能力没就绪 | 先查 `/api/runtime/active` |

## 看到这些错误时

| 错误文本 | 直接看哪里 |
|----------|------------|
| `selector is required` | 请求体里有没有 `selector / code / profileId` |
| `launch code not found` | Code 是否真实存在 |
| `selector matched multiple profiles` | 是否要补 `tags / groupId` 或改 `matchMode=first` |
| `no active browser debug target` | 先查 `/api/runtime/active` |
| `automation script api is unavailable` | 当前环境是否已启用脚本能力 |

## 排查顺序

```text
1. health
2. 目标接口响应
3. launch/logs
4. runtime/active 或 profile status
5. 应用内日志 / 内核 / 代理
```
''',
};

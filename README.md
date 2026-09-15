# Fluxio

横向多源信息流聚合器 —— 添加网页或 RSS 订阅源，左右滑动切换浏览多个信息源。支持一键收藏到 Obsidian / ima 知识库，内置文件阅读器，iOS 系统分享接收。

## 核心特性

- **横向多源切换**：TabBarView 横向滑动切换不同信息源（已禁用水平滑动手势，点击 Tab 切换，避免与上下滑动冲突）
- **网页源 + RSS 订阅源**：
  - 网页源：WebView 直接浏览任意网页/博客/资讯站
  - RSS 订阅源：解析 RSS 2.0 / Atom 订阅，渲染结构化文章列表（标题/摘要/时间），点击后用 WebView 打开详情，列表项可一键收藏
- **源管理增强**：分组（按分类管理/筛选）、启停（停用源不进信息流 Tab）、编辑、删除、拖拽排序、类型选择
- **35+ 预设信息源**：开箱即用，涵盖 AI 资讯、技术博客、科技新闻、编程社区、Go 语言、独立开发、热榜聚合（TopHub/Buzzing/NewsNow/rebang.today 等）、Buzzing 子站（HN/国外新闻）、国外双语（ThreadEast/Horizon/Ground News/Feedly/Inoreader）
- **本地持久化**：源列表存本地（shared_preferences），无需后端
- **跨平台**：Windows 桌面（WebView2）+ Android / iOS（原生 WebView）
- **一键收藏到 Obsidian**：把当前浏览的网页以 **Markdown 摘要 + 完整网页 HTML 快照** 双份存入 Obsidian vault 收件箱，带 frontmatter（source/url/title/captured/tags）
- **一键同步到 ima 知识库**：收藏内容自动同步到 ima 知识库（API 对接，后台静默同步）
- **收藏历史**：浏览本地收件箱里所有已收藏的 `.md` / `.html`，点击用系统默认应用打开
- **文件阅读器**：支持打开本地 `.md` / `.markdown` / `.html` / `.htm` / `.txt` 文件，Markdown 渲染、WebView 渲染、字体大小调节、收藏文件内容到 Obsidian / ima
- **iOS 系统分享接收**：Share Extension + 剪贴板检测 + URL Scheme 唤起，Safari 浏览网页 → 分享菜单 →「收藏到 Fluxio」，后台静默收藏
- **收件箱（Inbox）API**：本地收件服务（127.0.0.1:8730），浏览器扩展、剪贴板复制、局域网投递页都能一键投递收藏
- **回到信息流**：详情页一键返回信息流首页并**精确恢复**浏览位置；切换 Tab 不丢 WebView 状态
- **已读标识**：列表页已读过的文章样式区分，避免重复阅读

## 快速开始

```bash
# 克隆项目
git clone https://github.com/IYABAO/Fluxio.git
cd Fluxio

# 安装依赖
flutter pub get

# Windows 桌面版
flutter run -d windows

# Android / iOS
flutter run -d <device>
```

## 下载安装

### Windows
- 构建产物：`dist/fluxio-windows/fluxio.exe`（约 30 MB）
- 直接双击运行（需要 WebView2 Runtime，Windows 10/11 通常已自带）

### Android
- APK 包：`dist/fluxio-android.apk`（约 52 MB）
- 下载后在手机上安装（需开启「未知来源应用安装」）

### iOS
- 未签名 IPA：GitHub Actions 构建产物 `fluxio-ios-unsigned`
- 使用 Sideloadly 签名安装（确保不勾选「Remove app extensions」，否则 Share Extension 会失效）
- 每 7 天需重签（免费开发者账号限制）

## 使用

### 添加信息源（网页 / RSS）

1. 打开「管理信息源」，点右下角 **+**
2. 选择类型：**网页**（直接浏览 URL）或 **RSS 订阅**（解析文章列表）
3. 填写名称、URL、分组（可输入新分组名）
4. 已添加的源可：编辑 / 删除 / 拖拽排序 / 开关启停；顶部 Chip 按分组筛选

> RSS 源加载：列表下拉刷新；外网源若本机需代理访问，RssService 会自动读取 Windows 系统代理（ProxyEnable=1 时）。

### 一键导入预设源

1. 打开「管理信息源」
2. 点击「一键导入常用源」
3. 35+ 预设源自动导入（可按需删除不需要的）

预设源分组：
- **AI 资讯**（4个）：大黑AI速报、机器之心、量子位、新智元
- **技术博客**（4个）：PLBear 博客、阮一峰周刊、酷壳、美团技术团队
- **科技新闻**（4个）：Hacker News、TechCrunch、The Verge、Ars Technica
- **编程社区**（4个）：掘金、SegmentFault、V2EX、Stack Overflow
- **Go 语言**（2个）：Go 官方博客、Go 中文网
- **独立开发**（2个）：Indie Hackers、Product Hunt
- **热榜聚合**（8个）：TopHub、Buzzing、NewsNow、rebang.today、糖果梦、NewsHub、划水摸鱼、热摸爽
- **Buzzing 子站**（2个）：HN 热门、国外新闻头条
- **国外双语**（5个）：ThreadEast、Horizon、Ground News、Feedly、Inoreader

### 收藏到 Obsidian

1. 打开设置页，配置你的 Obsidian vault 路径
2. 浏览任意信息源页面，点右上角「收藏到 Obsidian」（RSS 文章列表态请用列表项右侧 ☆）
3. 每次收藏在 `<vault>/Fluxio收件箱/` 下产出两个文件（`<YYYY-MM-DD-HHmmss>-<微秒>` 为基名）：
   - **`<基名>.md`**：Obsidian 友好的 Markdown 摘要 —— frontmatter（`source`/`url`/`title`/`captured`/`type`/`tags: [fluxio, inbox]`）+ 原文链接 + **完整纯文本正文**（`<body>` 全文，只剔除脚本/样式等不可见元素，不精简、不截断），并内链指向同名 HTML 快照
   - **`<基名>.html`**：**自包含网页快照** —— 整页 HTML + 内联全部内联/外链 CSS（`fetch` 外链样式表，失败保留原 link），本地双击打开即可还原原站排版/图片/布局
   - HTML 提取失败时仅生成 `.md`（type 回退为 `webclip_content` / `webclip_link`）

### 同步到 ima 知识库

1. 打开设置页，配置 ima API Key 和 Client ID
2. 启用 ima 同步开关
3. 收藏内容自动同步到 ima 知识库（后台静默同步，不阻塞收藏操作）
4. 收藏历史页可查看每条记录的 ima 同步状态

### 文件阅读器

1. 打开「收藏历史」页
2. 点击右上角「📁 打开文件」
3. 选择本地 `.md` / `.markdown` / `.html` / `.htm` / `.txt` 文件
4. 文件阅读器自动渲染：
   - `.md` / `.markdown`：Markdown 渲染（支持代码块、表格、列表等）
   - `.html` / `.htm`：WebView 渲染（还原网页排版）
   - `.txt`：纯文本显示
5. 支持字体大小调节（12-24px）
6. 支持收藏文件内容到 Obsidian / ima

### iOS 系统分享接收

**方式一：Share Extension（推荐）**
1. Safari 浏览任意网页
2. 点击底部分享按钮
3. 选择「收藏到 Fluxio」
4. 自动跳转到 Fluxio，后台静默收藏到 Obsidian / ima

**方式二：剪贴板检测**
1. 复制任意 `http(s)` 链接
2. 打开 Fluxio，自动弹出「📥 检测到链接 → 收藏」
3. 点击确认，后台静默收藏

**方式三：URL Scheme**
- `fluxio://share?url=<url>&title=<title>`
- 可从其他 App 唤起 Fluxio 并自动收藏

### 收件箱（Inbox）：任何来源一键投递收藏

Fluxio 内置本地收件服务（`127.0.0.1:8730`，应用启动时自动运行），浏览器扩展、剪贴板复制、局域网投递页都能把链接一键投进 Obsidian 收件箱，走与站内收藏完全相同的链路（md + 自包含 HTML 双份）。

- **浏览器扩展**（`tool/extension/`，Chrome/Edge MV3）：点图标 → 当前页直接收藏；右键图标 → 选项，粘贴设置页的 Token
- **剪贴板捕获**：复制任意 `http(s)` 链接，应用内弹条「📥 检测到链接 → 收藏」，一键确认
- **本地 API**：`POST /api/inbox`（`X-Inbox-Token` 鉴权）+ `GET /api/health`，供脚本/自动化投递
- **Token**：设置页「收件箱（Inbox）」查看/复制/重置
- 投递示例：
  ```bash
  curl -X POST http://127.0.0.1:8730/api/inbox \
    -H "X-Inbox-Token: <token>" -H "Content-Type: application/json" \
    -d '{"url":"https://example.com","source":"网页"}'
  ```

### 详情页与回到信息流

- 浏览信息流时点击任意文章链接，**自动打开全屏新页面**（独立 WebView）加载详情，信息流页面保持不变
- 详情页 AppBar 带返回箭头，点击直接回到信息流，**滚动位置 100% 精确保留**（无滚动动画、无位置偏移）
- 切换 Tab 时每个源的 WebView 保持存活（keep-alive），不重新加载、不丢浏览位置

## 技术栈

- Flutter 3.x / Dart 3.x
- `webview_flutter`（Android/iOS）+ `webview_flutter_windows`（Windows WebView2）
- `shared_preferences` 本地存储
- `flutter_markdown_plus` Markdown 渲染
- `file_picker` 文件选择
- `url_launcher` 外部链接打开
- RSS/Atom 解析：`dart:io` HttpClient + 轻量扫描解析（零第三方依赖）
- iOS Share Extension：Swift + App Group + MethodChannel

## 架构

```
lib/
├── main.dart                  # 应用入口（Windows 初始化 WebView2 环境）
├── models/
│   ├── feed_source.dart       # 信息源模型（id/title/url/group/enabled/type）
│   ├── preset_sources.dart    # 预设信息源（35+ 站点，9 个分组）
│   ├── web_page_info.dart     # 页面信息（url/title/content/html）模型
│   └── clip_record.dart       # 收藏记录模型（id/title/url/source/status/createdAt/localPath/errorMessage）
├── services/
│   ├── source_store.dart      # 本地持久化（含首次启动示例源注入）
│   ├── obsidian_store.dart    # Obsidian 收藏：vault 路径 + Markdown 写入
│   ├── ima_service.dart       # ima 知识库同步：API 对接 + 后台静默同步
│   ├── rss_service.dart       # RSS/Atom 订阅抓取与解析（含系统代理支持）
│   ├── inbox_server.dart      # 本地收件服务（127.0.0.1:8730）
│   ├── clipboard_detector.dart # 剪贴板检测（URL 识别 + 防重复 + 可开关）
│   ├── share_receiver_service.dart # 分享接收服务（Share Extension + 剪贴板统一处理）
│   ├── ios_share_bridge.dart  # iOS 分享桥接（MethodChannel + App Group）
│   └── wechat_official_service.dart # 微信公众号服务
├── screens/
│   ├── home_screen.dart       # 主页：横向多源 TabBarView + 收藏/历史入口 + 分享事件监听
│   ├── manage_sources_screen.dart  # 源管理：增/删/改/启停/分组/排序/类型/一键导入
│   ├── settings_screen.dart   # 设置：Obsidian vault 路径 + ima 配置 + 收件箱 Token
│   ├── clipboard_history_screen.dart  # 收藏历史：本地收件箱浏览 + 文件阅读器入口
│   └── file_reader_screen.dart # 文件阅读器：.md/.html/.txt 文件渲染 + 字体调节 + 收藏
└── widgets/
    ├── source_webview.dart    # 跨平台 WebView 容器（条件导入）+ RSS 分支
    ├── rss_feed_view.dart     # RSS 订阅源文章列表（含收藏/下拉刷新/已读标识）
    ├── platform_webview_interface.dart
    ├── platform_webview_windows.dart  # Windows WebView2 实现
    └── platform_webview_mobile.dart   # Android/iOS 实现

ios/
├── Runner/
│   ├── AppDelegate.swift      # MethodChannel 注册 + URL Scheme 唤起 + App Group 读写
│   ├── Runner.entitlements    # 主 App App Group 配置
│   └── Info.plist             # URL Scheme (fluxio://) + LSApplicationQueriesSchemes
└── ShareExtension/            # iOS 分享扩展
    ├── ShareViewController.swift # 分享处理逻辑
    ├── Info.plist             # 扩展配置
    ├── MainInterface.storyboard # 分享界面
    └── ShareExtension.entitlements # 扩展 App Group 配置

tool/
├── extension/                 # Chrome/Edge 浏览器扩展（MV3）
├── rss_smoke.dart             # RSS 抓取冒烟测试
└── test_sources.py            # 信息源可访问性批量测试脚本

assets/
└── preset_sources_hot.json    # 热榜聚合预设源 JSON（可手动导入）
```

## 测试

```bash
flutter test
```

- `test/obsidian_store_test.dart`：Obsidian 收藏（frontmatter、HTML 快照双文件、超长正文不截断、转义）
- `test/source_store_test.dart`：源持久化（seed、新增字段序列化往返、旧 JSON 兼容、启停持久化）
- `test/rss_service_test.dart`：RSS 2.0 / Atom 解析、CDATA/实体剥离、时间排序、边界情况

## CI/CD

- **CI**（`.github/workflows/ci.yml`）：flutter analyze + flutter test，每次 push 自动运行
- **iOS Build**（`.github/workflows/ios-build.yml`）：构建未签名 IPA，产物可下载
- 构建状态：
  - CI：![CI](https://github.com/IYABAO/Fluxio/actions/workflows/ci.yml/badge.svg)
  - iOS Build：![iOS Build](https://github.com/IYABAO/Fluxio/actions/workflows/ios-build.yml/badge.svg)

## Roadmap

### 已完成 ✅
- [x] M1 项目骨架 + 多源横向切换 + 本地存储（MVP）
- [x] P1 收藏当前页到 Obsidian（本地直写 vault 收件箱）
- [x] 源管理增强（RSS 订阅源、分组、启停、编辑、类型选择）
- [x] 收藏历史页（本地收件箱浏览）
- [x] 收件箱 API + 浏览器扩展 + 剪贴板捕获
- [x] ima 知识库同步（API 对接 + 后台静默同步）
- [x] 文件阅读器（.md / .html / .txt 文件渲染 + 字体调节）
- [x] iOS 系统分享接收（Share Extension + 剪贴板检测 + URL Scheme）
- [x] 35+ 预设信息源（热榜聚合 / Buzzing 子站 / 国外双语）
- [x] 跨平台构建（Windows / Android / iOS）
- [x] 已读标识（列表页已读文章样式区分）
- [x] 手势冲突修复（禁用水平滑动，点击 Tab 切换）

### 进行中 🔄
- [ ] 安卓版分享接收功能（Intent Filter + receive_sharing_intent）
- [ ] 设置页剪贴板检测开关
- [ ] 分享收藏正文提取（HTTP 请求获取网页正文）

### 规划中 📋
- [ ] 文件阅读器系统分享接收（其他 App 分享文件到 Fluxio）
- [ ] AI 摘要（收藏内容自动生成摘要）
- [ ] 全文搜索（收藏内容本地搜索）
- [ ] 标签系统（收藏内容打标签 + 按标签筛选）
- [ ] 云端同步（多设备收藏同步）
- [ ] Windows 安装包（MSIX / Inno Setup）
- [ ] 应用商店发布（Google Play / App Store）

## 相关项目

- [fluxio-mcp](https://github.com/IYABAO/fluxio-mcp)：Fluxio 配套 MCP Server（search_web + fetch_web_md），可接入任意支持 MCP 协议的 AI 客户端
- [CookingCoder](https://github.com/IYABAO/CookingCoder)：40 道菜 + 程序化度量库 + MCP 服务 + 流程图，独立域名 [cook.plbear.com](https://cook.plbear.com)
- [IYABAO.github.io](https://github.com/IYABAO/IYABAO.github.io)：个人博客 [www.plbear.com](https://www.plbear.com)，200+ 篇技术文章

## 作者

- **Allen Lin（林壮）**
- 博客：[www.plbear.com](https://www.plbear.com)
- 掘金：[林壮Allen](https://juejin.cn/user/3043039172367101)
- GitHub：[IYABAO](https://github.com/IYABAO)

## License

MIT License — 详见 [LICENSE](LICENSE) 文件

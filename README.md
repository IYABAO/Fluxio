# Fluxio

横向多源信息流聚合器 —— 添加网页或 RSS 订阅源，左右滑动切换浏览多个信息源。

## 核心特性

- **横向多源切换**：TabBarView 横向滑动切换不同信息源
- **网页源 + RSS 订阅源**：
  - 网页源：WebView 直接浏览任意网页/博客/资讯站
  - RSS 订阅源：解析 RSS 2.0 / Atom 订阅，渲染结构化文章列表（标题/摘要/时间），点击后用 WebView 打开详情，列表项可一键收藏
- **源管理增强**：分组（按分类管理/筛选）、启停（停用源不进信息流 Tab）、编辑、删除、拖拽排序、类型选择
- **本地持久化**：源列表存本地（shared_preferences），无需后端
- **跨平台**：Windows 桌面（WebView2）+ Android / iOS（原生 WebView）
- **开箱即用**：首次启动预置示例源（大黑AI速报 / Hacker News / PLBear 博客）
- **一键收藏到 Obsidian**：把当前浏览的网页以 **Markdown 摘要 + 完整网页 HTML 快照** 双份存入 Obsidian vault 收件箱，带 frontmatter（source/url/title/captured/tags）
- **收藏历史**：浏览本地收件箱里所有已收藏的 `.md` / `.html`，点击用系统默认应用打开
- **回到信息流**：详情页一键返回信息流首页并**精确恢复**浏览位置；切换 Tab 不丢 WebView 状态

## 快速开始

```bash
# Windows 桌面版
flutter run -d windows

# Android / iOS
flutter run -d <device>
```

## 使用

### 添加信息源（网页 / RSS）

1. 打开「管理信息源」，点右下角 **+**
2. 选择类型：**网页**（直接浏览 URL）或 **RSS 订阅**（解析文章列表）
3. 填写名称、URL、分组（可输入新分组名）
4. 已添加的源可：编辑 / 删除 / 拖拽排序 / 开关启停；顶部 Chip 按分组筛选

> RSS 源加载：列表下拉刷新；外网源若本机需代理访问，RssService 会自动读取 Windows 系统代理（ProxyEnable=1 时）。

### 收藏到 Obsidian

1. 打开设置页，配置你的 Obsidian vault 路径
2. 浏览任意信息源页面，点右上角「收藏到 Obsidian」（RSS 文章列表态请用列表项右侧 ☆）
3. 每次收藏在 `<vault>/Fluxio收件箱/` 下产出两个文件（`<YYYY-MM-DD-HHmmss>-<微秒>` 为基名）：
   - **`<基名>.md`**：Obsidian 友好的 Markdown 摘要 —— frontmatter（`source`/`url`/`title`/`captured`/`type`/`tags: [fluxio, inbox]`）+ 原文链接 + **完整纯文本正文**（`<body>` 全文，只剔除脚本/样式等不可见元素，不精简、不截断），并内链指向同名 HTML 快照
   - **`<基名>.html`**：**自包含网页快照** —— 整页 HTML + 内联全部内联/外链 CSS（`fetch` 外链样式表，失败保留原 link），本地双击打开即可还原原站排版/图片/布局
   - HTML 提取失败时仅生成 `.md`（type 回退为 `webclip_content` / `webclip_link`）

> P2（规划中）：云端收件箱 + Obsidian 插件拉取（更接近 WeChat Inbox Sync 的完整链路）

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

> P2（规划中）：局域网投递页（手机头条复制链接→手机浏览器投递）；P3：企业微信官方 API 接入（云函数 + 云端队列，零封号风险）。

### 详情页与回到信息流

- 浏览信息流时点击任意文章链接，**自动打开全屏新页面**（独立 WebView）加载详情，信息流页面保持不变
- 详情页 AppBar 带返回箭头，点击直接回到信息流，**滚动位置 100% 精确保留**（无滚动动画、无位置偏移）
- 切换 Tab 时每个源的 WebView 保持存活（keep-alive），不重新加载、不丢浏览位置

## 技术栈

- Flutter 3.x / Dart 3.x
- `webview_flutter`（Android/iOS）+ `webview_flutter_windows`（Windows WebView2）
- `shared_preferences` 本地存储
- RSS/Atom 解析：`dart:io` HttpClient + 轻量扫描解析（零第三方依赖）

## 架构

```
lib/
├── main.dart                  # 应用入口（Windows 初始化 WebView2 环境）
├── models/
│   ├── feed_source.dart       # 信息源模型（id/title/url/group/enabled/type）
│   └── web_page_info.dart     # 页面信息（url/title/content/html）模型
├── services/
│   ├── source_store.dart      # 本地持久化（含首次启动示例源注入）
│   ├── obsidian_store.dart    # Obsidian 收藏：vault 路径 + Markdown 写入
│   └── rss_service.dart       # RSS/Atom 订阅抓取与解析（含系统代理支持）
├── screens/
│   ├── home_screen.dart       # 主页：横向多源 TabBarView + 收藏/历史入口
│   ├── manage_sources_screen.dart  # 源管理：增/删/改/启停/分组/排序/类型
│   ├── settings_screen.dart   # 设置：Obsidian vault 路径
│   └── clipboard_history_screen.dart  # 收藏历史：本地收件箱浏览
└── widgets/
    ├── source_webview.dart    # 跨平台 WebView 容器（条件导入）+ RSS 分支
    ├── rss_feed_view.dart     # RSS 订阅源文章列表（含收藏/下拉刷新）
    ├── platform_webview_interface.dart
    ├── platform_webview_windows.dart  # Windows WebView2 实现
    └── platform_webview_mobile.dart   # Android/iOS 实现
```

## 测试

```bash
flutter test
```

- `test/obsidian_store_test.dart`：Obsidian 收藏（frontmatter、HTML 快照双文件、超长正文不截断、转义）
- `test/source_store_test.dart`：源持久化（seed、新增字段序列化往返、旧 JSON 兼容、启停持久化）
- `test/rss_service_test.dart`：RSS 2.0 / Atom 解析、CDATA/实体剥离、时间排序、边界情况

## Roadmap

- [x] M1 项目骨架 + 多源横向切换 + 本地存储（MVP）
- [x] P1 收藏当前页到 Obsidian（本地直写 vault 收件箱）
- [x] 源管理增强（RSS 订阅源、分组、启停、编辑、类型选择）
- [x] 收藏历史页（本地收件箱浏览）
- [ ] ima 知识库同步
- [ ] AI 摘要
- [ ] Flutter App 版发布

## License

MIT

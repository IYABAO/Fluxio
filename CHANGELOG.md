# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-09-19

首个正式版本。横向多源信息流聚合器，覆盖 Windows / Android / iOS 三端。

### 信息流
- 横向多源切换：点击 Tab 在多个信息源间切换（禁用水平滑动手势，避免与列表上下滑动冲突）
- 网页源：WebView 直接浏览任意网页 / 博客 / 资讯站
- RSS 订阅源：解析 RSS 2.0 / Atom，渲染结构化文章列表（标题 / 摘要 / 时间），点击进入详情
- 源管理：分组、启停、编辑、删除、拖拽排序、类型选择
- 35+ 预设信息源一键导入：AI 资讯、技术博客、科技新闻、编程社区、Go 语言、独立开发、热榜聚合（TopHub / Buzzing / NewsNow / rebang.today 等）、Buzzing 子站、国外双语
- 本地持久化（shared_preferences），无需后端
- RSS 抓取自动读取 Windows 系统代理
- 已读标识：列表页已读文章样式区分

### 收藏与知识库
- 一键收藏到 Obsidian：Markdown 摘要（frontmatter + 完整纯文本正文）+ 自包含网页 HTML 快照双份写入 vault 收件箱
- 一键同步到 ima 知识库：API 对接，后台静默同步，收藏历史可查看同步状态
- 收藏历史：浏览本地收件箱全部 `.md` / `.html`，点击用系统默认应用打开
- 收件箱（Inbox）本地服务 `127.0.0.1:8730`：Chrome/Edge MV3 浏览器扩展、剪贴板捕获、局域网投递页、`POST /api/inbox`（Token 鉴权）均可一键投递

### 文件阅读器
- 打开本地 `.md` / `.markdown` / `.html` / `.htm` / `.txt` 文件
- Markdown 渲染（代码块、表格、列表）、HTML 用 WebView 渲染、纯文本显示
- 字体大小调节（12–24px），文件内容可再收藏到 Obsidian / ima
- 系统「用 Fluxio 打开」入口

### iOS 分享接收
- Share Extension：Safari 分享菜单 →「收藏到 Fluxio」，后台静默收藏
- 剪贴板检测兜底：复制链接打开 App 弹条确认收藏
- URL Scheme：`fluxio://share?url=<url>&title=<title>`
- App Group + MethodChannel 与主 App 通信

### 浏览体验
- 详情页独立全屏 WebView，返回后 100% 精确恢复信息流滚动位置
- 切换 Tab 各源 WebView keep-alive，不重新加载、不丢状态
- 列表滑动性能优化

### 工程
- Flutter 3.x / Dart 3.x，三端（Windows WebView2 / Android / iOS 原生 WebView）
- CI：push / PR 自动 `flutter analyze` + `flutter test`
- Release：打 `v*` tag 自动构建 iOS 未签名 IPA 与 Windows x64 便携包并发布 GitHub Release
- 单元测试：Obsidian 收藏、源持久化（含旧 JSON 兼容）、RSS/Atom 解析

### 已知限制
- iOS 未签名 IPA 需用 Sideloadly 自签安装（保留 Share Extension，勿勾选移除扩展），免费账号 7 天重签
- Android 分享接收、AI 摘要、全文搜索、标签系统、云端同步见 Roadmap

[0.1.0]: https://github.com/IYABAO/Fluxio/releases/tag/v0.1.0

import 'package:flutter/widgets.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';

/// WebView 平台抽象：屏蔽不同平台（Windows WebView2 / Android / iOS）的差异。
abstract class PlatformWebView {
  /// 根据源构建 WebView。
  ///
  /// [onPageInfoChanged]：页面导航/加载完成后回调当前页面 URL 与标题，
  /// 供上层"收藏到 Obsidian"使用。
  Widget build(
    FeedSource source, {
    ValueChanged<WebPageInfo>? onPageInfoChanged,
  });

  /// 提取当前页面纯文本；失败或不可用时返回 null。
  ///
  /// 由上层在"收藏到 Obsidian"时调用。
  Future<String?> extractContent();

  /// 提取当前页面完整 HTML 快照（保留样式/图片/布局）；失败返回 null。
  Future<String?> extractHtml();

  /// 回到信息流（源的首页），并尽量恢复之前浏览的滚动位置。
  Future<void> backToFeed();
}

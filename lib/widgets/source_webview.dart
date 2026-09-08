import 'package:flutter/material.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import 'platform_webview_interface.dart';
import 'platform_webview_mobile.dart'
    if (dart.library.io) 'platform_webview_windows.dart'
    as platform;
import 'rss_feed_view.dart';

/// 单个信息源 WebView 的对外控制句柄（由 HomeScreen 持有）。
///
/// 让上层在不直接接触平台私有 State 的前提下，
/// 触发"收藏时提取正文"与"回到信息流"两个动作。
class SourceWebViewController {
  _SourceWebViewState? _state;

  /// 提取当前页面纯文本；失败返回 null。
  Future<String?> extractContent() =>
      _state?.extractContent() ?? Future.value(null);

  /// 提取当前页面完整 HTML 快照（保留样式）；失败返回 null。
  Future<String?> extractHtml() =>
      _state?.extractHtml() ?? Future.value(null);

  /// 回到信息流首页并尽量恢复滚动位置。
  Future<void> backToFeed() => _state?.backToFeed() ?? Future.value();

  /// RSS 源当前是否处于"文章列表"态（未打开任何文章）。
  bool get isRssListMode => _state?.isRssListMode ?? false;
}

/// 单个信息源的 WebView 容器（跨平台）。
///
/// 通过条件导入选择平台实现：
/// - Windows 桌面：webview_flutter_windows（WebView2）
/// - Android / iOS：webview_flutter 主包
///
/// 横向滑动切换的核心单元：每个源渲染一个独立的 WebView，
/// 由上层 TabBarView 负责横向滑动切换。
///
/// 启用 [AutomaticKeepAliveClientMixin]：切换 Tab 时保住 WebView 状态
/// （当前 URL、浏览历史、滚动位置），切回时不会重新加载丢位置。
class SourceWebView extends StatefulWidget {
  final FeedSource source;
  final ValueChanged<WebPageInfo>? onPageInfoChanged;

  /// 可选：绑定到外部控制句柄，供 HomeScreen 调用提取正文/回到信息流。
  final SourceWebViewController? controller;

  const SourceWebView({
    super.key,
    required this.source,
    this.onPageInfoChanged,
    this.controller,
  });

  @override
  State<SourceWebView> createState() => _SourceWebViewState();
}

class _SourceWebViewState extends State<SourceWebView>
    with AutomaticKeepAliveClientMixin {
  /// 平台 WebView 实例（在 state 内创建并复用，避免每次 build 重建 controller）。
  late final PlatformWebView _platformWebView =
      platform.createPlatformWebView();

  /// RSS 源当前打开的文章 URL：null 表示显示文章列表。
  /// 仅在 [widget.source.isRss] 时使用。
  String? _rssArticleUrl;

  @override
  bool get wantKeepAlive => true;

  Future<String?> extractContent() => _platformWebView.extractContent();

  Future<String?> extractHtml() => _platformWebView.extractHtml();

  /// RSS 源当前是否处于"文章列表"态。
  bool get isRssListMode => widget.source.isRss && _rssArticleUrl == null;

  /// 回到信息流：
  /// - RSS 源正在看文章 → 回到文章列表；
  /// - 否则委托平台 WebView 回到源首页。
  Future<void> backToFeed() async {
    if (widget.source.isRss && _rssArticleUrl != null) {
      if (mounted) setState(() => _rssArticleUrl = null);
      return;
    }
    await _platformWebView.backToFeed();
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // RSS 订阅源：列表态（_rssArticleUrl == null）显示文章列表；
    // 点开文章后用 WebView 加载（此时 feedUrl = 文章 URL，返回由 backToFeed 拦截回列表）。
    if (widget.source.isRss) {
      final articleUrl = _rssArticleUrl;
      if (articleUrl == null) {
        return RssFeedView(
          source: widget.source,
          onOpenArticle: (url) {
            if (mounted) setState(() => _rssArticleUrl = url);
          },
        );
      }
      // 用文章 URL 构造一个临时"网页源"，让 WebView 直接加载详情。
      final articleSource = FeedSource(
        id: widget.source.id,
        title: widget.source.title,
        url: articleUrl,
        type: kSourceTypeWeb,
      );
      return _platformWebView.build(
        articleSource,
        onPageInfoChanged: widget.onPageInfoChanged,
      );
    }

    return _platformWebView.build(
      widget.source,
      onPageInfoChanged: widget.onPageInfoChanged,
    );
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) {
      widget.controller?._state = null;
    }
    super.dispose();
  }
}

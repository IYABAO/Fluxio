import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_windows.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/web_content_extractor.dart';
import 'platform_webview_interface.dart';
import 'platform_webview_mobile.dart' as mobile;

/// Windows 平台实现：基于 WebView2（webview_flutter_windows）。
class WindowsWebView implements PlatformWebView {
  _WindowsWebViewImplState? _state;

  @override
  Widget build(
    FeedSource source, {
    ValueChanged<WebPageInfo>? onPageInfoChanged,
  }) {
    return _WindowsWebViewImpl(
      source: source,
      onPageInfoChanged: onPageInfoChanged,
      onStateReady: (s) => _state = s,
    );
  }

  @override
  Future<String?> extractContent() =>
      _state?.extractContent() ?? Future.value(null);

  @override
  Future<String?> extractHtml() =>
      _state?.extractHtml() ?? Future.value(null);

  @override
  Future<void> backToFeed() => _state?.backToFeed() ?? Future.value();
}

class _WindowsWebViewImpl extends StatefulWidget {
  final FeedSource source;
  final ValueChanged<WebPageInfo>? onPageInfoChanged;
  final ValueChanged<_WindowsWebViewImplState> onStateReady;

  const _WindowsWebViewImpl({
    required this.source,
    required this.onPageInfoChanged,
    required this.onStateReady,
  });

  @override
  State<_WindowsWebViewImpl> createState() => _WindowsWebViewImplState();
}

class _WindowsWebViewImplState extends State<_WindowsWebViewImpl> {
  /// WebView2 controller 在 State 中创建并复用：
  /// 避免在 build 中新建 controller 导致 State 复用时 controller 错乱。
  late final WebviewController _controller = WebviewController();

  bool _isLoading = true;
  bool _hasError = false;

  /// 当前页面 URL（来自包内置的 urlChanged 流）。
  String _currentUrl = '';

  /// 当前页面标题（来自包内置的 titleChanged 流）。
  String _currentTitle = '';

  /// 信息流首页 URL（源配置的 URL）。
  late final String _feedUrl = widget.source.url;

  /// 信息流首页最近一次上报的滚动位置（由页面滚动监听实时更新）。
  int _feedScrollY = 0;

  /// 离开信息流首页时保存的滚动位置（避免详情页滚动污染 _feedScrollY）。
  /// 返回信息流时用此值恢复，这是最可靠的恢复来源。
  int _savedFeedScrollY = 0;

  /// 上一次 URL 是否为信息流首页（用于检测"离开首页"的瞬间并保存滚动位置）。
  bool _wasFeed = false;

  /// 浏览器历史是否可后退（来自 historyChanged 流）。
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    widget.onStateReady(this);
    _init();
  }

  Future<void> _init() async {
    try {
      // WebView2 用户数据目录已在 main() 中通过 initializeEnvironment 指定。
      await _controller.initialize();
      // 监听浏览器历史变化（canGoBack / canGoForward）。
      _controller.historyChanged.listen((h) {
        if (!mounted) return;
        _canGoBack = h.canGoBack;
      });
      // 监听页面通过 window.chrome.webview.postMessage 上报的滚动位置。
      _controller.webMessage.listen((msg) {
        if (!mounted) return;
        _onWebMessage(msg);
      });
      // 监听加载状态：navigationCompleted 表示加载完成。
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        if (state == LoadingState.navigationCompleted) {
          setState(() => _isLoading = false);
          _onPageLoaded();
        }
      });
      // 监听 URL 变化（页面内跳转/前进后退）——包内置流，安全。
      _controller.url.listen((url) {
        if (!mounted) return;
        _wasFeed = _isFeed(url);
        _currentUrl = url;
        _notifyPageInfo();
      });
      // 监听标题变化——包内置流，安全。
      _controller.title.listen((title) {
        if (!mounted) return;
        _currentTitle = title;
        _notifyPageInfo();
      });
      // 监听加载错误。
      _controller.onLoadError.listen((_) {
        if (mounted) setState(() => _hasError = true);
      });
      await _controller.loadUrl(_feedUrl);
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  /// 处理页面上报的滚动消息：兼容 WebMessage 对象 / String / Map 三种类型。
  ///
  /// webview_flutter_windows 的 webMessage 流返回 WebMessage 对象（.data 为字符串），
  /// 不是 Map，必须先取 .data 再 jsonDecode，否则消息会被 `msg is! Map` 直接丢弃。
  void _onWebMessage(dynamic msg) {
    Map? parsed;
    if (msg is Map) {
      parsed = msg;
    } else if (msg is String) {
      try { parsed = jsonDecode(msg) as Map?; } catch (_) {}
    } else if (msg != null) {
      // WebMessage 对象：尝试取 .data 字段
      try {
        final data = msg.data;
        if (data is String) {
          try { parsed = jsonDecode(data) as Map?; } catch (_) {}
        }
      } catch (_) {
        // 兜底：toString() 后尝试解析
        try { parsed = jsonDecode(msg.toString()) as Map?; } catch (_) {}
      }
    }
    if (parsed == null) return;
    // 处理导航请求：用户点击链接 → 打开全屏新页面加载详情
    if (parsed['fluxio'] == 'navigate') {
      final url = parsed['url'];
      if (url is String && url.isNotEmpty) {
        _showDetailPage(url);
      }
      return;
    }
    if (parsed['fluxio'] != 'scroll') return;
    final y = parsed['y'];
    if (y is! num) return;
    if (_isFeed(_currentUrl) && y > 0) {
      _feedScrollY = y.toInt();
      _savedFeedScrollY = y.toInt(); // 同步保存
    }
  }

  /// 页面加载完成：
  /// - 注入滚动监听（页面滚动时实时上报位置）；
  /// - 若回到信息流首页，恢复之前记录的滚动位置。
  void _onPageLoaded() {
    _controller.executeScript(kInstallScrollListenerJs).catchError((_) {});
    _scheduleFeedRestore();
  }

  /// 回到信息流首页后的滚动恢复调度。
  ///
  /// 采用"容器自适应 + 多次重试"：SPA 首页内容往往异步渲染、容器高度动态
  /// 增长，单次 `scrollTo` 可能因页面还没长高而失效；因此在 200/500/1200/2000/3000ms
  /// 各尝试一次，且仅当已回到信息流首页时执行。
  ///
  /// 恢复位置优先使用 `_savedFeedScrollY`（离开首页时保存的可靠值），
  /// 其次用 `_feedScrollY`（实时更新值，可能被竞态污染）。
  void _scheduleFeedRestore() {
    if (!_isFeed(_currentUrl)) return;
    final restoreY = _savedFeedScrollY > 0 ? _savedFeedScrollY : _feedScrollY;
    if (restoreY <= 0) return;
    const delays = [200, 500, 1200, 2000, 3000];
    for (final d in delays) {
      Future.delayed(Duration(milliseconds: d), () {
        if (!mounted) return;
        if (!_isFeed(_currentUrl)) return;
        _controller.executeScript(kInstallScrollListenerJs).catchError((_) {});
        _controller
            .executeScript(kRestoreScrollJs(restoreY))
            .catchError((_) {});
      });
    }
  }

  /// 回到信息流首页：
  /// 直接 loadUrl 重新加载首页（不使用 goBack，避免浏览器 bfcache 恢复错误的
  /// 滚动位置覆盖我们的恢复逻辑），加载完成后恢复记录的位置。
  Future<void> backToFeed() async {
    try {
      await _controller.loadUrl(_feedUrl);
      _scheduleFeedRestore();
    } catch (_) {
      // 忽略。
    }
  }

  /// 打开全屏详情页：用独立 WebViewController 加载 URL，信息流页面保持不变。
  /// 这样返回时滚动位置完全保留，不需要保存/恢复。
  void _showDetailPage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _DetailPage(url: url)),
    );
  }

  /// 提取当前页面纯文本。
  Future<String?> extractContent() async {
    try {
      final res = await _controller.executeScript(kExtractContentJs);
      if (res is String && res.trim().isNotEmpty) {
        return res.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 提取当前页面自包含 HTML 快照（内联样式，保留图片/布局）。
  Future<String?> extractHtml() async {
    try {
      final res = await _controller.executeScript(kExtractHtmlJs);
      if (res is String && res.trim().isNotEmpty) {
        return res.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 判断 url 是否为信息流首页（归一化尾斜杠后比较）。
  bool _isFeed(String url) {
    if (url.isEmpty) return false;
    return _norm(url) == _norm(_feedUrl);
  }

  String _norm(String u) {
    var s = u.trim();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// 汇总当前 URL + 标题并上报（用包内置流，不执行脚本，避免原生错误）。
  void _notifyPageInfo() {
    if (_currentUrl.isEmpty) return;
    widget.onPageInfoChanged?.call(WebPageInfo(
      url: _currentUrl,
      title: _currentTitle.isEmpty ? widget.source.title : _currentTitle,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final onDetail = !_isFeed(_currentUrl);
    return Stack(
      children: [
        Positioned.fill(child: Webview(_controller)),
        if (_isLoading && !_hasError)
          const Center(child: CircularProgressIndicator()),
        if (_hasError)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('页面加载失败', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _hasError = false);
                    _init();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        // 详情页（非首页）右下角悬浮"返回信息流"按钮，点击回到信息流并恢复位置。
        if (onDetail)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'back_to_feed_${widget.source.id}',
              tooltip: '返回信息流',
              backgroundColor: const Color(0xFF0D9488), // teal-600 主题色
              foregroundColor: Colors.white,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
              ),
              onPressed: _backToFeedWithFeedback,
              icon: const Icon(Icons.view_agenda_outlined, size: 22),
              label: const Text('返回信息流', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  void _backToFeedWithFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在返回信息流…'),
        duration: Duration(seconds: 1),
      ),
    );
    backToFeed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// 工厂：Windows 上返回 WebView2 实现；其他桌面/移动平台回退到主包实现。
///
/// 注意：本文件通过 `dart.library.io` 条件导入被编译进所有 io 平台
/// （Windows / Android / iOS），因此必须在运行时用 Platform.isWindows
/// 精确区分，避免在 Android / iOS 上错误使用 WebView2 实现。
PlatformWebView createPlatformWebView() =>
    Platform.isWindows ? WindowsWebView() : mobile.createPlatformWebView();

/// 全屏详情页：用独立 WebviewController 加载 URL，信息流页面保持不变。
/// 返回时直接 pop，信息流滚动位置完全保留，不需要保存/恢复。
class _DetailPage extends StatefulWidget {
  final String url;
  const _DetailPage({required this.url});

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  late final WebviewController _controller;
  bool _isLoading = true;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _controller = WebviewController();
    _initDetail();
  }

  Future<void> _initDetail() async {
    await _controller.initialize();
    _controller.loadingState.listen((state) {
      if (!mounted) return;
      if (state == LoadingState.navigationCompleted) {
        setState(() => _isLoading = false);
      }
    });
    _controller.title.listen((t) {
      if (!mounted) return;
      setState(() => _title = t);
    });
    await _controller.loadUrl(widget.url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title.isNotEmpty ? _title : '详情',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        leading: IconButton(
          tooltip: '返回信息流',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: '在浏览器中打开',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () {
              // 用系统浏览器打开
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Webview(_controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

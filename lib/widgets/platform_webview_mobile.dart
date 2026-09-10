import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/web_content_extractor.dart';
import 'platform_webview_interface.dart';

/// Android / iOS / Web 平台实现：基于 webview_flutter 官方主包。
///
/// 采用「全屏新页面打开详情」的模态窗方案：
/// - 信息流页面注入 JS 拦截所有链接点击；
/// - 点击链接 → 通过 JavaScriptChannel 把 URL 发给 Dart 端；
/// - Dart 端 push 一个全屏 _DetailPage（独立 WebViewController 加载 URL）；
/// - 返回时直接 pop，信息流页面的滚动位置 100% 保留，不需要保存/恢复。
class MobileWebView implements PlatformWebView {
  _MobileWebViewImplState? _state;

  @override
  Widget build(
    FeedSource source, {
    ValueChanged<WebPageInfo>? onPageInfoChanged,
  }) {
    return _MobileWebViewImpl(
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

class _MobileWebViewImpl extends StatefulWidget {
  final FeedSource source;
  final ValueChanged<WebPageInfo>? onPageInfoChanged;
  final ValueChanged<_MobileWebViewImplState> onStateReady;

  const _MobileWebViewImpl({
    required this.source,
    required this.onPageInfoChanged,
    required this.onStateReady,
  });

  @override
  State<_MobileWebViewImpl> createState() => _MobileWebViewImplState();
}

class _MobileWebViewImplState extends State<_MobileWebViewImpl> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  late final String _feedUrl = widget.source.url;
  String _currentUrl = '';
  String _currentTitle = '';

  @override
  void initState() {
    super.initState();
    widget.onStateReady(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // JavaScriptChannel：接收页面滚动位置 + 链接点击导航请求。
      ..addJavaScriptChannel(
        'FluxioBridge',
        onMessageReceived: (message) {
          if (!mounted) return;
          _onBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            final url = change.url ?? '';
            if (!mounted) return;
            _currentUrl = url;
            _notifyPageInfo();
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _onPageLoaded();
            _capturePageInfo();
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _hasError = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.source.url));
  }

  /// 处理 FluxioBridge 消息：兼容 scroll（滚动位置上报）和 navigate（链接点击）。
  void _onBridgeMessage(String raw) {
    try {
      final msg = jsonDecode(raw);
      if (msg is! Map) return;
      // 导航请求：用户点击链接 → 打开全屏新页面加载详情
      if (msg['fluxio'] == 'navigate') {
        final url = msg['url'];
        if (url is String && url.isNotEmpty) {
          _showDetailPage(url);
        }
        return;
      }
    } catch (_) {}
  }

  Future<void> _onPageLoaded() async {
    // 注入滚动监听 + 链接点击拦截（同一脚本同时处理两种消息）。
    try {
      await _controller.runJavaScript(kInstallScrollListenerJs);
    } catch (_) {}
  }

  /// 打开全屏详情页：用独立 WebViewController 加载 URL，信息流页面保持不变。
  /// 返回时直接 pop，信息流滚动位置完全保留，不需要保存/恢复。
  void _showDetailPage(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _MobileDetailPage(url: url)),
    );
  }

  Future<void> backToFeed() async {
    try {
      await _controller.loadRequest(Uri.parse(_feedUrl));
    } catch (_) {}
  }

  Future<String?> extractContent() async {
    try {
      final raw =
          await _controller.runJavaScriptReturningResult(kExtractContentJs);
      final s = _decodeJsString(raw);
      if (s != null && s.trim().isNotEmpty) return s.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> extractHtml() async {
    try {
      final raw =
          await _controller.runJavaScriptReturningResult(kExtractHtmlJs);
      final s = _decodeJsString(raw);
      if (s != null && s.trim().isNotEmpty) return s.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// runJavaScriptReturningResult 返回 JSON 编码字符串，先解码再取文本。
  String? _decodeJsString(Object? raw) {
    if (raw == null) return null;
    try {
      final v = raw is String ? jsonDecode(raw) : raw;
      if (v is String) return v;
    } catch (_) {
      if (raw is String) return raw;
    }
    return null;
  }

  Future<void> _capturePageInfo() async {
    try {
      final url = await _controller.currentUrl();
      final title = await _controller.getTitle();
      if (mounted) {
        _currentTitle = title ?? '';
        widget.onPageInfoChanged?.call(WebPageInfo(
          url: url ?? '',
          title: title ?? '',
        ));
      }
    } catch (_) {}
  }

  void _notifyPageInfo() {
    if (_currentUrl.isEmpty) return;
    widget.onPageInfoChanged?.call(WebPageInfo(
      url: _currentUrl,
      title: _currentTitle.isEmpty ? widget.source.title : _currentTitle,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
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
                    _controller.reload();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 全屏详情页：用独立 WebViewController 加载 URL，信息流页面保持不变。
/// 返回时直接 pop，信息流滚动位置完全保留。
class _MobileDetailPage extends StatefulWidget {
  final String url;
  const _MobileDetailPage({required this.url});

  @override
  State<_MobileDetailPage> createState() => _MobileDetailPageState();
}

class _MobileDetailPageState extends State<_MobileDetailPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _captureTitle();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _captureTitle() async {
    try {
      final title = await _controller.getTitle();
      if (mounted && title != null && title.isNotEmpty) {
        setState(() => _title = title);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title.isEmpty ? '详情' : _title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: const Color(0xFF0D9488), // teal-600 主题色
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () {
              // 预留：外部浏览器打开
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// 工厂：返回移动平台实现。
PlatformWebView createPlatformWebView() => MobileWebView();

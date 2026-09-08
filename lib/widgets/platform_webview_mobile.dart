import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/web_content_extractor.dart';
import 'platform_webview_interface.dart';

/// Android / iOS / Web 平台实现：基于 webview_flutter 官方主包。
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
  int _feedScrollY = 0;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    widget.onStateReady(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 接收页面滚动监听通过 JS channel 上报的位置。
      ..addJavaScriptChannel(
        'FluxioBridge',
        onMessageReceived: (message) {
          if (!mounted) return;
          try {
            final msg = jsonDecode(message.message);
            if (msg is Map &&
                msg['fluxio'] == 'scroll' &&
                _isFeed(_currentUrl)) {
              final y = msg['y'];
              if (y is num) _feedScrollY = y.toInt();
            }
          } catch (_) {}
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

  Future<void> _onPageLoaded() async {
    // 注入滚动监听（页面滚动时实时上报位置）。
    try {
      await _controller.runJavaScriptReturningResult(kInstallScrollListenerJs);
    } catch (_) {}
    _scheduleFeedRestore();
  }

  /// 回到信息流首页后的滚动恢复调度：容器自适应 + 多次重试
  /// （SPA 内容异步渲染、容器高度动态增长），并兜底 goBack/bfcache 场景。
  void _scheduleFeedRestore() {
    if (!_isFeed(_currentUrl) || _feedScrollY <= 0) return;
    const delays = [200, 500, 1200];
    for (final d in delays) {
      Future.delayed(Duration(milliseconds: d), () async {
        if (!mounted) return;
        if (!_isFeed(_currentUrl)) return;
        try {
          await _controller
              .runJavaScriptReturningResult(kRestoreScrollJs(_feedScrollY));
        } catch (_) {}
      });
    }
  }

  Future<void> backToFeed() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        _scheduleFeedRestore();
        return;
      }
      await _controller.loadRequest(Uri.parse(_feedUrl));
      _scheduleFeedRestore();
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

  bool _isFeed(String url) {
    if (url.isEmpty) return false;
    return _norm(url) == _norm(_feedUrl);
  }

  String _norm(String u) {
    var s = u.trim();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
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
      title: widget.source.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final onDetail = !_isFeed(_currentUrl);
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
        // 详情页（非首页）右下角悬浮"返回信息流"按钮，点击回到信息流并恢复位置。
        if (onDetail)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'back_to_feed_${widget.source.id}',
              tooltip: '返回信息流',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1F2937),
              elevation: 6,
              shape: const CircleBorder(
                side: BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
              ),
              onPressed: _backToFeedWithFeedback,
              child: const Icon(Icons.view_agenda_outlined, size: 20),
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
}

/// 工厂：返回移动平台实现。
PlatformWebView createPlatformWebView() => MobileWebView();

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/clip_record.dart';
import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/clip_history_store.dart';
import '../services/ima_service.dart';
import '../services/obsidian_store.dart';
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
  final _obsidianStore = ObsidianStore();
  final _imaService = ImaService();
  final _clipHistoryStore = ClipHistoryStore();
  bool _isLoading = true;
  bool _saving = false;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FluxioGesture',
        onMessageReceived: _onGestureMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _captureTitle();
            _injectGestureDetector();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// 处理来自 WebView 的手势消息。
  void _onGestureMessage(JavaScriptMessage message) {
    final action = message.message;
    if (action == 'double_tap') {
      // 双击收藏
      _saveCurrentPage();
      _showGestureHint('双击已收藏');
    } else if (action == 'swipe_left') {
      // 左滑返回
      if (mounted) Navigator.pop(context);
    } else if (action == 'swipe_right') {
      // 右滑也返回（详情页没有上一篇）
      if (mounted) Navigator.pop(context);
    }
  }

  /// 显示手势操作提示（顶部浮动提示）。
  void _showGestureHint(String text) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 16,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1200), () {
      entry.remove();
    });
  }

  /// 注入手势检测 JavaScript。
  Future<void> _injectGestureDetector() async {
    const js = '''
(function() {
  if (window.__fluxioGestureInjected) return;
  window.__fluxioGestureInjected = true;

  var lastTapTime = 0;
  var lastTapX = 0;
  var lastTapY = 0;
  var touchStartX = 0;
  var touchStartY = 0;
  var touchStartTime = 0;
  var isSwiping = false;

  // 双击检测
  document.addEventListener('touchend', function(e) {
    var now = Date.now();
    var touch = e.changedTouches[0];
    var x = touch.clientX;
    var y = touch.clientY;

    if (now - lastTapTime < 300 &&
        Math.abs(x - lastTapX) < 50 &&
        Math.abs(y - lastTapY) < 50) {
      // 双击
      if (typeof FluxioGesture !== 'undefined') {
        FluxioGesture.postMessage('double_tap');
      }
      lastTapTime = 0;
    } else {
      lastTapTime = now;
      lastTapX = x;
      lastTapY = y;
    }
  }, { passive: true });

  // 横向滑动检测
  document.addEventListener('touchstart', function(e) {
    var touch = e.touches[0];
    touchStartX = touch.clientX;
    touchStartY = touch.clientY;
    touchStartTime = Date.now();
    isSwiping = false;
  }, { passive: true });

  document.addEventListener('touchmove', function(e) {
    var touch = e.touches[0];
    var deltaX = touch.clientX - touchStartX;
    var deltaY = touch.clientY - touchStartY;

    // 如果水平移动距离大于垂直移动距离，且超过阈值，认为是横向滑动
    if (Math.abs(deltaX) > 30 && Math.abs(deltaX) > Math.abs(deltaY) * 1.5) {
      isSwiping = true;
    }
  }, { passive: true });

  document.addEventListener('touchend', function(e) {
    if (!isSwiping) return;

    var touch = e.changedTouches[0];
    var deltaX = touch.clientX - touchStartX;
    var deltaY = touch.clientY - touchStartY;
    var deltaTime = Date.now() - touchStartTime;

    // 滑动距离超过 80px，时间小于 500ms，且水平距离大于垂直距离
    if (Math.abs(deltaX) > 80 &&
        deltaTime < 500 &&
        Math.abs(deltaX) > Math.abs(deltaY)) {
      if (typeof FluxioGesture !== 'undefined') {
        if (deltaX < 0) {
          FluxioGesture.postMessage('swipe_left');
        } else {
          FluxioGesture.postMessage('swipe_right');
        }
      }
    }

    isSwiping = false;
  }, { passive: true });
})();
''';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _captureTitle() async {
    try {
      final title = await _controller.getTitle();
      if (mounted && title != null && title.isNotEmpty) {
        setState(() => _title = title);
      }
    } catch (_) {}
  }

  /// 收藏当前页面：立即返回成功，实际保存/同步在后台静默执行。
  Future<void> _saveCurrentPage() async {
    if (_saving) return;
    final url = widget.url;
    final title = _title.isEmpty ? url : _title;

    // 检查是否至少配置了一个收藏目标（Obsidian 或 ima）
    final vaultPath = await _obsidianStore.getVaultPath();
    final obsidianConfigured = vaultPath != null && vaultPath.isNotEmpty;
    final imaEnabled = await _imaService.getEnabled();
    final imaConfigured = imaEnabled && await _imaService.isConfigured();

    if (!obsidianConfigured && !imaConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置 Obsidian vault 路径或 ima 知识库')),
        );
      }
      return;
    }

    // 确定收藏来源标签
    final source = obsidianConfigured && imaConfigured
        ? 'Obsidian + ima'
        : obsidianConfigured
            ? 'Obsidian'
            : 'ima';

    // 1. 立即创建 pending 状态的收藏记录
    final recordId = ClipHistoryStore.generateId();
    final record = ClipRecord(
      id: recordId,
      title: title,
      url: url,
      source: source,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    await _clipHistoryStore.add(record);

    // 2. 立即显示"已加入收藏队列"
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已加入收藏队列（$source），后台正在保存...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // 3. 后台静默执行实际的保存和同步（不阻塞 UI）
    _executeSaveInBackground(
      recordId: recordId,
      url: url,
      title: title,
      obsidianConfigured: obsidianConfigured,
      imaConfigured: imaConfigured,
    );
  }

  /// 后台执行实际的保存和同步操作。
  Future<void> _executeSaveInBackground({
    required String recordId,
    required String url,
    required String title,
    required bool obsidianConfigured,
    required bool imaConfigured,
  }) async {
    try {
      // 提取当前页面 HTML + 纯文本
      String? html;
      String? text;
      try {
        final rawHtml = await _controller.runJavaScriptReturningResult(kExtractHtmlJs);
        html = _decodeJsString(rawHtml);
        final rawText = await _controller.runJavaScriptReturningResult(kExtractContentJs);
        text = _decodeJsString(rawText);
      } catch (_) {}

      final info = WebPageInfo(url: url, title: title, content: text, html: html);

      // 1. 保存到 Obsidian（如果已配置）
      String? obsidianPath;
      String? obsidianError;
      if (obsidianConfigured) {
        try {
          final files = await _obsidianStore.saveClip(info, sourceTitle: 'Fluxio 详情页');
          obsidianPath = files.first.path;
        } catch (e) {
          obsidianError = '$e';
        }
      }

      // 2. 同步到 ima（如果已配置）
      String? imaError;
      if (imaConfigured) {
        try {
          await _syncToImaSilent(info);
        } catch (e) {
          imaError = '$e';
        }
      }

      // 3. 更新记录状态
      final hasError = obsidianError != null || imaError != null;
      final status = hasError ? 'failed' : 'success';
      final errorMsg = hasError
          ? [
              if (obsidianError != null) 'Obsidian: $obsidianError',
              if (imaError != null) 'ima: $imaError',
            ].join('; ')
          : null;

      await _clipHistoryStore.updateStatus(
        recordId,
        status: status,
        localPath: obsidianPath,
        errorMessage: errorMsg,
      );

      // 4. 显示最终结果（如果页面还在）
      if (mounted) {
        final msg = hasError ? '收藏完成（部分失败）' : '收藏完成 ✓';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      // 兜底：更新为失败
      await _clipHistoryStore.updateStatus(
        recordId,
        status: 'failed',
        errorMessage: '$e',
      );
    }
  }

  /// 异步同步到 ima 知识库：直接上传文章内容（Markdown），附注原文链接。
  Future<void> _syncToIma(WebPageInfo info) async {
    try {
      final enabled = await _imaService.getEnabled();
      if (!enabled) return;
      final configured = await _imaService.isConfigured();
      if (!configured) return;

      // 直接构建 Markdown 内容（包含正文 + 原文链接附注）
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final sb = StringBuffer();
      sb.writeln('---');
      sb.writeln('title: "${info.title.replaceAll('"', "'")}"');
      sb.writeln('source: "Fluxio 详情页"');
      sb.writeln('url: "${info.url}"');
      sb.writeln('saved: "$dateStr"');
      sb.writeln('tags: [fluxio, inbox]');
      sb.writeln('---');
      sb.writeln();
      sb.writeln('# ${info.title}');
      sb.writeln();
      sb.writeln('> 原文链接：[${info.url}](${info.url})');
      sb.writeln('> 收藏时间：$dateStr');
      sb.writeln('> 收藏来源：Fluxio 信息流');
      sb.writeln();
      sb.writeln('---');
      sb.writeln();
      if (info.content != null && info.content!.isNotEmpty) {
        sb.writeln(info.content);
      } else {
        sb.writeln('（正文提取失败，请点击原文链接查看完整内容）');
      }
      final fileName = '${dateStr}-${info.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.md';
      final result = await _imaService.uploadMarkdown(fileName: fileName, content: sb.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success ? 'ima：已上传文章内容' : 'ima 同步失败：${result.message}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {}
  }

  /// 静默同步到 ima（不显示 SnackBar，后台执行用）。
  /// 返回 true 表示成功，false 表示失败。
  Future<bool> _syncToImaSilent(WebPageInfo info) async {
    try {
      final enabled = await _imaService.getEnabled();
      if (!enabled) return false;
      final configured = await _imaService.isConfigured();
      if (!configured) return false;

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final sb = StringBuffer();
      sb.writeln('---');
      sb.writeln('title: "${info.title.replaceAll('"', "'")}"');
      sb.writeln('source: "Fluxio 详情页"');
      sb.writeln('url: "${info.url}"');
      sb.writeln('saved: "$dateStr"');
      sb.writeln('tags: [fluxio, inbox]');
      sb.writeln('---');
      sb.writeln();
      sb.writeln('# ${info.title}');
      sb.writeln();
      sb.writeln('> 原文链接：[${info.url}](${info.url})');
      sb.writeln('> 收藏时间：$dateStr');
      sb.writeln('> 收藏来源：Fluxio 信息流');
      sb.writeln();
      sb.writeln('---');
      sb.writeln();
      if (info.content != null && info.content!.isNotEmpty) {
        sb.writeln(info.content);
      } else {
        sb.writeln('（正文提取失败，请点击原文链接查看完整内容）');
      }
      final fileName = '${dateStr}-${info.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.md';
      final result = await _imaService.uploadMarkdown(fileName: fileName, content: sb.toString());
      return result.success;
    } catch (_) {
      return false;
    }
  }

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
          // 收藏按钮
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.bookmark_border),
            tooltip: '收藏到 Obsidian',
            onPressed: _saving ? null : _saveCurrentPage,
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

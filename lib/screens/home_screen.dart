import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show inboxServer;
import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/ima_service.dart';
import '../services/obsidian_store.dart';
import '../services/source_store.dart';
import '../widgets/source_webview.dart';
import 'clipboard_history_screen.dart';
import 'manage_sources_screen.dart';
import 'settings_screen.dart';

/// 主页：横向多源信息流。
///
/// 核心交互：PageView 横向滑动切换不同信息源，
/// 顶部 TabBar 显示当前源，右上角进入源管理/设置/收藏。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = SourceStore();
  final _obsidianStore = ObsidianStore();
  final _imaService = ImaService();

  List<FeedSource> _sources = [];
  bool _loading = true;

  /// 当前可见 Tab 的索引（用于定位"当前源"）。
  int _currentIndex = 0;

  /// 各源最近一次上报的页面信息：source.id -> WebPageInfo。
  final Map<String, WebPageInfo> _pageInfos = {};

  /// 各源的 WebView 控制句柄：source.id -> controller（稳定绑定，供收藏/返回用）。
  final Map<String, SourceWebViewController> _controllersBySource = {};

  /// 是否正在收藏（防止连点）。
  bool _saving = false;

  /// 剪贴板 URL 捕获：上次看到的内容（防重复弹条）。
  Timer? _clipboardTimer;
  String? _lastClipboard;
  bool _clipboardPromptVisible = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _startClipboardWatch();
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    super.dispose();
  }

  /// 每 2 秒看一次剪贴板：出现新的 http(s) 链接 → 弹条「收藏到 Fluxio？」。
  void _startClipboardWatch() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_clipboardPromptVisible || !mounted) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || text == _lastClipboard) {
        _lastClipboard = text.isEmpty ? _lastClipboard : text;
        return;
      }
      _lastClipboard = text;
      final url = _extractUrl(text);
      if (url == null) return;
      if (!context.mounted) return;
      _clipboardPromptVisible = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📥 检测到链接：${url.length > 40 ? '${url.substring(0, 40)}…' : url}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '收藏',
            onPressed: () async {
              final result = await inboxServer.saveUrl(url, source: '剪贴板');
              _clipboardPromptVisible = false;
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(result.ok
                    ? '已收藏 → ${result.record ?? '收件箱'}'
                    : '收藏失败：${result.error}'),
                duration: const Duration(seconds: 3),
              ));
            },
          ),
          onVisible: () {
            // 条消失后允许下一次提示
            Future.delayed(const Duration(seconds: 10), () {
              _clipboardPromptVisible = false;
            });
          },
        ),
      );
    });
  }

  String? _extractUrl(String text) {
    // 普通字符串 + 转义：单引号字符类、中文标点均合法
    final match =
        RegExp('https?://[^\\s<>"\'，。；]+').firstMatch(text);
    return match?.group(0);
  }

  Future<void> _reload() async {
    final list = await _store.load();
    if (mounted) {
      setState(() {
        _sources = list;
        _loading = false;
      });
    }
  }

  /// 当前可见的信息源（只包含启用的源，Tab 与索引均基于它）。
  List<FeedSource> get _activeSources =>
      _sources.where((s) => s.enabled).toList();

  /// 打开源管理页，返回后刷新源列表。
  Future<void> _openManage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManageSourcesScreen(store: _store)),
    );
    _reload();
  }

  /// 打开设置页。
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  /// 打开收藏历史页。
  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClipboardHistoryScreen()),
    );
  }

  /// 收藏当前 Tab 页面到 Obsidian。
  ///
  /// 会先实时提取当前页面正文，把内容详情写入 Markdown；
  /// 提取失败时回退为仅收藏链接。
  Future<void> _saveCurrentToObsidian() async {
    if (_saving || _activeSources.isEmpty) return;
    final source = _activeSources[_currentIndex];

    // RSS 订阅源在"文章列表"态：提示用列表项右侧收藏按钮，或打开文章后收藏。
    final controller = _controllersBySource[source.id];
    if (source.isRss && controller?.isRssListMode == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RSS 订阅源请在文章列表点右侧 ☆ 收藏，或打开文章后收藏'),
        ),
      );
      return;
    }

    final info = _pageInfos[source.id];
    if (info == null || info.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前页面还没加载好，请稍后再收藏')),
      );
      return;
    }

    final vaultPath = await _obsidianStore.getVaultPath();
    if (vaultPath == null || vaultPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请先配置 Obsidian vault 路径'),
            action: SnackBarAction(
              label: '去设置',
              onPressed: _openSettings,
            ),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      // 实时提取当前页面纯文本 + 完整 HTML 快照（保留样式）。
      final html = await controller?.extractHtml();
      final text = await controller?.extractContent();
      final enriched = WebPageInfo(
        url: info.url,
        title: info.title,
        content: text,
        html: html,
      );

      final files = await _obsidianStore.saveClip(
        enriched,
        sourceTitle: source.title,
      );

      // 异步同步到 ima 知识库（不阻塞 Obsidian 收藏反馈）
      _syncToIma(enriched, source.title);

      if (mounted) {
        final hasHtml = html != null && html.isNotEmpty;
        final dirPath = files.first.parent.path;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasHtml
                  ? '已收藏：完整网页快照 + Markdown 摘要 → $dirPath'
                  : '已收藏（仅链接）→ $dirPath',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收藏失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 异步同步收藏内容到 ima 知识库。
  ///
  /// 优先使用 importUrls（ima 自动抓取网页内容，质量更好），
  /// URL 无效时回退到 uploadMarkdown（上传本地提取的 Markdown）。
  Future<void> _syncToIma(WebPageInfo info, String sourceTitle) async {
    try {
      final enabled = await _imaService.getEnabled();
      if (!enabled) return;
      final configured = await _imaService.isConfigured();
      if (!configured) return;

      // 优先用 URL 导入（ima 自动抓取完整网页内容）
      final url = info.url.trim();
      final isValidUrl = url.startsWith('http://') || url.startsWith('https://');

      if (isValidUrl) {
        final result = await _imaService.importUrls(urls: [url]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.success ? 'ima：${result.message}' : 'ima 同步失败：${result.message}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // URL 无效时回退到上传 Markdown
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final sb = StringBuffer();
      sb.writeln('---');
      sb.writeln('title: "${info.title.replaceAll('"', "'")}"');
      sb.writeln('source: "$sourceTitle"');
      sb.writeln('url: "${info.url}"');
      sb.writeln('saved: "$dateStr"');
      sb.writeln('tags: [fluxio, inbox]');
      sb.writeln('---');
      sb.writeln();
      sb.writeln('# ${info.title}');
      sb.writeln();
      sb.writeln('> 来源：[$sourceTitle](${info.url})');
      sb.writeln('> 收藏时间：$dateStr');
      sb.writeln();
      if (info.content != null && info.content!.isNotEmpty) {
        sb.writeln(info.content);
      } else {
        sb.writeln('（正文提取失败，仅收藏链接）');
      }

      final fileName = '${dateStr}-${_sanitizeFileName(info.title)}.md';
      final result = await _imaService.uploadMarkdown(
        fileName: fileName,
        content: sb.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success ? 'ima：${result.message}' : 'ima 同步失败：${result.message}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // ima 同步失败不影响主流程，静默处理
    }
  }

  String _sanitizeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return clean.substring(0, clean.length > 50 ? 50 : clean.length);
  }

  /// 当前 Tab 的 WebView 回到信息流首页（保留之前浏览位置）。
  void _backToFeed() {
    if (_activeSources.isEmpty) return;
    final source = _activeSources[_currentIndex];
    _controllersBySource[source.id]?.backToFeed();
  }

  /// 处理子 WebView 上报的页面信息。
  void _onPageInfoChanged(FeedSource source, WebPageInfo info) {
    if (mounted) {
      setState(() => _pageInfos[source.id] = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_sources.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fluxio')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Fluxio\n横向多源信息流',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '添加多个网页源，左右滑动切换浏览',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openManage,
                icon: const Icon(Icons.add),
                label: const Text('添加信息源'),
              ),
            ],
          ),
        ),
      );
    }

    // 有源但全部停用：提示去管理页启用。
    if (_activeSources.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fluxio')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pause_circle_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                '所有信息源都已停用',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '去管理页启用或添加信息源',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openManage,
                icon: const Icon(Icons.tune),
                label: const Text('管理信息源'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: _activeSources.length,
      child: Builder(builder: (context) {
        // 监听 TabController 的 index 变化（点击或滑动都触发），
        // 更新当前源用于"收藏到 Obsidian"。
        final tc = DefaultTabController.of(context);
        if (tc.index != _currentIndex) {
          // 延迟到下一帧再 setState，避免 build 期间修改状态。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && tc.index != _currentIndex) {
              setState(() => _currentIndex = tc.index);
            }
          });
        }
        final sources = _activeSources;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Fluxio'),
            actions: [
              IconButton(
                tooltip: '回到信息流',
                icon: const Icon(Icons.home_outlined, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: _backToFeed,
              ),
              IconButton(
                tooltip: '收藏到 Obsidian',
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: _saveCurrentToObsidian,
              ),
              IconButton(
                tooltip: '收藏历史',
                icon: const Icon(Icons.history, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: _openHistory,
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: _openSettings,
              ),
              IconButton(
                tooltip: '管理信息源',
                icon: const Icon(Icons.tune, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: _openManage,
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: sources.map((s) => Tab(text: s.title)).toList(),
            ),
          ),
          body: TabBarView(
            children: sources
                .map((s) => SourceWebView(
                      source: s,
                      controller: _controllersBySource
                          .putIfAbsent(s.id, () => SourceWebViewController()),
                      onPageInfoChanged: (info) => _onPageInfoChanged(s, info),
                    ))
                .toList(),
          ),
        );
      }),
    );
  }
}

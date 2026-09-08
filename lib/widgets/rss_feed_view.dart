import 'package:flutter/material.dart';

import '../models/feed_source.dart';
import '../models/web_page_info.dart';
import '../services/obsidian_store.dart';
import '../services/rss_service.dart';

/// RSS/Atom 订阅源的文章列表视图。
///
/// 展示订阅源解析出的结构化文章列表（标题/摘要/时间），支持：
/// - 点击文章 → 由外层 SourceWebView 用 WebView 打开详情
/// - 列表项右侧"收藏"→ 直接把该文章链接 + 摘要存入 Obsidian 收件箱
///   （列表态没有 WebView，不提取正文/HTML，收藏链接级内容）
/// - 下拉刷新
class RssFeedView extends StatefulWidget {
  final FeedSource source;
  final ValueChanged<String> onOpenArticle;

  const RssFeedView({
    super.key,
    required this.source,
    required this.onOpenArticle,
  });

  @override
  State<RssFeedView> createState() => _RssFeedViewState();
}

class _RssFeedViewState extends State<RssFeedView> {
  final _rss = RssService();
  final _obsidian = ObsidianStore();

  List<RssArticle>? _articles;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await _rss.fetch(widget.source.url);
      if (mounted) setState(() => _articles = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _refresh() async {
    await _load();
  }

  /// 收藏列表项：保存该文章链接 + 摘要（列表态无 WebView 提取）。
  Future<void> _save(RssArticle article) async {
    try {
      final vault = await _obsidian.getVaultPath();
      if (vault == null || vault.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先配置 Obsidian vault 路径（右上角设置）'),
          ),
        );
        return;
      }
      await _obsidian.saveClip(
        WebPageInfo(
          url: article.link,
          title: article.title,
          content: article.summary,
        ),
        sourceTitle: widget.source.title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已收藏：${article.title}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '订阅加载失败\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    final articles = _articles;
    if (articles == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (articles.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 12),
          Center(
            child: Text(
              '这个订阅源暂无文章\n下拉刷新试试',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (ctx, index) {
        final a = articles[index];
        return ListTile(
          title: Text(
            a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.summary != null && a.summary!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    a.summary!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (a.pubDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _formatDate(a.pubDate!),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
            ],
          ),
          trailing: IconButton(
            tooltip: '收藏到 Obsidian',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _save(a),
          ),
          onTap: () => widget.onOpenArticle(a.link),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

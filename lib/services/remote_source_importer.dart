import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/feed_source.dart';

/// 远程信息源导入服务：从自定义 URL 下载并解析信息源列表。
///
/// 支持两种格式：
/// - JSON 格式：`[{"title": "...", "url": "...", "group": "...", "type": "web"}, ...]`
/// - Markdown 格式：解析 `## 分组名` 下的 `- [标题](URL)` 列表项
class RemoteSourceImporter {
  /// 从 URL 导入信息源列表。
  ///
  /// 自动检测格式（JSON 或 Markdown）并解析。
  /// 返回解析出的信息源列表。
  static Future<List<FeedSource>> importFromUrl(String url) async {
    // 下载内容
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Fluxio/1.0',
        'Accept': 'application/json, text/plain, text/markdown, */*',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('下载失败：HTTP ${response.statusCode}');
    }

    final content = utf8.decode(response.bodyBytes);

    // 尝试解析为 JSON
    try {
      final json = jsonDecode(content);
      if (json is List) {
        return _parseJsonList(json);
      }
      if (json is Map && json['sources'] is List) {
        return _parseJsonList(json['sources'] as List);
      }
    } catch (_) {
      // 不是 JSON，继续尝试 Markdown
    }

    // 尝试解析为 Markdown
    final markdownSources = _parseMarkdown(content);
    if (markdownSources.isNotEmpty) {
      return markdownSources;
    }

    throw Exception('无法解析文件格式，请确保是 JSON 或 Markdown 格式的信息源列表');
  }

  /// 解析 JSON 列表为信息源。
  static List<FeedSource> _parseJsonList(List<dynamic> list) {
    final sources = <FeedSource>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map<String, dynamic>) continue;

      final title = (item['title'] ?? item['name'] ?? '').toString();
      final url = (item['url'] ?? item['link'] ?? '').toString();
      if (title.isEmpty || url.isEmpty) continue;

      final group = (item['group'] ?? item['category'] ?? '导入').toString();
      final type = (item['type'] ?? kSourceTypeWeb).toString();

      sources.add(FeedSource(
        id: 'remote-${DateTime.now().millisecondsSinceEpoch}-$i',
        title: title,
        url: url,
        group: group,
        type: type == 'rss' ? kSourceTypeRss : kSourceTypeWeb,
      ));
    }
    return sources;
  }

  /// 解析 Markdown 内容为信息源。
  ///
  /// 支持的格式：
  /// ```markdown
  /// ## 分组名
  /// - [标题](URL)
  /// - [标题](URL)
  ///
  /// ## 另一个分组
  /// - [标题](URL)
  /// ```
  static List<FeedSource> _parseMarkdown(String content) {
    final sources = <FeedSource>[];
    final lines = const LineSplitter().convert(content);

    String currentGroup = '导入';
    var index = 0;

    for (final line in lines) {
      final trimmed = line.trim();

      // 检测分组标题：## 分组名 或 ### 分组名
      final groupMatch = RegExp(r'^#{2,3}\s+(.+)$').firstMatch(trimmed);
      if (groupMatch != null) {
        currentGroup = groupMatch.group(1)!.trim();
        continue;
      }

      // 检测列表项中的链接：- [标题](URL) 或 * [标题](URL)
      final linkMatch = RegExp(r'^[-*]\s+\[([^\]]+)\]\(([^)]+)\)').firstMatch(trimmed);
      if (linkMatch != null) {
        final title = linkMatch.group(1)!.trim();
        final url = linkMatch.group(2)!.trim();

        if (title.isNotEmpty && url.isNotEmpty && url.startsWith('http')) {
          // 判断是否是 RSS 源
          final isRss = url.contains('/feed') ||
              url.contains('/rss') ||
              url.contains('feed.xml') ||
              url.contains('rss.xml') ||
              title.toLowerCase().contains('rss') ||
              title.toLowerCase().contains('订阅');

          sources.add(FeedSource(
            id: 'remote-${DateTime.now().millisecondsSinceEpoch}-$index',
            title: title,
            url: url,
            group: currentGroup,
            type: isRss ? kSourceTypeRss : kSourceTypeWeb,
          ));
          index++;
        }
      }
    }

    return sources;
  }
}

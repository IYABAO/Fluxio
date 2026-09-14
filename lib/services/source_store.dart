import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_source.dart';
import '../models/preset_sources.dart';

/// 本地存储服务：把信息源列表持久化到 shared_preferences。
///
/// MVP 阶段纯客户端本地存储，不依赖后端。
class SourceStore {
  static const _prefsKey = 'fluxio.sources.v1';
  static const _seedDoneKey = 'fluxio.seed.v1';

  /// 首次启动时预置的示例源（提升开箱体验）。
  static const List<FeedSource> _seedSources = [
    FeedSource(
      id: 'seed-daheiai',
      title: '大黑AI速报',
      url: 'https://news.daheiai.com/',
    ),
    FeedSource(
      id: 'seed-hn',
      title: 'Hacker News',
      url: 'https://news.ycombinator.com/',
    ),
    FeedSource(
      id: 'seed-blog',
      title: 'PLBear 博客',
      url: 'https://www.plbear.com/',
    ),
  ];

  /// 读取全部信息源；首次使用时自动写入示例源。
  Future<List<FeedSource>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_seedDoneKey) ?? false)) {
      await prefs.setBool(_seedDoneKey, true);
      await prefs.setString(
          _prefsKey, jsonEncode(_seedSources.map((s) => s.toJson()).toList()));
    }

    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FeedSource.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏时返回空列表，避免崩溃。
      return [];
    }
  }

  /// 保存全部信息源（覆盖写）。
  Future<void> save(List<FeedSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(sources.map((s) => s.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  /// 一键导入常用信息源预设。
  ///
  /// 导入逻辑：
  /// - 相同 URL 的源：覆盖更新（标题、分组、类型），保留原有的启用状态和 id
  /// - 不同 URL 的源：增量添加
  ///
  /// 返回导入结果：新增数量、覆盖数量。
  Future<ImportResult> importPresets() async {
    return importSources(PresetSources.all);
  }

  /// 导入外部信息源列表（通用方法）。
  ///
  /// 导入逻辑：
  /// - 相同 URL 的源：覆盖更新（标题、分组、类型），保留原有的启用状态和 id
  /// - 不同 URL 的源：增量添加
  ///
  /// [sources] 为要导入的信息源列表。
  /// 返回导入结果：新增数量、覆盖数量。
  Future<ImportResult> importSources(List<FeedSource> sources) async {
    final existing = await load();

    var added = 0;
    var updated = 0;

    // 用 URL 建立现有源的索引（规范化 URL：去掉末尾斜杠，转小写）
    final existingByUrl = <String, int>{};
    for (var i = 0; i < existing.length; i++) {
      final key = _normalizeUrl(existing[i].url);
      existingByUrl[key] = i;
    }

    final result = List<FeedSource>.from(existing);

    for (final source in sources) {
      final key = _normalizeUrl(source.url);
      final existingIndex = existingByUrl[key];

      if (existingIndex != null) {
        // 相同 URL：覆盖更新，保留原有的启用状态和 id
        final old = result[existingIndex];
        result[existingIndex] = old.copyWith(
          title: source.title,
          url: source.url,
          group: source.group,
          type: source.type,
        );
        updated++;
      } else {
        // 不同 URL：增量添加
        result.add(source);
        existingByUrl[key] = result.length - 1;
        added++;
      }
    }

    await save(result);
    return ImportResult(added: added, updated: updated, total: result.length);
  }

  /// 规范化 URL：去掉末尾斜杠，转小写，用于比较是否相同源。
  static String _normalizeUrl(String url) {
    var u = url.trim().toLowerCase();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

/// 导入结果。
class ImportResult {
  /// 新增数量。
  final int added;

  /// 覆盖更新数量。
  final int updated;

  /// 导入后总数量。
  final int total;

  const ImportResult({
    required this.added,
    required this.updated,
    required this.total,
  });
}

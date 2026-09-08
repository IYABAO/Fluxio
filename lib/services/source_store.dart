import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_source.dart';

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
}

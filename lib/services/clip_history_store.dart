import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/clip_record.dart';

/// 收藏记录存储：统一管理 Obsidian 和 ima 收藏记录。
///
/// 用 SharedPreferences 持久化存储，支持添加、查询、更新状态。
class ClipHistoryStore {
  static const _key = 'fluxio.clip_history.v1';
  static const _maxRecords = 500; // 最多保留 500 条记录

  /// 获取所有收藏记录（按创建时间倒序）。
  Future<List<ClipRecord>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final records = list
          .map((e) => ClipRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 添加一条收藏记录。
  Future<void> add(ClipRecord record) async {
    final records = await getAll();
    records.insert(0, record);
    // 超过最大数量时删除最旧的
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    await _save(records);
  }

  /// 更新记录状态。
  Future<void> updateStatus(
    String id, {
    required String status,
    String? localPath,
    String? errorMessage,
  }) async {
    final records = await getAll();
    final index = records.indexWhere((r) => r.id == id);
    if (index == -1) return;
    records[index] = records[index].copyWith(
      status: status,
      localPath: localPath,
      errorMessage: errorMessage,
    );
    await _save(records);
  }

  /// 删除一条记录。
  Future<void> delete(String id) async {
    final records = await getAll();
    records.removeWhere((r) => r.id == id);
    await _save(records);
  }

  /// 清空所有记录。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 保存到 SharedPreferences。
  Future<void> _save(List<ClipRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    await prefs.setString(_key, json);
  }

  /// 生成唯一 ID。
  static String generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'clip_$now';
  }
}

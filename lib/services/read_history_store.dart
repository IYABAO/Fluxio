import 'package:shared_preferences/shared_preferences.dart';

/// 已读历史管理服务：记录用户已读过的文章 URL。
///
/// 用 SharedPreferences 持久化，最多保留 1000 条已读记录。
class ReadHistoryStore {
  static const _key = 'fluxio.read_history.v1';
  static const _maxRecords = 1000;

  /// 获取所有已读的文章 URL 集合。
  Future<Set<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  /// 判断某个 URL 是否已读。
  Future<bool> isRead(String url) async {
    final all = await getAll();
    return all.contains(_normalize(url));
  }

  /// 标记某个 URL 为已读。
  Future<void> markAsRead(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final normalized = _normalize(url);

    // 如果已经存在，先移除（移到最前面）
    list.remove(normalized);
    // 插入到最前面（最新的在前面）
    list.insert(0, normalized);

    // 超过最大数量时删除最旧的
    if (list.length > _maxRecords) {
      list.removeRange(_maxRecords, list.length);
    }

    await prefs.setStringList(_key, list);
  }

  /// 批量标记多个 URL 为已读。
  Future<void> markAllAsRead(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];

    for (final url in urls) {
      final normalized = _normalize(url);
      list.remove(normalized);
      list.insert(0, normalized);
    }

    if (list.length > _maxRecords) {
      list.removeRange(_maxRecords, list.length);
    }

    await prefs.setStringList(_key, list);
  }

  /// 清除所有已读记录。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 规范化 URL：去掉末尾斜杠，转小写。
  String _normalize(String url) {
    var u = url.trim().toLowerCase();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

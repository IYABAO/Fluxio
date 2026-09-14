import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 剪贴板检测服务（方案C）。
///
/// 功能：
/// - App 启动/前台时检测剪贴板内容
/// - 识别 URL 并弹出收藏确认
/// - 防重复检测（记录上次处理的 URL）
/// - 可在设置中开关
class ClipboardDetector {
  static const _lastClipboardKey = 'fluxio.clipboard.lastUrl.v1';
  static const _enabledKey = 'fluxio.clipboard.enabled.v1';

  /// URL 正则匹配（http/https）。
  static final _urlRegex = RegExp(
    'https?://[^\\s<>"\'\\]\\)]+',
    caseSensitive: false,
  );

  /// 检测剪贴板是否启用。
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true; // 默认启用
  }

  /// 设置剪贴板检测开关。
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// 获取上次处理的 URL（防重复）。
  Future<String?> getLastProcessedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastClipboardKey);
  }

  /// 记录已处理的 URL。
  Future<void> markAsProcessed(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastClipboardKey, url);
  }

  /// 检测剪贴板内容，返回提取到的 URL（如果有）。
  ///
  /// 返回 null 表示：
  /// - 剪贴板检测未启用
  /// - 剪贴板为空
  /// - 剪贴板内容不是 URL
  /// - 该 URL 已经处理过（防重复）
  Future<String?> detect() async {
    // 1. 检查是否启用
    if (!await isEnabled()) return null;

    // 2. 读取剪贴板内容
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.trim().isEmpty) {
      return null;
    }

    final text = data.text!.trim();

    // 3. 提取 URL（支持文本中包含 URL 的情况）
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;

    final url = match.group(0)!;

    // 4. 防重复：如果和上次处理的 URL 相同，不重复提示
    final lastUrl = await getLastProcessedUrl();
    if (lastUrl != null && _normalizeUrl(lastUrl) == _normalizeUrl(url)) {
      return null;
    }

    return url;
  }

  /// 规范化 URL（去掉末尾斜杠，转小写，用于比较）。
  String _normalizeUrl(String url) {
    var normalized = url.trim().toLowerCase();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 从分享文本中提取 URL 和标题。
  ///
  /// 微信/头条/浏览器分享的格式通常是：
  /// - "标题 https://example.com"
  /// - "https://example.com 标题"
  /// - 纯 URL
  ///
  /// 返回 (url, title)，title 可能为 null。
  (String url, String? title) extractUrlAndTitle(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) {
      return (text.trim(), null);
    }

    final url = match.group(0)!;
    final title = text.replaceAll(url, '').trim();

    return (url, title.isEmpty ? null : title);
  }
}

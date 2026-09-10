import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 微信公众号同步服务。
///
/// 功能：把博客文章 / Fluxio 收藏内容同步到微信公众号「福清而不淡」。
///
/// 接入方式：
/// 1. 公众号后台 → 开发 → 基本配置 → 获取 AppID 和 AppSecret
/// 2. 配置 IP 白名单（需要把服务器 IP 加入白名单）
/// 3. 调用本服务上传图文素材 / 群发
///
/// 注意：
/// - 订阅号只有部分 API 权限，群发需通过「发表」接口
/// - 服务号可直接使用群发接口
/// - Access Token 有效期 7200 秒，需缓存并自动刷新
class WechatOfficialService {
  static const String _kAppId = 'wechat_app_id';
  static const String _kAppSecret = 'wechat_app_secret';
  static const String _kAccessToken = 'wechat_access_token';
  static const String _kTokenExpiresAt = 'wechat_token_expires_at';

  static const String _baseUrl = 'https://api.weixin.qq.com';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── 配置读写 ──────────────────────────────────────────────

  Future<String?> getAppId() async => (await _sp).getString(_kAppId);
  Future<void> setAppId(String v) async => (await _sp).setString(_kAppId, v);

  Future<String?> getAppSecret() async => (await _sp).getString(_kAppSecret);
  Future<void> setAppSecret(String v) async =>
      (await _sp).setString(_kAppSecret, v);

  Future<bool> isConfigured() async {
    final appId = await getAppId();
    final appSecret = await getAppSecret();
    return appId != null && appId.isNotEmpty &&
           appSecret != null && appSecret.isNotEmpty;
  }

  // ── Access Token 管理 ─────────────────────────────────────

  /// 获取有效的 Access Token（缓存优先，过期自动刷新）。
  Future<String?> getValidAccessToken() async {
    final prefs = await _sp;
    final token = prefs.getString(_kAccessToken);
    final expiresAt = prefs.getInt(_kTokenExpiresAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Token 还有 5 分钟以上有效期，直接使用
    if (token != null && token.isNotEmpty && expiresAt - now > 300) {
      return token;
    }

    // 刷新 Token
    return await _refreshAccessToken();
  }

  /// 刷新 Access Token。
  Future<String?> _refreshAccessToken() async {
    final appId = await getAppId();
    final appSecret = await getAppSecret();
    if (appId == null || appSecret == null) return null;

    try {
      final url = '$_baseUrl/cgi-bin/token'
          '?grant_type=client_credential'
          '&appid=$appId'
          '&secret=$appSecret';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final token = data['access_token'];
      final expiresIn = data['expires_in'] ?? 7200;

      if (token is String && token.isNotEmpty) {
        final prefs = await _sp;
        await prefs.setString(_kAccessToken, token);
        await prefs.setInt(
          _kTokenExpiresAt,
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn,
        );
        return token;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── 图文素材上传 ───────────────────────────────────────────

  /// 上传图文素材（草稿），返回 media_id。
  ///
  /// [articles] 是图文消息列表，每条包含：
  /// - title: 标题
  /// - content: 正文 HTML
  /// - thumb_media_id: 封面图片 media_id
  /// - author: 作者
  /// - digest: 摘要
  /// - content_source_url: 原文链接
  Future<String?> uploadNews(List<Map<String, dynamic>> articles) async {
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final url = '$_baseUrl/cgi-bin/material/add_news?access_token=$token';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'articles': articles}),
      );
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      return data['media_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 上传图片素材，返回 media_id（用于图文封面）。
  Future<String?> uploadImage(File imageFile) async {
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final url = '$_baseUrl/cgi-bin/material/add_material'
          '?access_token=$token&type=image';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.files.add(await http.MultipartFile.fromPath(
        'media',
        imageFile.path,
      ));
      final resp = await request.send();
      final body = await resp.stream.bytesToString();
      final data = jsonDecode(body);
      return data['media_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── 发表 / 群发 ────────────────────────────────────────────

  /// 发表图文（订阅号使用「发表」接口，发表后可在公众号后台看到）。
  ///
  /// 注意：发表接口仅对已认证的订阅号/服务号开放。
  Future<Map<String, dynamic>?> publishArticle(String mediaId) async {
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final url = '$_baseUrl/cgi-bin/freepublish/submit?access_token=$token';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'media_id': mediaId}),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// 测试连接（获取 Access Token 验证配置是否正确）。
  Future<Map<String, dynamic>> testConnection() async {
    final appId = await getAppId();
    final appSecret = await getAppSecret();

    if (appId == null || appId.isEmpty) {
      return {'ok': false, 'error': 'AppID 未配置'};
    }
    if (appSecret == null || appSecret.isEmpty) {
      return {'ok': false, 'error': 'AppSecret 未配置'};
    }

    final token = await _refreshAccessToken();
    if (token == null) {
      return {'ok': false, 'error': '获取 Access Token 失败，请检查 AppID/AppSecret 和 IP 白名单'};
    }

    return {'ok': true, 'access_token': token.substring(0, 10) + '...'};
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_page_info.dart';
import 'obsidian_store.dart';

/// 本地收件 HTTP 服务（Fluxio Inbox）。
///
/// 浏览器扩展 / 剪贴板钩子 / 局域网投递页通过 POST /api/inbox 投递链接，
/// 服务端校验后复用现有收藏链路（WebContentExtractor 语义 → saveClip）。
/// 仅绑定 loopback（127.0.0.1），不暴露局域网（P2 再加 0.0.0.0 开关）。
class InboxServer {
  InboxServer({ObsidianStore? obsidianStore})
      : _obsidianStore = obsidianStore ?? ObsidianStore();

  static const int defaultPort = 8730;
  static const String tokenKey = 'inbox_token';

  final ObsidianStore _obsidianStore;
  HttpServer? _server;
  int _port = defaultPort;

  int get port => _port;
  bool get isRunning => _server != null;
  String get endpoint => 'http://127.0.0.1:$_port';

  /// 读取或生成收件 token（浏览器扩展配置用）。
  Future<String> getToken() async {
    final sp = await SharedPreferences.getInstance();
    var token = sp.getString(tokenKey);
    if (token == null || token.isEmpty) {
      token = _generateToken();
      await sp.setString(tokenKey, token);
    }
    return token;
  }

  Future<void> resetToken() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(tokenKey, _generateToken());
  }

  String _generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').substring(0, 32);
  }

  /// 启动服务；端口被占时自动 +1 探测（最多 +10）。
  Future<void> start() async {
    if (_server != null) return;
    HttpServer? server;
    for (var p = defaultPort; p < defaultPort + 10; p++) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        _port = p;
        break;
      } on SocketException {
        continue;
      }
    }
    if (server == null) {
      throw StateError('无法绑定收件端口（$defaultPort-${defaultPort + 9}）');
    }
    _server = server;
    server.listen(_handle);
    debugPrint('Fluxio Inbox listening on $endpoint');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // CORS 预检：浏览器/扩展发 OPTIONS 时直接返回 204
      if (req.method == 'OPTIONS') {
        req.response
          ..statusCode = 204
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
          ..headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Inbox-Token')
          ..headers.add('Access-Control-Max-Age', '86400');
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && req.uri.path == '/api/health') {
        await _respond(req, 200, {'ok': true, 'version': 1});
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/api/inbox') {
        await _handleInbox(req);
        return;
      }
      await _respond(req, 404, {'ok': false, 'error': 'NOT_FOUND'});
    } catch (e) {
      debugPrint('inbox server error: $e');
      await _respond(req, 500, {'ok': false, 'error': 'INTERNAL'});
    }
  }

  Future<void> _handleInbox(HttpRequest req) async {
    final token = req.headers.value('X-Inbox-Token') ?? '';
    final expected = await getToken();
    if (token.isEmpty || token != expected) {
      return _respond(req, 401, {'ok': false, 'error': 'INVALID_TOKEN'});
    }

    final body = await utf8.decoder.bind(req).join();
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return _respond(req, 400, {'ok': false, 'error': 'BAD_JSON'});
    }

    final url = (data['url'] as String? ?? '').trim();
    final extContent = (data['content'] as String? ?? '').trim();
    final extHtml = (data['html'] as String? ?? '').trim();
    final source = (data['source'] as String? ?? '网页').trim();
    final title = (data['title'] as String? ?? '').trim();

    // 扩展直接传了渲染后的 Markdown / HTML（SPA 页面也能拿到正文），直接写入
    if (extContent.isNotEmpty || extHtml.isNotEmpty) {
      final info = WebPageInfo(
        url: url,
        title: title.isNotEmpty ? title : (extContent.isNotEmpty ? _firstLine(extContent) : url),
        content: extContent,
        html: extHtml,
      );
      try {
        final files = await _obsidianStore.saveClip(info, sourceTitle: source);
        return _respond(req, 200, {
          'ok': true,
          'saved': true,
          'record': files.isNotEmpty ? files.first.uri.pathSegments.last : null,
        });
      } catch (e) {
        return _respond(req, 500, {'ok': false, 'error': 'SAVE_FAILED', 'message': '$e'});
      }
    }

    // 回退：Fluxio 自己 fetch 并提取内容（剪贴板收藏等场景）
    final result = await saveUrl(
      url,
      source: source,
      title: title.isNotEmpty ? title : null,
    );
    if (result.error == 'INVALID_URL') {
      return _respond(req, 400, {'ok': false, 'error': 'INVALID_URL'});
    }
    if (!result.ok) {
      return _respond(
          req, 500, {'ok': false, 'error': 'SAVE_FAILED', 'message': result.error});
    }
    return _respond(req, 200, {'ok': true, 'saved': true, 'record': result.record});
  }

  /// 公开入口：从任意来源收藏一个 URL（剪贴板钩子 / 扩展 / 投递页共用）。
  ///
  /// 抓取与提取均为尽力而为：失败仍收藏链接（保证一键可用）。
  Future<({bool ok, String? error, String? record})> saveUrl(
    String url, {
    String source = '网页',
    String? title,
  }) async {
    url = url.trim();
    if (!_isHttpUrl(url)) {
      return (ok: false, error: 'INVALID_URL', record: null);
    }

    var content = '';
    var html = '';
    try {
      final fetched = await _fetch(url);
      final extracted = _extract(fetched);
      content = extracted.$2;  // 纯文本正文
      html = fetched;           // 原始完整 HTML（保留样式/布局）
    } catch (e) {
      debugPrint('inbox fetch failed for $url: $e');
    }

    final t = (title ?? '').trim();
    final fallbackTitle =
        t.isNotEmpty ? t : (content.isNotEmpty ? _firstLine(content) : url);
    final info = WebPageInfo(
      url: url,
      title: fallbackTitle,
      content: content,
      html: html,
    );

    try {
      final files = await _obsidianStore.saveClip(info, sourceTitle: source);
      return (
        ok: true,
        error: null,
        record: files.isNotEmpty ? files.first.uri.pathSegments.last : null,
      );
    } catch (e) {
      return (ok: false, error: '$e', record: null);
    }
  }

  bool _isHttpUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  Future<String> _fetch(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) FluxioInbox/1.0');
      final res = await req.close();
      if (res.statusCode >= 400) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final bytes = await res.fold<List<int>>(
          <int>[], (acc, chunk) => acc..addAll(chunk));
      return _decode(bytes, res.headers.contentType?.parameters['charset']);
    } finally {
      client.close(force: true);
    }
  }

  String _decode(List<int> bytes, String? charset) {
    try {
      if (charset != null && charset.toLowerCase() != 'utf-8') {
        return latin1.decode(bytes);
      }
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 极简提取：<title> + 去脚本/样式后的正文纯文本（MVP 够用，P2 强化）。
  (String, String) _extract(String html) {
    final titleMatch = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
        .firstMatch(html);
    final title = titleMatch?.group(1)?.trim() ?? '';

    var cleaned = html.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    // 保留换行语义：块级标签转 \n
    cleaned = cleaned.replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|tr|br|section|article)>', caseSensitive: false),
        '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
    cleaned = cleaned.replaceAll(RegExp(r'&lt;', caseSensitive: false), '<');
    cleaned = cleaned.replaceAll(RegExp(r'&gt;', caseSensitive: false), '>');
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();
    if (cleaned.length > 100000) {
      cleaned = '${cleaned.substring(0, 100000)}…';
    }
    return (title, cleaned);
  }

  String _firstLine(String s) {
    final line = s.trim().split('\n').first.trim();
    return line.isEmpty ? '未命名' : (line.length > 60 ? '${line.substring(0, 60)}…' : line);
  }

  Future<void> _respond(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..headers.add('Access-Control-Allow-Origin', '*')
      ..headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Inbox-Token')
      ..write(jsonEncode(body));
    return req.response.close();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 腾讯 ima 知识库 OpenAPI 同步服务。
///
/// 鉴权：请求头 ima-openapi-clientid + ima-openapi-apikey
/// 获取凭证：https://ima.qq.com/agent-interface
///
/// 核心能力：
/// - 获取知识库列表
/// - 上传 Markdown / 文件到指定知识库
/// - 测试连接
class ImaService {
  static const String _kClientId = 'ima_client_id';
  static const String _kApiKey = 'ima_api_key';
  static const String _kKnowledgeBaseId = 'ima_knowledge_base_id';
  static const String _kEnabled = 'ima_enabled';

  static const String _baseUrl = 'https://ima.qq.com/openapi/wiki/v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── 配置读写 ──────────────────────────────────────────────

  Future<bool> getEnabled() async => (await _sp).getBool(_kEnabled) ?? false;
  Future<void> setEnabled(bool v) async => (await _sp).setBool(_kEnabled, v);

  Future<String?> getClientId() async => (await _sp).getString(_kClientId);
  Future<void> setClientId(String v) async => (await _sp).setString(_kClientId, v);

  Future<String?> getApiKey() async => (await _sp).getString(_kApiKey);
  Future<void> setApiKey(String v) async => (await _sp).setString(_kApiKey, v);

  Future<String?> getKnowledgeBaseId() async => (await _sp).getString(_kKnowledgeBaseId);
  Future<void> setKnowledgeBaseId(String v) async => (await _sp).setString(_kKnowledgeBaseId, v);

  Future<bool> isConfigured() async {
    final cid = await getClientId();
    final key = await getApiKey();
    final kb = await getKnowledgeBaseId();
    return cid != null && cid.isNotEmpty &&
           key != null && key.isNotEmpty &&
           kb != null && kb.isNotEmpty;
  }

  // ── API 调用 ──────────────────────────────────────────────

  Map<String, String> _headers(String clientId, String apiKey) => {
        'Content-Type': 'application/json',
        'ima-openapi-clientid': clientId,
        'ima-openapi-apikey': apiKey,
      };

  /// 测试连接：调用知识库列表接口验证凭证是否有效。
  Future<({bool ok, String message, List<ImaKnowledgeBase>? bases})> testConnection() async {
    final clientId = await getClientId();
    final apiKey = await getApiKey();
    if (clientId == null || clientId.isEmpty || apiKey == null || apiKey.isEmpty) {
      return (ok: false, message: '请先配置 Client ID 和 API Key', bases: null);
    }
    try {
      final bases = await _fetchKnowledgeBases(clientId, apiKey);
      return (ok: true, message: '连接成功，共 ${bases.length} 个知识库', bases: bases);
    } catch (e) {
      return (ok: false, message: '连接失败：$e', bases: null);
    }
  }

  /// 获取知识库列表。
  Future<List<ImaKnowledgeBase>> fetchKnowledgeBases() async {
    final clientId = await getClientId();
    final apiKey = await getApiKey();
    if (clientId == null || apiKey == null) return [];
    return _fetchKnowledgeBases(clientId, apiKey);
  }

  Future<List<ImaKnowledgeBase>> _fetchKnowledgeBases(String clientId, String apiKey) async {
    final uri = Uri.parse('$_baseUrl/search_knowledge_base');
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      _headers(clientId, apiKey).forEach((k, v) => req.headers.add(k, v));
      req.add(utf8.encode(jsonEncode({'query': '', 'cursor': '', 'limit': 50})));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] != 0 && data['code'] != 200) {
        throw Exception('${data['message'] ?? data['msg'] ?? '未知错误'} (code=${data['code']})');
      }
      final list = (data['data']?['info_list'] ?? data['data']?['list'] ?? []) as List;
      return list.map((e) => ImaKnowledgeBase.fromJson(e as Map<String, dynamic>)).toList();
    } finally {
      client.close();
    }
  }

  /// 上传 Markdown 内容到指定知识库。
  ///
  /// 返回 (success, message)
  Future<({bool success, String message})> uploadMarkdown({
    required String fileName,
    required String content,
    String? knowledgeBaseId,
  }) async {
    final clientId = await getClientId();
    final apiKey = await getApiKey();
    final kbId = knowledgeBaseId ?? await getKnowledgeBaseId();
    if (clientId == null || clientId.isEmpty) {
      return (success: false, message: '未配置 Client ID');
    }
    if (apiKey == null || apiKey.isEmpty) {
      return (success: false, message: '未配置 API Key');
    }
    if (kbId == null || kbId.isEmpty) {
      return (success: false, message: '未选择知识库');
    }

    try {
      final uri = Uri.parse('$_baseUrl/create_media');
      final client = HttpClient();
      try {
        final req = await client.postUrl(uri);
        _headers(clientId, apiKey).forEach((k, v) => req.headers.add(k, v));
        final payload = {
          'file_name': fileName,
          'file_size': content.length,
          'content_type': 'text/markdown',
          'knowledge_base_id': kbId,
          'file_ext': 'md',
          'content': base64Encode(utf8.encode(content)),
        };
        req.add(utf8.encode(jsonEncode(payload)));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data['code'] != 0 && data['code'] != 200) {
          return (success: false, message: '${data['message'] ?? data['msg'] ?? '上传失败'} (code=${data['code']})');
        }
        return (success: true, message: '已同步到 ima 知识库');
      } finally {
        client.close();
      }
    } catch (e) {
      return (success: false, message: '同步失败：$e');
    }
  }

  /// 通过 URL 导入网页到知识库（适合网页收藏，ima 自动抓取内容）。
  ///
  /// 返回 (success, message)
  Future<({bool success, String message})> importUrls({
    required List<String> urls,
    String? knowledgeBaseId,
  }) async {
    final clientId = await getClientId();
    final apiKey = await getApiKey();
    final kbId = knowledgeBaseId ?? await getKnowledgeBaseId();
    if (clientId == null || clientId.isEmpty) {
      return (success: false, message: '未配置 Client ID');
    }
    if (apiKey == null || apiKey.isEmpty) {
      return (success: false, message: '未配置 API Key');
    }
    if (kbId == null || kbId.isEmpty) {
      return (success: false, message: '未选择知识库');
    }
    if (urls.isEmpty) {
      return (success: false, message: 'URL 列表为空');
    }

    try {
      final uri = Uri.parse('$_baseUrl/import_urls');
      final client = HttpClient();
      try {
        final req = await client.postUrl(uri);
        _headers(clientId, apiKey).forEach((k, v) => req.headers.add(k, v));
        final payload = {
          'knowledge_base_id': kbId,
          'urls': urls,
        };
        req.add(utf8.encode(jsonEncode(payload)));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data['code'] != 0 && data['code'] != 200) {
          return (success: false, message: '${data['message'] ?? data['msg'] ?? '导入失败'} (code=${data['code']})');
        }
        final results = data['data']?['results'] as Map<String, dynamic>?;
        if (results != null) {
          final failed = results.entries.where((e) => (e.value['ret_code'] ?? 0) != 0).toList();
          if (failed.isNotEmpty) {
            return (success: false, message: '${failed.length} 个 URL 导入失败: ${failed.first.value['errmsg'] ?? '未知错误'}');
          }
        }
        return (success: true, message: '已导入 ${urls.length} 个网页到 ima 知识库');
      } finally {
        client.close();
      }
    } catch (e) {
      return (success: false, message: '导入失败：$e');
    }
  }
}

/// ima 知识库模型。
class ImaKnowledgeBase {
  final String id;
  final String name;
  final String? description;

  const ImaKnowledgeBase({required this.id, required this.name, this.description});

  factory ImaKnowledgeBase.fromJson(Map<String, dynamic> json) {
    return ImaKnowledgeBase(
      id: (json['kb_id'] ?? json['id'] ?? json['knowledge_base_id'] ?? '').toString(),
      name: (json['kb_name'] ?? json['name'] ?? json['title'] ?? '未命名').toString(),
      description: json['description']?.toString(),
    );
  }

  @override
  String toString() => 'ImaKnowledgeBase(id=$id, name=$name)';
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 单条订阅文章。
class RssArticle {
  final String title;
  final String link;
  final DateTime? pubDate;
  final String? summary;

  const RssArticle({
    required this.title,
    required this.link,
    this.pubDate,
    this.summary,
  });
}

/// RSS/Atom 订阅解析服务（纯客户端，无后端）。
///
/// 通过 [HttpClient] 抓取订阅地址并解析出文章列表：
/// - RSS 2.0：`<item>` 块，取 `title/link/pubDate/description`
/// - Atom：`<entry>` 块，取 `title/link[@href]/published|updated/summary|content`
///
/// 采用轻量扫描解析（不依赖第三方 XML 库），结构简单、可控、可测。
class RssService {
  /// 抓取并解析订阅源，返回文章列表（按时间倒序，无时间时保持原序）。
  Future<List<RssArticle>> fetch(String url, {Duration? timeout}) async {
    final client = HttpClient()..connectionTimeout = timeout ?? const Duration(seconds: 10);
    // Windows 桌面端：dart:io 默认只读环境变量代理，不读系统代理。
    // 若系统代理开启（WebView2 可访问外网而 HttpClient 不能时），自动复用系统代理。
    final sysProxy = _windowsSystemProxy();
    client.findProxy = (uri) {
      if (sysProxy != null) return 'PROXY $sysProxy';
      return 'DIRECT';
    };
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(timeout ?? const Duration(seconds: 10));
      req.headers.set('User-Agent', 'Fluxio/0.1 (+https://github.com/IYABAO/Fluxio)');
      final resp = await req.close().timeout(timeout ?? const Duration(seconds: 10));
      final body = await _readBody(resp);
      final decoded = _decodeBody(resp, body);
      return parse(decoded);
    } finally {
      client.close(force: true);
    }
  }

  static String? _cachedProxy;
  static bool _proxyProbed = false;

  /// 读取 Windows 系统代理（IE 设置）：仅当 ProxyEnable=1 时返回 ProxyServer。
  /// 非 Windows 平台或读取失败返回 null。
  static String? _windowsSystemProxy() {
    if (!Platform.isWindows) return null;
    if (_proxyProbed) return _cachedProxy;
    _proxyProbed = true;
    try {
      final enable = Process.runSync(
          'reg',
          [
            'query',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
            '/v',
            'ProxyEnable',
          ],
          runInShell: true);
      if (enable.exitCode != 0 ||
          !enable.stdout.toString().toLowerCase().contains('0x1')) {
        return _cachedProxy = null;
      }
      final server = Process.runSync(
          'reg',
          [
            'query',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
            '/v',
            'ProxyServer',
          ],
          runInShell: true);
      if (server.exitCode != 0) return _cachedProxy = null;
      final line = server.stdout
          .toString()
          .split('\r\n')
          .firstWhere((l) => l.contains('ProxyServer'), orElse: () => '');
      final idx = line.lastIndexOf('REG_SZ');
      if (idx < 0) return _cachedProxy = null;
      var val = line.substring(idx + 6).trim();
      if (val.isEmpty) return _cachedProxy = null;
      // 兼容 "http=..;https=.." 形式：优先 https，其次 http。
      if (val.contains('=')) {
        String? httpProxy;
        for (final p in val.split(';')) {
          final kv = p.split('=');
          if (kv.length != 2) continue;
          if (kv[0].trim().toLowerCase() == 'https') return _cachedProxy = kv[1].trim();
          if (kv[0].trim().toLowerCase() == 'http') httpProxy = kv[1].trim();
        }
        return _cachedProxy = httpProxy;
      }
      return _cachedProxy = val;
    } catch (_) {
      return _cachedProxy = null;
    }
  }

  /// 读取原始字节。
  Future<List<int>> _readBody(HttpClientResponse resp) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// 根据响应头 charset 解码；无 charset 时按 UTF-8 解码（失败回退 latin1）。
  String _decodeBody(HttpClientResponse resp, List<int> bytes) {
    String? charset;
    final ct = resp.headers.contentType;
    if (ct != null) {
      charset = ct.parameters['charset']?.toLowerCase().replaceAll('"', '');
    }
    if (charset != null && charset.isNotEmpty && charset != 'utf-8') {
      try {
        return _decodeCharset(charset, bytes);
      } catch (_) {
        // 未知编码回退 utf8
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decodeCharset(String charset, List<int> bytes) {
    // 仅支持常见单字节/GBK 中文编码，其余回退 utf8。
    if (charset.contains('gb') || charset.contains('gbk') || charset.contains('gb2312')) {
      return _decodeGbk(bytes);
    }
    if (charset.contains('latin') || charset.contains('iso')) {
      return latin1.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decodeGbk(List<int> bytes) {
    // dart:io 无内置 GBK 解码；用 latin1 占位再尝试 utf8。
    // 大多数现代订阅源为 UTF-8，GBK 场景极少；这里返回 utf8 容错。
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 解析 XML 文本为文章列表。
  ///
  /// 纯函数，便于单测。返回按发布时间倒序（无时间条目排在最后）的文章列表。
  List<RssArticle> parse(String xml) {
    final articles = <RssArticle>[];
    final normalized = _stripBom(xml);

    // RSS 2.0：<item>...</item>
    _forEachBlock(normalized, 'item', (block) {
      final title = _tag(block, 'title');
      final link = _tag(block, 'link');
      if (title == null || link == null) return;
      final date = _parseDate(_tag(block, 'pubDate'));
      final summary = _tag(block, 'description') ?? _tag(block, 'content:encoded');
      articles.add(RssArticle(title: title, link: link, pubDate: date, summary: summary));
    });

    // Atom：<entry>...</entry>
    if (articles.isEmpty) {
      _forEachBlock(normalized, 'entry', (block) {
        final title = _tag(block, 'title');
        final link = _attrHrefFromBlock(block);
        if (title == null || link == null) return;
        final date = _parseDate(_tag(block, 'published') ?? _tag(block, 'updated'));
        final summary = _tag(block, 'summary') ?? _tag(block, 'content');
        articles.add(RssArticle(title: title, link: link, pubDate: date, summary: summary));
      });
    }

    // 按发布时间倒序；无时间条目排最后。
    articles.sort((a, b) {
      final da = a.pubDate?.millisecondsSinceEpoch;
      final db = b.pubDate?.millisecondsSinceEpoch;
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return 0;
    });
    return articles;
  }

  String _stripBom(String s) => s.startsWith('\uFEFF') ? s.substring(1) : s;

  /// 遍历 XML 顶层块：找到 `<tag ...>...</tag>` 的配对块并回调。
  void _forEachBlock(String xml, String tag, void Function(String block) cb) {
    final open = RegExp('<$tag(?:\\s[^>]*)?>');
    var start = 0;
    while (true) {
      final m = open.firstMatch(xml.substring(start));
      if (m == null) break;
      final openEnd = start + m.end;
      // 找对应的闭合 </tag>（简单配对，嵌套的同名 tag 罕见）
      final close = RegExp('</$tag\\s*>');
      final cm = close.firstMatch(xml.substring(openEnd));
      if (cm == null) break;
      final blockEnd = openEnd + cm.start;
      cb(xml.substring(openEnd, blockEnd));
      start = openEnd + cm.end;
    }
  }

  /// 取块内第一个 `<name>` 的文本（剥离 CDATA、解码实体）。
  String? _tag(String block, String name) {
    final raw = _tagRaw(block, name);
    if (raw == null) return null;
    return _cleanText(raw);
  }

  /// 取块内第一个 `<name ...>` 的原始内容（含属性）。
  String? _tagRaw(String block, String name) {
    final re = RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name\\s*>');
    final m = re.firstMatch(block);
    return m?.group(1);
  }

  /// 从 entry/item 块内直接提取 `<link ... href="...">`（兼容自闭合 Atom link）。
  String? _attrHrefFromBlock(String block) {
    final m = RegExp('<link\\s[^>]*?href\\s*=\\s*["\']([^"\']+)["\']')
        .firstMatch(block);
    return m?.group(1);
  }

  /// 剥离 CDATA 包裹并解码 HTML 实体、压缩空白。
  String _cleanText(String s) {
    var t = s.trim();
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');
    t = t.replaceAllMapped(cdata, (m) => m.group(1) ?? '');
    t = t
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// 解析常见日期格式：RFC822（RSS pubDate）、ISO8601（Atom）。
  DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final t = s.trim();
    final rfc822 = RegExp(
        r'^[A-Za-z]{3},\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*(.*)$');
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})');
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    try {
      final r = rfc822.firstMatch(t);
      if (r != null) {
        final mon = months[r.group(2)];
        if (mon == null) return null;
        final h = int.parse(r.group(4)!);
        final min = int.parse(r.group(5)!);
        final sec = int.parse(r.group(6)!);
        var tz = r.group(7)?.trim() ?? '';
        var offset = Duration.zero;
        if (tz == 'GMT' || tz == 'UT' || tz == 'UTC' || tz == 'Z') {
          offset = Duration.zero;
        } else if (tz.startsWith('+') || tz.startsWith('-')) {
          final sign = tz.startsWith('-') ? -1 : 1;
          final tzh = int.tryParse(tz.substring(1, 3)) ?? 0;
          final tzm = int.tryParse(tz.length >= 5 ? tz.substring(3, 5) : '0') ?? 0;
          offset = Duration(hours: sign * tzh, minutes: sign * tzm);
        }
        final utc = DateTime.utc(
            int.parse(r.group(3)!), mon, int.parse(r.group(1)!), h, min, sec);
        return utc.subtract(offset);
      }
      final i = iso.firstMatch(t);
      if (i != null) {
        return DateTime.utc(
            int.parse(i.group(1)!), int.parse(i.group(2)!), int.parse(i.group(3)!),
            int.parse(i.group(4)!), int.parse(i.group(5)!), int.parse(i.group(6)!));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

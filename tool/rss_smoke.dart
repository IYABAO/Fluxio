// RSS 抓取冒烟验证：真实网络抓取 + 解析，验证 RssService 端到端可用。
// 用法：D:\flutter\bin\cache\dart-sdk\bin\dart.bat run tool/rss_smoke.dart
import 'package:fluxio/services/rss_service.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty
      ? args.first
      : 'https://www.ruanyifeng.com/blog/atom.xml';
  final svc = RssService();
  try {
    final list = await svc.fetch(url, timeout: const Duration(seconds: 30));
    print('OK fetch: $url');
    print('articles: ${list.length}');
    for (final a in list.take(5)) {
      print('- ${a.pubDate?.toIso8601String() ?? '无时间'} | ${a.title} | ${a.link}');
    }
  } catch (e) {
    print('FAIL: $e');
    rethrow;
  }
}

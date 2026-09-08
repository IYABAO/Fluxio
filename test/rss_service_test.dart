import 'package:flutter_test/flutter_test.dart';
import 'package:fluxio/services/rss_service.dart';

void main() {
  final rss = RssService();

  group('RssService.parse - RSS 2.0', () {
    test('解析 item 的 title/link/pubDate/summary 并按时间倒序', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>测试源</title>
  <item>
    <title>第一篇</title>
    <link>https://example.com/1</link>
    <pubDate>Wed, 02 Oct 2024 08:00:00 GMT</pubDate>
    <description>第一篇摘要</description>
  </item>
  <item>
    <title>第二篇</title>
    <link>https://example.com/2</link>
    <pubDate>Thu, 03 Oct 2024 08:00:00 GMT</pubDate>
    <description>第二篇摘要</description>
  </item>
</channel></rss>
''';
      final articles = rss.parse(xml);
      expect(articles.length, 2);
      // 时间倒序：第二篇在前。
      expect(articles.first.title, '第二篇');
      expect(articles.first.link, 'https://example.com/2');
      expect(articles.first.pubDate, DateTime.utc(2024, 10, 3, 8));
      expect(articles.first.summary, '第二篇摘要');
      expect(articles.last.title, '第一篇');
    });

    test('CDATA 包裹与 HTML 实体被正确剥离', () {
      const xml = '''
<rss version="2.0"><channel>
  <item>
    <title><![CDATA[<b>标题 &amp; 符号</b>]]></title>
    <link>https://example.com/1</link>
    <description><![CDATA[<p>正文 &lt;代码&gt; 示例</p>]]></description>
  </item>
</channel></rss>
''';
      final articles = rss.parse(xml);
      expect(articles.single.title, '<b>标题 & 符号</b>');
      expect(articles.single.summary, '<p>正文 <代码> 示例</p>');
    });

    test('无 pubDate 的条目排在最后', () {
      const xml = '''
<rss version="2.0"><channel>
  <item><title>有日期</title><link>https://e.com/1</link>
    <pubDate>Wed, 02 Oct 2024 08:00:00 GMT</pubDate></item>
  <item><title>无日期</title><link>https://e.com/2</link></item>
</channel></rss>
''';
      final articles = rss.parse(xml);
      expect(articles.first.title, '有日期');
      expect(articles.last.title, '无日期');
    });
  });

  group('RssService.parse - Atom', () {
    test('解析 entry 的 title/link/published/summary', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom 源</title>
  <entry>
    <title>Atom 第一篇</title>
    <link href="https://atom.example.com/1" rel="alternate"/>
    <published>2024-10-04T09:30:00Z</published>
    <summary>Atom 摘要</summary>
  </entry>
</feed>
''';
      final articles = rss.parse(xml);
      expect(articles.length, 1);
      expect(articles.single.title, 'Atom 第一篇');
      expect(articles.single.link, 'https://atom.example.com/1');
      expect(articles.single.pubDate, DateTime.utc(2024, 10, 4, 9, 30));
      expect(articles.single.summary, 'Atom 摘要');
    });
  });

  group('RssService.parse - 边界', () {
    test('空输入返回空列表', () {
      expect(rss.parse(''), isEmpty);
      expect(rss.parse('<rss></rss>'), isEmpty);
    });

    test('BOM 前缀不影响解析', () {
      const xml = '\uFEFF<rss version="2.0"><channel>'
          '<item><title>带BOM</title><link>https://e.com/1</link></item>'
          '</channel></rss>';
      expect(rss.parse(xml).single.title, '带BOM');
    });

    test('缺失 link 的 item 被跳过', () {
      const xml = '<rss version="2.0"><channel>'
          '<item><title>无链接</title></item>'
          '<item><title>正常</title><link>https://e.com/2</link></item>'
          '</channel></rss>';
      final articles = rss.parse(xml);
      expect(articles.single.title, '正常');
    });
  });
}

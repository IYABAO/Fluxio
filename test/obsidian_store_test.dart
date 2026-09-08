import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxio/models/web_page_info.dart';
import 'package:fluxio/services/obsidian_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpVault;

  setUp(() {
    tmpVault = Directory.systemTemp.createTempSync('fluxio_obsidian_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    if (tmpVault.existsSync()) {
      tmpVault.deleteSync(recursive: true);
    }
  });

  test('未配置 vault 路径时 saveClip 抛错', () async {
    final store = ObsidianStore();
    expect(
      () => store.saveClip(
        const WebPageInfo(url: 'https://example.com', title: '示例'),
        sourceTitle: '源',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('配置路径后 saveClip 写入带 frontmatter 的 Markdown 到收件箱', () async {
    final store = ObsidianStore();
    await store.setVaultPath(tmpVault.path);

    final files = await store.saveClip(
      const WebPageInfo(url: 'https://news.daheiai.com/', title: '大黑AI速报'),
      sourceTitle: '大黑AI速报',
    );
    expect(files, isNotEmpty);
    final file = files.first;

    // 文件应位于 <vault>/Fluxio收件箱/
    expect(file.path, startsWith(tmpVault.path));
    expect(file.path, contains(ObsidianStore.inboxDirName));
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    expect(content, contains('source: "大黑AI速报"'));
    expect(content, contains('url: "https://news.daheiai.com/"'));
    expect(content, contains('title: "大黑AI速报"'));
    expect(content, contains('type: webclip_link'));
    expect(content, contains('- fluxio'));
    expect(content, contains('- inbox'));
    expect(content, contains('原文：https://news.daheiai.com/'));
    // 无正文时回退为"仅链接"占位。
    expect(content, contains('纯文本提取失败，仅收藏链接'));
  });

  test('有纯文本时写入内容详情，type 为 webclip_content', () async {
    final store = ObsidianStore();
    await store.setVaultPath(tmpVault.path);

    final files = await store.saveClip(
      const WebPageInfo(
        url: 'https://news.daheiai.com/post/1',
        title: 'AI 行业速报',
        content: '这是正文第一段。\n\n这是正文第二段。',
      ),
      sourceTitle: '大黑AI速报',
    );
    final content = files.first.readAsStringSync();
    expect(content, contains('type: webclip_content'));
    expect(content, contains('这是正文第一段。'));
    expect(content, contains('这是正文第二段。'));
    expect(content, contains('---\n\n这是正文第一段。'));
  });

  test('有 HTML 快照时生成 .html 文件并在 md 中引用', () async {
    final store = ObsidianStore();
    await store.setVaultPath(tmpVault.path);

    const html = '<!DOCTYPE html><html><head><title>AI 行业速报</title>'
        '<style>body{color:#333}</style></head>'
        '<body><h1>AI 行业速报</h1><p>这是正文。</p></body></html>';
    final files = await store.saveClip(
      const WebPageInfo(
        url: 'https://news.daheiai.com/post/1',
        title: 'AI 行业速报',
        content: '这是正文。',
        html: html,
      ),
      sourceTitle: '大黑AI速报',
    );

    // 应生成 .md 与 .html 两个文件。
    expect(files.length, 2);
    final md = files.firstWhere((f) => f.path.endsWith('.md'));
    final htmlFile = files.firstWhere((f) => f.path.endsWith('.html'));

    expect(md.readAsStringSync(), contains('type: webclip_html'));
    expect(md.readAsStringSync(), contains('完整网页快照'));
    expect(htmlFile.readAsStringSync(), contains('<style>body{color:#333}</style>'));
    expect(htmlFile.readAsStringSync(), contains('这是正文。'));
  });

  test('超长正文全量保存，不截断', () async {
    final store = ObsidianStore();
    await store.setVaultPath(tmpVault.path);

    final longBody = List.filled(60000, '字').join();
    final files = await store.saveClip(
      WebPageInfo(url: 'https://example.com/long', title: '超长文章', content: longBody),
      sourceTitle: '源',
    );
    final content = files.first.readAsStringSync();
    // 全量保留，不截断、无截断标记。
    expect(content, contains(longBody));
    expect(content, isNot(contains('正文过长已截断')));
  });

  test('frontmatter 中的引号和换行被转义', () async {
    final store = ObsidianStore();
    await store.setVaultPath(tmpVault.path);

    final files = await store.saveClip(
      const WebPageInfo(
        url: 'https://example.com/a?x="q"',
        title: '标题"含引号"',
      ),
      sourceTitle: '含"引号"源',
    );

    final content = files.first.readAsStringSync();
    expect(content, contains(r'source: "含\"引号\"源"'));
    expect(content, contains(r'url: "https://example.com/a?x=\"q\""'));
  });
}

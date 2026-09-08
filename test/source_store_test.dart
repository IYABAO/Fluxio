import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxio/models/feed_source.dart';
import 'package:fluxio/services/source_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('首次加载应注入示例源', () async {
    final store = SourceStore();
    final sources = await store.load();

    expect(sources.length, 3);
    expect(sources[0].title, '大黑AI速报');
    expect(sources[0].url, 'https://news.daheiai.com/');
    expect(sources[1].title, 'Hacker News');
    expect(sources[2].title, 'PLBear 博客');
  });

  test('重复加载不会重复注入示例源', () async {
    final store = SourceStore();
    final first = await store.load();
    expect(first.length, 3);

    // 再次加载（模拟重启）应仍为 3 个，不重复注入。
    final second = await store.load();
    expect(second.length, 3);
  });

  test('添加源后保存并重新加载应保留', () async {
    final store = SourceStore();
    await store.load(); // 触发 seed

    final sources = await store.load();
    sources.add(const FeedSource(
      id: 'custom-1',
      title: '自定义源',
      url: 'https://example.com/',
    ));
    await store.save(sources);

    final reloaded = await store.load();
    expect(reloaded.length, 4);
    expect(reloaded.last.title, '自定义源');
  });

  test('FeedSource 序列化往返', () {
    const src = FeedSource(id: 'a', title: '标题', url: 'https://x.com');
    final json = src.toJson();
    final back = FeedSource.fromJson(json);
    expect(back.id, 'a');
    expect(back.title, '标题');
    expect(back.url, 'https://x.com');
    expect(back.group, kDefaultGroup);
    expect(back.enabled, isTrue);
    expect(back.type, kSourceTypeWeb);
  });

  test('新字段（分组/启停/类型）序列化往返', () {
    const src = FeedSource(
      id: 'a',
      title: 'RSS 源',
      url: 'https://x.com/feed.xml',
      group: 'AI',
      enabled: false,
      type: kSourceTypeRss,
    );
    final back = FeedSource.fromJson(src.toJson());
    expect(back.group, 'AI');
    expect(back.enabled, isFalse);
    expect(back.type, kSourceTypeRss);
    expect(back.isRss, isTrue);
  });

  test('旧 JSON（无新字段）反序列化给默认值，兼容历史数据', () {
    final back = FeedSource.fromJson({
      'id': 'legacy',
      'title': '旧源',
      'url': 'https://old.com',
    });
    expect(back.group, kDefaultGroup);
    expect(back.enabled, isTrue);
    expect(back.type, kSourceTypeWeb);
    expect(back.isRss, isFalse);
  });

  test('停用的源保存后仍保留（启停状态持久化）', () async {
    final store = SourceStore();
    await store.load(); // seed
    final sources = await store.load();
    sources[0] = sources[0].copyWith(enabled: false);
    await store.save(sources);

    final reloaded = await store.load();
    expect(reloaded[0].enabled, isFalse);
  });
}

import '../models/feed_source.dart';

/// 常用信息源预设库：一键导入，快速搭建信息流。
///
/// 按分组分类，覆盖 AI 资讯、技术博客、科技新闻、编程社区等方向。
/// 导入逻辑：相同 URL 的源覆盖更新，不同 URL 的源增量添加。
class PresetSources {
  /// 全部预设源列表。
  static const List<FeedSource> all = [
    // ========== AI 资讯 ==========
    FeedSource(
      id: 'preset-daheiai',
      title: '大黑AI速报',
      url: 'https://news.daheiai.com/',
      group: 'AI资讯',
    ),
    FeedSource(
      id: 'preset-jiqizhixin',
      title: '机器之心',
      url: 'https://www.jiqizhixin.com/',
      group: 'AI资讯',
    ),
    FeedSource(
      id: 'preset-leiphone-ai',
      title: '雷锋网 - AI',
      url: 'https://www.leiphone.com/category/ai',
      group: 'AI资讯',
    ),
    FeedSource(
      id: 'preset-36kr-ai',
      title: '36氪 - AI',
      url: 'https://36kr.com/information/AI/',
      group: 'AI资讯',
    ),

    // ========== 技术博客 ==========
    FeedSource(
      id: 'preset-plbear',
      title: 'PLBear 博客',
      url: 'https://www.plbear.com/',
      group: '技术博客',
    ),
    FeedSource(
      id: 'preset-ruanyf',
      title: '阮一峰的网络日志',
      url: 'https://www.ruanyifeng.com/blog/',
      group: '技术博客',
    ),
    FeedSource(
      id: 'preset-coolshell',
      title: '酷壳 - CoolShell',
      url: 'https://coolshell.cn/',
      group: '技术博客',
    ),
    FeedSource(
      id: 'preset-liaoxuefeng',
      title: '廖雪峰的官方网站',
      url: 'https://www.liaoxuefeng.com/',
      group: '技术博客',
    ),

    // ========== 科技新闻 ==========
    FeedSource(
      id: 'preset-hackernews',
      title: 'Hacker News',
      url: 'https://news.ycombinator.com/',
      group: '科技新闻',
    ),
    FeedSource(
      id: 'preset-techcrunch',
      title: 'TechCrunch',
      url: 'https://techcrunch.com/',
      group: '科技新闻',
    ),
    FeedSource(
      id: 'preset-theverge',
      title: 'The Verge',
      url: 'https://www.theverge.com/',
      group: '科技新闻',
    ),
    FeedSource(
      id: 'preset-ithome',
      title: 'IT之家',
      url: 'https://www.ithome.com/',
      group: '科技新闻',
    ),

    // ========== 编程社区 ==========
    FeedSource(
      id: 'preset-github-trending',
      title: 'GitHub Trending',
      url: 'https://github.com/trending',
      group: '编程社区',
    ),
    FeedSource(
      id: 'preset-juejin',
      title: '掘金',
      url: 'https://juejin.cn/',
      group: '编程社区',
    ),
    FeedSource(
      id: 'preset-infoq',
      title: 'InfoQ 中文站',
      url: 'https://www.infoq.cn/',
      group: '编程社区',
    ),
    FeedSource(
      id: 'preset-csdn',
      title: 'CSDN',
      url: 'https://www.csdn.net/',
      group: '编程社区',
    ),

    // ========== Go 语言 ==========
    FeedSource(
      id: 'preset-go-blog',
      title: 'Go 官方博客',
      url: 'https://go.dev/blog/',
      group: 'Go语言',
    ),
    FeedSource(
      id: 'preset-go-cn',
      title: 'Golang 中文网',
      url: 'https://studygolang.com/',
      group: 'Go语言',
    ),

    // ========== 独立开发 ==========
    FeedSource(
      id: 'preset-indiehackers',
      title: 'Indie Hackers',
      url: 'https://www.indiehackers.com/',
      group: '独立开发',
    ),
    FeedSource(
      id: 'preset-v2ex',
      title: 'V2EX',
      url: 'https://www.v2ex.com/',
      group: '独立开发',
    ),
  ];

  /// 按分组获取预设源。
  static Map<String, List<FeedSource>> get byGroup {
    final map = <String, List<FeedSource>>{};
    for (final s in all) {
      map.putIfAbsent(s.group, () => []).add(s);
    }
    return map;
  }

  /// 所有分组名。
  static List<String> get groups => byGroup.keys.toList();

  /// 预设源总数。
  static int get count => all.length;
}

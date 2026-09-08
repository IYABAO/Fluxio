/// 信息源类型：`web` 为网页源（WebView 直接浏览），`rss` 为订阅源（解析文章列表）。
const String kSourceTypeWeb = 'web';
const String kSourceTypeRss = 'rss';

/// 默认分组名。
const String kDefaultGroup = '默认';

/// 信息源模型：一个源 = 一个可横向浏览的信息来源。
///
/// - `type == web`：`url` 是网页地址，用 WebView 直接浏览；
/// - `type == rss`：`url` 是 RSS/Atom 订阅地址，解析为结构化文章列表，
///   点击文章后用 WebView 打开详情。
class FeedSource {
  final String id;
  final String title;
  final String url;

  /// 分组名（用于源管理里分类整理）。
  final String group;

  /// 是否启用（停用的源不显示在信息流 Tab）。
  final bool enabled;

  /// 源类型：`web` 或 `rss`。
  final String type;

  const FeedSource({
    required this.id,
    required this.title,
    required this.url,
    this.group = kDefaultGroup,
    this.enabled = true,
    this.type = kSourceTypeWeb,
  });

  bool get isRss => type == kSourceTypeRss;

  /// 从 JSON 反序列化（兼容旧数据：缺失字段给默认值）。
  factory FeedSource.fromJson(Map<String, dynamic> json) {
    return FeedSource(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      group: (json['group'] as String?) ?? kDefaultGroup,
      enabled: (json['enabled'] as bool?) ?? true,
      type: (json['type'] as String?) ?? kSourceTypeWeb,
    );
  }

  /// 序列化为 JSON（用于本地持久化）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'group': group,
        'enabled': enabled,
        'type': type,
      };

  /// 复制并修改部分字段。
  FeedSource copyWith({
    String? title,
    String? url,
    String? group,
    bool? enabled,
    String? type,
  }) {
    return FeedSource(
      id: id,
      title: title ?? this.title,
      url: url ?? this.url,
      group: group ?? this.group,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
    );
  }
}

/// 当前浏览的页面信息（用于收藏到 Obsidian）。
class WebPageInfo {
  final String url;
  final String title;

  /// 页面纯文本（供 Obsidian Markdown 摘要，可能为空）。
  final String? content;

  /// 页面完整 HTML 快照（保留样式/图片/布局，可能为空）。
  final String? html;

  const WebPageInfo({
    required this.url,
    required this.title,
    this.content,
    this.html,
  });

  WebPageInfo copyWith({String? content, String? html}) {
    return WebPageInfo(
      url: url,
      title: title,
      content: content,
      html: html,
    );
  }

  @override
  String toString() =>
      'WebPageInfo(url: $url, title: $title, contentLen: ${content?.length ?? 0}, htmlLen: ${html?.length ?? 0})';
}

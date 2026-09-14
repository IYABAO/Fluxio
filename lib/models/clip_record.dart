/// 收藏记录模型：统一管理 Obsidian 和 ima 两种收藏方式。
class ClipRecord {
  /// 唯一 ID（时间戳 + 随机数）
  final String id;

  /// 文章标题
  final String title;

  /// 原文 URL
  final String url;

  /// 收藏来源：Obsidian / ima / 两者
  final String source;

  /// 状态：pending（排队中）/ success（成功）/ failed（失败）
  final String status;

  /// 创建时间
  final DateTime createdAt;

  /// Obsidian 本地文件路径（仅 Obsidian 收藏有）
  final String? localPath;

  /// 错误信息（失败时）
  final String? errorMessage;

  const ClipRecord({
    required this.id,
    required this.title,
    required this.url,
    required this.source,
    required this.status,
    required this.createdAt,
    this.localPath,
    this.errorMessage,
  });

  ClipRecord copyWith({
    String? status,
    String? localPath,
    String? errorMessage,
  }) {
    return ClipRecord(
      id: id,
      title: title,
      url: url,
      source: source,
      status: status ?? this.status,
      createdAt: createdAt,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'source': source,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'localPath': localPath,
        'errorMessage': errorMessage,
      };

  factory ClipRecord.fromJson(Map<String, dynamic> json) => ClipRecord(
        id: json['id'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        source: json['source'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        localPath: json['localPath'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );
}

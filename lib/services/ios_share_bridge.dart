import 'dart:async';

import 'package:flutter/services.dart';

/// iOS 原生分享接收桥接（处理 Share Extension + URL Scheme）。
///
/// 功能：
/// - 监听 URL Scheme 唤起（fluxio://share?url=xxx）
/// - 从 App Group UserDefaults 读取 Share Extension 保存的分享队列
/// - 清空已处理的分享队列
/// - 通知 Flutter 层有新的分享内容
class IosShareBridge {
  static const _channel = MethodChannel('com.plbear.fluxio/share');

  /// App Group ID（必须和 Share Extension 一致）。
  static const appGroupID = 'group.com.plbear.fluxio';

  /// 流控制器：当有新的分享内容时通知 UI。
  static final StreamController<SharedUrl> _shareController =
      StreamController<SharedUrl>.broadcast();

  /// 分享事件流。
  static Stream<SharedUrl> get shareStream => _shareController.stream;

  /// 初始化：设置 MethodChannel 回调。
  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived') {
        final url = call.arguments['url'] as String?;
        final title = call.arguments['title'] as String?;
        if (url != null && url.isNotEmpty) {
          _shareController.add(SharedUrl(
            url: url,
            title: title,
            source: 'url_scheme',
          ));
        }
      }
      return null;
    });
  }

  /// 从 App Group 读取待处理的分享队列（Share Extension 保存的）。
  ///
  /// 返回待处理的分享 URL 列表，读取后会清空队列。
  static Future<List<SharedUrl>> getPendingShares() async {
    try {
      final result = await _channel.invokeMethod('getPendingShares');
      if (result is List) {
        return result
            .map((item) => SharedUrl(
                  url: item['url'] as String,
                  title: item['title'] as String?,
                  source: 'share_extension',
                ))
            .toList();
      }
    } catch (e) {
      // 非 iOS 平台或原生代码未实现，返回空列表
    }
    return [];
  }

  /// 清空 App Group 中的分享队列。
  static Future<void> clearPendingShares() async {
    try {
      await _channel.invokeMethod('clearPendingShares');
    } catch (e) {
      // 忽略错误
    }
  }

  /// 检查是否有新的分享内容（App 启动或前台时调用）。
  static Future<void> checkForNewShares() async {
    final shares = await getPendingShares();
    for (final share in shares) {
      _shareController.add(share);
    }
    if (shares.isNotEmpty) {
      await clearPendingShares();
    }
  }

  /// 释放资源。
  static void dispose() {
    _shareController.close();
  }
}

/// 分享的 URL 信息。
class SharedUrl {
  final String url;
  final String? title;
  final String source; // 'share_extension' / 'url_scheme'

  SharedUrl({
    required this.url,
    this.title,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'source': source,
      };
}

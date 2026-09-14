import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'obsidian_store.dart';
import 'ima_service.dart';
import 'web_content_extractor.dart';
import '../models/web_page_info.dart';
import '../models/clip_record.dart';
import 'clip_history_store.dart';

/// 分享接收服务（统一处理 Share Extension + 剪贴板检测）。
///
/// 功能：
/// - 接收来自 Share Extension 的分享 URL（通过 App Group 或 URL Scheme）
/// - 接收来自剪贴板检测的 URL
/// - 统一走收藏逻辑（提取正文 → 保存 Obsidian → 上传 ima）
/// - 后台静默执行，不阻塞 UI
/// - 收藏历史记录
class ShareReceiverService {
  static const _shareChannel = MethodChannel('com.plbear.fluxio/share');

  final ObsidianStore _obsidianStore = ObsidianStore();
  final ImaService _imaService = ImaService();
  final WebContentExtractor _extractor = WebContentExtractor();
  final ClipHistoryStore _historyStore = ClipHistoryStore();

  /// 流控制器：当有新的分享内容时通知 UI。
  final StreamController<ShareEvent> _shareController =
      StreamController<ShareEvent>.broadcast();

  /// 分享事件流。
  Stream<ShareEvent> get shareStream => _shareController.stream;

  /// 初始化：设置 MethodChannel 回调（处理 Share Extension 唤起）。
  void init() {
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived') {
        final url = call.arguments['url'] as String?;
        final title = call.arguments['title'] as String?;
        if (url != null && url.isNotEmpty) {
          _handleShare(url, title: title, source: 'share_extension');
        }
      }
      return null;
    });
  }

  /// 处理分享内容（统一入口）。
  ///
  /// [url] 分享的网页 URL
  /// [title] 分享的标题（可选）
  /// [source] 来源：'share_extension' / 'clipboard' / 'url_scheme'
  /// [showConfirmation] 是否显示确认对话框（剪贴板检测时用）
  Future<void> handleShare(
    String url, {
    String? title,
    String source = 'unknown',
    bool showConfirmation = false,
  }) async {
    if (showConfirmation) {
      // 剪贴板检测：先通知 UI 显示确认框
      _shareController.add(ShareEvent(
        url: url,
        title: title,
        source: source,
        needsConfirmation: true,
      ));
    } else {
      // Share Extension / URL Scheme：直接后台收藏
      await _executeShare(url, title: title, source: source);
    }
  }

  /// 确认收藏（用户在确认框中点击"收藏"后调用）。
  Future<void> confirmShare(String url, {String? title, String source = 'clipboard'}) async {
    await _executeShare(url, title: title, source: source);
  }

  /// 取消收藏（用户在确认框中点击"取消"后调用）。
  Future<void> cancelShare(String url) async {
    // 记录为已处理，避免重复提示
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fluxio.clipboard.lastUrl.v1', url);
  }

  /// 执行收藏（后台静默）。
  Future<void> _executeShare(
    String url, {
    String? title,
    required String source,
  }) async {
    // 1. 创建收藏记录（pending 状态）
    final record = ClipRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      title: title ?? url,
      source: source,
      createdAt: DateTime.now(),
      status: 'pending',
    );
    await _historyStore.addRecord(record);

    // 2. 通知 UI：收藏开始
    _shareController.add(ShareEvent(
      url: url,
      title: title,
      source: source,
      status: ShareStatus.processing,
    ));

    try {
      // 3. 提取网页内容
      WebPageInfo? info;
      try {
        info = await _extractor.extract(url);
      } catch (e) {
        // 提取失败，用基本信息
        info = WebPageInfo(
          url: url,
          title: title ?? url,
          content: '',
          html: '',
        );
      }

      // 4. 保存到 Obsidian（如果配置了）
      String? obsidianPath;
      try {
        final vaultPath = await _obsidianStore.getVaultPath();
        if (vaultPath != null && vaultPath.isNotEmpty) {
          final files = await _obsidianStore.saveClip(
            info,
            sourceTitle: title ?? '分享收藏',
          );
          obsidianPath = files.first.path;
        }
      } catch (e) {
        // Obsidian 保存失败不影响 ima
      }

      // 5. 上传到 ima（如果配置了）
      bool imaSuccess = false;
      try {
        if (await _imaService.isConfigured()) {
          imaSuccess = await _imaService.uploadDocument(
            title: info.title,
            content: info.content,
            sourceUrl: url,
          );
        }
      } catch (e) {
        // ima 上传失败
      }

      // 6. 更新收藏记录状态
      final success = obsidianPath != null || imaSuccess;
      await _historyStore.updateStatus(
        record.id,
        success ? 'success' : 'failed',
        obsidianPath: obsidianPath,
        imaSynced: imaSuccess,
      );

      // 7. 通知 UI：收藏完成
      _shareController.add(ShareEvent(
        url: url,
        title: title,
        source: source,
        status: success ? ShareStatus.success : ShareStatus.failed,
        message: success ? '收藏成功' : '收藏失败，请检查 Obsidian/ima 配置',
      ));
    } catch (e) {
      // 8. 异常处理
      await _historyStore.updateStatus(record.id, 'failed');
      _shareController.add(ShareEvent(
        url: url,
        title: title,
        source: source,
        status: ShareStatus.failed,
        message: '收藏失败：$e',
      ));
    }
  }

  /// 释放资源。
  void dispose() {
    _shareController.close();
  }
}

/// 分享事件。
class ShareEvent {
  final String url;
  final String? title;
  final String source;
  final ShareStatus status;
  final bool needsConfirmation;
  final String? message;

  ShareEvent({
    required this.url,
    this.title,
    required this.source,
    this.status = ShareStatus.received,
    this.needsConfirmation = false,
    this.message,
  });
}

/// 分享状态。
enum ShareStatus {
  received, // 已接收
  processing, // 处理中
  success, // 成功
  failed, // 失败
}

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_page_info.dart';

/// Obsidian 同步服务（P1：本地直写）。
///
/// 参考 WeChat Inbox Sync 的 "send now, organize later" 模式：
/// 用户浏览网页时点"收藏"，把当前页以 Markdown 形式直接写入
/// Obsidian vault 的收件箱目录，之后在 Obsidian 里再整理。
///
/// 目录结构：
///   `<vault>/Fluxio收件箱/<YYYY-MM-DD-HHmmss>.md`
///
/// 写出的 Markdown 带 frontmatter（来源、URL、标题、捕获时间、标签），
/// 方便 Obsidian 的 Dataview / 搜索 / Graph 视图使用。
class ObsidianStore {
  static const _vaultPathKey = 'fluxio.obsidian.vaultPath.v1';
  static const inboxDirName = 'Fluxio收件箱';

  /// 读取已配置的 vault 绝对路径；未配置返回 null。
  Future<String?> getVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vaultPathKey);
  }

  /// 保存 vault 绝对路径。
  Future<void> setVaultPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vaultPathKey, path.trim());
  }

  /// 校验路径是否可用；返回 null 表示可用，否则返回错误信息。
  Future<String?> validatePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '路径不能为空';
    final dir = Directory(trimmed);
    if (!await dir.exists()) return '目录不存在';
    return null;
  }

  /// 把当前页面写入 Obsidian vault 收件箱，返回写入的文件列表。
  ///
  /// 每次收藏产出：
  /// - `<时间戳>.md`：Obsidian 友好的 Markdown（frontmatter + 链接 + 纯文本摘要，
  ///   若页面有纯文本则写入，无则仅链接）
  /// - `<时间戳>.html`：**完整网页快照**（保留原始样式/图片/布局），页面 HTML
  ///   提取成功时生成，供完整样式阅读
  ///
  /// 抛出 [StateError]：未配置 vault 路径时。
  /// 抛出 [FileSystemException]：写入失败时。
  Future<List<File>> saveClip(
    WebPageInfo info, {
    required String sourceTitle,
  }) async {
    final vaultPath = await getVaultPath();
    if (vaultPath == null || vaultPath.isEmpty) {
      throw StateError('未配置 Obsidian vault 路径，请先在设置中配置');
    }

    final dir = Directory('$vaultPath${Platform.pathSeparator}$inboxDirName');
    await dir.create(recursive: true);

    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch ~/ 1000;
    final baseName =
        '${_pad2(now.year)}-${_pad2(now.month)}-${_pad2(now.day)}-'
        '${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}'
        '-$stamp';

    final files = <File>[];

    // 1) Markdown 摘要（供 Obsidian 检索/双链/快速阅读）。
    final mdFile = File('${dir.path}${Platform.pathSeparator}$baseName.md');
    await mdFile.writeAsString(
      _buildMarkdown(info, sourceTitle: sourceTitle, now: now, htmlBase: baseName),
      encoding: utf8,
    );
    files.add(mdFile);

    // 2) 完整网页快照（保留样式），提取成功时生成。
    final html = info.html?.trim();
    if (html != null && html.isNotEmpty) {
      final htmlFile = File('${dir.path}${Platform.pathSeparator}$baseName.html');
      // 注入 <base href> 确保相对路径的 CSS/图片/字体在本地打开时能正确加载
      final baseTag = '<base href="${info.url}">';
      var htmlWithBase = html;
      if (html.contains(RegExp(r'<head[^>]*>', caseSensitive: false))) {
        htmlWithBase = html.replaceFirst(
          RegExp(r'(<head[^>]*>)', caseSensitive: false),
          '\$1\n$baseTag',
        );
      } else {
        htmlWithBase = '$baseTag\n$html';
      }
      await htmlFile.writeAsString(htmlWithBase, encoding: utf8);
      files.add(htmlFile);
    }

    return files;
  }

  /// 生成带 frontmatter 的 Markdown。
  ///
  /// 有纯文本（[WebPageInfo.content]）时写入完整内容（不截断）；
  /// 无纯文本时回退为"仅链接 + 思考占位"。
  /// [htmlBase] 为同名 HTML 快照的文件基名，用于在 Markdown 中引用。
  String _buildMarkdown(
    WebPageInfo info, {
    required String sourceTitle,
    required DateTime now,
    required String htmlBase,
  }) {
    final content = info.content?.trim();
    final hasContent = content != null && content.isNotEmpty;
    final hasHtml = (info.html?.trim() ?? '').isNotEmpty;

    final body = hasContent
        ? '---\n\n$content\n\n---\n'
        : '<!-- 纯文本提取失败，仅收藏链接 -->\n\n<!-- 在此记录你的思考 -->\n';

    final snapshotLine =
        hasHtml ? '> 完整网页快照：[[$htmlBase.html]]\n' : '';

    return '''---
source: "${_escapeFm(sourceTitle)}"
url: "${_escapeFm(info.url)}"
title: "${_escapeFm(info.title)}"
captured: ${now.toIso8601String()}
type: ${hasHtml ? 'webclip_html' : (hasContent ? 'webclip_content' : 'webclip_link')}
tags:
  - fluxio
  - inbox
---

# ${info.title}

> 来源：$sourceTitle
> 原文：${info.url}
$snapshotLine
$body
''';
  }

  /// 转义 frontmatter 中的特殊字符（引号、反斜杠、换行）。
  String _escapeFm(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}

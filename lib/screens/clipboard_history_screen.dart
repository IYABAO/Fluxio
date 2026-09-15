import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../models/clip_record.dart';
import '../services/clip_history_store.dart';
import 'file_reader_screen.dart';

/// 收藏历史页：统一显示 Obsidian 和 ima 两种方式的收藏记录。
///
/// - 每条记录显示来源标签（Obsidian / ima / Obsidian + ima）、状态、标题、时间
/// - Obsidian 记录可点击打开本地文件
/// - ima 记录可点击打开原文链接
/// - 支持下拉刷新
class ClipboardHistoryScreen extends StatefulWidget {
  const ClipboardHistoryScreen({super.key});

  @override
  State<ClipboardHistoryScreen> createState() => _ClipboardHistoryScreenState();
}

class _ClipboardHistoryScreenState extends State<ClipboardHistoryScreen> {
  final _store = ClipHistoryStore();

  List<ClipRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final records = await _store.getAll();
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// 打开收藏记录：Obsidian 打开本地文件，ima 打开原文链接。
  Future<void> _openRecord(ClipRecord record) async {
    // 如果有本地文件路径，优先打开本地文件
    if (record.localPath != null && record.localPath!.isNotEmpty) {
      try {
        final file = File(record.localPath!);
        if (await file.exists()) {
          if (Platform.isWindows) {
            await Process.start('cmd', ['/c', 'start', '', record.localPath!]);
          } else if (Platform.isMacOS) {
            await Process.start('open', [record.localPath!]);
          } else {
            await Process.start('xdg-open', [record.localPath!]);
          }
          return;
        }
      } catch (_) {}
    }

    // 否则打开原文链接
    try {
      final uri = Uri.parse(record.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败：$e')),
        );
      }
    }
  }

  /// 删除一条收藏记录。
  Future<void> _deleteRecord(ClipRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏记录'),
        content: Text('确定要删除「${record.title}」吗？\n（仅删除本地记录，不删除已保存的文件）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _store.delete(record.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏历史'),
        actions: [
          IconButton(
            tooltip: '打开文件',
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// 打开本地文件（.md / .html），用 Fluxio 阅读器打开。
  Future<void> _openFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'html', 'htm', 'txt'],
        dialogTitle: '选择要打开的文件',
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null && filePath.isNotEmpty) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FileReaderScreen(filePath: filePath),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件失败：$e')),
        );
      }
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              '还没有收藏记录\n收藏网页后会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _records.length,
        itemBuilder: (ctx, index) {
          final record = _records[index];
          return _buildRecordTile(record);
        },
      ),
    );
  }

  Widget _buildRecordTile(ClipRecord record) {
    final isPending = record.status == 'pending';
    final isFailed = record.status == 'failed';
    final isSuccess = record.status == 'success';

    // 状态颜色和图标
    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (isPending) {
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
      statusText = '保存中';
    } else if (isFailed) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
      statusText = '失败';
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
      statusText = '已完成';
    }

    // 来源标签颜色
    Color sourceColor;
    if (record.source.contains('ima') && record.source.contains('Obsidian')) {
      sourceColor = Colors.purple;
    } else if (record.source.contains('ima')) {
      sourceColor = Colors.blue;
    } else {
      sourceColor = Colors.teal;
    }

    return Dismissible(
      key: Key(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteRecord(record),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: sourceColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                record.source,
                style: TextStyle(fontSize: 10, color: sourceColor),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              record.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  _fmt(record.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(fontSize: 11, color: statusColor),
                ),
                if (isFailed && record.errorMessage != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.errorMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
        onTap: () => _openRecord(record),
      ),
    );
  }

  String _fmt(DateTime d) {
    final local = d.toLocal();
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }
}

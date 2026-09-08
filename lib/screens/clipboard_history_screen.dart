import 'dart:io';

import 'package:flutter/material.dart';

import '../services/obsidian_store.dart';

/// 收藏历史页：浏览 Obsidian 收件箱（Fluxio收件箱）里所有收藏文件，
/// 点击用系统默认应用打开（Obsidian / 浏览器等）。
class ClipboardHistoryScreen extends StatefulWidget {
  const ClipboardHistoryScreen({super.key});

  @override
  State<ClipboardHistoryScreen> createState() => _ClipboardHistoryScreenState();
}

class _ClipboardHistoryScreenState extends State<ClipboardHistoryScreen> {
  final _obsidian = ObsidianStore();

  String? _vaultPath;
  List<FileSystemEntity> _files = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vault = await _obsidian.getVaultPath();
      if (vault == null || vault.isEmpty) {
        setState(() {
          _loading = false;
          _error = '未配置 Obsidian vault 路径，请先在设置中配置';
        });
        return;
      }
      final dir = Directory('$vault${Platform.pathSeparator}${ObsidianStore.inboxDirName}');
      final entries = dir.existsSync()
          ? dir
              .listSync()
              .whereType<File>()
              .where((f) =>
                  f.path.endsWith('.md') ||
                  f.path.endsWith('.html') ||
                  f.path.endsWith('.htm'))
              .toList()
          : <File>[];
      entries.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      setState(() {
        _vaultPath = vault;
        _files = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 用系统默认应用打开文件（Windows `start` / mac `open` / linux `xdg-open`）。
  Future<void> _openFile(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else {
        await Process.start('xdg-open', [path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏历史'),
        actions: [
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有收藏记录\n收藏网页后会出现在这里', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '收件箱：${_vaultPath}${Platform.pathSeparator}${ObsidianStore.inboxDirName}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _files.length,
            itemBuilder: (ctx, index) {
              final f = _files[index];
              final name = f.path.split(Platform.pathSeparator).last;
              final base = name.endsWith('.html') || name.endsWith('.htm')
                  ? name.substring(0, name.length - 5)
                  : name.substring(0, name.length - 3);
              final modified = f.statSync().modified;
              final isHtml = name.endsWith('.html') || name.endsWith('.htm');
              return ListTile(
                leading: Icon(
                  isHtml ? Icons.language : Icons.description_outlined,
                  color: isHtml ? Colors.blue : Colors.green,
                ),
                title: Text(base, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fmt(modified)),
                trailing: const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
                onTap: () => _openFile(f.path),
              );
            },
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    final local = d.toLocal();
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }
}

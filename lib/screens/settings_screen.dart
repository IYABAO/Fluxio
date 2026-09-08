import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show inboxServer;
import '../services/obsidian_store.dart';

/// 设置页：配置 Obsidian vault 路径（本地直写同步）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _obsidianStore = ObsidianStore();
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await _obsidianStore.getVaultPath();
    if (path != null && path.isNotEmpty && mounted) {
      _controller.text = path;
    }
  }

  Future<({bool running, String endpoint, String token})> _loadInboxInfo() async {
    final token = await inboxServer.getToken();
    return (
      running: inboxServer.isRunning,
      endpoint: inboxServer.endpoint,
      token: token,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final path = _controller.text.trim();
    final error = await _obsidianStore.validatePath(path);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('路径无效：$error')));
      }
      return;
    }
    setState(() => _saving = true);
    await _obsidianStore.setVaultPath(path);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obsidian vault 已保存，收藏会写入 ${ObsidianStore.inboxDirName}')),
      );
    }
  }

  void _openInbox() async {
    final path = await _obsidianStore.getVaultPath();
    if (path == null || path.isEmpty) return;
    final inbox = Directory(
        '$path${Platform.pathSeparator}${ObsidianStore.inboxDirName}');
    if (!await inbox.exists()) {
      await inbox.create(recursive: true);
    }
    if (Platform.isWindows) {
      Process.run('explorer', [inbox.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Obsidian 同步'),
            subtitle: Text('把浏览的网页收藏为 Markdown，写入你的知识库收件箱'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Obsidian vault 路径',
              hintText: '例如 C:\\Users\\you\\Documents\\MyVault',
              border: OutlineInputBorder(),
              helperText: '填 vault 的绝对路径，收藏会写入其中的 Fluxio收件箱 目录',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openInbox,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开收件箱'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '收件箱（Inbox）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '浏览器扩展 / 剪贴板复制链接 / 手机投递页，通过本地收件服务一键投递收藏。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FutureBuilder<({bool running, String endpoint, String token})>(
                future: _loadInboxInfo(),
                builder: (context, snap) {
                  final info = snap.data;
                  final running = info?.running ?? false;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 10,
                              color: running ? Colors.green : Colors.red),
                          const SizedBox(width: 6),
                          Text(running ? '服务运行中' : '服务未运行',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: running ? Colors.green : Colors.red)),
                          const Spacer(),
                          Text(info?.endpoint ?? '—',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              'Token: ${info?.token ?? '…'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: Colors.blueGrey),
                            ),
                          ),
                          IconButton(
                            tooltip: '复制 Token',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: info == null
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: info.token));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content:
                                                Text('Token 已复制，粘贴到浏览器扩展配置')));
                                  },
                          ),
                          IconButton(
                            tooltip: '重置 Token',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: () async {
                              await inboxServer.resetToken();
                              if (!context.mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Token 已重置，请同步更新扩展配置')));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '投递示例：curl -X POST http://127.0.0.1:8730/api/inbox '
                        '-H "X-Inbox-Token: <token>" -H "Content-Type: application/json" '
                        '-d "{\\"url\\":\\"https://example.com\\",\\"source\\":\\"网页\\"}"',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '同步原理',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '浏览任意网页时点右上角"收藏到 Obsidian"，'
              '当前页面会以 Markdown 形式（含来源/URL/时间/tags 元数据）'
              '写入 <vault>/Fluxio收件箱/，之后在 Obsidian 里整理即可。\n\n'
              '参考 WeChat Inbox Sync 的 send-now-organize-later 模式。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

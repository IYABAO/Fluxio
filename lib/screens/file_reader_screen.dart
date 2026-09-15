import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/clip_record.dart';
import '../models/web_page_info.dart';
import '../services/clip_history_store.dart';
import '../services/ima_service.dart';
import '../services/obsidian_store.dart';

/// 文件阅读器页面：支持打开本地 .md / .html 文件，提供良好的阅读体验。
///
/// - Markdown 文件：使用 flutter_markdown_plus 渲染，支持代码高亮
/// - HTML 文件：使用 WebView 渲染（复用系统 WebView 内核）
/// - 统一界面：标题栏、阅读进度、字体大小调节、收藏按钮
/// - 收藏文件内容到 Obsidian / ima
class FileReaderScreen extends StatefulWidget {
  /// 文件路径（本地文件）
  final String filePath;

  const FileReaderScreen({super.key, required this.filePath});

  @override
  State<FileReaderScreen> createState() => _FileReaderScreenState();
}

class _FileReaderScreenState extends State<FileReaderScreen> {
  final _obsidianStore = ObsidianStore();
  final _imaService = ImaService();
  final _historyStore = ClipHistoryStore();

  late File _file;
  String _fileName = '';
  String _fileExtension = '';
  String _fileContent = '';
  bool _loading = true;
  bool _saving = false;

  // WebViewController（HTML 文件用）
  WebViewController? _webController;

  // 字体大小（Markdown 用）
  double _fontSize = 16.0;

  // 滚动控制器（Markdown 用）
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _file = File(widget.filePath);
    _fileName = _file.uri.pathSegments.last;
    _fileExtension = _fileName.split('.').last.toLowerCase();

    try {
      if (await _file.exists()) {
        _fileContent = await _file.readAsString();

        // HTML 文件：初始化 WebViewController
        if (_fileExtension == 'html' || _fileExtension == 'htm') {
          _webController = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadFile(widget.filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败：$e')),
        );
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 收藏文件内容到 Obsidian / ima。
  Future<void> _saveToObsidian() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 构建 WebPageInfo
      final info = WebPageInfo(
        url: 'file://${widget.filePath}',
        title: _fileName,
        content: _fileContent,
        html: '',
      );

      // 创建收藏记录
      final record = ClipRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        url: 'file://${widget.filePath}',
        title: _fileName,
        source: 'file_reader',
        createdAt: DateTime.now(),
        status: 'pending',
      );
      await _historyStore.add(record);

      // 保存到 Obsidian
      String? obsidianPath;
      try {
        final vaultPath = await _obsidianStore.getVaultPath();
        if (vaultPath != null && vaultPath.isNotEmpty) {
          final files = await _obsidianStore.saveClip(
            info,
            sourceTitle: '本地文件：$_fileName',
          );
          if (files.isNotEmpty) {
            obsidianPath = files.first.path;
          }
        }
      } catch (e) {
        // Obsidian 保存失败不影响 ima
      }

      // 上传到 ima
      bool imaSuccess = false;
      try {
        if (await _imaService.isConfigured()) {
          final result = await _imaService.uploadMarkdown(
            fileName: '$_fileName.md',
            content: _fileContent,
          );
          imaSuccess = result.success;
        }
      } catch (e) {
        // ima 上传失败
      }

      // 更新收藏记录状态
      final success = obsidianPath != null || imaSuccess;
      await _historyStore.updateStatus(
        record.id,
        status: success ? 'success' : 'failed',
        localPath: obsidianPath,
        errorMessage: success ? null : '请检查 Obsidian/ima 配置',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '✅ 收藏成功' : '❌ 收藏失败，请检查 Obsidian/ima 配置'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收藏失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 显示字体大小调节对话框。
  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('字体大小'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: _fontSize,
                  min: 12,
                  max: 24,
                  divisions: 6,
                  label: '${_fontSize.toInt()}px',
                  onChanged: (v) {
                    setDialogState(() => _fontSize = v);
                    setState(() => _fontSize = v);
                  },
                ),
                Text(
                  '当前：${_fontSize.toInt()}px',
                  style: TextStyle(fontSize: _fontSize),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _fileName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // 字体大小（仅 Markdown）
          if (_fileExtension == 'md')
            IconButton(
              tooltip: '字体大小',
              icon: const Icon(Icons.text_fields),
              onPressed: _showFontSizeDialog,
            ),
          // 收藏按钮
          IconButton(
            tooltip: '收藏到 Obsidian / ima',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bookmark_border),
            onPressed: _saving ? null : _saveToObsidian,
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

    if (_fileContent.isEmpty) {
      return const Center(
        child: Text('文件为空或读取失败'),
      );
    }

    // Markdown 文件
    if (_fileExtension == 'md') {
      return _buildMarkdownView();
    }

    // HTML 文件
    if (_fileExtension == 'html' || _fileExtension == 'htm') {
      return _buildHtmlView();
    }

    // 其他文件：纯文本显示
    return _buildTextView();
  }

  /// Markdown 渲染视图。
  Widget _buildMarkdownView() {
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: _fileContent,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(fontSize: _fontSize, height: 1.6),
            h1: TextStyle(fontSize: _fontSize + 10, fontWeight: FontWeight.bold, height: 1.4),
            h2: TextStyle(fontSize: _fontSize + 8, fontWeight: FontWeight.bold, height: 1.4),
            h3: TextStyle(fontSize: _fontSize + 6, fontWeight: FontWeight.bold, height: 1.4),
            h4: TextStyle(fontSize: _fontSize + 4, fontWeight: FontWeight.bold, height: 1.4),
            h5: TextStyle(fontSize: _fontSize + 2, fontWeight: FontWeight.bold, height: 1.4),
            h6: TextStyle(fontSize: _fontSize, fontWeight: FontWeight.bold, height: 1.4),
            listBullet: TextStyle(fontSize: _fontSize),
            tableCellsPadding: const EdgeInsets.all(8),
            tableColumnWidth: const FlexColumnWidth(),
            code: TextStyle(
              fontSize: _fontSize - 2,
              fontFamily: 'monospace',
              backgroundColor: Colors.grey.withOpacity(0.1),
            ),
            codeblockPadding: const EdgeInsets.all(12),
            codeblockDecoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            blockquote: TextStyle(
              fontSize: _fontSize,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
            blockquotePadding: const EdgeInsets.only(left: 12),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey, width: 3)),
            ),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              // 链接点击：用外部浏览器打开
              // 这里可以调用 url_launcher
            }
          },
        ),
      ),
    );
  }

  /// HTML 渲染视图（WebView）。
  Widget _buildHtmlView() {
    if (_webController == null) {
      return const Center(child: Text('WebView 初始化失败'));
    }
    return WebViewWidget(controller: _webController!);
  }

  /// 纯文本视图（其他文件类型）。
  Widget _buildTextView() {
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _fileContent,
          style: TextStyle(fontSize: _fontSize, height: 1.6, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

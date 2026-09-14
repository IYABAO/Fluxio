import 'package:flutter/material.dart';

import '../models/feed_source.dart';
import '../models/preset_sources.dart';
import '../services/remote_source_importer.dart';
import '../services/source_store.dart';

/// 源管理页：添加 / 编辑 / 删除 / 启停 / 分组筛选 / 排序。
///
/// 支持两种源类型：
/// - 网页源：WebView 直接浏览
/// - RSS 订阅源：解析文章列表，点击后用 WebView 打开详情
class ManageSourcesScreen extends StatefulWidget {
  final SourceStore store;

  const ManageSourcesScreen({super.key, required this.store});

  @override
  State<ManageSourcesScreen> createState() => _ManageSourcesScreenState();
}

class _ManageSourcesScreenState extends State<ManageSourcesScreen> {
  List<FeedSource> _sources = [];
  bool _loading = true;

  /// 当前分组筛选：null 表示"全部"。
  String? _groupFilter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.store.load();
    if (mounted) {
      setState(() {
        _sources = list;
        _loading = false;
      });
    }
  }

  /// 当前所有分组名（去重、保持出现顺序）。
  List<String> get _groups {
    final seen = <String>{};
    final result = <String>[];
    for (final s in _sources) {
      if (seen.add(s.group)) result.add(s.group);
    }
    return result;
  }

  List<FeedSource> get _visible {
    final filter = _groupFilter;
    if (filter == null) return _sources;
    return _sources.where((s) => s.group == filter).toList();
  }

  /// 弹出一键导入确认对话框。
  Future<void> _showImportDialog() async {
    final presetCount = PresetSources.count;
    final groups = PresetSources.groups;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('一键导入常用信息源'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将导入 $presetCount 个常用信息源，按以下分组：',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...groups.map((g) {
                final count = PresetSources.byGroup[g]!.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g, style: const TextStyle(fontSize: 13))),
                      Text('$count 个', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.teal),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '相同 URL 的源将覆盖更新（保留启用状态），不同 URL 的源将增量添加。不会删除您已有的源。',
                        style: TextStyle(fontSize: 12, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download),
            label: const Text('开始导入'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await _importPresets();
    }
  }

  /// 执行一键导入。
  Future<void> _importPresets() async {
    // 显示加载中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在导入信息源...'),
          ],
        ),
      ),
    );

    try {
      final result = await widget.store.importPresets();
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        await _reload();
        // 显示导入结果
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入完成：新增 ${result.added} 个，覆盖 ${result.updated} 个，共 ${result.total} 个源'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 弹出从 URL 导入的对话框。
  Future<void> _showUrlImportDialog() async {
    final urlCtrl = TextEditingController(
      text: 'https://raw.githubusercontent.com/IYABAO/Fluxio/refs/heads/main/README.md',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.teal),
            SizedBox(width: 8),
            Text('从 URL 导入信息源'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '输入包含信息源列表的文件 URL，支持 JSON 和 Markdown 格式。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '文件 URL',
                  hintText: 'https://example.com/sources.json',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('支持的格式：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text(
                      'JSON:\n[{"title":"...","url":"...","group":"...","type":"web"}]',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Markdown:\n## 分组名\n- [标题](URL)',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              final url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(ctx, url);
            },
            icon: const Icon(Icons.download),
            label: const Text('开始导入'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      await _importFromUrl(result);
    }
  }

  /// 从 URL 导入信息源。
  Future<void> _importFromUrl(String url) async {
    // 显示加载中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在下载并解析...'),
          ],
        ),
      ),
    );

    try {
      // 下载并解析
      final sources = await RemoteSourceImporter.importFromUrl(url);

      if (sources.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未解析到任何信息源，请检查文件格式'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // 执行导入
      final result = await widget.store.importSources(sources);

      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        await _reload();
        // 显示导入结果
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入完成：解析到 ${sources.length} 个，新增 ${result.added} 个，覆盖 ${result.updated} 个，共 ${result.total} 个源',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 弹出添加对话框（类型 / 名称 / URL / 分组）。
  Future<void> _showAddDialog() async {
    final result = await _showSourceDialog(initial: null);
    if (result == null || !mounted) return;

    var url = result['url']!;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final newSource = FeedSource(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: result['title']!,
      url: url,
      group: result['group']!,
      type: result['type']!,
    );
    setState(() => _sources.add(newSource));
    await widget.store.save(_sources);
  }

  /// 弹出编辑对话框；[initial] 为 null 时是新增，否则编辑。
  Future<Map<String, String>?> _showSourceDialog({FeedSource? initial}) async {
    final isEdit = initial != null;
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final urlCtrl = TextEditingController(text: initial?.url ?? '');
    final groupCtrl = TextEditingController(text: initial?.group ?? kDefaultGroup);
    final groups = _groups;

    String type = initial?.type ?? kSourceTypeWeb;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑信息源' : '添加信息源'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类型选择（仅新增时可改）。
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: kSourceTypeWeb,
                      label: Text('网页'),
                      icon: Icon(Icons.public),
                    ),
                    ButtonSegment(
                      value: kSourceTypeRss,
                      label: Text('RSS 订阅'),
                      icon: Icon(Icons.rss_feed),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: isEdit
                      ? null
                      : (s) => setDialogState(() => type = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '如：大黑AI速报',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: type == kSourceTypeRss ? '订阅 URL' : 'URL',
                    hintText: type == kSourceTypeRss
                        ? 'https://example.com/feed.xml 或 https://example.com/rss'
                        : 'https://news.daheiai.com/',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                // 分组：下拉选择已有分组，或输入新分组。
                Autocomplete<String>(
                  initialValue:
                      TextEditingValue(text: groupCtrl.text),
                  optionsBuilder: (value) {
                    final q = value.text.trim();
                    if (q.isEmpty) return groups;
                    return groups.where((g) => g.contains(q));
                  },
                  onSelected: (v) => groupCtrl.text = v,
                  fieldViewBuilder: (ctx, tc, focus, onField) {
                    groupCtrl.addListener(() {
                      if (tc.text != groupCtrl.text) {
                        tc.value = TextEditingValue(
                            text: groupCtrl.text,
                            selection: TextSelection.collapsed(
                                offset: groupCtrl.text.length));
                      }
                    });
                    return TextField(
                      controller: tc,
                      decoration: const InputDecoration(
                        labelText: '分组',
                        hintText: '默认',
                        helperText: '可输入新分组名',
                      ),
                      focusNode: focus,
                      onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                final url = urlCtrl.text.trim();
                final group = groupCtrl.text.trim().isEmpty
                    ? kDefaultGroup
                    : groupCtrl.text.trim();
                if (title.isEmpty || url.isEmpty) return;
                Navigator.pop(
                    ctx, {'title': title, 'url': url, 'group': group, 'type': type});
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  /// 编辑一个源。
  Future<void> _editSource(int index) async {
    final s = _sources[index];
    final result = await _showSourceDialog(initial: s);
    if (result == null || !mounted) return;
    var url = result['url']!;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    setState(() {
      _sources[index] = s.copyWith(
        title: result['title']!,
        url: url,
        group: result['group']!,
        type: result['type']!,
      );
    });
    await widget.store.save(_sources);
  }

  /// 启停切换。
  Future<void> _toggleEnabled(int index) async {
    final s = _sources[index];
    setState(() => _sources[index] = s.copyWith(enabled: !s.enabled));
    await widget.store.save(_sources);
  }

  /// 删除一个源。
  Future<void> _removeSource(int index) async {
    final s = _sources[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除信息源'),
        content: Text('确定删除「${s.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _sources.removeAt(index));
      await widget.store.save(_sources);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('信息源管理'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导入信息源',
            icon: const Icon(Icons.download_outlined),
            onSelected: (value) {
              if (value == 'preset') {
                _showImportDialog();
              } else if (value == 'url') {
                _showUrlImportDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'preset',
                child: Row(
                  children: [
                    Icon(Icons.star_outline, size: 20),
                    SizedBox(width: 12),
                    Text('导入预设源（22个常用源）'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'url',
                child: Row(
                  children: [
                    Icon(Icons.link, size: 20),
                    SizedBox(width: 12),
                    Text('从 URL 导入（自定义源列表）'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: '添加信息源',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? const Center(
                  child: Text(
                    '还没有信息源\n点击右下角 + 添加第一个网址',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    // 分组筛选 Chips。
                    _groupFilterBar(),
                    const Divider(height: 1),
                    Expanded(child: _sourceList()),
                  ],
                ),
    );
  }

  /// 分组筛选 Chips（全部 + 各分组）。
  Widget _groupFilterBar() {
    final groups = _groups;
    final filter = _groupFilter;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('全部 (${_sources.length})'),
              selected: filter == null,
              onSelected: (_) => setState(() => _groupFilter = null),
            ),
          ),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g),
                selected: filter == g,
                onSelected: (_) => setState(() => _groupFilter = g),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceList() {
    final visible = _visible;
    if (visible.isEmpty) {
      return const Center(
        child: Text('该分组下没有信息源', style: TextStyle(color: Colors.grey)),
      );
    }
    return ReorderableListView.builder(
      itemCount: visible.length,
      onReorderItem: (oldIndex, newIndex) {
        // 在完整列表中重排（分组筛选下只重排当前分组的可见顺序）。
        final item = visible[oldIndex];
        final fullIndex = _sources.indexOf(item);
        setState(() => _sources.removeAt(fullIndex));
        // 映射回完整列表目标位置。
        var target = newIndex;
        final targetItem = target < visible.length ? visible[target] : null;
        final insertAt = targetItem == null ? _sources.length : _sources.indexOf(targetItem);
        _sources.insert(insertAt, item);
        widget.store.save(_sources);
      },
      itemBuilder: (ctx, index) {
        final s = visible[index];
        final fullIndex = _sources.indexOf(s);
        return ListTile(
          key: ValueKey(s.id),
          leading: Switch(
            value: s.enabled,
            onChanged: (_) => _toggleEnabled(fullIndex),
          ),
          title: Row(
            children: [
              Flexible(child: Text(s.title, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Icon(
                s.isRss ? Icons.rss_feed : Icons.public,
                size: 14,
                color: s.isRss ? Colors.orange : Colors.blueGrey,
              ),
            ],
          ),
          subtitle: Text(
            '${s.group} · ${s.url}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editSource(fullIndex),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removeSource(fullIndex),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/biometric_service.dart';
import '../../../models/item.dart';
import '../../item_detail/presentation/item_detail_screen.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collections = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient();
      final cols = await api.listCollections();
      if (!mounted) return;
      setState(() {
        _collections = cols;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String? theme;
    bool isPrivate = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('创建收藏馆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '描述(可选)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: theme,
                items: const [
                  DropdownMenuItem(value: null, child: Text('主题：默认')),
                  DropdownMenuItem(value: 'nostalgia', child: Text('主题：怀旧')),
                  DropdownMenuItem(value: 'museum', child: Text('主题：博物馆')),
                  DropdownMenuItem(value: 'diary', child: Text('主题：日记')),
                  DropdownMenuItem(value: 'minimal', child: Text('主题：极简')),
                ],
                onChanged: (v) => setLocal(() => theme = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('私密'),
                value: isPrivate,
                onChanged: (v) => setLocal(() => isPrivate = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final name = nameController.text.trim();
      final desc = descController.text.trim();
      if (name.isEmpty) return;
      setState(() => _loading = true);
      try {
        final api = ApiClient();
        await api.createCollection(
          name: name,
          description: desc.isEmpty ? null : desc,
          theme: theme,
          isPrivate: isPrivate,
        );
        await _fetch();
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCollection(Map<String, dynamic> col) async {
    final isPrivate = (col['is_private'] as bool?) ?? true;
    if (isPrivate) {
      final bio = BiometricService();
      // Only require auth if hardware is available
      if (await bio.isAvailable) {
        final authenticated = await bio.authenticate(reason: '验证身份以查看私密收藏馆');
        if (!authenticated) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('验证失败，无法查看')));
          }
          return;
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CollectionDetailScreen(collection: col),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏馆'),
        actions: [
          IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _collections.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final c = _collections[index];
                  final name = c['name'] as String? ?? '未命名';
                  final desc = c['description'] as String?;
                  final isPrivate = (c['is_private'] as bool?) ?? true;
                  final theme = c['theme'] as String?;
                  final count =
                      (c['items'] as List<dynamic>? ?? const []).length;
                  return ListTile(
                    title: Row(
                      children: [
                        Text(name),
                        if (isPrivate) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.lock, size: 14, color: Colors.grey),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      [
                        if (desc != null && desc.isNotEmpty) desc,
                        '共 $count 件',
                        isPrivate ? '私密' : '公开',
                        if (theme != null && theme.isNotEmpty) '主题:$theme',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openCollection(c),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新建收藏馆'),
      ),
    );
  }
}

class _CollectionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> collection;
  const _CollectionDetailScreen({required this.collection});

  @override
  State<_CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<_CollectionDetailScreen> {
  bool _loading = true;
  String? _error;
  List<Item> _items = const [];
  bool _isPrivate = true;
  late Map<String, dynamic> _collection;
  _CollectionViewMode _viewMode = _CollectionViewMode.grid;

  @override
  void initState() {
    super.initState();
    _collection = Map<String, dynamic>.from(widget.collection);
    _isPrivate = (_collection['is_private'] as bool?) ?? true;
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiClient();
      final items = await api.listCollectionItems(_collection['id'] as String);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _editCollection() async {
    final nameController = TextEditingController(
      text: _collection['name'] as String? ?? '',
    );
    final descController = TextEditingController(
      text: _collection['description'] as String? ?? '',
    );
    String? theme = _collection['theme'] as String?;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setLocal) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('编辑收藏馆', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: '描述(可选)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: theme,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('主题：默认')),
                    DropdownMenuItem(value: 'nostalgia', child: Text('主题：怀旧')),
                    DropdownMenuItem(value: 'museum', child: Text('主题：博物馆')),
                    DropdownMenuItem(value: 'diary', child: Text('主题：日记')),
                    DropdownMenuItem(value: 'minimal', child: Text('主题：极简')),
                  ],
                  onChanged: (v) => setLocal(() => theme = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true) return;
    final name = nameController.text.trim();
    final desc = descController.text.trim();
    if (name.isEmpty) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final api = ApiClient();
      final updated = await api.updateCollection(
        collectionId: _collection['id'] as String,
        name: name,
        description: desc.isEmpty ? null : desc,
        theme: theme,
      );
      if (!mounted) return;
      setState(() {
        _collection = updated;
        _isPrivate = (_collection['is_private'] as bool?) ?? true;
      });
      messenger?.showSnackBar(const SnackBar(content: Text('已更新')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('更新失败: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFromCollection(Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('移除物品'),
        content: Text('确定从该收藏馆移除“${item.title ?? '未命名'}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final api = ApiClient();
      await api.removeItemFromCollection(
        collectionId: _collection['id'] as String,
        itemId: item.id,
      );
      await _fetch();
      messenger?.showSnackBar(const SnackBar(content: Text('已移除')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('移除失败: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openItem(Item item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)));
  }

  void _openExhibit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CollectionExhibitScreen(
          title: _collection['name'] as String? ?? '未命名',
          items: _items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _collection['name'] as String? ?? '未命名';
    final theme = _collection['theme'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          PopupMenuButton<_CollectionViewMode>(
            initialValue: _viewMode,
            onSelected: (v) {
              if (v == _CollectionViewMode.exhibit) {
                _openExhibit();
                return;
              }
              setState(() => _viewMode = v);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _CollectionViewMode.grid, child: Text('网格')),
              PopupMenuItem(
                value: _CollectionViewMode.waterfall,
                child: Text('瀑布流'),
              ),
              PopupMenuItem(
                value: _CollectionViewMode.exhibit,
                child: Text('沉浸式展览'),
              ),
            ],
          ),
          IconButton(
            onPressed: _editCollection,
            icon: const Icon(Icons.edit),
            tooltip: '编辑',
          ),
          Row(
            children: [
              const Text('私密'),
              Switch(
                value: _isPrivate,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  setState(() => _isPrivate = v);
                  try {
                    final api = ApiClient();
                    await api.updateCollection(
                      collectionId: _collection['id'] as String,
                      isPrivate: v,
                    );
                    _collection['is_private'] = v;
                    messenger?.showSnackBar(
                      const SnackBar(content: Text('隐私设置已更新')),
                    );
                  } catch (e) {
                    setState(() => _isPrivate = !v);
                    messenger?.showSnackBar(
                      SnackBar(content: Text('更新失败: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                if (theme != null && theme.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('主题：$theme'),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetch,
                    child: _viewMode == _CollectionViewMode.waterfall
                        ? MasonryGridView.count(
                            padding: const EdgeInsets.all(8),
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            itemCount: _items.length,
                            itemBuilder: (context, index) =>
                                _CollectionItemTile(
                                  item: _items[index],
                                  onOpen: _openItem,
                                  onRemove: _removeFromCollection,
                                ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) =>
                                _CollectionItemTile(
                                  item: _items[index],
                                  onOpen: _openItem,
                                  onRemove: _removeFromCollection,
                                ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

enum _CollectionViewMode { grid, waterfall, exhibit }

class _CollectionItemTile extends StatelessWidget {
  final Item item;
  final void Function(Item item) onOpen;
  final void Function(Item item) onRemove;

  const _CollectionItemTile({
    required this.item,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final base = ApiClient().baseUrl;
    final img = item.imagePaths.isNotEmpty
        ? '$base${item.imagePaths.first}'
        : null;
    return InkWell(
      onTap: () => onOpen(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (img != null)
              Positioned.fill(child: Image.network(img, fit: BoxFit.cover))
            else
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Text('无图')),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => onRemove(item),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                padding: const EdgeInsets.all(8),
                child: Text(
                  item.title ?? '未命名',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionExhibitScreen extends StatefulWidget {
  final String title;
  final List<Item> items;

  const _CollectionExhibitScreen({required this.title, required this.items});

  @override
  State<_CollectionExhibitScreen> createState() =>
      _CollectionExhibitScreenState();
}

class _CollectionExhibitScreenState extends State<_CollectionExhibitScreen> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.title} (${_index + 1}/${items.length})'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('暂无物品', style: TextStyle(color: Colors.white)),
            )
          : PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, index) {
                final item = items[index];
                final base = ApiClient().baseUrl;
                final img = item.imagePaths.isNotEmpty
                    ? '$base${item.imagePaths.first}'
                    : null;
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(item: item),
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (img != null)
                        Positioned.fill(
                          child: Image.network(img, fit: BoxFit.contain),
                        )
                      else
                        const Center(
                          child: Text(
                            '无图',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 24,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            item.title ?? '未命名',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

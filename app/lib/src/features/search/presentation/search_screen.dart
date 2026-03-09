import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../core/services/api_client.dart';
import '../../../models/item.dart';
import '../../item_detail/presentation/item_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Item> _results = [];
  bool _loading = false;
  String? _selectedTag;
  String? _selectedMood;
  String? _selectedCategory;

  // Pre-defined filters for quick access
  final _tags = ['复古', '金属', '木质', '电子', '玩具', 'hidden'];
  final _moods = ['怀旧', '温暖', '忧郁', '宁静', '神秘'];
  final _categories = ['衣物', '电子用品', '家具', '玩具', '纸制品', '生活用品'];

  @override
  void initState() {
    super.initState();
    // Load initial data (all items)
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final items = await api.listItems(
        query: _searchCtrl.text.trim(),
        tag: _selectedTag,
        mood: _selectedMood,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() => _results = items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('搜索失败: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedTag = null;
      _selectedMood = null;
      _selectedCategory = null;
      _searchCtrl.clear();
    });
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: '搜索物品...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (_selectedTag != null ||
                    _selectedMood != null ||
                    _selectedCategory != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: _clearFilters,
                      tooltip: '清除筛选',
                    ),
                  ),
                _buildFilterChip<String>(
                  label: '分类',
                  value: _selectedCategory,
                  options: _categories,
                  onSelected: (v) {
                    setState(() => _selectedCategory = v);
                    _search();
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip<String>(
                  label: '情绪',
                  value: _selectedMood,
                  options: _moods,
                  onSelected: (v) {
                    setState(() => _selectedMood = v);
                    _search();
                  },
                ),
                const SizedBox(width: 8),
                _buildFilterChip<String>(
                  label: '标签',
                  value: _selectedTag,
                  options: _tags,
                  onSelected: (v) {
                    setState(() => _selectedTag = v);
                    _search();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? const Center(child: Text('未找到相关物品'))
                : MasonryGridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return _SearchItemTile(item: item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip<T>({
    required String label,
    required T? value,
    required List<T> options,
    required ValueChanged<T?> onSelected,
  }) {
    return FilterChip(
      label: Text(value?.toString() ?? label),
      selected: value != null,
      onSelected: (_) async {
        final result = await showMenu<T>(
          context: context,
          position: const RelativeRect.fromLTRB(0, 0, 0, 0), // Placeholder
          items: [
            const PopupMenuItem(value: null, child: Text('全部')),
            ...options.map(
              (o) => PopupMenuItem(value: o, child: Text(o.toString())),
            ),
          ],
        );
        if (result != value) {
          onSelected(result);
        }
      },
      showCheckmark: false,
      deleteIcon: const Icon(Icons.arrow_drop_down, size: 18),
      onDeleted: () async {
        // Trigger the menu again
        final result = await showMenu<T>(
          context: context,
          position: RelativeRect.fromLTRB(
            // Approximate position, hard to get exact in this context
            // Ideally we use a GlobalKey to find render box
            0,
            100,
            0,
            0,
          ),
          items: [
            const PopupMenuItem(value: null, child: Text('全部')),
            ...options.map(
              (o) => PopupMenuItem(value: o, child: Text(o.toString())),
            ),
          ],
        );
        onSelected(result);
      },
    );
  }
}

class _SearchItemTile extends StatelessWidget {
  final Item item;

  const _SearchItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final base = ApiClient().baseUrl;
    final img = item.imagePaths.isNotEmpty
        ? '$base${item.imagePaths.first}'
        : null;

    return InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)));
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: img != null
                ? Image.network(img, fit: BoxFit.cover)
                : Container(
                    height: 120,
                    color: Colors.grey[200],
                    child: const Center(child: Icon(Icons.image_not_supported)),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title ?? '未命名',
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.category != null)
            Text(item.category!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

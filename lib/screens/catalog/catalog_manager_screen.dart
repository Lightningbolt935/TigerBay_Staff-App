import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color constants
// ─────────────────────────────────────────────────────────────────────────────

const _kGold = Color(0xFFD4AF37);
const _kDark = Color(0xFF121212);
const _kCardBg = Color(0xFF1E1E1E);
const _kBorder = Color(0xFF2C2C2C);
const _kTextSecondary = Color(0xFF8A8B92);

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _Dish {
  final int id;
  final String name;
  final double price;
  final String description;
  final String? imageUrl;

  const _Dish({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    this.imageUrl,
  });

  factory _Dish.fromMap(Map<String, dynamic> m) => _Dish(
        id: (m['id'] as num).toInt(),
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        description: m['description'] as String? ?? '',
        imageUrl: m['image_url'] as String?,
      );
}

class _Reward {
  final int id;
  final String title;
  final int pointsRequired;
  final String description;
  final String? imageUrl;

  const _Reward({
    required this.id,
    required this.title,
    required this.pointsRequired,
    required this.description,
    this.imageUrl,
  });

  factory _Reward.fromMap(Map<String, dynamic> m) => _Reward(
        id: (m['id'] as num).toInt(),
        title: m['title'] as String? ?? '',
        pointsRequired: (m['points_required'] as num?)?.toInt() ?? 0,
        description: m['description'] as String? ?? '',
        imageUrl: m['image_url'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Full CRUD Catalog & Rewards Manager.
/// - Tab 1: Dishes  (table: `dishes`,  bucket: `MENU`)
/// - Tab 2: Rewards (table: `rewards`, bucket: `Rewards`)
class CatalogManagerScreen extends StatefulWidget {
  const CatalogManagerScreen({super.key});

  @override
  State<CatalogManagerScreen> createState() => _CatalogManagerScreenState();
}

class _CatalogManagerScreenState extends State<CatalogManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final SupabaseService _supabase = SupabaseService();

  List<_Dish> _dishes = [];
  List<_Reward> _rewards = [];

  bool _loadingDishes = true;
  bool _loadingRewards = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loaders ──────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadDishes(), _loadRewards()]);
  }

  Future<void> _loadDishes() async {
    if (!mounted) return;
    setState(() => _loadingDishes = true);
    try {
      final rows = await _supabase.getDishes();
      if (mounted) {
        setState(() => _dishes = rows.map(_Dish.fromMap).toList());
      }
    } catch (e) {
      if (mounted) _showError('Failed to load dishes: $e');
    } finally {
      if (mounted) setState(() => _loadingDishes = false);
    }
  }

  Future<void> _loadRewards() async {
    if (!mounted) return;
    setState(() => _loadingRewards = true);
    try {
      final rows = await _supabase.getRewards();
      if (mounted) {
        setState(() => _rewards = rows.map(_Reward.fromMap).toList());
      }
    } catch (e) {
      if (mounted) _showError('Failed to load rewards: $e');
    } finally {
      if (mounted) setState(() => _loadingRewards = false);
    }
  }

  // ── CRUD: Dishes ──────────────────────────────────────────────────────────

  Future<void> _addDish(_DishFormResult r) async {
    String? imageUrl;
    if (r.imageFile != null) {
      imageUrl = await _uploadImage(
        file: r.imageFile!,
        bucket: 'MENU',
        pathPrefix: 'item',
      );
    }
    await _supabase.insertDish(
      name: r.name,
      price: r.price,
      description: r.description,
      imageUrl: imageUrl,
    );
    await _loadDishes();
  }

  Future<void> _updateDish(_Dish dish, _DishFormResult r) async {
    String? imageUrl = dish.imageUrl;
    if (r.imageFile != null) {
      imageUrl = await _uploadImage(
        file: r.imageFile!,
        bucket: 'MENU',
        pathPrefix: 'item',
      );
    }
    await _supabase.updateDish(
      id: dish.id,
      name: r.name,
      price: r.price,
      description: r.description,
      imageUrl: imageUrl,
    );
    await _loadDishes();
  }

  Future<void> _deleteDish(_Dish dish) async {
    final confirmed = await _confirmDelete(dish.name);
    if (!confirmed) return;
    try {
      await _supabase.deleteDish(dish.id);
      await _loadDishes();
    } catch (e) {
      if (mounted) _showError('Delete failed: $e');
    }
  }

  // ── CRUD: Rewards ─────────────────────────────────────────────────────────

  Future<void> _addReward(_RewardFormResult r) async {
    String? imageUrl;
    if (r.imageFile != null) {
      imageUrl = await _uploadImage(
        file: r.imageFile!,
        bucket: 'Rewards',
        pathPrefix: 'reward',
      );
    }
    await _supabase.insertReward(
      title: r.title,
      pointsRequired: r.pointsRequired,
      description: r.description,
      imageUrl: imageUrl,
    );
    await _loadRewards();
  }

  Future<void> _updateReward(_Reward reward, _RewardFormResult r) async {
    String? imageUrl = reward.imageUrl;
    if (r.imageFile != null) {
      imageUrl = await _uploadImage(
        file: r.imageFile!,
        bucket: 'Rewards',
        pathPrefix: 'reward',
      );
    }
    await _supabase.updateReward(
      id: reward.id,
      title: r.title,
      pointsRequired: r.pointsRequired,
      description: r.description,
      imageUrl: imageUrl,
    );
    await _loadRewards();
  }

  Future<void> _deleteReward(_Reward reward) async {
    final confirmed = await _confirmDelete(reward.title);
    if (!confirmed) return;
    try {
      await _supabase.deleteReward(reward.id);
      await _loadRewards();
    } catch (e) {
      if (mounted) _showError('Delete failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _uploadImage({
    required File file,
    required String bucket,
    required String pathPrefix,
  }) async {
    final bytes = await file.readAsBytes();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${pathPrefix}_$ts.jpg';
    return _supabase.uploadCatalogImage(
      bucket: bucket,
      path: path,
      bytes: bytes,
      mimeType: 'image/jpeg',
    );
  }

  Future<bool> _confirmDelete(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _kCardBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Confirm Delete',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Are you sure you want to delete "$name"? This cannot be undone.',
              style: const TextStyle(color: _kTextSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: _kTextSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
    ));
  }

  // ── Sheet launchers ───────────────────────────────────────────────────────

  void _openDishForm({_Dish? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DishFormSheet(
        existing: existing,
        onSave: (result) async {
          if (existing == null) {
            await _addDish(result);
          } else {
            await _updateDish(existing, result);
          }
        },
      ),
    );
  }

  void _openRewardForm({_Reward? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RewardFormSheet(
        existing: existing,
        onSave: (result) async {
          if (existing == null) {
            await _addReward(result);
          } else {
            await _updateReward(existing, result);
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Catalog & Rewards',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kGold,
          labelColor: _kGold,
          unselectedLabelColor: _kTextSecondary,
          tabs: const [
            Tab(text: 'Menu Items'),
            Tab(text: 'Rewards'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) {
          final isDishes = _tabController.index == 0;
          return FloatingActionButton.extended(
            backgroundColor: _kGold,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: Text(
              isDishes ? 'Add Dish' : 'Add Reward',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              if (isDishes) {
                _openDishForm();
              } else {
                _openRewardForm();
              }
            },
          );
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DishesTab(
            dishes: _dishes,
            loading: _loadingDishes,
            onEdit: (d) => _openDishForm(existing: d),
            onDelete: _deleteDish,
          ),
          _RewardsTab(
            rewards: _rewards,
            loading: _loadingRewards,
            onEdit: (r) => _openRewardForm(existing: r),
            onDelete: _deleteReward,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Dishes
// ─────────────────────────────────────────────────────────────────────────────

class _DishesTab extends StatelessWidget {
  final List<_Dish> dishes;
  final bool loading;
  final void Function(_Dish) onEdit;
  final void Function(_Dish) onDelete;

  const _DishesTab({
    required this.dishes,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: _kGold));
    }
    if (dishes.isEmpty) {
      return const _EmptyState(
        icon: Icons.restaurant_menu_outlined,
        message: 'No dishes yet.\nTap "Add Dish" to get started.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: dishes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final d = dishes[i];
        return _ItemCard(
          imageUrl: d.imageUrl,
          title: d.name,
          subtitle: '£${d.price.toStringAsFixed(2)}',
          description: d.description,
          onEdit: () => onEdit(d),
          onDelete: () => onDelete(d),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Rewards
// ─────────────────────────────────────────────────────────────────────────────

class _RewardsTab extends StatelessWidget {
  final List<_Reward> rewards;
  final bool loading;
  final void Function(_Reward) onEdit;
  final void Function(_Reward) onDelete;

  const _RewardsTab({
    required this.rewards,
    required this.loading,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: _kGold));
    }
    if (rewards.isEmpty) {
      return const _EmptyState(
        icon: Icons.card_giftcard_outlined,
        message: 'No rewards yet.\nTap "Add Reward" to get started.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: rewards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = rewards[i];
        return _ItemCard(
          imageUrl: r.imageUrl,
          title: r.title,
          subtitle: '${r.pointsRequired} pts',
          description: r.description,
          onEdit: () => onEdit(r),
          onDelete: () => onDelete(r),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Item Card
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Thumbnail ──
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: _Thumbnail(imageUrl: imageUrl),
          ),
          // ── Info ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(subtitle,
                        style: const TextStyle(
                            color: _kGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _kTextSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          // ── Actions ──
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: _kGold,
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.redAccent,
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  const _Thumbnail({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(size),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: size,
                height: size,
                color: _kBorder,
                child: const Center(
                    child: CircularProgressIndicator(
                        color: _kGold, strokeWidth: 2)),
              ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) => Container(
        width: size,
        height: size,
        color: _kBorder,
        child: const Icon(Icons.image_not_supported_outlined,
            color: _kTextSecondary, size: 28),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: _kTextSecondary),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dish Form Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DishFormResult {
  final String name;
  final double price;
  final String description;
  final File? imageFile;
  const _DishFormResult({
    required this.name,
    required this.price,
    required this.description,
    this.imageFile,
  });
}

class _DishFormSheet extends StatefulWidget {
  final _Dish? existing;
  final Future<void> Function(_DishFormResult) onSave;

  const _DishFormSheet({this.existing, required this.onSave});

  @override
  State<_DishFormSheet> createState() => _DishFormSheetState();
}

class _DishFormSheetState extends State<_DishFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _desc;
  File? _imageFile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price =
        TextEditingController(text: e != null ? e.price.toString() : '');
    _desc = TextEditingController(text: e?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_DishFormResult(
        name: _name.text.trim(),
        price: double.tryParse(_price.text.trim()) ?? 0.0,
        description: _desc.text.trim(),
        imageFile: _imageFile,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return _FormSheetWrapper(
      title: isEdit ? 'Edit Dish' : 'Add Dish',
      saving: _saving,
      onSave: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImagePickerBox(
              file: _imageFile,
              existingUrl: widget.existing?.imageUrl,
              onTap: _saving ? null : _pickImage,
            ),
            const SizedBox(height: 16),
            _FormField(
              controller: _name,
              label: 'Dish Name',
              hint: 'e.g. Tiger Roll',
              enabled: !_saving,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _price,
              label: 'Price (£)',
              hint: 'e.g. 12.99',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Price is required';
                if (double.tryParse(v.trim()) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _desc,
              label: 'Description',
              hint: 'Short description...',
              maxLines: 3,
              enabled: !_saving,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reward Form Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RewardFormResult {
  final String title;
  final int pointsRequired;
  final String description;
  final File? imageFile;
  const _RewardFormResult({
    required this.title,
    required this.pointsRequired,
    required this.description,
    this.imageFile,
  });
}

class _RewardFormSheet extends StatefulWidget {
  final _Reward? existing;
  final Future<void> Function(_RewardFormResult) onSave;

  const _RewardFormSheet({this.existing, required this.onSave});

  @override
  State<_RewardFormSheet> createState() => _RewardFormSheetState();
}

class _RewardFormSheetState extends State<_RewardFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _points;
  late final TextEditingController _desc;
  File? _imageFile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _points = TextEditingController(
        text: e != null ? e.pointsRequired.toString() : '');
    _desc = TextEditingController(text: e?.description ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _points.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_RewardFormResult(
        title: _title.text.trim(),
        pointsRequired: int.tryParse(_points.text.trim()) ?? 0,
        description: _desc.text.trim(),
        imageFile: _imageFile,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return _FormSheetWrapper(
      title: isEdit ? 'Edit Reward' : 'Add Reward',
      saving: _saving,
      onSave: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImagePickerBox(
              file: _imageFile,
              existingUrl: widget.existing?.imageUrl,
              onTap: _saving ? null : _pickImage,
            ),
            const SizedBox(height: 16),
            _FormField(
              controller: _title,
              label: 'Reward Title',
              hint: 'e.g. Free Dessert',
              enabled: !_saving,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _points,
              label: 'Points Required',
              hint: 'e.g. 500',
              keyboardType: TextInputType.number,
              enabled: !_saving,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Points is required';
                if (int.tryParse(v.trim()) == null) return 'Enter a whole number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _desc,
              label: 'Description',
              hint: 'Short description...',
              maxLines: 3,
              enabled: !_saving,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Form Components
// ─────────────────────────────────────────────────────────────────────────────

class _FormSheetWrapper extends StatelessWidget {
  final String title;
  final bool saving;
  final VoidCallback onSave;
  final Widget child;

  const _FormSheetWrapper({
    required this.title,
    required this.saving,
    required this.onSave,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            child,
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: _kGold.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: saving ? null : onSave,
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2.5),
                      )
                    : const Text('Save',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  final File? file;
  final String? existingUrl;
  final VoidCallback? onTap;

  const _ImagePickerBox({this.file, this.existingUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (file != null) {
      content = Image.file(file!, fit: BoxFit.cover);
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      content = Image.network(existingUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    } else {
      content = _placeholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _kDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kGold.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_camera_outlined,
                        size: 14, color: Colors.black),
                    SizedBox(width: 4),
                    Text('Change Photo',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 36, color: _kTextSecondary),
          SizedBox(height: 8),
          Text('Tap to choose image',
              style: TextStyle(color: _kTextSecondary, fontSize: 13)),
        ],
      );
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          enabled: enabled,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _kTextSecondary.withValues(alpha: 0.5)),
            filled: true,
            fillColor: _kDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kGold),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.danger),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

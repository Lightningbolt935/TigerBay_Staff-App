import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/staff_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local color constants (dark-themed, matching CatalogManagerScreen)
// ─────────────────────────────────────────────────────────────────────────────

const _kGold = Color(0xFFD4AF37);
const _kDark = Color(0xFF121212);
const _kCardBg = Color(0xFF1E1E1E);
const _kBorder = Color(0xFF2C2C2C);
const _kTextSecondary = Color(0xFF8A8B92);

// ─────────────────────────────────────────────────────────────────────────────
// Local data model — mirrors the `newsfeed` Supabase table exactly
// ─────────────────────────────────────────────────────────────────────────────

class _NewsPost {
  final int id;
  final String title;
  final String subtitle;
  final String content;
  final String? imageUrl;
  final bool isPremium;
  final DateTime createdAt;
  final dynamic branchId; // nullable bigint / uuid

  const _NewsPost({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.content,
    this.imageUrl,
    required this.isPremium,
    required this.createdAt,
    this.branchId,
  });

  factory _NewsPost.fromMap(Map<String, dynamic> m) => _NewsPost(
        id: (m['id'] as num).toInt(),
        title: m['title'] as String? ?? '',
        subtitle: m['subtitle'] as String? ?? '',
        content: m['content'] as String? ?? '',
        imageUrl: m['image_url'] as String?,
        isPremium: m['is_premium'] as bool? ?? false,
        createdAt: DateTime.parse(m['created_at'] as String),
        branchId: m['branch_id'],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Full CRUD News Feed Manager.
/// Table: `newsfeed` | Storage bucket: `news`
class NewsFeedManagerScreen extends StatefulWidget {
  const NewsFeedManagerScreen({super.key});

  @override
  State<NewsFeedManagerScreen> createState() => _NewsFeedManagerScreenState();
}

class _NewsFeedManagerScreenState extends State<NewsFeedManagerScreen> {
  final _supabase = Supabase.instance.client;

  List<_NewsPost> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPosts());
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadPosts() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('newsfeed')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _posts = (rows as List<dynamic>)
              .map((e) => _NewsPost.fromMap(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) _showError('Failed to load posts: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _savePost(_NewsFormResult r, {_NewsPost? existing}) async {
    String? imageUrl = existing?.imageUrl;

    // Upload new image if one was selected
    if (r.imageFile != null) {
      final bytes = await r.imageFile!.readAsBytes();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'news/post_$ts.jpg';
      await _supabase.storage
          .from('news')
          .uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      imageUrl = _supabase.storage.from('news').getPublicUrl(path);
    }

    final payload = <String, dynamic>{
      'title': r.title,
      'subtitle': r.subtitle,
      'content': r.content,
      'image_url': imageUrl,
      'is_premium': r.isPremium,
      if (r.branchId != null) 'branch_id': r.branchId,
    };

    if (existing == null) {
      await _supabase.from('newsfeed').insert(payload);
    } else {
      await _supabase.from('newsfeed').update(payload).eq('id', existing.id);
    }

    await _loadPosts();
  }

  Future<void> _deletePost(_NewsPost post) async {
    final confirmed = await _confirmDelete(post.title);
    if (!confirmed) return;
    try {
      await _supabase.from('newsfeed').delete().eq('id', post.id);
      await _loadPosts();
    } catch (e) {
      if (mounted) _showError('Delete failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _confirmDelete(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _kCardBg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Post',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Are you sure you want to delete "$title"? This cannot be undone.',
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

  void _openForm({_NewsPost? existing}) {
    final branchId = context.read<StaffProvider>().branch?.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewsFormSheet(
        existing: existing,
        activeBranchId: branchId,
        onSave: (result) => _savePost(result, existing: existing),
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
        leading: const BackButton(),
        title: const Text(
          'News Feed Manager',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextSecondary),
            tooltip: 'Refresh',
            onPressed: _loadPosts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kGold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Post News',
            style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kGold))
          : _posts.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  color: _kGold,
                  backgroundColor: _kCardBg,
                  onRefresh: _loadPosts,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final post = _posts[i];
                      return _NewsCard(
                        post: post,
                        onEdit: () => _openForm(existing: post),
                        onDelete: () => _deletePost(post),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// News Card
// ─────────────────────────────────────────────────────────────────────────────

class _NewsCard extends StatelessWidget {
  final _NewsPost post;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NewsCard({
    required this.post,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero image ──
          if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: _NetworkImage(
                url: post.imageUrl!,
                height: 160,
                width: double.infinity,
              ),
            )
          else
            const _ImagePlaceholder(
              height: 90,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),

          // ── Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row + PREMIUM badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (post.isPremium) ...[
                      const SizedBox(width: 8),
                      const _PremiumBadge(),
                    ],
                  ],
                ),

                if (post.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ],

                if (post.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _kTextSecondary, fontSize: 13, height: 1.4),
                  ),
                ],

                const SizedBox(height: 12),

                // ── Footer: timestamp + actions ──
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined,
                        size: 13, color: _kTextSecondary),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a')
                          .format(post.createdAt.toLocal()),
                      style: const TextStyle(
                          color: _kTextSecondary, fontSize: 11),
                    ),
                    const Spacer(),
                    _ActionIconButton(
                      icon: Icons.edit_outlined,
                      color: _kGold,
                      tooltip: 'Edit',
                      onPressed: onEdit,
                    ),
                    const SizedBox(width: 6),
                    _ActionIconButton(
                      icon: Icons.delete_outline,
                      color: Colors.redAccent,
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4AF37), Color(0xFFF5E17A)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'PREMIUM',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }
}

class _NetworkImage extends StatelessWidget {
  final String url;
  final double height;
  final double width;

  const _NetworkImage(
      {required this.url, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      height: height,
      width: width,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _ImagePlaceholder(height: height),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(
              height: height,
              width: width,
              color: _kBorder,
              child: const Center(
                  child: CircularProgressIndicator(
                      color: _kGold, strokeWidth: 2)),
            ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final double height;
  final BorderRadius borderRadius;

  const _ImagePlaceholder({
    required this.height,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: double.infinity,
        color: _kBorder,
        child: const Icon(Icons.newspaper_outlined,
            color: _kTextSecondary, size: 32),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _kCardBg,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.newspaper_outlined,
                  color: _kTextSecondary, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No posts yet',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap "Post News" to publish\nyour first announcement.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// News Form Sheet  (Add / Edit)
// ─────────────────────────────────────────────────────────────────────────────

class _NewsFormResult {
  final String title;
  final String subtitle;
  final String content;
  final bool isPremium;
  final File? imageFile;
  final dynamic branchId;

  const _NewsFormResult({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.isPremium,
    this.imageFile,
    this.branchId,
  });
}

class _NewsFormSheet extends StatefulWidget {
  final _NewsPost? existing;
  final dynamic activeBranchId; // from StaffProvider.branch?.id
  final Future<void> Function(_NewsFormResult) onSave;

  const _NewsFormSheet({
    this.existing,
    this.activeBranchId,
    required this.onSave,
  });

  @override
  State<_NewsFormSheet> createState() => _NewsFormSheetState();
}

class _NewsFormSheetState extends State<_NewsFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _contentCtrl;

  File? _imageFile;
  bool _isPremium = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _subtitleCtrl = TextEditingController(text: e?.subtitle ?? '');
    _contentCtrl = TextEditingController(text: e?.content ?? '');
    _isPremium = e?.isPremium ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_NewsFormResult(
        title: _titleCtrl.text.trim(),
        subtitle: _subtitleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        isPremium: _isPremium,
        imageFile: _imageFile,
        branchId: widget.activeBranchId,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

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
        child: Form(
          key: _formKey,
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

              // Sheet title
              Text(
                isEdit ? 'Edit Post' : 'New Post',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),

              // Image picker
              _ImagePickerBox(
                file: _imageFile,
                existingUrl: widget.existing?.imageUrl,
                onTap: _saving ? null : _pickImage,
              ),
              const SizedBox(height: 16),

              // Title (required)
              _FormField(
                controller: _titleCtrl,
                label: 'Title',
                hint: 'e.g. Staff Night Out — Save the Date',
                enabled: !_saving,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 12),

              // Subtitle
              _FormField(
                controller: _subtitleCtrl,
                label: 'Subtitle',
                hint: 'Short teaser shown on the feed card',
                enabled: !_saving,
              ),
              const SizedBox(height: 12),

              // Content (required)
              _FormField(
                controller: _contentCtrl,
                label: 'Content',
                hint: 'Full announcement body text...',
                maxLines: 5,
                enabled: !_saving,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Content is required'
                    : null,
              ),
              const SizedBox(height: 12),

              // Is Premium toggle
              Container(
                decoration: BoxDecoration(
                  color: _kDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: SwitchListTile(
                  value: _isPremium,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _isPremium = v),
                  activeThumbColor: _kGold,
                  title: const Text(
                    'Premium Post',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Marks this post with a PREMIUM badge',
                    style: TextStyle(color: _kTextSecondary, fontSize: 12),
                  ),
                  secondary: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.star_rounded,
                        color: _kGold, size: 18),
                  ),
                ),
              ),

              // Branch scope info pill
              if (widget.activeBranchId != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: _kTextSecondary),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Will be associated with your active branch.',
                          style: TextStyle(
                              color: _kTextSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button — disabled + gold spinner during save
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
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Color(0xFFD4AF37),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          isEdit ? 'Save Changes' : 'Publish Post',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Picker Box
// ─────────────────────────────────────────────────────────────────────────────

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
      content = Image.network(
        existingUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      content = _placeholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 170,
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
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
          Text('Tap to add a cover image',
              style: TextStyle(color: _kTextSecondary, fontSize: 13)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Field
// ─────────────────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final bool enabled;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.enabled = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          enabled: enabled,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: _kTextSecondary.withValues(alpha: 0.5)),
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}


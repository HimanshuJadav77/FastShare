import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wifi_ftp/ui/theme/app_theme.dart';
import 'package:wifi_ftp/ui/theme/app_animations.dart';

/// Full-screen bottom sheet for picking files from internal storage on Android.
/// Shows a drag handle, breadcrumb path chips, file/folder grid, and a
/// gradient send button when files are selected.
class StorageBrowser extends StatefulWidget {
  final String initialPath;
  const StorageBrowser({super.key, this.initialPath = '/storage/emulated/0'});

  @override
  State<StorageBrowser> createState() => _StorageBrowserState();
}

class _StorageBrowserState extends State<StorageBrowser> {
  late String _currentPath;
  List<FileSystemEntity> _entities = [];
  bool _isLoading = true;
  final Set<String> _selectedPaths = {};

  static const _root = '/storage/emulated/0';

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final items = await Directory(_currentPath).list().toList();
      items.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      setState(() { _entities = items; _isLoading = false; });
    } catch (_) {
      setState(() { _entities = []; _isLoading = false; });
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _refresh();
  }

  void _goBack() {
    if (_currentPath == _root || _currentPath == '/') {
      Navigator.pop(context);
    } else {
      _navigateTo(p.dirname(_currentPath));
    }
  }

  void _toggleFile(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  List<String> get _breadcrumbs {
    final relative = _currentPath.replaceFirst(_root, '');
    if (relative.isEmpty || relative == '/') return ['Home'];
    return ['Home', ...relative.split('/').where((s) => s.isNotEmpty)];
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      height: screenHeight * 0.92,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Drag handle ──
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ext.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
            child: Row(
              children: [
                AppAnimations.scaleOnTap(
                  onTap: _goBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Files',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (_selectedPaths.isNotEmpty)
                        Text(
                          '${_selectedPaths.length} selected',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selectedPaths.isNotEmpty)
                  AppAnimations.scaleOnTap(
                    onTap: () => setState(() => _selectedPaths.clear()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ext.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: ext.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                AppAnimations.scaleOnTap(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Breadcrumb path chips ──
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _breadcrumbs.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: ext.textMuted.withValues(alpha: 0.4),
                ),
              ),
              itemBuilder: (_, i) {
                final crumb = _breadcrumbs[i];
                final isLast = i == _breadcrumbs.length - 1;
                return GestureDetector(
                  onTap: isLast ? null : () {
                    if (i == 0) {
                      _navigateTo(_root);
                    } else {
                      // Rebuild path to this segment
                      final parts = _breadcrumbs.sublist(1, i + 1);
                      _navigateTo('$_root/${parts.join('/')}');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isLast
                          ? Theme.of(context).primaryColor.withValues(alpha: 0.12)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      crumb,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
                        color: isLast
                            ? Theme.of(context).primaryColor
                            : ext.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── Separator ──
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.06),
          ),

          // ── File list ──
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      strokeCap: StrokeCap.round,
                      color: Theme.of(context).primaryColor,
                    ),
                  )
                : _entities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 56,
                              color: ext.textMuted.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Folder is empty',
                              style: TextStyle(
                                color: ext.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: _selectedPaths.isNotEmpty ? 100 : 24,
                        ),
                        itemCount: _entities.length,
                        itemBuilder: (_, i) {
                          final entity = _entities[i];
                          final name = p.basename(entity.path);
                          if (name.startsWith('.')) return const SizedBox.shrink();

                          final isDir = entity is Directory;
                          final isSelected = _selectedPaths.contains(entity.path);

                          return _FileRow(
                            name: name,
                            isDir: isDir,
                            isSelected: isSelected,
                            file: isDir ? null : entity as File,
                            onTap: () {
                              if (isDir) {
                                _navigateTo(entity.path);
                              } else {
                                _toggleFile(entity.path);
                              }
                            },
                            ext: ext,
                          );
                        },
                      ),
          ),

          // ── Send button (appears when files are selected) ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
            child: _selectedPaths.isNotEmpty
                ? Container(
                    key: const ValueKey('send'),
                    padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: AppAnimations.scaleOnTap(
                      onTap: () => Navigator.pop(context, _selectedPaths.toList()),
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: ext.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Send ${_selectedPaths.length} File${_selectedPaths.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}

// ── Individual file/folder row ──
class _FileRow extends StatelessWidget {
  final String name;
  final bool isDir;
  final bool isSelected;
  final File? file;
  final VoidCallback onTap;
  final AppThemeExtension ext;

  const _FileRow({
    required this.name,
    required this.isDir,
    required this.isSelected,
    required this.file,
    required this.onTap,
    required this.ext,
  });

  static const _ext2icon = {
    'jpg': Icons.image_rounded, 'jpeg': Icons.image_rounded, 'png': Icons.image_rounded,
    'gif': Icons.gif_rounded, 'webp': Icons.image_rounded, 'heic': Icons.image_rounded,
    'mp4': Icons.videocam_rounded, 'mov': Icons.videocam_rounded, 'avi': Icons.videocam_rounded,
    'mp3': Icons.music_note_rounded, 'wav': Icons.music_note_rounded, 'flac': Icons.music_note_rounded,
    'pdf': Icons.picture_as_pdf_rounded,
    'zip': Icons.folder_zip_rounded, 'rar': Icons.folder_zip_rounded, '7z': Icons.folder_zip_rounded,
    'apk': Icons.android_rounded,
    'doc': Icons.description_rounded, 'docx': Icons.description_rounded,
    'xls': Icons.table_chart_rounded, 'xlsx': Icons.table_chart_rounded,
  };

  IconData get _icon {
    if (isDir) return Icons.folder_rounded;
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return _ext2icon[extension] ?? Icons.insert_drive_file_rounded;
  }

  Color _iconColor(BuildContext context) {
    if (isSelected) return Theme.of(context).primaryColor;
    if (isDir) return const Color(0xFFFF9F0A); // warm amber for folders
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => const Color(0xFF30D158),
      'mp4' || 'mov' || 'avi' => const Color(0xFFFF453A),
      'mp3' || 'wav' || 'flac' => const Color(0xFF5E5CE6),
      'pdf' => const Color(0xFFFF3B30),
      'zip' || 'rar' || '7z' => const Color(0xFFFF9F0A),
      'apk' => const Color(0xFF30D158),
      _ => ext.textMuted,
    };
  }

  String _sizeLabel() {
    if (file == null) return '';
    try {
      final len = file!.lengthSync();
      if (len < 1024) return '$len B';
      if (len < 1024 * 1024) return '${(len / 1024).toStringAsFixed(0)} KB';
      return '${(len / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAnimations.scaleOnTap(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.25),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            // ── Icon pill ──
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _iconColor(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _iconColor(context), size: 22),
            ),
            const SizedBox(width: 14),

            // ── Name + size ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isDir && _sizeLabel().isNotEmpty)
                    Text(
                      _sizeLabel(),
                      style: TextStyle(
                        fontSize: 11,
                        color: ext.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),

            // ── Trailing ──
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  color: Theme.of(context).primaryColor, size: 22)
            else if (isDir)
              Icon(Icons.chevron_right_rounded,
                  color: ext.textMuted.withValues(alpha: 0.4), size: 20),
          ],
        ),
      ),
    );
  }
}

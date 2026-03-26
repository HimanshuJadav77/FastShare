import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wifi_ftp/ui/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(_currentPath);
      final list = await dir.list().toList();
      
      // Sort: Directories first, then alphabetically
      list.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      setState(() {
        _entities = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[BROWSER] Error: $e');
      setState(() {
        _entities = [];
        _isLoading = false;
      });
    }
  }

  void _onEntityTap(FileSystemEntity entity) {
    if (entity is Directory) {
      setState(() {
        _currentPath = entity.path;
      });
      _refresh();
    } else if (entity is File) {
      setState(() {
        if (_selectedPaths.contains(entity.path)) {
          _selectedPaths.remove(entity.path);
        } else {
          _selectedPaths.add(entity.path);
        }
      });
    }
  }

  void _goBack() {
    if (_currentPath == '/storage/emulated/0' || _currentPath == '/') {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _currentPath = p.dirname(_currentPath);
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.appColors;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _selectedPaths.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, _selectedPaths.toList()),
              label: Text('Send ${_selectedPaths.length} Files'),
              icon: const Icon(Icons.send),
              backgroundColor: Theme.of(context).primaryColor,
            )
          : null,
      body: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: _goBack,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Internal Storage',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        Text(
                          _currentPath.replaceFirst('/storage/emulated/0', 'Home'),
                          style: TextStyle(color: ext.textMuted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_selectedPaths.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedPaths.clear()),
                      child: const Text('Clear'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
  
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _entities.isEmpty
                      ? Center(
                          child: Text(
                            'Folder is empty or inaccessible',
                            style: TextStyle(color: ext.textMuted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _entities.length,
                          itemBuilder: (context, index) {
                            final entity = _entities[index];
                            final isDir = entity is Directory;
                            final name = p.basename(entity.path);
                            final isSelected = _selectedPaths.contains(entity.path);
                            
                            // Skip hidden files
                            if (name.startsWith('.')) return const SizedBox.shrink();
  
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                              leading: Icon(
                                isDir ? Icons.folder : Icons.insert_drive_file,
                                color: isSelected 
                                    ? Theme.of(context).primaryColor 
                                    : (isDir ? Theme.of(context).primaryColor : ext.textMuted),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 14, 
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                  color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              subtitle: isDir ? null : _buildFileSize(entity as File),
                              trailing: !isDir && isSelected 
                                  ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                                  : (isDir ? const Icon(Icons.chevron_right, size: 16) : null),
                              onTap: () => _onEntityTap(entity),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSize(File file) {
    try {
      final len = file.lengthSync();
      final mb = len / (1024 * 1024);
      return Text(
        '${mb.toStringAsFixed(1)} MB',
        style: TextStyle(fontSize: 11, color: context.appColors.textMuted),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

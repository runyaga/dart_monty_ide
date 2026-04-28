import 'dart:async';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';

/// A sidebar widget that displays files in the workspace.
class FileExplorer extends StatefulWidget {
  /// Creates a [FileExplorer].
  const FileExplorer({
    required this.vfs,
    required this.onFileSelected,
    super.key,
  });

  /// The VFS to use for file operations.
  final MontyVfs vfs;

  /// Callback when a file is selected.
  final ValueChanged<String> onFileSelected;

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  List<String> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final files = await widget.vfs.listFiles();
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading files: $e')),
        );
      }
    }
  }

  Future<void> _createFile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Python File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'filename.py'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final fileName = name.endsWith('.py') ? name : '$name.py';
      await widget.vfs.writeFile(fileName, '# $fileName\n');
      await _refresh();
      widget.onFileSelected(fileName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border:
            Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'FILES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                IconButton(
                  onPressed: () => unawaited(_refresh()),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Files',
                ),
                IconButton(
                  onPressed: () => unawaited(_createFile()),
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'New File',
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_files.isEmpty)
            const Expanded(child: Center(child: Text('No files')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return ListTile(
                    leading: const Icon(Icons.description, size: 18),
                    title: Text(
                      file,
                      style: const TextStyle(fontSize: 13),
                    ),
                    dense: true,
                    onTap: () => widget.onFileSelected(file),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: () async {
                        await widget.vfs.deleteFile(file);
                        await _refresh();
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Use hive_flutter for ValueListenableBuilder
import 'package:intl/intl.dart';

import 'models/chat_data.dart'; // Import SavedChatSession model

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Box<SavedChatSession> _savedChatsBox;

  @override
  void initState() {
    super.initState();
    // Box should already be open from main.dart
    _savedChatsBox = Hive.box<SavedChatSession>('savedChats');
  }

  Future<void> _deleteBookmark(dynamic key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bookmark?'),
        content: const Text('Are you sure you want to remove this saved chat? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _savedChatsBox.delete(key);
      // No need for setState, ValueListenableBuilder handles updates
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark deleted.'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        backgroundColor: theme.colorScheme.surfaceVariant, // Match theme
        elevation: 1,
      ),
      backgroundColor: theme.colorScheme.background,
      body: ValueListenableBuilder<Box<SavedChatSession>>(
        // Listen directly to the box for changes
        valueListenable: _savedChatsBox.listenable(),
        builder: (context, box, _) {
          final bookmarks = box.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Sort newest first

          if (bookmarks.isEmpty) {
            return Center(
              child: Text(
                'No chats saved yet.\nTap the bookmark icon in a chat to save it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            itemCount: bookmarks.length,
            separatorBuilder: (context, index) => Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final session = bookmarks[index];
              return ListTile(
                leading: Icon(Icons.bookmark_rounded, color: theme.colorScheme.primary),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Saved: ${format.format(session.timestamp)}'),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error.withOpacity(0.8)),
                  tooltip: 'Delete Bookmark',
                  onPressed: () => _deleteBookmark(session.key), // Pass Hive key
                ),
                onTap: () {
                  // Return the session ID when a bookmark is tapped
                  Navigator.pop(context, session.sessionId);
                },
              );
            },
          );
        },
      ),
    );
  }
}
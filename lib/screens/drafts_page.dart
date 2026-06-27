import 'package:flutter/material.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/screens/btk_form_page.dart';

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  List<Map<String, dynamic>> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshDrafts();
  }

  Future<void> _refreshDrafts() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getAllDrafts();
    setState(() {
      _drafts = data;
      _isLoading = false;
    });
  }

  void _openDraft(Map<String, dynamic> draft) async {
    final id = draft['id'];

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BtkFormPage(draftId: id)),
    );
    _refreshDrafts();
  }

  void _deleteDraft(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('წაშლა'),
        content: const Text('ნამდვილად გსურთ ამ დრაფტის წაშლა?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('წაშლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteDraft(id);
      _refreshDrafts();
    }
  }

  void _deleteAllDrafts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ყველას წაშლა'),
        content: const Text('ნამდვილად გსურთ ყველა დრაფტის წაშლა? ეს მოქმედება შეუქცევადია.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('ყველას წაშლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteAllDrafts();
      _refreshDrafts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('შენახული დრაფტები'),
        backgroundColor: colorScheme.surfaceContainerHigh,
        actions: [
          if (_drafts.isNotEmpty)
            IconButton(
              onPressed: _deleteAllDrafts,
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              tooltip: 'ყველას წაშლა',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 64, color: colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('დრაფტები ვერ მოიძებნა', 
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _drafts.length,
                  itemBuilder: (context, index) {
                    final draft = _drafts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(Icons.assignment_rounded, color: colorScheme.onPrimaryContainer),
                        ),
                        title: Text(draft['title'] ?? 'უსახელო დრაფტი', 
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${draft['form_type']} • ${draft['date']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteDraft(draft['id']),
                        ),
                        onTap: () => _openDraft(draft),
                      ),
                    );
                  },
                ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/draft_item.dart';
import '../services/draft_service.dart';
import '../widgets/snapping_list_view.dart';
import 'farmer_registry_screen.dart';

/// Fixed row height for the snap-to-item draft list below.
const double _kDraftCardExtent = 128;

/// Lists farmer registrations the inspector saved as drafts (in-progress,
/// not yet submitted). Tapping a draft resumes the registration wizard
/// exactly where it was left off, via [FarmerRegistryScreen.draftToResume].
class DraftsListScreen extends StatefulWidget {
  const DraftsListScreen({super.key});

  @override
  State<DraftsListScreen> createState() => _DraftsListScreenState();
}

class _DraftsListScreenState extends State<DraftsListScreen> {
  final DraftService _draftService = DraftService();
  List<DraftItem> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() {
      _isLoading = true;
    });
    final drafts = await _draftService.getDrafts();
    if (mounted) {
      setState(() {
        _drafts = drafts;
        _isLoading = false;
      });
    }
  }

  Future<void> _resumeDraft(DraftItem draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmerRegistryScreen(draftToResume: draft),
      ),
    );
    // The draft may have been submitted (and thus deleted) or updated
    // while the wizard was open, so refresh the list on return.
    if (mounted) {
      _loadDrafts();
    }
  }

  Future<void> _confirmDelete(DraftItem draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard draft?'),
        content: Text(
          'This will permanently delete the saved draft for '
          '"${draft.displayName}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _draftService.deleteDraft(draft.id);
      await _loadDrafts();
    }
  }

  String _formatUpdatedAt(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drafts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDrafts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.drafts_outlined,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No saved drafts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap "Save as Draft" while registering a farmer to '
                      'pick it up again later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF757575)),
                    ),
                  ],
                ),
              ),
            )
          : SnappingListView<DraftItem>(
              items: _drafts,
              itemExtent: _kDraftCardExtent,
              padding: const EdgeInsets.all(12),
              onRefresh: _loadDrafts,
              keyOf: (draft) => draft.id,
              itemBuilder: (context, draft, index) {
                final totalSteps = draft.stepCompleted.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: const Color(
                          0xFF4CAF50,
                        ).withValues(alpha: 0.15),
                        child: const Icon(
                          Icons.edit_note,
                          color: Color(0xFF388E3C),
                        ),
                      ),
                      title: Text(
                        draft.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          if (draft.locationSummary != null)
                            Text(
                              draft.locationSummary!,
                              style: const TextStyle(fontSize: 13),
                            ),
                          Text(
                            '${draft.completedStepCount}/$totalSteps steps '
                            'completed · Updated ${_formatUpdatedAt(draft.updatedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _confirmDelete(draft),
                        tooltip: 'Discard',
                      ),
                      onTap: () => _resumeDraft(draft),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

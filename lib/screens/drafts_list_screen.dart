import 'package:flutter/material.dart';
import '../models/draft_item.dart';
import '../services/draft_service.dart';
import '../theme/app_theme.dart';
import '../widgets/snapping_list_view.dart';
import 'farmer_registry_screen.dart';

/// Fixed row height for the snap-to-item draft list below.
const double _kDraftCardExtent = 132;

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
            child: const Text(
              'Discard',
              style: TextStyle(color: AppTheme.danger),
            ),
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Drafts'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDrafts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen),
            )
          : _drafts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppTheme.paleGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.drafts_outlined,
                        size: 44,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No saved drafts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap "Save as Draft" while registering a farmer to '
                      'pick it up again later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : SnappingListView<DraftItem>(
              items: _drafts,
              itemExtent: _kDraftCardExtent,
              padding: const EdgeInsets.all(16),
              onRefresh: _loadDrafts,
              keyOf: (draft) => draft.id,
              itemBuilder: (context, draft, index) {
                final totalSteps = draft.stepCompleted.length;
                final progress = totalSteps == 0
                    ? 0.0
                    : draft.completedStepCount / totalSteps;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      onTap: () => _resumeDraft(draft),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg,
                          ),
                          border: Border.all(color: AppTheme.border),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppTheme.paleGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit_note,
                                color: AppTheme.darkGreen,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    draft.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (draft.locationSummary != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      draft.locationSummary!,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 5,
                                      backgroundColor: AppTheme.divider,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            AppTheme.primaryGreen,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${draft.completedStepCount}/$totalSteps steps · '
                                    'Updated ${_formatUpdatedAt(draft.updatedAt)}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.danger,
                              ),
                              onPressed: () => _confirmDelete(draft),
                              tooltip: 'Discard',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

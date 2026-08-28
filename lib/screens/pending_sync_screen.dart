import 'package:flutter/material.dart';
import '../models/pending_sync_item.dart';
import '../services/offline_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/snapping_list_view.dart';
import 'farmer_registry_screen.dart';

/// Fixed row height for the snap-to-item pending-sync list below. This is
/// taller than the other lists since these cards can show retry/error text.
const double _kPendingSyncCardExtent = 176;

/// Shows farmer registrations that are queued locally because they were
/// captured while offline (or the live submission failed due to a network
/// error). Lets the inspector manually trigger a sync attempt, and shows
/// per-item status (retry count / last error) so it's clear why something
/// is still pending.
class PendingSyncScreen extends StatefulWidget {
  const PendingSyncScreen({super.key});

  @override
  State<PendingSyncScreen> createState() => _PendingSyncScreenState();
}

class _PendingSyncScreenState extends State<PendingSyncScreen> {
  final OfflineSyncService _syncService = OfflineSyncService();
  List<PendingSyncItem> _items = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });
    final items = await _syncService.getPendingItems();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
    });

    final hasConnectivity = await _syncService.hasConnectivity();
    if (!hasConnectivity) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still no internet connection. Try again later.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    final result = await _syncService.syncPendingItems();
    await _loadItems();

    if (mounted) {
      setState(() {
        _isSyncing = false;
      });

      final message = result.failed == 0
          ? 'Synced ${result.synced} farmer(s) successfully!'
          : 'Synced ${result.synced} farmer(s). '
                '${result.failed} still failed - see details below.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.failed == 0
              ? AppTheme.success
              : AppTheme.warning,
        ),
      );
    }
  }

  /// Opens the full registration wizard pre-filled with this pending item's
  /// data (jumping straight to Attachments), so the inspector can fix
  /// whatever is blocking sync - most commonly an oversized document/PDF
  /// that keeps timing out on a weak field connection - without retyping
  /// the whole registration. See FarmerRegistryScreen.pendingItemToResume.
  Future<void> _editItem(PendingSyncItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmerRegistryScreen(pendingItemToResume: item),
      ),
    );
    // Refresh the list in case the item was edited/resubmitted (or the
    // inspector backed out without changes - harmless either way).
    if (mounted) {
      await _loadItems();
    }
  }

  Future<void> _confirmDelete(PendingSyncItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard pending registration?'),
        content: Text(
          'This will permanently delete the locally saved registration for '
          '"${item.displayName}". This cannot be undone.',
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
      await _syncService.removeItem(item.id);
      await _loadItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pending Sync'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppTheme.successBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_done,
                      size: 44,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No farmer registrations are waiting to sync.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : SnappingListView<PendingSyncItem>(
              items: _items,
              itemExtent: _kPendingSyncCardExtent,
              padding: const EdgeInsets.all(16),
              onRefresh: _loadItems,
              keyOf: (item) => item.id,
              itemBuilder: (context, item, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusLg,
                      ),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: AppTheme.warningBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_off,
                                color: AppTheme.warning,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (item.registration != null)
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: AppTheme.primaryGreen,
                                ),
                                onPressed: () => _editItem(item),
                                tooltip:
                                    'Edit (e.g. remove an oversized document)',
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.danger,
                              ),
                              onPressed: () => _confirmDelete(item),
                              tooltip: 'Discard',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Captured: ${item.createdAt.toLocal()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (item.farms.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Farm: ${item.farms.first['name'] ?? '-'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        if (item.retryCount > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Retry attempts: ${item.retryCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.lastError != null)
                            Text(
                              'Last error: ${item.lastError}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.danger,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _syncNow,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                ),
              ),
            ),
    );
  }
}

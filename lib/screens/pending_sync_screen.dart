import 'package:flutter/material.dart';
import '../models/pending_sync_item.dart';
import '../services/offline_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/snapping_list_view.dart';
import 'farmer_registry_screen.dart';

/// Fixed row height for the snap-to-item pending-sync list below. This is
/// taller than the other lists since these cards now also show a
/// checkbox, a status badge, and (for failed items) a Retry button.
const double _kPendingSyncCardExtent = 214;

/// Shows farmer registrations that are queued locally because they were
/// captured while offline (or the live submission failed due to a network
/// error).
///
/// Implements the app spec's "Selective Farm Synchronization" workflow
/// (task spec sections 10-16): the enumerator explicitly checks which
/// records to upload via per-item checkboxes (with an optional "Select
/// All"), then taps "SYNC SELECTED" - only the checked records are
/// uploaded, everything else stays untouched in the local queue. A
/// dashboard strip shows live counts (Ready to Sync / Syncing / Failed),
/// and any record that fails shows its specific error plus a per-item
/// [ RETRY ] button that retries ONLY that farm.
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
  // Set of item ids currently mid-sync, so the UI can show a per-item
  // "Syncing..." badge even while other (not-selected) items sit
  // untouched. Only populated during an active _syncSelected() call.
  final Set<String> _syncingIds = {};
  // Session-only counter for the dashboard's "Synced" tile - successfully
  // synced items are removed from the persisted queue immediately (task
  // spec section 13: never re-uploaded / never lingers as a duplicate), so
  // there is nothing to keep displaying them in the main list itself.
  int _syncedThisSession = 0;

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

  int get _readyCount =>
      _items.where((i) => i.status != SyncStatus.syncFailed).length;
  int get _failedCount =>
      _items.where((i) => i.status == SyncStatus.syncFailed).length;
  int get _selectedCount => _items.where((i) => i.selected).length;
  bool get _allSelected =>
      _items.isNotEmpty && _items.every((i) => i.selected);

  void _toggleSelected(PendingSyncItem item, bool? value) {
    setState(() {
      item.selected = value ?? false;
    });
  }

  /// "Select All" is available so the enumerator can deliberately select
  /// every pending farm when connectivity is strong - but this only ever
  /// checks the boxes. Sync itself remains a separate, explicit action
  /// (task spec section 11: sync must never auto-trigger).
  void _toggleSelectAll(bool? value) {
    setState(() {
      for (final item in _items) {
        item.selected = value ?? false;
      }
    });
  }

  Future<void> _syncSelected() async {
    final selectedIds = _items.where((i) => i.selected).map((i) => i.id).toList();
    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one farm to sync.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncingIds
        ..clear()
        ..addAll(selectedIds);
      for (final item in _items) {
        if (item.selected) {
          item.status = SyncStatus.syncing;
        }
      }
    });

    final hasConnectivity = await _syncService.hasConnectivity();
    if (!hasConnectivity) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncingIds.clear();
          for (final item in _items) {
            if (item.status == SyncStatus.syncing) {
              item.status = SyncStatus.readyToSync;
            }
          }
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

    final result = await _syncService.syncSelectedItems(selectedIds);
    await _loadItems();

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncingIds.clear();
        _syncedThisSession += result.synced;
      });

      final message = result.failed == 0
          ? 'Synced ${result.synced} farm(s) successfully!'
          : 'Synced ${result.synced} farm(s). '
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

  /// Retries ONLY [item] (task spec section 14) - every other queued farm,
  /// selected or not, is left completely untouched.
  Future<void> _retryItem(PendingSyncItem item) async {
    setState(() {
      _syncingIds.add(item.id);
      item.status = SyncStatus.syncing;
    });

    final hasConnectivity = await _syncService.hasConnectivity();
    if (!hasConnectivity) {
      if (mounted) {
        setState(() {
          _syncingIds.remove(item.id);
          item.status = SyncStatus.syncFailed;
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

    final result = await _syncService.retryItem(item.id);
    await _loadItems();

    if (mounted) {
      setState(() {
        _syncingIds.remove(item.id);
        if (result.synced > 0) _syncedThisSession += result.synced;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.synced > 0
                ? '"${item.displayName}" synced successfully!'
                : '"${item.displayName}" failed again - see error below.',
          ),
          backgroundColor:
              result.synced > 0 ? AppTheme.success : AppTheme.warning,
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

  Widget _buildDashboard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: _DashboardTile(
              label: 'Ready to Sync',
              value: _readyCount,
              color: AppTheme.info,
              bgColor: AppTheme.infoBg,
              icon: Icons.cloud_upload_outlined,
            ),
          ),
          Expanded(
            child: _DashboardTile(
              label: 'Failed',
              value: _failedCount,
              color: AppTheme.danger,
              bgColor: AppTheme.dangerBg,
              icon: Icons.error_outline,
            ),
          ),
          Expanded(
            child: _DashboardTile(
              label: 'Synced',
              value: _syncedThisSession,
              color: AppTheme.success,
              bgColor: AppTheme.successBg,
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
      ),
    );
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
          : Column(
              children: [
                _buildDashboard(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _allSelected,
                        activeColor: AppTheme.primaryGreen,
                        onChanged: _isSyncing ? null : _toggleSelectAll,
                      ),
                      const Text(
                        'Select All',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$_selectedCount of ${_items.length} selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SnappingListView<PendingSyncItem>(
                    items: _items,
                    itemExtent: _kPendingSyncCardExtent,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    onRefresh: _loadItems,
                    keyOf: (item) => item.id,
                    itemBuilder: (context, item, index) {
                      final isFailed = item.status == SyncStatus.syncFailed;
                      final isSyncingThis = _syncingIds.contains(item.id) ||
                          item.status == SyncStatus.syncing;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusLg,
                            ),
                            border: Border.all(
                              color: isFailed
                                  ? AppTheme.danger.withValues(alpha: 0.4)
                                  : AppTheme.border,
                            ),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: item.selected,
                                    activeColor: AppTheme.primaryGreen,
                                    onChanged: (_isSyncing || isSyncingThis)
                                        ? null
                                        : (value) =>
                                            _toggleSelected(item, value),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.displayName,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          item.displayId,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (item.registration != null)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.primaryGreen,
                                      ),
                                      onPressed: (_isSyncing || isSyncingThis)
                                          ? null
                                          : () => _editItem(item),
                                      tooltip:
                                          'Edit (e.g. remove an oversized document)',
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppTheme.danger,
                                    ),
                                    onPressed: (_isSyncing || isSyncingThis)
                                        ? null
                                        : () => _confirmDelete(item),
                                    tooltip: 'Discard',
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 48),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _StatusBadge(
                                      isSyncing: isSyncingThis,
                                      isFailed: isFailed,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Captured: ${item.createdAt.toLocal()}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (item.farms.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Farm: ${item.farms.first['name'] ?? '-'}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                    if (isFailed && item.lastError != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.lastError!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        height: 30,
                                        child: OutlinedButton.icon(
                                          onPressed: isSyncingThis
                                              ? null
                                              : () => _retryItem(item),
                                          icon: const Icon(
                                            Icons.refresh,
                                            size: 15,
                                          ),
                                          label: const Text(
                                            '[ RETRY ]',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.danger,
                                            side: const BorderSide(
                                              color: AppTheme.danger,
                                            ),
                                            padding: const EdgeInsets
                                                .symmetric(horizontal: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _syncSelected,
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
                  label: Text(
                    _isSyncing
                        ? 'Syncing...'
                        : 'SYNC SELECTED ($_selectedCount)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _DashboardTile({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isSyncing;
  final bool isFailed;

  const _StatusBadge({required this.isSyncing, required this.isFailed});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    late final Color bg;
    late final IconData icon;

    if (isSyncing) {
      label = 'Syncing...';
      color = AppTheme.info;
      bg = AppTheme.infoBg;
      icon = Icons.sync;
    } else if (isFailed) {
      label = 'Sync Failed';
      color = AppTheme.danger;
      bg = AppTheme.dangerBg;
      icon = Icons.error_outline;
    } else {
      label = 'Ready to Sync';
      color = AppTheme.textSecondary;
      bg = AppTheme.divider;
      icon = Icons.cloud_upload_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

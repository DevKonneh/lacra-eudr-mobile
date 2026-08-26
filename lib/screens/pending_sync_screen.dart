import 'package:flutter/material.dart';
import '../models/pending_sync_item.dart';
import '../services/offline_sync_service.dart';

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
            backgroundColor: Colors.red,
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
          backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
        ),
      );
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
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
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
      appBar: AppBar(
        title: const Text('Pending Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_done,
                    size: 72,
                    color: Colors.green.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No farmer registrations are waiting to sync.',
                    style: TextStyle(color: Color(0xFF757575)),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_off, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _confirmDelete(item),
                              tooltip: 'Discard',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Captured: ${item.createdAt.toLocal()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                        if (item.farms.isNotEmpty)
                          Text(
                            'Farm: ${item.farms.first['name'] ?? '-'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (item.retryCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Retry attempts: ${item.retryCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                          if (item.lastError != null)
                            Text(
                              'Last error: ${item.lastError}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
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
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
    );
  }
}

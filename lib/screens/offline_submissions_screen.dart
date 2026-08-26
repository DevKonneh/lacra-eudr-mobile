import 'package:flutter/material.dart';
import '../models/offline_submission_record.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/snapping_list_view.dart';

/// Fixed row height for the snap-to-item list below.
const double _kOfflineSubmissionCardExtent = 148;

/// Backend/admin visibility into farmer registrations that inspectors'
/// devices have captured while offline (or whose live submission failed)
/// but that have NOT yet fully synced to the real Farmer table.
///
/// This is populated by [OfflineSyncService] best-effort "reporting" a
/// small text-only summary to the backend as soon as something is queued
/// locally, and again whenever its retry/error state changes - see
/// ApiService.reportOfflineSubmission / OfflineSyncService._reportShadowRecord.
///
/// Unlike [PendingSyncScreen] (which shows what's queued on *this* device
/// and can trigger a sync), this screen shows what's queued across *every*
/// inspector's device - it is read-only visibility for admins/team leads to
/// answer "is there field data out there that hasn't reached the server
/// yet, and from whom?".
class OfflineSubmissionsScreen extends StatefulWidget {
  const OfflineSubmissionsScreen({super.key});

  @override
  State<OfflineSubmissionsScreen> createState() =>
      _OfflineSubmissionsScreenState();
}

class _OfflineSubmissionsScreenState extends State<OfflineSubmissionsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<OfflineSubmissionRecord> _records = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _authService.getToken();
      final records = await _apiService.getOfflineSubmissions(authToken: token);

      // Newest-reported-first, so the most recent field activity is at the
      // top (matches the ordering convention used by FarmersListScreen).
      records.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'FAILED':
        return Colors.red;
      case 'SYNCED':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  String _formatTime(DateTime dt) {
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
        title: const Text('Unsynced Field Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Could not load offline field data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF757575)),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: 420,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
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
                        'All field data is in sync',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No inspector currently has unsynced farmer '
                        'registrations sitting on their device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF757575)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFF3E0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '${_records.length} registration(s) captured in the field '
            'have not yet reached the server.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF795548)),
          ),
        ),
        Expanded(
          child: SnappingListView<OfflineSubmissionRecord>(
            items: _records,
            itemExtent: _kOfflineSubmissionCardExtent,
            padding: const EdgeInsets.all(12),
            onRefresh: _load,
            keyOf: (r) => r.id,
            itemBuilder: (context, record, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.resolvedDisplayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  record.status,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                record.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor(record.status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (record.locationSummary.isNotEmpty)
                          Text(
                            record.locationSummary,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        if (record.farmName != null &&
                            record.farmName!.trim().isNotEmpty)
                          Text(
                            'Farm: ${record.farmName} · '
                            '${record.cropType ?? '-'}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Inspector: ${record.inspectorName ?? 'Unknown'} · '
                          '${_formatTime(record.reportedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                        if (record.retryCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Retry attempts: ${record.retryCount}'
                              '${record.lastError != null ? ' · ${record.lastError}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

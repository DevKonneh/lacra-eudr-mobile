import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small rounded status pill used across Farmers list/detail, Drafts,
/// Pending Sync and Offline Submissions screens so every "status" concept
/// in the app (Verified, Pending, Conflict, Synced, Failed, ...) reads
/// visually consistently.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(label);
    final bgColor = AppTheme.statusBgColor(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

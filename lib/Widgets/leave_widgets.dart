import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';

/// Colour for a leave status: PENDING / APPROVED / DECLINED / CANCELLED.
Color leaveStatusColor(String status) => switch (status.toUpperCase()) {
      'APPROVED' => AppColors.success,
      'DECLINED' => AppColors.redDeep,
      'CANCELLED' => AppColors.textDim,
      _ => AppColors.warning,
    };

IconData leaveStatusIcon(String status) => switch (status.toUpperCase()) {
      'APPROVED' => Icons.check_circle_rounded,
      'DECLINED' => Icons.cancel_rounded,
      'CANCELLED' => Icons.block_rounded,
      _ => Icons.hourglass_top_rounded,
    };

/// "PENDING" -> "Pending"
String leaveStatusLabel(String status) {
  final s = status.trim().toLowerCase();
  if (s.isEmpty) return 'Pending';
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Parses a server date / timestamp. Returns null if it can not be read.
DateTime? parseServerDate(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v'.trim());
  if (d == null) return null;
  return d.isUtc ? d.toLocal() : d;
}

/// "Mon, 26 Oct 2026" for one day, "26 Oct - 28 Oct 2026" for a range.
String fmtLeaveRange(dynamic from, dynamic to) {
  final f = parseServerDate(from);
  final t = parseServerDate(to) ?? f;
  if (f == null) return '${from ?? ''}';
  if (t == null || sameDay(f, t)) return DateFormat('EEE, dd MMM yyyy').format(f);
  final start = f.year == t.year
      ? DateFormat('dd MMM').format(f)
      : DateFormat('dd MMM yyyy').format(f);
  return '$start - ${DateFormat('dd MMM yyyy').format(t)}';
}

String fmtDays(dynamic n) {
  final v = int.tryParse('${n ?? ''}') ?? 1;
  return '$v day${v == 1 ? '' : 's'}';
}

bool isTrue(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String errText(Object e) => e is ApiException ? e.message : e.toString();

/// Status badge: Pending / Approved / Declined / Cancelled.
class LeaveStatusChip extends StatelessWidget {
  const LeaveStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Pill(
        leaveStatusLabel(status),
        icon: leaveStatusIcon(status),
        color: leaveStatusColor(status),
      );
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Gmail-style time: today -> "02:15 PM", this year -> "21 Oct", older ->
/// "21 Oct 2025".
String fmtInboxTime(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return DateFormat('hh:mm a').format(d);
  }
  if (d.year == now.year) return DateFormat('dd MMM').format(d);
  return DateFormat('dd MMM yyyy').format(d);
}

/// "Today", "Yesterday" or "Tue, 21 Oct" - used for the day dividers in a chat.
String fmtDayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, dd MMM').format(d);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Open" (still going) or "Resolved" badge.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) => Pill(
        open ? 'Open' : 'Resolved',
        icon: open ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
        color: open ? AppColors.warning : AppColors.success,
      );
}

/// Bottom sheet: take a picture or pick one from the gallery. Returns the
/// compressed JPEG bytes, or null if cancelled / failed.
Future<Uint8List?> pickComplaintPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add a picture',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 14),
            _SheetOption(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            const SizedBox(height: 10),
            _SheetOption(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  try {
    final XFile? pic = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 70,
    );
    if (pic == null) return null;
    return await pic.readAsBytes();
  } catch (_) {
    if (context.mounted) {
      showToast(context,
          'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. '
          'Check the app permission in phone Settings.');
    }
    return null;
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.redTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  gradient: AppGradients.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      );
}

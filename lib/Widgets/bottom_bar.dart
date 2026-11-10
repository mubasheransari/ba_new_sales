import 'package:flutter/material.dart';
import 'package:ords_ba/Theme/app_theme.dart';

enum BottomTab { home, history, profile }

class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.active, required this.onChanged});
  final BottomTab active;
  final ValueChanged<BottomTab> onChanged;

  static const _items = <BottomTab, (IconData, IconData, String)>{
    BottomTab.home: (Icons.home_outlined, Icons.home_rounded, 'Home'),
    BottomTab.history: (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'History'),
    BottomTab.profile: (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.redDeep.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final e in _items.entries)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: e.key == active ? AppGradients.horizontal : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          e.key == active ? e.value.$2 : e.value.$1,
                          color: e.key == active ? Colors.white : AppColors.textDim,
                          size: 22,
                        ),
                        if (e.key == active) ...[
                          const SizedBox(width: 6),
                          Text(
                            e.value.$3,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

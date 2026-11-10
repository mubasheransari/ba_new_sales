import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _maskCnic(String? c) {
    if (c == null || c.length < 6) return c ?? '--';
    return '${c.substring(0, 5)}-*******-${c.substring(c.length - 1)}';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Logout?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('You will need to login again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final name = titleCase(user?.fullName ?? 'BA');
    final mart = martNameFor(user) ?? '--';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
        children: [
          const Text('Profile',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.text)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                  child: Text(
                    name.isEmpty ? 'B' : name[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.1,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Pill(user?.role ?? 'BA',
                          icon: Icons.verified_user_rounded,
                          color: Colors.white,
                          filled: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: cardDecoration(radius: 22),
            child: Column(
              children: [
                _Row(Icons.alternate_email_rounded, 'Email', user?.email ?? '--'),
                const Divider(height: 1),
                _Row(Icons.badge_outlined, 'CNIC', _maskCnic(user?.cnic)),
                const Divider(height: 1),
                _Row(Icons.storefront_rounded, 'Mart location', mart),
              ],
            ),
          ),
          const SizedBox(height: 22),
          GradientButton(
            text: 'LOGOUT',
            icon: Icons.logout_rounded,
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.red, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

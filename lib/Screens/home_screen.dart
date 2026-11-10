import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Bloc/dashboard_cubit.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/complaints_screen.dart';
import 'package:ords_ba/Screens/mark_attendance.dart';
import 'package:ords_ba/Screens/leaves_screen.dart';
import 'package:ords_ba/Screens/products.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/nav.dart';
import 'package:ords_ba/Widgets/sales_chart.dart';
import 'package:ords_ba/Widgets/shelf_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SaleRecord> _sales = const [];
  int _leaveUnread = 0;
  int _leavePending = 0;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user;
    if (user != null) _sales = SalesStore(user.storageKey).history();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLeaveSummary());
  }

  /// Counts for the Leave card (new replies / waiting for approval).
  Future<void> _loadLeaveSummary() async {
    if (!mounted) return;
    final token = context.read<AuthBloc>().state.token;
    if (token == null || token.isEmpty) return;
    try {
      final rows = await context.read<Repository>().fetchLeaves(token: token);
      if (!mounted) return;
      var unread = 0;
      var pending = 0;
      for (final l in rows) {
        final u = l['unread'];
        if (u == true || u == 1 || u == '1') unread++;
        if ('${l['status']}'.toUpperCase() == 'PENDING') pending++;
      }
      setState(() {
        _leaveUnread = unread;
        _leavePending = pending;
      });
    } catch (_) {
      // The card still works without the counts.
    }
  }

  void _reloadSales() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    setState(() => _sales = SalesStore(user.storageKey).history());
  }

  Future<void> _openAttendance() async {
    await pushWithBlocs<void>(context, const MarkAttendanceScreen());
    if (mounted) _reloadSales();
  }

  Future<void> _openSales() async {
    final at = context.read<AttendanceCubit>().state;
    if (at.needsShelf) {
      showShelfDialog(context);
      return;
    }
    if (!at.canEnterSales) {
      showToast(
        context,
        at.isCompletedToday
            ? 'You already marked attendance OUT today. Sales are closed.'
            : 'Please mark your attendance IN before entering sales.',
      );
      return;
    }
    await pushWithBlocs<bool>(context, const ProductsScreen());
    if (mounted) {
      _reloadSales();
      // New sales may have been saved: reload the chart from the server.
      context.read<DashboardCubit>().refreshCurrent();
    }
  }

  Future<void> _openComplaints() async {
    await pushWithBlocs<void>(context, const ComplaintsScreen());
    if (mounted) context.read<ComplaintsCubit>().refresh();
  }

  Future<void> _openLeaves() async {
    await pushWithBlocs<void>(context, const LeavesScreen());
    if (mounted) _loadLeaveSummary();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final name = titleCase(user?.fullName ?? 'BA');
    final mart = martNameFor(user);
    final today = dateKey(DateTime.now());
    final todaySales = _sales.where((s) => s.saleDate == today).toList();
    final todayQty = todaySales.fold(0, (a, s) => a + s.totalQty);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () async {
          context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
          context.read<AttendanceCubit>().sync();
          context.read<ComplaintsCubit>().refresh();
          context.read<DashboardCubit>().refreshCurrent();
          _loadLeaveSummary();
          _reloadSales();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
          children: [
            _Header(name: name, mart: mart),
            const SizedBox(height: 18),
            BlocBuilder<AttendanceCubit, AttendanceState>(
              builder: (context, at) => _StatusCard(at: at, todayQty: todayQty),
            ),
            const SizedBox(height: 18),
            SalesChart(sales: _sales),
            const SizedBox(height: 22),
            BlocBuilder<AttendanceCubit, AttendanceState>(
              builder: (context, at) => _ActionCard(
                title: 'Mark\nAttendance',
                subtitle: at.isCheckedIn
                    ? 'You are on duty. Tap to mark OUT.'
                    : at.isCompletedToday
                        ? 'Attendance completed for today.'
                        : 'Be at your mart with GPS on.',
                icon: Icons.fingerprint_rounded,
                button: at.isCheckedIn ? 'Attendance OUT' : 'Attendance IN',
                buttonIcon: Icons.location_on_rounded,
                gradient: AppGradients.primary,
                onTap: _openAttendance,
              ),
            ),
            const SizedBox(height: 18),
            BlocBuilder<AttendanceCubit, AttendanceState>(
              builder: (context, at) => _ActionCard(
                title: 'Daily\nSales',
                subtitle: at.canEnterSales
                    ? 'Enter today\'s sales for your mart.'
                    : at.needsShelf
                        ? 'Upload today\'s shelf picture to unlock sales.'
                        : 'Mark attendance IN to unlock sales.',
                icon: Icons.point_of_sale_rounded,
                button: 'Enter your sales',
                buttonIcon: at.canEnterSales
                    ? Icons.add_shopping_cart_rounded
                    : Icons.lock_outline_rounded,
                gradient: AppGradients.soft,
                locked: !at.canEnterSales,
                onTap: _openSales,
              ),
            ),
            const SizedBox(height: 18),
            BlocBuilder<ComplaintsCubit, ComplaintsState>(
              builder: (context, cs) => _ActionCard(
                title: 'Complaints\n& Problems',
                subtitle: cs.unreadCount > 0
                    ? 'You have ${cs.unreadCount} new repl${cs.unreadCount == 1 ? 'y' : 'ies'} from support.'
                    : cs.openCount > 0
                        ? '${cs.openCount} complaint${cs.openCount == 1 ? '' : 's'} still open.'
                        : 'Report a problem and chat with support.',
                icon: Icons.support_agent_rounded,
                button: 'Open complaints',
                buttonIcon: Icons.forum_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFF8E1B1B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                badge: cs.unreadCount,
                onTap: _openComplaints,
              ),
            ),
            const SizedBox(height: 18),
            _ActionCard(
              title: 'Leave\nManagement',
              subtitle: _leaveUnread > 0
                  ? 'You have $_leaveUnread new repl${_leaveUnread == 1 ? 'y' : 'ies'} from the admin.'
                  : _leavePending > 0
                      ? '$_leavePending leave request${_leavePending == 1 ? '' : 's'} waiting for approval.'
                      : 'Apply for leave and chat with the admin.',
              icon: Icons.event_available_rounded,
              button: 'Open leaves',
              buttonIcon: Icons.forum_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFF8E1B1B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              badge: _leaveUnread,
              onTap: _openLeaves,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.redTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule_rounded, color: AppColors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'If you forget to mark OUT, attendance is closed '
                      'automatically at 12:00 AM.',
                      style: TextStyle(color: AppColors.text, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ header ------------------------------ */

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.mart});
  final String name;
  final String? mart;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting(),
                  style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => AppGradients.horizontal.createShader(r),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 27, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              if (mart != null) ...[
                const SizedBox(height: 6),
                Pill(mart!, icon: Icons.storefront_rounded),
              ],
            ],
          ),
        ),
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: AppGradients.primary,
            shape: BoxShape.circle,
          ),
          child: Text(initials.isEmpty ? 'BA' : initials,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/* --------------------------- today's status --------------------------- */

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.at, required this.todayQty});
  final AttendanceState at;
  final int todayQty;

  @override
  Widget build(BuildContext context) {
    final (String title, String sub, IconData icon, Color c) = at.isCheckedIn
        ? (
            'On duty',
            'Since ${fmtTime(at.today!.inAt)}',
            Icons.check_circle_rounded,
            AppColors.success
          )
        : at.isCompletedToday
            ? (
                'Day completed',
                '${fmtTime(at.today!.inAt)}  -  ${fmtTime(at.today!.outAt)}'
                    '${at.today!.autoOut ? ' (auto)' : ''}',
                Icons.verified_rounded,
                AppColors.red
              )
            : (
                'Not marked yet',
                'Mark attendance to start your day',
                Icons.radio_button_unchecked_rounded,
                AppColors.warning
              );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(radius: 22),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEEE, dd MMM').format(DateTime.now()),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                Text(sub,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
              ],
            ),
          ),
          Column(
            children: [
              Text('$todayQty',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.red)),
              const Text('sold today',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- action cards ----------------------------- */

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.button,
    required this.buttonIcon,
    required this.gradient,
    required this.onTap,
    this.locked = false,
    this.badge = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String button;
  final IconData buttonIcon;
  final Gradient gradient;
  final VoidCallback onTap;
  final bool locked;

  /// Small red number on the button (e.g. unread complaint replies).
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -26,
            top: -10,
            child: Icon(icon, size: 190, color: Colors.white.withValues(alpha: 0.16)),
          ),
          Positioned(
            right: 22,
            top: 22,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.94),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: locked ? 0.55 : 1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(buttonIcon, color: AppColors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(button,
                            style: const TextStyle(
                                color: AppColors.redDeep,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        if (badge > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.red,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('$badge',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

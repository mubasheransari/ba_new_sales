import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/leave_thread_screen.dart';
import 'package:ords_ba/Screens/new_leave_screen.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';
import 'package:ords_ba/Widgets/leave_widgets.dart';
import 'package:ords_ba/Widgets/nav.dart';

enum _Filter { all, pending, approved, declined, cancelled }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.pending => 'Pending',
        _Filter.approved => 'Approved',
        _Filter.declined => 'Declined',
        _Filter.cancelled => 'Cancelled',
      };

  String get status => name.toUpperCase();
}

/// Inbox of the BA's leave requests (same look as the complaints inbox):
/// summary card, filter pills, one tile per request with status + unread dot.
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> {
  _Filter _filter = _Filter.all;
  List<Map<String, dynamic>> _leaves = const [];
  bool _loading = true;
  String? _error;

  Repository get _repo => context.read<Repository>();
  String get _token => context.read<AuthBloc>().state.token ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _repo.fetchLeaves(token: _token, filter: 'all');
      if (!mounted) return;
      setState(() {
        _leaves = rows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errText(e);
        _loading = false;
      });
      if (_leaves.isNotEmpty) showToast(context, errText(e));
    }
  }

  String _statusOf(Map<String, dynamic> l) =>
      '${l['status'] ?? 'PENDING'}'.toUpperCase();

  int _count(_Filter f) => f == _Filter.all
      ? _leaves.length
      : _leaves.where((l) => _statusOf(l) == f.status).length;

  int get _unread => _leaves.where((l) => isTrue(l['unread'])).length;

  List<Map<String, dynamic>> get _visible => _filter == _Filter.all
      ? _leaves
      : _leaves.where((l) => _statusOf(l) == _filter.status).toList();

  Future<void> _openThread(int id) async {
    await pushWithBlocs<void>(context, LeaveThreadScreen(leaveId: id));
    if (mounted) _load(spinner: false);
  }

  Future<void> _apply() async {
    final id = await pushWithBlocs<int>(context, const NewLeaveScreen());
    if (!mounted) return;
    if (id == null) return; // cancelled
    await _load(spinner: false);
    if (!mounted) return;
    if (id > 0) await _openThread(id);
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaves')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _apply,
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_calendar_rounded),
        label: const Text('Apply for leave',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () => _load(spinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            _SummaryCard(
              unread: _unread,
              pending: _count(_Filter.pending),
            ),
            const SizedBox(height: 14),
            _FilterBar(
              filter: _filter,
              count: _count,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 70),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.red),
                ),
              )
            else if (_error != null && _leaves.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Column(
                  children: [
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load leaves',
                      subtitle: _error,
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: _leaves.isEmpty
                      ? 'No leave requests yet'
                      : 'No ${_filter.label.toLowerCase()} leaves',
                  subtitle: _leaves.isEmpty
                      ? 'Need a day off? Tap "Apply for leave". Replies '
                          'from the admin will appear here.'
                      : 'Nothing to show in this list.',
                ),
              )
            else
              for (final l in list) ...[
                _LeaveTile(
                  leave: l,
                  onTap: () {
                    final id = int.tryParse('${l['leave_id']}');
                    if (id != null) _openThread(id);
                  },
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ summary ------------------------------ */

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.unread, required this.pending});
  final int unread;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apply for leave',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  unread > 0
                      ? '$unread request${unread == 1 ? '' : 's'} with a new reply'
                      : pending > 0
                          ? '$pending waiting for approval'
                          : 'Track approval right here in the app.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------ filters ------------------------------ */

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.count,
    required this.onChanged,
  });

  final _Filter filter;
  final int Function(_Filter) count;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_Filter f) {
      final on = filter == f;
      return GestureDetector(
        onTap: () => onChanged(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? AppGradients.horizontal : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${f.label} (${count(f)})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: on ? Colors.white : AppColors.text,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final f in _Filter.values) chip(f)]),
      ),
    );
  }
}

/* ------------------------------- a row ------------------------------- */

class _LeaveTile extends StatelessWidget {
  const _LeaveTile({required this.leave, required this.onTap});
  final Map<String, dynamic> leave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = leave;
    final status = '${l['status'] ?? 'PENDING'}';
    final color = leaveStatusColor(status);
    final unread = isTrue(l['unread']);
    final role = '${l['last_sender_role'] ?? ''}'.toUpperCase();
    final who = role == 'BA'
        ? 'You: '
        : (role == 'ADMIN' || role == 'STAFF')
            ? 'Admin: '
            : '';
    final snippet = '${l['snippet'] ?? l['reason'] ?? 'Leave request'}';
    final when = fmtInboxTime(
        parseServerDate(l['last_message_at'] ?? l['created_at']));

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(radius: 20).copyWith(
          border: Border.all(
            color: unread ? AppColors.red.withValues(alpha: 0.55) : AppColors.border,
            width: unread ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(leaveStatusIcon(status), color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fmtLeaveRange(l['from_date'], l['to_date']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight:
                                unread ? FontWeight.w900 : FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (when.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          when,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w500,
                            color: unread ? AppColors.red : AppColors.textDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$who$snippet',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.25,
                            color: unread ? AppColors.text : AppColors.textDim,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      LeaveStatusChip(status: status),
                      const SizedBox(width: 8),
                      Pill(
                        fmtDays(l['total_days']),
                        icon: Icons.date_range_rounded,
                        color: AppColors.textDim,
                      ),
                    ],
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

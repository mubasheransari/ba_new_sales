import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:ords_ba/Screens/complaint_chat_screen.dart';
import 'package:ords_ba/Screens/new_complaint_screen.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';
import 'package:ords_ba/Widgets/nav.dart';

enum _Filter { all, open, resolved }

/// Inbox of the BA's complaints (like a mail inbox): subject, last message,
/// time, an unread dot and an Open / Resolved badge.
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    context.read<ComplaintsCubit>().load();
  }

  Future<void> _openChat(Complaint c) async {
    await pushWithBlocs<void>(
      context,
      ComplaintChatScreen(complaintId: c.id, title: c.title),
    );
    if (mounted) context.read<ComplaintsCubit>().refresh();
  }

  Future<void> _newComplaint() async {
    final id = await pushWithBlocs<int>(context, const NewComplaintScreen());
    if (!mounted) return;
    if (id != null && id > 0) {
      await pushWithBlocs<void>(
        context,
        ComplaintChatScreen(complaintId: id, title: 'Complaint #$id'),
      );
      if (mounted) context.read<ComplaintsCubit>().refresh();
    }
  }

  List<Complaint> _visible(List<Complaint> all) => switch (_filter) {
        _Filter.all => all,
        _Filter.open => all.where((c) => c.isOpen).toList(),
        _Filter.resolved => all.where((c) => !c.isOpen).toList(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newComplaint,
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New complaint',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: BlocBuilder<ComplaintsCubit, ComplaintsState>(
        builder: (context, st) {
          final list = _visible(st.complaints);
          return RefreshIndicator(
            color: AppColors.red,
            onRefresh: () => context.read<ComplaintsCubit>().refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
              children: [
                _SummaryCard(state: st),
                const SizedBox(height: 14),
                _FilterBar(
                  filter: _filter,
                  all: st.complaints.length,
                  open: st.openCount,
                  resolved: st.resolvedCount,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 14),
                if (st.load == ComplaintsLoad.loading ||
                    st.load == ComplaintsLoad.initial)
                  const Padding(
                    padding: EdgeInsets.only(top: 70),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.red),
                    ),
                  )
                else if (st.load == ComplaintsLoad.error)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Column(
                      children: [
                        EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load complaints',
                          subtitle: st.error,
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.read<ComplaintsCubit>().load(),
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
                      icon: Icons.forum_outlined,
                      title: st.complaints.isEmpty
                          ? 'No complaints yet'
                          : _filter == _Filter.open
                              ? 'No open complaints'
                              : 'No resolved complaints',
                      subtitle: st.complaints.isEmpty
                          ? 'Facing a problem? Tap "New complaint" and tell '
                              'us. Replies will appear here.'
                          : 'Nothing to show in this list.',
                    ),
                  )
                else
                  for (final c in list) ...[
                    _ComplaintTile(complaint: c, onTap: () => _openChat(c)),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ------------------------------ summary ------------------------------ */

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});
  final ComplaintsState state;

  @override
  Widget build(BuildContext context) {
    final unread = state.unreadCount;
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
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Report a problem',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  unread > 0
                      ? '$unread conversation${unread == 1 ? '' : 's'} with a new reply'
                      : state.openCount > 0
                          ? '${state.openCount} still open'
                          : 'We reply right here in the app.',
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
    required this.all,
    required this.open,
    required this.resolved,
    required this.onChanged,
  });

  final _Filter filter;
  final int all;
  final int open;
  final int resolved;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_Filter f, String label, int n) {
      final on = filter == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? AppGradients.horizontal : null,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$label ($n)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: on ? Colors.white : AppColors.text,
              ),
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
      child: Row(
        children: [
          chip(_Filter.all, 'All', all),
          chip(_Filter.open, 'Open', open),
          chip(_Filter.resolved, 'Resolved', resolved),
        ],
      ),
    );
  }
}

/* ------------------------------- a row ------------------------------- */

class _ComplaintTile extends StatelessWidget {
  const _ComplaintTile({required this.complaint, required this.onTap});
  final Complaint complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final open = c.isOpen;
    final who = c.lastSenderRole == 'BA'
        ? 'You: '
        : c.lastSenderRole == 'STAFF'
            ? 'Support: '
            : '';
    final accent = open ? AppColors.red : AppColors.success;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(radius: 20).copyWith(
          border: Border.all(
            color: c.unread ? AppColors.red.withValues(alpha: 0.55) : AppColors.border,
            width: c.unread ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                open ? Icons.forum_rounded : Icons.check_circle_rounded,
                color: accent,
                size: 24,
              ),
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
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight:
                                c.unread ? FontWeight.w900 : FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fmtInboxTime(c.lastMessageAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              c.unread ? FontWeight.w800 : FontWeight.w500,
                          color: c.unread ? AppColors.red : AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$who${c.snippet}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.25,
                            color: c.unread ? AppColors.text : AppColors.textDim,
                            fontWeight:
                                c.unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (c.unread) ...[
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
                      StatusChip(open: open),
                      const SizedBox(width: 8),
                      Pill(
                        '${c.messageCount} message${c.messageCount == 1 ? '' : 's'}',
                        icon: Icons.chat_bubble_outline_rounded,
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

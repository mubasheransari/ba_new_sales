import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';
import 'package:ords_ba/Widgets/leave_widgets.dart';

/// One leave request as a chat: the BA's reason, the admin's replies and
/// decision, with a clear status banner (same look as the complaint chat).
class LeaveThreadScreen extends StatefulWidget {
  const LeaveThreadScreen({super.key, required this.leaveId});
  final int leaveId;

  @override
  State<LeaveThreadScreen> createState() => _LeaveThreadScreenState();
}

class _LeaveThreadScreenState extends State<LeaveThreadScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _sending = false;
  bool _cancelling = false;
  bool _firstScrollDone = false;
  String? _error;

  Repository get _repo => context.read<Repository>();
  String get _token => context.read<AuthBloc>().state.token ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _toBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await _repo.fetchLeaveThread(token: _token, id: widget.leaveId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
      if (!_firstScrollDone) {
        _firstScrollDone = true;
        _toBottom(animate: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errText(e);
        _loading = false;
      });
      if (_data != null) showToast(context, errText(e));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.sendLeaveMessage(
          token: _token, id: widget.leaveId, message: text);
      _input.clear();
      await _load(silent: true);
      _toBottom();
    } catch (e) {
      if (mounted) showToast(context, errText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: const Text(
            'The request will be marked as cancelled and the admin will '
            'be told.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel leave'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _repo.cancelLeave(token: _token, id: widget.leaveId);
      await _load(silent: true);
      if (mounted) showToast(context, 'Leave request cancelled.', error: false);
      _toBottom();
    } catch (e) {
      if (mounted) showToast(context, errText(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final status = '${d?['status'] ?? ''}';
    final canCancel = d != null && isTrue(d['can_cancel']);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d == null
                  ? 'Leave #${widget.leaveId}'
                  : fmtLeaveRange(d['from_date'], d['to_date']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (d != null && status.isNotEmpty)
              Text(
                leaveStatusLabel(status),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: leaveStatusColor(status),
                ),
              ),
          ],
        ),
        actions: [
          if (canCancel)
            PopupMenuButton<int>(
              enabled: !_cancelling,
              icon: _cancelling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.more_vert_rounded),
              onSelected: (_) => _cancel(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded, color: AppColors.red),
                      SizedBox(width: 10),
                      Text('Cancel request'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.red))
          : (_error != null && d == null)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not open this request',
                        subtitle: _error,
                      ),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : _buildThread(d!),
    );
  }

  Widget _buildThread(Map<String, dynamic> d) {
    final raw = d['messages'] is List ? d['messages'] as List : const [];
    final msgs = [
      for (final m in raw)
        if (m is Map) Map<String, dynamic>.from(m)
    ];

    // details card + messages with day dividers, in one flat list
    final items = <Object>[_DetailsMarker(d)];
    DateTime? prev;
    for (final m in msgs) {
      final t = parseServerDate(m['created_at']);
      if (t != null && (prev == null || !sameDay(prev, t))) items.add(t);
      if (t != null) prev = t;
      items.add(m);
    }

    final status = '${d['status'] ?? ''}';
    final canCancel = isTrue(d['can_cancel']);
    final canMessage = isTrue(d['can_message']);

    return Column(
      children: [
        _StatusBanner(
          status: status,
          canCancel: canCancel,
          busy: _cancelling,
          onCancel: _cancel,
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.red,
            onRefresh: () => _load(silent: true),
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final it = items[i];
                if (it is _DetailsMarker) return _DetailsCard(data: it.data);
                if (it is DateTime) return _DayDivider(label: fmtDayLabel(it));
                final m = it as Map<String, dynamic>;
                return '${m['sender_role'] ?? ''}'.toUpperCase() == 'SYSTEM'
                    ? _SystemLine(message: m)
                    : _Bubble(message: m);
              },
            ),
          ),
        ),
        if (canMessage)
          _Composer(controller: _input, sending: _sending, onSend: _send)
        else
          const _ClosedBar(),
      ],
    );
  }
}

class _DetailsMarker {
  const _DetailsMarker(this.data);
  final Map<String, dynamic> data;
}

/* ----------------------------- status banner ----------------------------- */

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.status,
    required this.canCancel,
    required this.busy,
    required this.onCancel,
  });

  final String status;
  final bool canCancel;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final color = leaveStatusColor(status);
    final text = switch (status.toUpperCase()) {
      'APPROVED' => 'Approved. You can still message the admin here.',
      'DECLINED' => 'Declined. See the admin\'s note below.',
      'CANCELLED' => 'You cancelled this request.',
      _ => 'Waiting for admin approval. Replies will appear here.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(leaveStatusIcon(status), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
          ),
          if (canCancel)
            TextButton(
              onPressed: busy ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.red,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

/* ------------------------------ details card ------------------------------ */

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = '${data['status'] ?? ''}';
    final note = '${data['decision_note'] ?? ''}'.trim();
    final color = leaveStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_note_rounded, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtLeaveRange(data['from_date'], data['to_date']),
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        LeaveStatusChip(status: status),
                        const SizedBox(width: 8),
                        Pill(
                          fmtDays(data['total_days']),
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
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin note',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  const SizedBox(height: 3),
                  Text(note,
                      style: const TextStyle(
                          fontSize: 14, height: 1.3, color: AppColors.text)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------- messages ------------------------------- */

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.redDeep)),
          ),
        ),
      );
}

/// "Approved" / "Declined" / "Cancelled" line in the middle of the chat.
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final body = '${message['body'] ?? ''}';
    final lower = body.toLowerCase();
    final status = lower.contains('approv')
        ? 'APPROVED'
        : lower.contains('declin')
            ? 'DECLINED'
            : lower.contains('cancel')
                ? 'CANCELLED'
                : 'PENDING';
    final color = leaveStatusColor(status);
    final time = parseServerDate(message['created_at']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(leaveStatusIcon(status), size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  time == null ? body : '$body  -  ${fmtTime(time)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = isTrue(m['is_mine']);
    final body = '${m['body'] ?? ''}';
    final sender = '${m['sender_name'] ?? ''}'.trim();
    final time = parseServerDate(m['created_at']);
    final maxW = MediaQuery.sizeOf(context).width * 0.78;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: maxW),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          gradient: mine ? AppGradients.horizontal : null,
          color: mine ? null : Colors.white,
          border: mine ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          boxShadow: mine ? null : cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && sender.isNotEmpty) ...[
              Text(sender,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red)),
              const SizedBox(height: 3),
            ],
            if (body.isNotEmpty)
              Text(
                body,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.3,
                  color: mine ? Colors.white : AppColors.text,
                ),
              ),
            if (time != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  fmtTime(time),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textDim,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* -------------------------------- composer -------------------------------- */

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    counterText: '',
                    isDense: true,
                    hintText: 'Type a message...',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, v, _) {
                  final canSend = !sending && v.text.trim().isNotEmpty;
                  return Opacity(
                    opacity: canSend || sending ? 1 : 0.5,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: canSend ? onSend : null,
                          child: Center(
                            child: sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 21),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedBar extends StatelessWidget {
  const _ClosedBar();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(
              'Messaging is closed for this request.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
}

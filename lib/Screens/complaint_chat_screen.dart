import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/complaint_thread_cubit.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';

/// One complaint as a chat: the BA's problem, support's replies, pictures,
/// and a clear Open / Resolved status (like a mail thread).
class ComplaintChatScreen extends StatelessWidget {
  const ComplaintChatScreen({
    super.key,
    required this.complaintId,
    required this.title,
  });

  final int complaintId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final inbox = context.read<ComplaintsCubit>();
    return BlocProvider<ComplaintThreadCubit>(
      create: (_) => ComplaintThreadCubit(
        service: inbox.service,
        inbox: inbox,
        complaintId: complaintId,
      )..load(),
      child: _ChatBody(initialTitle: title),
    );
  }
}

/* --------------------------------- body --------------------------------- */

class _ChatBody extends StatefulWidget {
  const _ChatBody({required this.initialTitle});
  final String initialTitle;

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  Uint8List? _pending;
  bool _firstScrollDone = false;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 140;
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

  Future<void> _attach() async {
    FocusScope.of(context).unfocus();
    final bytes = await pickComplaintPhoto(context);
    if (bytes != null && mounted) setState(() => _pending = bytes);
  }

  Future<void> _send() async {
    final cubit = context.read<ComplaintThreadCubit>();
    if (cubit.state.sending) return;
    final text = _input.text;
    final img = _pending;
    if (text.trim().isEmpty && img == null) return;

    final ok = await cubit.send(text: text, image: img);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      setState(() => _pending = null);
      _toBottom();
    }
  }

  Future<void> _confirmStatus(bool resolve) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(resolve ? 'Mark as resolved?' : 'Reopen complaint?'),
        content: Text(resolve
            ? 'Use this when the problem is fixed. You can reopen it any '
                'time by replying.'
            : 'The complaint will be marked as open again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(resolve ? 'Mark resolved' : 'Reopen'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      context.read<ComplaintThreadCubit>().setResolved(resolve);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // toast for actions / errors
        BlocListener<ComplaintThreadCubit, ThreadState>(
          listenWhen: (a, b) => a.messageId != b.messageId && b.message != null,
          listener: (context, st) =>
              showToast(context, st.message!, error: st.messageIsError),
        ),
        // scroll when messages arrive
        BlocListener<ComplaintThreadCubit, ThreadState>(
          listenWhen: (a, b) =>
              (a.thread?.messages.length ?? 0) != (b.thread?.messages.length ?? 0),
          listener: (context, st) {
            final msgs = st.thread!.messages;
            if (!_firstScrollDone) {
              _firstScrollDone = true;
              _toBottom(animate: false);
            } else if (_nearBottom || (msgs.isNotEmpty && msgs.last.isMine)) {
              _toBottom();
            }
          },
        ),
      ],
      child: BlocBuilder<ComplaintThreadCubit, ThreadState>(
        builder: (context, st) {
          final t = st.thread;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t?.title ?? widget.initialTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (t != null)
                    Text(
                      t.isOpen ? 'Open' : 'Resolved',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.isOpen ? AppColors.warning : AppColors.success,
                      ),
                    ),
                ],
              ),
              actions: [
                if (t != null)
                  PopupMenuButton<bool>(
                    enabled: !st.changingStatus,
                    icon: st.changingStatus
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.more_vert_rounded),
                    onSelected: _confirmStatus,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: t.isOpen,
                        child: Row(
                          children: [
                            Icon(
                              t.isOpen
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.replay_rounded,
                              color: t.isOpen
                                  ? AppColors.success
                                  : AppColors.red,
                            ),
                            const SizedBox(width: 10),
                            Text(t.isOpen ? 'Mark as resolved' : 'Reopen'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: switch (st.load) {
              ThreadLoad.loading => const Center(
                  child: CircularProgressIndicator(color: AppColors.red)),
              ThreadLoad.error => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not open this conversation',
                        subtitle: st.error,
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.read<ComplaintThreadCubit>().load(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ThreadLoad.ready => _buildChat(context, st, t!),
            },
          );
        },
      ),
    );
  }

  Widget _buildChat(BuildContext context, ThreadState st, ComplaintThread t) {
    // messages + day dividers in one flat list
    final items = <Object>[];
    DateTime? prev;
    for (final m in t.messages) {
      final d = m.createdAt;
      if (d != null && (prev == null || !sameDay(prev, d))) items.add(d);
      if (d != null) prev = d;
      items.add(m);
    }

    return Column(
      children: [
        _StatusBanner(
          thread: t,
          busy: st.changingStatus,
          onToggle: () => _confirmStatus(t.isOpen),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              if (it is DateTime) return _DayDivider(label: fmtDayLabel(it));
              final m = it as ComplaintMessage;
              return m.isSystem ? _SystemLine(message: m) : _Bubble(message: m);
            },
          ),
        ),
        _Composer(
          controller: _input,
          pending: _pending,
          sending: st.sending,
          resolved: !t.isOpen,
          onAttach: _attach,
          onRemovePending: () => setState(() => _pending = null),
          onSend: _send,
        ),
      ],
    );
  }
}

/* ----------------------------- status banner ----------------------------- */

class _StatusBanner extends StatelessWidget {
  const _StatusBanner(
      {required this.thread, required this.busy, required this.onToggle});
  final ComplaintThread thread;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final open = thread.isOpen;
    final color = open ? AppColors.warning : AppColors.success;
    final text = open
        ? 'Still open. Support will reply here.'
        : thread.resolvedAt != null
            ? 'Resolved on ${DateFormat('dd MMM, hh:mm a').format(thread.resolvedAt!)}. '
                'Reply to reopen.'
            : 'Resolved. Reply to reopen.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(
            open ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
          ),
          TextButton(
            onPressed: busy ? null : onToggle,
            style: TextButton.styleFrom(
              foregroundColor: open ? AppColors.success : AppColors.red,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(open ? 'Mark resolved' : 'Reopen',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
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

/// "Marked as resolved" / "Reopened" line in the middle of the chat.
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.message});
  final ComplaintMessage message;

  @override
  Widget build(BuildContext context) {
    final resolved = message.body.toLowerCase().contains('resolved');
    final color = resolved ? AppColors.success : AppColors.warning;
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
              Icon(
                resolved ? Icons.check_circle_rounded : Icons.replay_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                '${message.body}  -  ${fmtTime(message.createdAt)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text),
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
  final ComplaintMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.isMine;
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
            if (!mine && m.senderName.isNotEmpty) ...[
              Text(m.senderName,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red)),
              const SizedBox(height: 3),
            ],
            if (m.hasImage) ...[
              _ChatImage(messageId: m.id),
              if (m.body.isNotEmpty) const SizedBox(height: 7),
            ],
            if (m.body.isNotEmpty)
              Text(
                m.body,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.3,
                  color: mine ? Colors.white : AppColors.text,
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                fmtTime(m.createdAt),
                style: TextStyle(
                  fontSize: 10.5,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture in a bubble. The server needs the login token to return it, so
/// it is downloaded through the repository and cached by the cubit.
class _ChatImage extends StatefulWidget {
  const _ChatImage({required this.messageId});
  final int messageId;

  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ComplaintThreadCubit>().imageFor(widget.messageId);
  }

  void _retry() {
    setState(() {
      _future = context.read<ComplaintThreadCubit>().imageFor(widget.messageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData && snap.data!.isNotEmpty) {
          final bytes = snap.data!;
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _FullImage(bytes: bytes)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                width: 230,
                height: 170,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        }
        final failed = snap.hasError;
        return GestureDetector(
          onTap: failed ? _retry : null,
          child: Container(
            width: 230,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: failed
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          color: AppColors.textDim, size: 30),
                      SizedBox(height: 4),
                      Text('Tap to retry',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 12)),
                    ],
                  )
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
          ),
        );
      },
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Image.memory(bytes),
          ),
        ),
      );
}

/* -------------------------------- composer -------------------------------- */

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.pending,
    required this.sending,
    required this.resolved,
    required this.onAttach,
    required this.onRemovePending,
    required this.onSend,
  });

  final TextEditingController controller;
  final Uint8List? pending;
  final bool sending;
  final bool resolved;
  final VoidCallback onAttach;
  final VoidCallback onRemovePending;
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
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(pending!,
                              width: 76, height: 76, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: GestureDetector(
                            onTap: sending ? null : onRemovePending,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppColors.redDeep,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: sending ? null : onAttach,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    color: AppColors.red,
                    tooltip: 'Attach a picture',
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        hintText: resolved
                            ? 'Reply to reopen this complaint...'
                            : 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, v, _) {
                      final canSend = !sending &&
                          (v.text.trim().isNotEmpty || pending != null);
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
                                          valueColor: AlwaysStoppedAnimation(
                                              Colors.white),
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
            ],
          ),
        ),
      ),
    );
  }
}

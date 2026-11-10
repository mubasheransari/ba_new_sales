import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/leave_widgets.dart';

/// Form to apply for leave: from / to date and a reason (same look as the
/// New Complaint form). Pops with the new leave id so the list can open it.
class NewLeaveScreen extends StatefulWidget {
  const NewLeaveScreen({super.key});

  @override
  State<NewLeaveScreen> createState() => _NewLeaveScreenState();
}

class _NewLeaveScreenState extends State<NewLeaveScreen> {
  static const _reasonMax = 1000;
  static const _maxDays = 30;

  final _reason = TextEditingController();
  late DateTime _from;
  late DateTime _to;
  String? _reasonError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month, n.day);
    _to = _from;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int get _days => _to.difference(_from).inDays + 1;

  Future<void> _pick({required bool isFrom}) async {
    FocusScope.of(context).unfocus();
    final current = isFrom ? _from : _to;
    final first = isFrom ? _today : _from;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: _today.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
      }
    });
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final reason = _reason.text.trim();
    setState(() =>
        _reasonError = reason.isEmpty ? 'Please write the reason for your leave.' : null);
    if (reason.isEmpty) return;
    if (_days > _maxDays) {
      showToast(context, 'One leave can be at most $_maxDays days.');
      return;
    }

    setState(() => _busy = true);
    try {
      final token = context.read<AuthBloc>().state.token ?? '';
      final id = await context.read<Repository>().applyLeave(
            token: token,
            fromDate: _iso(_from),
            toDate: _iso(_to),
            reason: reason,
          );
      if (!mounted) return;
      showToast(context, 'Leave request sent for approval.', error: false);
      Navigator.of(context).pop(id ?? 0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final mart = martNameFor(user);

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for Leave')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: GradientButton(
            text: 'SEND REQUEST',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: _submit,
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.redTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mart == null
                          ? 'Pick one day or a date range. The admin will '
                              'approve or decline here in the app.'
                          : 'This request is for $mart. The admin will '
                              'approve or decline here in the app.',
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _Label('Dates'),
            Row(
              children: [
                Expanded(
                  child: _DateCard(
                    label: 'From',
                    date: _from,
                    onTap: _busy ? null : () => _pick(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateCard(
                    label: 'To',
                    date: _to,
                    onTap: _busy ? null : () => _pick(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Pill(
                  '${fmtDays(_days)} requested',
                  icon: Icons.date_range_rounded,
                  color: _days > _maxDays ? AppColors.redDeep : AppColors.red,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _Label('Reason'),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: _reasonMax,
              minLines: 5,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              onChanged: (_) {
                if (_reasonError != null) setState(() => _reasonError = null);
              },
              decoration: InputDecoration(
                hintText: 'Explain why you need leave...',
                alignLabelWithHint: true,
                errorText: _reasonError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.text)),
      );
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    color: AppColors.red, size: 18),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${date.day} ${_months[date.month - 1]}',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text)),
            Text('${_days[date.weekday - 1]}, ${date.year}',
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

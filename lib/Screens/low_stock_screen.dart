import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Model/review_models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// The BA ticks the products that are running low on the shelf and, for each
/// of them, ticks the customer review questions that apply.
/// A BA can submit as many times as needed in a day.
class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key, required this.all});

  /// Active SKU list already loaded by the products screen.
  final List<Sku> all;

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  final _search = TextEditingController();
  final Set<int> _selected = {};

  /// product (sku id) -> ids of the review questions ticked for it
  final Map<int, Set<int>> _answers = {};

  List<ReviewQuestion> _questions = const [];
  bool _loadingQuestions = true;
  bool _questionsFailed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final auth = context.read<AuthBloc>();
    final repo = context.read<Repository>();
    final token = auth.state.token;
    setState(() {
      _loadingQuestions = true;
      _questionsFailed = false;
    });
    if (token == null) {
      setState(() {
        _loadingQuestions = false;
        _questionsFailed = true;
      });
      return;
    }
    try {
      final q = await repo.fetchReviewQuestions(token: token);
      if (!mounted) return;
      setState(() {
        _questions = q;
        _loadingQuestions = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingQuestions = false;
        _questionsFailed = true;
      });
      if (e.isUnauthorized) {
        auth.add(const AuthLogoutRequested(
            reason: 'Session expired. Please login again.'));
      }
    }
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.remove(id)) {
        _answers.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _toggleQuestion(int sku, int questionId) {
    setState(() {
      final set = _answers.putIfAbsent(sku, () => <int>{});
      if (!set.remove(questionId)) set.add(questionId);
    });
  }

  /// Copies the ticks of one product to every selected product.
  void _copyToAll(int fromSku) {
    setState(() {
      final src = _answers[fromSku] ?? <int>{};
      for (final id in _selected) {
        _answers[id] = {...src};
      }
    });
    showToast(context, 'Applied to all selected products.', error: false);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final auth = context.read<AuthBloc>();
    final repo = context.read<Repository>();
    final token = auth.state.token;
    final user = auth.state.user;
    final userId = int.tryParse(user?.id ?? '');
    final locationId = user?.locationId;

    if (_selected.isEmpty) {
      showToast(context, 'Please tick at least one low stock product.');
      return;
    }
    if (token == null || userId == null || locationId == null) {
      showToast(context, 'Your user or location is missing. Please login again.');
      return;
    }

    setState(() => _busy = true);
    try {
      await repo.submitLowStock(
        token: token,
        userId: userId,
        locationId: locationId,
        skuIds: _selected.toList(),
        questionsBySku: {
          for (final id in _selected) id: (_answers[id] ?? <int>{}).toList(),
        },
      );
      if (!mounted) return;
      showToast(context, 'Low stock submitted (${_selected.length} items).',
          error: false);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.isUnauthorized) {
        auth.add(const AuthLogoutRequested(
            reason: 'Session expired. Please login again.'));
        return;
      }
      showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = widget.all.where((s) {
      return q.isEmpty ||
          s.itemName.toLowerCase().contains(q) ||
          s.blendName.toLowerCase().contains(q) ||
          s.itemCode.contains(q);
    }).toList();
    final count = _selected.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock'),
        actions: [
          if (count > 0)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _selected.clear();
                        _answers.clear();
                      }),
              child: const Text('Clear'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: GradientButton(
            text: count == 0
                ? 'SELECT LOW STOCK PRODUCTS'
                : 'SUBMIT LOW STOCK  -  $count item${count == 1 ? '' : 's'}',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: count == 0 ? null : _submit,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search product, blend or code',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          if (_questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.redTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.rate_review_rounded,
                        size: 18, color: AppColors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tick the products running low, then tick the '
                        'customer review questions that apply to each one.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.text, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
            child: Row(
              children: [
                Text('${list.length} products',
                    style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (count > 0) Pill('Selected: $count', icon: Icons.check_rounded),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No products found',
                    subtitle: 'Try a different search.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _productCard(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(Sku s) {
    final on = _selected.contains(s.skuId);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _busy ? null : () => _toggle(s.skuId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: cardDecoration(radius: 18).copyWith(
          border: Border.all(
            color: on ? AppColors.red : AppColors.border,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: on,
                  activeColor: AppColors.red,
                  onChanged: _busy ? null : (_) => _toggle(s.skuId),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [s.itemCode, s.blendName]
                            .where((e) => e.isNotEmpty)
                            .join('  -  '),
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (on) _questionBox(s),
          ],
        ),
      ),
    );
  }

  /// The customer review questions for one ticked product.
  Widget _questionBox(Sku s) {
    if (_loadingQuestions) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(6, 10, 6, 2),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.red),
            ),
            SizedBox(width: 8),
            Text('Loading customer review questions...',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      );
    }
    if (_questionsFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 0, 0),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 16, color: AppColors.textDim),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Review questions could not be loaded.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
            TextButton(onPressed: _loadQuestions, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_questions.isEmpty) return const SizedBox.shrink();

    final ticked = _answers[s.skuId] ?? const <int>{};
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.rate_review_rounded, size: 16, color: AppColors.red),
              SizedBox(width: 6),
              Text('Customer review',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 4),
          for (final qn in _questions)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _busy ? null : () => _toggleQuestion(s.skuId, qn.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: ticked.contains(qn.id),
                      activeColor: AppColors.red,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: _busy
                          ? null
                          : (_) => _toggleQuestion(s.skuId, qn.id),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, right: 4),
                        child: Text(qn.text,
                            style: const TextStyle(
                                fontSize: 13, height: 1.25, color: AppColors.text)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_selected.length > 1 && ticked.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _copyToAll(s.skuId),
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Use these answers for all selected products',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

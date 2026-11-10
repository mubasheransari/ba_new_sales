import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Screens/low_stock_screen.dart';
import 'package:ords_ba/Widgets/nav.dart';

const _kBlockedMsg = 'Please mark your attendance IN before entering sales.';

/* ===================================================================== */
/*  Catalog                                                               */
/* ===================================================================== */

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  late final SalesStore _store;
  final _cache = CacheStore();

  List<Sku> _all = const [];
  final Map<int, int> _cart = {};
  String _group = 'All';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthBloc>().state.user!;
    _store = SalesStore(user.storageKey);
    _cart.addAll(_store.loadCart());
    _load();

    // Safety net: even if this screen is opened from somewhere else,
    // sales cannot be entered without attendance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<AttendanceCubit>().state.canEnterSales) {
        Navigator.of(context).pop();
        showToast(context, _kBlockedMsg);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = _cache.readSkus();
    setState(() {
      _all = cached;
      _loading = cached.isEmpty;
      _error = null;
    });
    try {
      final fresh = await context.read<Repository>().fetchSkus();
      await _cache.saveSkus(fresh);
      if (!mounted) return;
      setState(() {
        _all = fresh;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_all.isEmpty) _error = e.message;
      });
      if (_all.isNotEmpty) {
        showToast(context, 'Showing saved products. ${e.message}');
      }
    }
  }

  int _qty(int id) => _cart[id] ?? 0;

  void _setQty(int id, int q) {
    setState(() {
      if (q <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = q > 99999 ? 99999 : q;
      }
    });
    _store.saveCart(_cart);
  }

  Future<void> _typeQty(Sku s) async {
    final v = await showQtyDialog(context, s.itemName, _qty(s.skuId));
    if (v != null) _setQty(s.skuId, v);
  }

  /// Low stock: BA ticks the SKUs that are running low and submits.
  Future<void> _openLowStock() =>
      pushWithBlocs<bool>(context, LowStockScreen(all: _all));

  Future<void> _openCart() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<AuthBloc>()),
            BlocProvider.value(value: context.read<AttendanceCubit>()),
            RepositoryProvider.value(value: context.read<Repository>()),
          ],
          child: CartScreen(all: _all, cart: _cart, store: _store),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {}); // cart may have changed
    if (done == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String>[
      'All',
      ...{for (final s in _all) s.group}.where((g) => g.isNotEmpty),
    ];
    final q = _search.text.trim().toLowerCase();
    final filtered = _all.where((s) {
      final gOk = _group == 'All' || s.group == _group;
      final qOk = q.isEmpty ||
          s.itemName.toLowerCase().contains(q) ||
          s.blendName.toLowerCase().contains(q) ||
          s.itemCode.contains(q);
      return gOk && qOk;
    }).toList();

    final lines = _cart.length;
    final totalQty = _cart.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Sales'),
        actions: [
          IconButton(
            tooltip: 'Low stock',
            icon: const Icon(Icons.report_problem_outlined),
            onPressed: _all.isEmpty ? null : _openLowStock,
          ),
          IconButton(
            tooltip: 'Refresh products',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      bottomNavigationBar: lines == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: GradientButton(
                  text: 'VIEW LIST  -  $lines item${lines == 1 ? '' : 's'}  -  Qty $totalQty',
                  icon: Icons.shopping_bag_outlined,
                  onPressed: _openCart,
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
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final g = groups[i];
                final sel = g == _group;
                return ChoiceChip(
                  label: Text(g),
                  selected: sel,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _group = g),
                  selectedColor: AppColors.red,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(
                        color: sel ? Colors.transparent : AppColors.border),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
            child: Row(
              children: [
                Text('${filtered.length} products',
                    style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (lines > 0) Pill('In list: $lines', icon: Icons.check_rounded),
              ],
            ),
          ),
          Expanded(child: _body(filtered)),
        ],
      ),
    );
  }

  Widget _body(List<Sku> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: GradientButton(
                    text: 'RETRY', height: 46, onPressed: _load),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No products found',
        subtitle: 'Try a different search or group.',
      );
    }
    return RefreshIndicator(
      color: AppColors.red,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final s = filtered[i];
          return _SkuCard(
            sku: s,
            qty: _qty(s.skuId),
            onInc: () => _setQty(s.skuId, _qty(s.skuId) + 1),
            onDec: () => _setQty(s.skuId, _qty(s.skuId) - 1),
            onTypeQty: () => _typeQty(s),
          );
        },
      ),
    );
  }
}

class _SkuCard extends StatelessWidget {
  const _SkuCard({
    required this.sku,
    required this.qty,
    required this.onInc,
    required this.onDec,
    required this.onTypeQty,
  });
  final Sku sku;
  final int qty;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onTypeQty;

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(radius: 18).copyWith(
        border: Border.all(
          color: selected ? AppColors.red : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: AppColors.red),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sku.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (sku.blendName.isNotEmpty) Pill(sku.blendName),
                    if (sku.itemCode.isNotEmpty)
                      Pill('#${sku.itemCode}', color: AppColors.textDim),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          qty == 0
              ? InkWell(
                  onTap: onInc,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white),
                  ),
                )
              : QtyStepper(
                  qty: qty, onInc: onInc, onDec: onDec, onTypeQty: onTypeQty),
        ],
      ),
    );
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.qty,
    required this.onInc,
    required this.onDec,
    required this.onTypeQty,
  });
  final int qty;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onTypeQty;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
              width: 34, height: 38, child: Icon(i, color: AppColors.red, size: 20)),
        );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onDec),
          GestureDetector(
            onTap: onTypeQty,
            child: Container(
              constraints: const BoxConstraints(minWidth: 34),
              alignment: Alignment.center,
              child: Text('$qty',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.redDeep)),
            ),
          ),
          btn(Icons.add_rounded, onInc),
        ],
      ),
    );
  }
}

Future<int?> showQtyDialog(BuildContext context, String title, int current) {
  final c = TextEditingController(text: current > 0 ? '$current' : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: const InputDecoration(labelText: 'Quantity'),
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v) ?? 0),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0),
          child: const Text('Set'),
        ),
      ],
    ),
  );
}

/* ===================================================================== */
/*  Cart / confirm                                                        */
/* ===================================================================== */

class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.all,
    required this.cart,
    required this.store,
  });
  final List<Sku> all;
  final Map<int, int> cart; // shared with the catalog screen
  final SalesStore store;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _saving = false;

  List<MapEntry<Sku, int>> get _rows {
    final byId = {for (final s in widget.all) s.skuId: s};
    final out = <MapEntry<Sku, int>>[];
    for (final e in widget.cart.entries) {
      final s = byId[e.key];
      if (s != null && e.value > 0) out.add(MapEntry(s, e.value));
    }
    out.sort((a, b) => a.key.itemName.compareTo(b.key.itemName));
    return out;
  }

  int get _totalQty => widget.cart.values.fold(0, (a, b) => a + b);

  void _setQty(int id, int q) {
    setState(() {
      if (q <= 0) {
        widget.cart.remove(id);
      } else {
        widget.cart[id] = q > 99999 ? 99999 : q;
      }
    });
    widget.store.saveCart(widget.cart);
  }

  Future<void> _submit() async {
    final auth = context.read<AuthBloc>();
    final user = auth.state.user;
    final token = auth.state.token;

    if (!context.read<AttendanceCubit>().state.canEnterSales) {
      showToast(context, _kBlockedMsg);
      return;
    }
    if (user?.locationId == null || token == null) {
      showToast(context, 'No mart location is assigned to your account.');
      return;
    }
    final rows = _rows;
    if (rows.isEmpty) return;

    final now = DateTime.now();
    final saleDate = dateKey(now);

    setState(() => _saving = true);
    try {
      final msg = await context.read<Repository>().enterSales(
            token: token,
            locationId: user!.locationId!,
            saleDate: saleDate,
            quantities: {for (final r in rows) r.key.skuId: r.value},
          );

      await widget.store.add(SaleRecord(
        id: now.microsecondsSinceEpoch.toString(),
        createdAt: now,
        saleDate: saleDate,
        locationId: user.locationId,
        lines: [
          for (final r in rows)
            SaleLine(
              skuId: r.key.skuId,
              name: r.key.itemName,
              blend: r.key.blendName,
              qty: r.value,
            ),
        ],
      ));
      widget.cart.clear();
      await widget.store.clearCart();

      if (!mounted) return;
      showToast(context, msg, error: false);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        auth.add(AuthLogoutRequested(reason: e.message));
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Order List')),
      bottomNavigationBar: rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: GradientButton(
                  text: 'CONFIRM & SUBMIT',
                  icon: Icons.check_circle_outline_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : _submit,
                ),
              ),
            ),
      body: rows.isEmpty
          ? const EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your list is empty',
              subtitle: 'Add products from the catalog.',
            )
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(label: 'Items', value: '${rows.length}'),
                      ),
                      Container(width: 1, height: 36, color: Colors.white30),
                      Expanded(
                        child: _Stat(label: 'Total qty', value: '$_totalQty'),
                      ),
                      Container(width: 1, height: 36, color: Colors.white30),
                      Expanded(
                        child: _Stat(
                            label: 'Date',
                            value: DateFormat('dd MMM').format(DateTime.now())),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final s = rows[i].key;
                      final q = rows[i].value;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: cardDecoration(),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.itemName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text)),
                                  const SizedBox(height: 6),
                                  if (s.blendName.isNotEmpty) Pill(s.blendName),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            QtyStepper(
                              qty: q,
                              onInc: () => _setQty(s.skuId, q + 1),
                              onDec: () => _setQty(s.skuId, q - 1),
                              onTypeQty: () async {
                                final v = await showQtyDialog(
                                    context, s.itemName, q);
                                if (v != null) _setQty(s.skuId, v);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ],
      );
}

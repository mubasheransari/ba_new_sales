import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Model/dashboard_models.dart';
import 'package:ords_ba/Repository/repository.dart';

class DashboardState extends Equatable {
  /// Selected filter: 7d | 2w | 1m | 1y. 7 days is the default.
  final String period;

  /// Server data already loaded, per filter (so switching back is instant).
  final Map<String, DashboardStats> data;
  final Set<String> loading;
  final Set<String> failed;
  final int rev;

  const DashboardState({
    this.period = '7d',
    this.data = const {},
    this.loading = const {},
    this.failed = const {},
    this.rev = 0,
  });

  DashboardState copyWith({
    String? period,
    Map<String, DashboardStats>? data,
    Set<String>? loading,
    Set<String>? failed,
  }) =>
      DashboardState(
        period: period ?? this.period,
        data: data ?? this.data,
        loading: loading ?? this.loading,
        failed: failed ?? this.failed,
        rev: rev + 1,
      );

  @override
  List<Object?> get props => [rev];
}

/// Loads the home chart from the server for the selected filter and keeps the
/// choice while the BA is logged in.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required this.repo,
    required this.tokenProvider,
    required this.onUnauthorized,
  }) : super(const DashboardState());

  final Repository repo;
  final String? Function() tokenProvider;
  final VoidCallback onUnauthorized;

  final Map<String, DateTime> _fetchedAt = {};
  static const _fresh = Duration(seconds: 45);

  /// BA tapped a filter.
  void select(String period) {
    if (period == state.period) return;
    emit(state.copyWith(period: period));
    ensure(period);
  }

  /// Loads [period] unless it was loaded a moment ago.
  Future<void> ensure(String period) async {
    final at = _fetchedAt[period];
    if (at != null && DateTime.now().difference(at) < _fresh) return;
    await _load(period);
  }

  /// A sale was saved / pull-to-refresh / app resumed: everything is stale.
  Future<void> refreshCurrent() {
    _fetchedAt.clear();
    return _load(state.period);
  }

  Future<void> _load(String period) async {
    if (state.loading.contains(period)) return;
    emit(state.copyWith(loading: {...state.loading, period}));

    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      emit(state.copyWith(
        loading: {...state.loading}..remove(period),
        failed: {...state.failed, period},
      ));
      return;
    }

    try {
      final s = await repo.fetchDashboardSales(token: token, period: period);
      if (isClosed) return;
      _fetchedAt[period] = DateTime.now();
      emit(state.copyWith(
        data: {...state.data, period: s},
        loading: {...state.loading}..remove(period),
        failed: {...state.failed}..remove(period),
      ));
    } on ApiException catch (e) {
      if (e.statusCode == 401) onUnauthorized();
      if (isClosed) return;
      // Keep whatever is on screen; the chart falls back to the sales saved
      // on this phone.
      emit(state.copyWith(
        loading: {...state.loading}..remove(period),
        failed: {...state.failed, period},
      ));
    }
  }
}

// Home dashboard chart data, as returned by GET dashboard/sales.

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _dbl(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// One bar: a day (7d / 2w / 1m) or a month (1y).
class DashboardPoint {
  final DateTime date;
  final int units;
  const DashboardPoint({required this.date, required this.units});

  factory DashboardPoint.fromJson(Map<String, dynamic> j) => DashboardPoint(
        date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        units: _int(j['units']),
      );
}

class DashboardStats {
  final String period; // 7d | 2w | 1m | 1y
  final String bucket; // day | month
  final int total;
  final int orders;
  final int previousTotal;
  final int? changePercent; // null when the previous period had no sales
  final double average;
  final int bestUnits;
  final List<DashboardPoint> points;

  const DashboardStats({
    required this.period,
    required this.bucket,
    required this.total,
    required this.orders,
    required this.previousTotal,
    required this.changePercent,
    required this.average,
    required this.bestUnits,
    required this.points,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        period: '${j['period'] ?? ''}',
        bucket: '${j['bucket'] ?? 'day'}',
        total: _int(j['total']),
        orders: _int(j['orders']),
        previousTotal: _int(j['previous_total']),
        changePercent:
            j['change_percent'] == null ? null : _int(j['change_percent']),
        average: _dbl(j['average']),
        bestUnits: _int(j['best_units']),
        points: [
          for (final p in (j['points'] as List? ?? const []))
            if (p is Map) DashboardPoint.fromJson(Map<String, dynamic>.from(p)),
        ],
      );
}

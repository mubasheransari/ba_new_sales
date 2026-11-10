import 'dart:convert';

import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Model/models.dart';

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Token + logged-in user (survives app restarts).
class SessionStore {
  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';
  final GetStorage _box = GetStorage();

  Future<void> save(String token, AppUser user) async {
    await _box.write(_kToken, token);
    await _box.write(_kUser, jsonEncode(user.toJson()));
  }

  Future<void> saveUser(AppUser user) =>
      _box.write(_kUser, jsonEncode(user.toJson()));

  String? readToken() {
    final v = _box.read<String>(_kToken);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  AppUser? readUser() {
    final raw = _box.read<String>(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _box.remove(_kToken);
    await _box.remove(_kUser);
  }
}

/// Cached lists so dropdowns / catalog still work with a bad connection.
class CacheStore {
  final GetStorage _box = GetStorage();

  Future<void> saveLocations(List<MartLocation> l) => _box.write(
      'cache_locations', jsonEncode([for (final e in l) e.toJson()]));

  List<MartLocation> readLocations() {
    final raw = _box.read<String>('cache_locations');
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          MartLocation.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSkus(List<Sku> l) =>
      _box.write('cache_skus', jsonEncode([for (final e in l) e.toJson()]));

  List<Sku> readSkus() {
    final raw = _box.read<String>('cache_skus');
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          Sku.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Attendance logs for one BA (kept locally for gating + history).
class AttendanceStore {
  AttendanceStore(String userKey) : _key = 'attendance_$userKey';
  final String _key;
  final GetStorage _box = GetStorage();

  List<AttendanceRecord> all() {
    final raw = _box.read<String>(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = [
        for (final e in jsonDecode(raw) as List)
          AttendanceRecord.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      list.sort((a, b) => b.inAt.compareTo(a.inAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  AttendanceRecord? forDate(String date) {
    for (final r in all()) {
      if (r.date == date) return r;
    }
    return null;
  }

  /// The most recent record that was never checked out.
  AttendanceRecord? openRecord() {
    for (final r in all()) {
      if (r.isOpen) return r;
    }
    return null;
  }

  Future<void> upsert(AttendanceRecord rec) async {
    final list = all().where((r) => r.date != rec.date).toList()..add(rec);
    await _box.write(_key, jsonEncode([for (final r in list) r.toJson()]));
  }
}

/// Cart + sales history for one BA.
class SalesStore {
  SalesStore(String userKey)
      : _cartKey = 'cart_$userKey',
        _histKey = 'sales_$userKey';
  final String _cartKey;
  final String _histKey;
  final GetStorage _box = GetStorage();

  Map<int, int> loadCart() {
    final raw = _box.read<String>(_cartKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) int.parse(e.key): (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCart(Map<int, int> cart) => _box.write(
      _cartKey, jsonEncode({for (final e in cart.entries) '${e.key}': e.value}));

  Future<void> clearCart() => _box.remove(_cartKey);

  List<SaleRecord> history() {
    final raw = _box.read<String>(_histKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = [
        for (final e in jsonDecode(raw) as List)
          SaleRecord.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> add(SaleRecord r) async {
    final list = history()..insert(0, r);
    await _box.write(_histKey, jsonEncode([for (final s in list) s.toJson()]));
  }
}

/// Mart name for a user: from profile if present, else from cached locations.
String? martNameFor(AppUser? u) {
  if (u == null) return null;
  if (u.locationName != null && u.locationName!.isNotEmpty) return u.locationName;
  if (u.locationId == null) return null;
  for (final l in CacheStore().readLocations()) {
    if (l.id == u.locationId) return l.name;
  }
  return null;
}

/// Remembers on which days this BA already uploaded the shelf picture
/// (date -> server id). Used to unlock sales / the app for the day.
class ShelfStore {
  ShelfStore(String userKey) : _key = 'shelf_$userKey';
  final String _key;
  final GetStorage _box = GetStorage();

  Map<String, dynamic> _all() {
    final raw = _box.read<String>(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  bool isDone(String date) => _all().containsKey(date);

  Future<void> markDone(String date, {String? serverId}) async {
    final m = _all();
    // keep only the last 30 days
    if (m.length > 30) {
      final keys = m.keys.toList()..sort();
      for (final k in keys.take(m.length - 30)) {
        m.remove(k);
      }
    }
    m[date] = serverId ?? '';
    await _box.write(_key, jsonEncode(m));
  }
}

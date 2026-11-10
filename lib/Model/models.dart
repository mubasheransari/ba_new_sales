import 'dart:convert';

num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().trim());
}

int? _int(dynamic v) => _num(v)?.toInt();
double? _dbl(dynamic v) => _num(v)?.toDouble();

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/* ------------------------------------------------------------------ */
/*  Location (mart)                                                     */
/* ------------------------------------------------------------------ */
class MartLocation {
  final int id;
  final String name;
  final String areaName;
  final String city;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;

  // Keep your existing radius configuration if you have one.
  final double radiusMeters;

  const MartLocation({
    required this.id,
    required this.name,
    required this.areaName,
    required this.city,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.radiusMeters = 100,
  });

  bool get hasCoordinates =>
      latitude != null && longitude != null;

  factory MartLocation.fromJson(Map<String, dynamic> json) {
    return MartLocation(
      id: int.parse(json['location_id'].toString()),
      name: json['mart_name']?.toString() ?? '',
      areaName: json['area_name']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      latitude: json['latitude'] == null
          ? null
          : (json['latitude'] as num).toDouble(),
      longitude: json['longitude'] == null
          ? null
          : (json['longitude'] as num).toDouble(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),

      // The API response does not currently contain radius_meters.
      // Keep this default only if 100 metres is your intended radius.
      radiusMeters: json['radius_meters'] == null
          ? 100
          : (json['radius_meters'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_id': id,
      'mart_name': name,
      'area_name': areaName,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt?.toIso8601String(),
      'radius_meters': radiusMeters,
    };
  }
}

/* ------------------------------------------------------------------ */
/*  User                                                                */
/* ------------------------------------------------------------------ */

class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? cnic;
  final String role;
  final int? locationId;
  final String? locationName;
  final String? areaName;
  final String? city;
  final double? latitude;
  final double? longitude;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.cnic,
    this.role = 'BA',
    this.locationId,
    this.locationName,
    this.areaName,
    this.city,
    this.latitude,
    this.longitude,
  });

  /// Key used to namespace local data per BA.
  String get storageKey => (email.isNotEmpty ? email : id)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '_');

  /// Whether the assigned location has valid coordinates.
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory AppUser.fromJson(Map<String, dynamic> j) {
    // Supports the new profile response:
    // user.location.location_id, mart_name, area_name, etc.
    final location = j['location'] is Map
        ? Map<String, dynamic>.from(j['location'] as Map)
        : <String, dynamic>{};

    // Also supports older flat location fields.
    final locationId = _int(
      _first(location, ['location_id', 'id']) ??
          _first(j, ['location_id']),
    );

    final locationName = _str(
      _first(location, ['mart_name', 'location_name', 'name']) ??
          _first(j, ['location_name', 'mart_name']),
    );

    return AppUser(
      id: _str(
            _first(j, ['user_id', 'id', 'ba_id', 'emp_id']),
          ) ??
          '',
      fullName: _str(
            _first(j, ['full_name', 'name', 'user_name']),
          ) ??
          'BA',
      email: _str(j['email']) ?? '',
      cnic: _str(j['cnic']),
      role: _str(
            _first(j, ['role_code', 'role']),
          ) ??
          'BA',
      locationId: locationId,
      locationName: locationName,
      areaName: _str(
        _first(location, ['area_name', 'area']) ??
            j['area_name'],
      ),
      city: _str(location['city'] ?? j['city']),
      latitude: _double(
        location['latitude'] ?? j['latitude'],
      ),
      longitude: _double(
        location['longitude'] ?? j['longitude'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': id,
        'full_name': fullName,
        'email': email,
        'cnic': cnic,
        'role_code': role,
        'location_id': locationId,
        'location_name': locationName,
        'location': locationId == null
            ? null
            : {
                'location_id': locationId,
                'mart_name': locationName,
                'area_name': areaName,
                'city': city,
                'latitude': latitude,
                'longitude': longitude,
              },
      };

  /// Fills missing values from a fresher copy, such as Get Profile.
  AppUser mergeWith(AppUser other) => AppUser(
        id: other.id.isNotEmpty ? other.id : id,
        fullName: other.fullName != 'BA' ? other.fullName : fullName,
        email: other.email.isNotEmpty ? other.email : email,
        cnic: other.cnic ?? cnic,
        role: other.role.isNotEmpty ? other.role : role,
        locationId: other.locationId ?? locationId,
        locationName: other.locationName ?? locationName,
        areaName: other.areaName ?? areaName,
        city: other.city ?? city,
        latitude: other.latitude ?? latitude,
        longitude: other.longitude ?? longitude,
      );

  AppUser withLocationName(String? name) => AppUser(
        id: id,
        fullName: fullName,
        email: email,
        cnic: cnic,
        role: role,
        locationId: locationId,
        locationName: name ?? locationName,
        areaName: areaName,
        city: city,
        latitude: latitude,
        longitude: longitude,
      );

  static dynamic _first(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) return value;
    }
    return null;
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final result = value.toString().trim();
    return result.isEmpty ? null : result;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

// class AppUser {
//   final String id;
//   final String fullName;
//   final String email;
//   final String? cnic;
//   final String role;
//   final int? locationId;
//   final String? locationName;

//   const AppUser({
//     required this.id,
//     required this.fullName,
//     required this.email,
//     this.cnic,
//     this.role = 'BA',
//     this.locationId,
//     this.locationName,
//   });

//   /// Key used to namespace local data (attendance, cart, history) per BA.
//   String get storageKey => (email.isNotEmpty ? email : id)
//       .toLowerCase()
//       .replaceAll(RegExp(r'[^a-z0-9]'), '_');

//   factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
//         id: _str(_first(j, ['user_id', 'id', 'ba_id', 'emp_id'])) ?? '',
//         fullName: _str(_first(j, ['full_name', 'name', 'user_name'])) ?? 'BA',
//         email: _str(j['email']) ?? '',
//         cnic: _str(j['cnic']),
//         role: _str(j['role']) ?? 'BA',
//         locationId: _int(j['location_id']),
//         locationName: _str(_first(j, ['location_name', 'location'])),
//       );

//   Map<String, dynamic> toJson() => {
//         'user_id': id,
//         'full_name': fullName,
//         'email': email,
//         'cnic': cnic,
//         'role': role,
//         'location_id': locationId,
//         'location_name': locationName,
//       };

//   /// Fills gaps from a fresher copy (e.g. profile API after login).
//   AppUser mergeWith(AppUser other) => AppUser(
//         id: other.id.isNotEmpty ? other.id : id,
//         fullName: other.fullName != 'BA' ? other.fullName : fullName,
//         email: other.email.isNotEmpty ? other.email : email,
//         cnic: other.cnic ?? cnic,
//         role: other.role,
//         locationId: other.locationId ?? locationId,
//         locationName: other.locationName ?? locationName,
//       );

//   AppUser withLocationName(String? name) => AppUser(
//         id: id,
//         fullName: fullName,
//         email: email,
//         cnic: cnic,
//         role: role,
//         locationId: locationId,
//         locationName: name ?? locationName,
//       );
// }

/* ------------------------------------------------------------------ */
/*  SKU                                                                 */
/* ------------------------------------------------------------------ */

class Sku {
  final int skuId;
  final String itemCode;
  final String itemName;
  final String blendName;
  final String group;

  const Sku({
    required this.skuId,
    required this.itemCode,
    required this.itemName,
    required this.blendName,
    required this.group,
  });

  /// Uses `con_blend_name` (consolidated blend) when present, otherwise
  /// `blend_name`. Names are trimmed - some come with a leading space
  /// (e.g. " AWAZ").
  factory Sku.fromJson(Map<String, dynamic> j) {
    final blend = _str(j['con_blend_name']) ?? _str(j['blend_name']) ?? '';
    final group = _str(j['sku_group']) ?? blend;
    return Sku(
      skuId: _int(j['sku_id']) ?? 0,
      itemCode: _str(j['item_code']) ?? '',
      itemName: _str(j['item_name']) ?? 'Unknown item',
      blendName: blend,
      group: group,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku_id': skuId,
        'item_code': itemCode,
        'item_name': itemName,
        'con_blend_name': blendName,
        'sku_group': group,
        'active': 'Y',
      };

  static bool isActive(Map<String, dynamic> j) {
    final a = j['active']?.toString().trim().toUpperCase();
    return a == null || a.isEmpty || a == 'Y' || a == '1' || a == 'TRUE';
  }
}

/* ------------------------------------------------------------------ */
/*  Attendance (local record)                                           */
/* ------------------------------------------------------------------ */

class AttendanceRecord {
  /// yyyy-MM-dd
  final String date;
  final DateTime inAt;
  final DateTime? outAt;

  /// True when the out time was set automatically at 12:00 AM.
  final bool autoOut;
  final double? inLat;
  final double? inLng;
  final String? locationName;

  const AttendanceRecord({
    required this.date,
    required this.inAt,
    this.outAt,
    this.autoOut = false,
    this.inLat,
    this.inLng,
    this.locationName,
  });

  bool get isOpen => outAt == null;

  AttendanceRecord copyWith({DateTime? outAt, bool? autoOut}) =>
      AttendanceRecord(
        date: date,
        inAt: inAt,
        outAt: outAt ?? this.outAt,
        autoOut: autoOut ?? this.autoOut,
        inLat: inLat,
        inLng: inLng,
        locationName: locationName,
      );

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) =>
      AttendanceRecord(
        date: j['date'].toString(),
        inAt: DateTime.parse(j['in'].toString()),
        outAt: j['out'] == null ? null : DateTime.tryParse(j['out'].toString()),
        autoOut: j['auto_out'] == true,
        inLat: _dbl(j['in_lat']),
        inLng: _dbl(j['in_lng']),
        locationName: _str(j['location_name']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'in': inAt.toIso8601String(),
        'out': outAt?.toIso8601String(),
        'auto_out': autoOut,
        'in_lat': inLat,
        'in_lng': inLng,
        'location_name': locationName,
      };
}

/* ------------------------------------------------------------------ */
/*  Sale (local history)                                                */
/* ------------------------------------------------------------------ */

class SaleLine {
  final int skuId;
  final String name;
  final String blend;
  final int qty;
  const SaleLine({
    required this.skuId,
    required this.name,
    required this.blend,
    required this.qty,
  });

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        skuId: _int(j['sku_id']) ?? 0,
        name: _str(j['name']) ?? '',
        blend: _str(j['blend']) ?? '',
        qty: _int(j['qty']) ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'sku_id': skuId, 'name': name, 'blend': blend, 'qty': qty};
}

class SaleRecord {
  final String id;
  final DateTime createdAt;
  final String saleDate; // yyyy-MM-dd (what was sent to the API)
  final int? locationId;
  final List<SaleLine> lines;

  const SaleRecord({
    required this.id,
    required this.createdAt,
    required this.saleDate,
    required this.locationId,
    required this.lines,
  });

  int get totalQty => lines.fold(0, (a, b) => a + b.qty);

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        id: j['id'].toString(),
        createdAt: DateTime.parse(j['created_at'].toString()),
        saleDate: j['sale_date'].toString(),
        locationId: _int(j['location_id']),
        lines: [
          for (final l in (j['lines'] as List? ?? []))
            SaleLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'sale_date': saleDate,
        'location_id': locationId,
        'lines': [for (final l in lines) l.toJson()],
      };

  @override
  String toString() => jsonEncode(toJson());
}


import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:ords_ba/Api_config/api_config.dart';
import 'package:ords_ba/Data/device_id.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:ords_ba/Model/dashboard_models.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Model/review_models.dart';

/// Thrown for any failed API call.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  /// Only HTTP 401 means the session is no longer valid.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class CnicCheckResult {
  final bool allowed;
  final String message;

  const CnicCheckResult({
    required this.allowed,
    required this.message,
  });
}

class LoginResult {
  final String token;
  final AppUser user;

  const LoginResult(this.token, this.user);
}

/// Every network call of the BA module lives here.
class Repository {
  Repository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /* ----------------------------- helpers ----------------------------- */

  Map<String, String> _headers({
    String? token,
    bool json = true,
  }) {
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
      if (DeviceId.isReady) 'X-Device-Id': DeviceId.value,
    };
  }

  dynamic _tryDecode(String body) {
    if (body.trim().isEmpty) return null;

    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _messageOf(dynamic data) {
    if (data is Map) {
      for (final key in [
        'message',
        'error',
        'msg',
        'detail',
        'error_message',
      ]) {
        final value = data[key];

        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }

      final nested = data['data'];

      if (nested is Map) {
        return _messageOf(nested);
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return data;
    }

    return null;
  }

  /// Sends a request and converts HTTP/API/network errors into ApiException.
  Future<dynamic> _send(
    Future<http.Response> Function() call, {
    Duration? timeout,
  }) async {
    http.Response response;

    try {
      response = await call().timeout(timeout ?? ApiConfig.timeout);
    } on SocketException {
      throw const ApiException(
        'No internet connection. Please try again.',
      );
    } on TimeoutException {
      throw const ApiException(
        'Server took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Try again.',
      );
    }

    final data = _tryDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final fallback = switch (response.statusCode) {
        401 => 'Session expired. Please login again.',
        403 => 'You are not allowed to do this.',
        404 => 'Service not found (404).',
        _ => 'Request failed (${response.statusCode}).',
      };

      throw ApiException(
        _messageOf(data) ?? fallback,
        response.statusCode,
      );
    }

    // Some ORDS handlers return HTTP 200 with success:false.
    if (data is Map) {
      final success = data['success'];
      final status = data['status']?.toString().toLowerCase();

      final failed = success == false ||
          success?.toString().toLowerCase() == 'false' ||
          status == 'error' ||
          status == 'fail' ||
          status == 'failed';

      if (failed) {
        throw ApiException(
          _messageOf(data) ?? 'Request failed.',
          response.statusCode,
        );
      }
    }

    return data;
  }

  /// Unwraps common response wrappers.
  Map<String, dynamic>? _findMap(
    dynamic data, [
    int depth = 0,
  ]) {
    if (data is! Map) return null;

    if (depth < 3) {
      for (final key in [
        'user',
        'profile',
        'data',
        'result',
      ]) {
        final value = data[key];

        if (value is Map) {
          return _findMap(value, depth + 1);
        }
      }
    }

    return Map<String, dynamic>.from(data);
  }

  String? _findToken(dynamic data) {
    if (data is Map) {
      for (final key in [
        'token',
        'access_token',
        'auth_token',
        'session_token',
        'bearer_token',
      ]) {
        final value = data[key];

        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }

      for (final key in [
        'data',
        'result',
        'user',
      ]) {
        final token = _findToken(data[key]);

        if (token != null) return token;
      }
    }

    return null;
  }

  /// Reads an ORDS collection, including next-page references.
  Future<List<Map<String, dynamic>>> _getAll(
    String firstUrl, {
    String? token,
  }) async {
    final output = <Map<String, dynamic>>[];
    final seenUrls = <String>{};

    String? url = firstUrl;
    var guard = 0;

    while (url != null && seenUrls.add(url) && guard++ < 100) {
      final currentUrl = url;

      final data = await _send(
        () => _client.get(
          Uri.parse(currentUrl),
          headers: _headers(
            token: token,
            json: false,
          ),
        ),
      );

      List? items;

      if (data is List) {
        items = data;
      } else if (data is Map) {
        final value = data['items'] ??
            data['data'] ??
            data['results'];

        if (value is List) {
          items = value;
        }
      }

      for (final item in items ?? const []) {
        if (item is Map) {
          output.add(Map<String, dynamic>.from(item));
        }
      }

      String? next;

      if (data is Map) {
        final nextValue = data['next'];

        if (nextValue is Map && nextValue[r'$ref'] != null) {
          final nextRef = nextValue[r'$ref'].toString();

          next = Uri.parse(currentUrl)
              .resolve(nextRef)
              .toString();
        }

        if (data['hasMore'] == false) {
          next = null;
        }
      }

      if ((items ?? const []).isEmpty) {
        next = null;
      }

      url = next;
    }

    return output;
  }

  /* ------------------------------ locations ------------------------------ */

  Future<List<MartLocation>> fetchLocations() async {
    const url =
        'http://tapex.mezangrp.com/ords/hrms/ba-sales-v2/locations/list/';

    final data = await _send(
      () => _client.get(
        Uri.parse(url),
        headers: _headers(json: false),
      ),
    );

    if (data is! Map) {
      throw const ApiException(
        'Unexpected locations response from server.',
      );
    }

    final items = data['locations'];

    if (items is! List) {
      return const [];
    }

    return items
        .whereType<Map>()
        .map(
          (item) => MartLocation.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  /* -------------------------------- auth -------------------------------- */

  /// Verifies that a CNIC exists in the active BA registration allowlist.
  /// CNIC is sent as 13 digits without hyphens.
  Future<CnicCheckResult> checkBaCnic({
    required String cnic,
  }) async {
    final normalizedCnic = cnic.replaceAll(
      RegExp(r'\D'),
      '',
    );

    if (normalizedCnic.length != 13) {
      throw const ApiException(
        'CNIC must contain exactly 13 digits.',
      );
    }

    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.checkBaCnic),
        headers: _headers(),
        body: jsonEncode({
          'cnic': normalizedCnic,
        }),
      ),
    );

    final responseMap = _findMap(data);

    final allowed = responseMap?['allowed'] == true ||
        responseMap?['allowed']?.toString().toLowerCase() == 'true';

    final message = responseMap?['message']?.toString() ??
        (allowed
            ? 'CNIC is authorized for BA registration.'
            : 'This CNIC is not authorized for BA registration.');

    return CnicCheckResult(
      allowed: allowed,
      message: message,
    );
  }

  Future<String> signup({
    required String fullName,
    required String email,
    required String cnic,
    required String password,
    required String confirmPassword,
    required int locationId,
  }) async {
    final normalizedCnic = cnic.replaceAll(
      RegExp(r'\D'),
      '',
    );

    if (normalizedCnic.length != 13) {
      throw const ApiException(
        'CNIC must contain exactly 13 digits.',
      );
    }

    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.signup),
        headers: _headers(),
        body: jsonEncode({
          'full_name': fullName,
          'email': email,
          'cnic': normalizedCnic,
          'password': password,
          'confirm_password': confirmPassword,
          'role': 'BA',
          'location_id': locationId,
          'device_id': DeviceId.value,
        }),
      ),
    );

    return _messageOf(data) ??
        'Account created. Please login.';
  }

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.login),
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'password': password,
          'device_id': DeviceId.value,
        }),
      ),
    );

    final token = _findToken(data);

    if (token == null) {
      throw const ApiException(
        'Login succeeded but no token was returned.',
      );
    }

    final map = _findMap(data) ?? {};
    final user = AppUser.fromJson(map);

    final finalUser = user.email.isEmpty
        ? user.mergeWith(
            AppUser(
              id: '',
              fullName: 'BA',
              email: email,
            ),
          )
        : user;

    return LoginResult(token, finalUser);
  }

  /// Checks whether an account can be used on this device.
  /// This check is advisory; the server must enforce device restrictions.
  Future<DeviceCheck> checkDevice({
    required String email,
    bool signup = false,
  }) async {
    try {
      final data = await _send(
        () => _client.post(
          Uri.parse(ApiConfig.deviceCheck),
          headers: _headers(),
          body: jsonEncode({
            'email': email,
            'device_id': DeviceId.value,
            'mode': signup ? 'signup' : 'login',
          }),
        ),
      );

      final responseMap = _findMap(data);

      if (responseMap?['allowed'] == false ||
          responseMap?['allowed']?.toString().toLowerCase() == 'false') {
        return DeviceCheck(
          false,
          responseMap?['message']?.toString() ??
              'This account is registered on another device.',
        );
      }
    } catch (_) {
      // Preserve the existing behaviour: allow the main API to decide.
    }

    return const DeviceCheck(true, '');
  }

  /// Links the account to this phone.
  Future<String?> bindDevice({
    String? token,
    required String email,
  }) async {
    try {
      final data = await _send(
        () => _client.post(
          Uri.parse(ApiConfig.deviceBind),
          headers: _headers(token: token),
          body: jsonEncode({
            'email': email,
            'device_id': DeviceId.value,
          }),
        ),
      );

      final responseMap = _findMap(data);

      if (responseMap?['bound'] == false ||
          responseMap?['bound']?.toString().toLowerCase() == 'false') {
        return responseMap?['message']?.toString() ??
            'Device could not be linked.';
      }

      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'No answer from the server.';
    }
  }

  Future<AppUser> fetchProfile(String token) async {
    final data = await _send(
      () => _client.get(
        Uri.parse(ApiConfig.profile),
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    final map = _findMap(data);

    if (map == null) {
      throw const ApiException('Could not read profile.');
    }

    return AppUser.fromJson(map);
  }

  /* ----------------------------- attendance ----------------------------- */

  Future<String> attendanceIn({
    required String token,
    required double latitude,
    required double longitude,
    required int locationId,
    required Uint8List selfie,
  }) {
    return _attendance(
      ApiConfig.attendanceIn,
      token,
      latitude,
      longitude,
      locationId,
      'Attendance IN marked.',
      extra: {
        'selfie_base64': base64Encode(selfie),
        'selfie_mime': 'image/jpeg',
      },
    );
  }

  Future<String> attendanceOut({
    required String token,
    required double latitude,
    required double longitude,
    required int locationId,
    required Uint8List selfie,
    required Uint8List shelf,
  }) {
    return _attendance(
      ApiConfig.attendanceOut,
      token,
      latitude,
      longitude,
      locationId,
      'Attendance OUT marked.',
      extra: {
        'selfie_base64': base64Encode(selfie),
        'selfie_mime': 'image/jpeg',
        'shelf_base64': base64Encode(shelf),
        'shelf_mime': 'image/jpeg',
      },
    );
  }

  Future<String> _attendance(
    String url,
    String token,
    double latitude,
    double longitude,
    int locationId,
    String fallback, {
    Map<String, dynamic> extra = const {},
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(url),
        headers: _headers(token: token),
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'location_id': locationId,
          ...extra,
        }),
      ),
      timeout: ApiConfig.uploadTimeout,
    );

    return _messageOf(data) ?? fallback;
  }

  /* -------------------------------- sales -------------------------------- */

  /// Fetches active SKUs only.
  Future<List<Sku>> fetchSkus() async {
    final rows = await _getAll(ApiConfig.skuList);

    final seen = <int>{};
    final output = <Sku>[];

    for (final row in rows) {
      if (!Sku.isActive(row)) continue;

      final sku = Sku.fromJson(row);

      if (sku.skuId == 0 || !seen.add(sku.skuId)) {
        continue;
      }

      output.add(sku);
    }

    output.sort((a, b) {
      final groupCompare = a.group
          .toLowerCase()
          .compareTo(b.group.toLowerCase());

      if (groupCompare != 0) {
        return groupCompare;
      }

      return a.itemName
          .toLowerCase()
          .compareTo(b.itemName.toLowerCase());
    });

    return output;
  }

  Future<String> enterSales({
    required String token,
    required int locationId,
    required String saleDate,
    required Map<int, int> quantities,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.enterSales),
        headers: _headers(token: token),
        body: jsonEncode({
          'location_id': locationId,
          'sale_date': saleDate,
          'items': [
            for (final entry in quantities.entries)
              {
                'sku_id': entry.key,
                'quantity': entry.value,
              },
          ],
        }),
      ),
    );

    return _messageOf(data) ?? 'Sales saved.';
  }

  /* --------------------------- shelf picture --------------------------- */

  Future<String> uploadShelfPicture({
    required String token,
    required int userId,
    required int locationId,
    required double latitude,
    required double longitude,
    required String fileName,
    required Uint8List bytes,
    String remarks = '',
  }) async {
    final lower = fileName.toLowerCase();

    final mime = lower.endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';

    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.shelfUpload),
        headers: _headers(token: token),
        body: jsonEncode({
          'user_id': userId,
          'location_id': locationId,
          'latitude': latitude,
          'longitude': longitude,
          'file_name': fileName,
          'image_mime': mime,
          'remarks': remarks,
          'image_base64': base64Encode(bytes),
        }),
      ),
      timeout: ApiConfig.uploadTimeout,
    );

    if (data is Map && data['id'] != null) {
      return data['id'].toString();
    }

    return '';
  }

  /* ----------------------------- low stock ----------------------------- */

  Future<String> submitLowStock({
    required String token,
    required int userId,
    required int locationId,
    required List<int> skuIds,
    Map<int, List<int>> questionsBySku = const {},
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.lowStockSubmit),
        headers: _headers(token: token),
        body: jsonEncode({
          'user_id': userId,
          'location_id': locationId,
          'items': [
            for (final id in skuIds)
              {
                'sku_id': id,
                'question_ids':
                    questionsBySku[id] ?? const <int>[],
              },
          ],
        }),
      ),
    );

    if (data is Map && data['id'] != null) {
      return data['id'].toString();
    }

    return '';
  }

  Future<List<ReviewQuestion>> fetchReviewQuestions({
    required String token,
  }) async {
    final data = await _send(
      () => _client.get(
        Uri.parse(ApiConfig.reviewQuestions),
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    final list = data is Map ? data['questions'] : null;

    if (list is! List) {
      return const [];
    }

    return [
      for (final item in list)
        if (item is Map)
          ReviewQuestion.fromJson(
            Map<String, dynamic>.from(item),
          ),
    ].where((question) {
      return question.id > 0 && question.text.isNotEmpty;
    }).toList();
  }

  /* ------------------------------ dashboard ------------------------------ */

  Future<DashboardStats> fetchDashboardSales({
    required String token,
    required String period,
  }) async {
    final uri = Uri.parse(ApiConfig.dashboardSales).replace(
      queryParameters: {
        'period': period,
      },
    );

    final data = await _send(
      () => _client.get(
        uri,
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    if (data is! Map) {
      throw const ApiException(
        'Unexpected dashboard response.',
      );
    }

    return DashboardStats.fromJson(
      Map<String, dynamic>.from(data),
    );
  }

  /* -------------------------------- leaves -------------------------------- */

  Future<List<Map<String, dynamic>>> fetchLeaves({
    required String token,
    String filter = 'all',
  }) async {
    final uri = Uri.parse(ApiConfig.leaveList).replace(
      queryParameters: {
        'filter': filter,
      },
    );

    final data = await _send(
      () => _client.get(
        uri,
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    final list = data is Map ? data['leaves'] : null;

    if (list is! List) {
      return const [];
    }

    return [
      for (final item in list)
        if (item is Map)
          Map<String, dynamic>.from(item),
    ];
  }

  Future<Map<String, dynamic>> fetchLeaveThread({
    required String token,
    required int id,
  }) async {
    final data = await _send(
      () => _client.get(
        Uri.parse(ApiConfig.leaveThread(id)),
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    if (data is! Map) {
      throw const ApiException(
        'Unexpected leave thread response.',
      );
    }

    return Map<String, dynamic>.from(data);
  }

  Future<int?> applyLeave({
    required String token,
    required String fromDate,
    required String toDate,
    required String reason,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.leaveApply),
        headers: _headers(token: token),
        body: jsonEncode({
          'from_date': fromDate,
          'to_date': toDate,
          'reason': reason,
        }),
      ),
    );

    if (data is Map) {
      return int.tryParse('${data['leave_id']}');
    }

    return null;
  }

  Future<void> sendLeaveMessage({
    required String token,
    required int id,
    required String message,
  }) async {
    await _send(
      () => _client.post(
        Uri.parse(ApiConfig.leaveMessage(id)),
        headers: _headers(token: token),
        body: jsonEncode({
          'message': message,
        }),
      ),
    );
  }

  Future<void> cancelLeave({
    required String token,
    required int id,
  }) async {
    await _send(
      () => _client.post(
        Uri.parse(ApiConfig.leaveCancel(id)),
        headers: _headers(token: token),
        body: '{}',
      ),
    );
  }

  /* ----------------------------- complaints ----------------------------- */

  Future<List<Complaint>> fetchComplaints({
    required String token,
  }) async {
    final data = await _send(
      () => _client.get(
        Uri.parse(ApiConfig.complaintList),
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    final list = data is Map ? data['complaints'] : null;

    if (list is! List) {
      return const [];
    }

    return [
      for (final item in list)
        if (item is Map)
          Complaint.fromJson(
            Map<String, dynamic>.from(item),
          ),
    ];
  }

  Future<ComplaintThread> fetchComplaintThread({
    required String token,
    required int id,
  }) async {
    final data = await _send(
      () => _client.get(
        Uri.parse(ApiConfig.complaintThread(id)),
        headers: _headers(
          token: token,
          json: false,
        ),
      ),
    );

    if (data is! Map) {
      throw const ApiException(
        'Unexpected complaint thread response.',
      );
    }

    return ComplaintThread.fromJson(
      Map<String, dynamic>.from(data),
    );
  }

  Future<int> createComplaint({
    required String token,
    required String title,
    required String description,
    Uint8List? image,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.complaintCreate),
        headers: _headers(token: token),
        body: jsonEncode({
          'title': title,
          'description': description,
          if (image != null)
            'image_base64': base64Encode(image),
          if (image != null)
            'image_mime': 'image/jpeg',
        }),
      ),
      timeout: ApiConfig.uploadTimeout,
    );

    final id = data is Map ? data['complaint_id'] : null;

    if (id is num) {
      return id.toInt();
    }

    return int.tryParse('$id') ?? 0;
  }

  Future<String> replyToComplaint({
    required String token,
    required int id,
    String message = '',
    Uint8List? image,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.complaintReply(id)),
        headers: _headers(token: token),
        body: jsonEncode({
          'message': message,
          if (image != null)
            'image_base64': base64Encode(image),
          if (image != null)
            'image_mime': 'image/jpeg',
        }),
      ),
      timeout: ApiConfig.uploadTimeout,
    );

    return data is Map
        ? '${data['status'] ?? ''}'.toUpperCase()
        : '';
  }

  Future<String> setComplaintStatus({
    required String token,
    required int id,
    required String status,
  }) async {
    final data = await _send(
      () => _client.post(
        Uri.parse(ApiConfig.complaintStatus(id)),
        headers: _headers(token: token),
        body: jsonEncode({
          'status': status,
        }),
      ),
    );

    return data is Map
        ? '${data['status'] ?? status}'.toUpperCase()
        : status;
  }

  Future<Uint8List> fetchComplaintImage({
    required String token,
    required int messageId,
  }) async {
    http.Response response;

    try {
      response = await _client
          .get(
            Uri.parse(
              ApiConfig.complaintImage(messageId),
            ),
            headers: _headers(
              token: token,
              json: false,
            ),
          )
          .timeout(ApiConfig.uploadTimeout);
    } on SocketException {
      throw const ApiException(
        'No internet connection. Please try again.',
      );
    } on TimeoutException {
      throw const ApiException(
        'Server took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Try again.',
      );
    }

    final contentType =
        response.headers['content-type'] ?? '';

    if (response.statusCode != 200 ||
        !contentType.startsWith('image/')) {
      throw ApiException(
        'Could not load the picture.',
        response.statusCode,
      );
    }

    return response.bodyBytes;
  }

  /// Call this when the Repository is no longer needed.
  void dispose() {
    _client.close();
  }
}

import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

/// The ID of this phone.
///
///  * Android: the Android ID (stays the same after reinstalling the app)
///  * iPhone : the "identifier for vendor"
///  * anything else: a random ID created once and saved on the phone
///
/// It is sent to the server on every request (header X-Device-Id) and shown
/// on the login screen. The server links a BA account to the phone it was
/// registered on and refuses logins from any other phone.
class DeviceId {
  DeviceId._();

  static String _value = '';

  /// Empty until [load] has finished (main() waits for it).
  static String get value => _value;
  static bool get isReady => _value.isNotEmpty;

  static Future<String> load() async {
    if (_value.isNotEmpty) return _value;

    String? id;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        id = await const AndroidId().getId();
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        id = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (_) {
      // fall through to the saved random ID below
    }

    var clean = _clean(id);
    if (clean.isEmpty) clean = _savedRandomId();
    _value = clean;
    return _value;
  }

  /// Letters, digits, dot, dash and underscore only; at most 64 characters.
  static String _clean(String? raw) {
    final s = (raw ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return s.length > 64 ? s.substring(0, 64) : s;
  }

  static String _savedRandomId() {
    final box = GetStorage();
    final saved = box.read<String>('device_id_fallback');
    if (saved != null && saved.isNotEmpty) return saved;
    final rnd = Random.secure();
    final id = List.generate(
        16, (_) => rnd.nextInt(16).toRadixString(16)).join();
    box.write('device_id_fallback', id);
    return id;
  }
}

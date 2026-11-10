import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';

/// Set to true if your backend allows a BA to mark IN again after OUT on the
/// same day. Default: one IN + one OUT per day.
const bool kAllowReCheckIn = false;

class AttendanceState extends Equatable {
  /// Today's record (null = not marked yet today).
  final AttendanceRecord? today;
  final bool busy;
  final String? message;
  final bool messageIsError;
  final int messageId;

  /// Today's shelf picture has been uploaded.
  final bool shelfDone;

  const AttendanceState({
    this.today,
    this.busy = false,
    this.message,
    this.messageIsError = true,
    this.messageId = 0,
    this.shelfDone = false,
  });

  /// BA is "on duty": marked IN today and not yet OUT.
  bool get isCheckedIn => today != null && today!.isOpen;

  /// Checked in but today's shelf picture is still missing -> the app is
  /// locked behind the shelf-picture popup.
  bool get needsShelf => isCheckedIn && !shelfDone;

  /// Sales need: attendance IN + shelf picture uploaded.
  bool get canEnterSales => isCheckedIn && shelfDone;

  bool get isCompletedToday => today != null && !today!.isOpen;

  AttendanceState copyWith({
    AttendanceRecord? today,
    bool clearToday = false,
    bool? busy,
    String? message,
    bool messageIsError = true,
    bool? shelfDone,
  }) =>
      AttendanceState(
        today: clearToday ? null : (today ?? this.today),
        busy: busy ?? this.busy,
        message: message,
        messageIsError: messageIsError,
        messageId: message == null ? messageId : messageId + 1,
        shelfDone: shelfDone ?? this.shelfDone,
      );

  @override
  List<Object?> get props =>
      [today?.toJson().toString(), busy, message, messageIsError, messageId, shelfDone];
}

class AttendanceCubit extends Cubit<AttendanceState> {
  AttendanceCubit({
    required Repository repo,
    required AttendanceStore store,
    required ShelfStore shelfStore,
    required String? Function() tokenProvider,
    required void Function() onUnauthorized,
  })  : _repo = repo,
        _store = store,
        _shelf = shelfStore,
        _token = tokenProvider,
        _onUnauthorized = onUnauthorized,
        super(const AttendanceState()) {
    sync();
  }

  final Repository _repo;
  final AttendanceStore _store;
  final ShelfStore _shelf;
  final String? Function() _token;
  final void Function() _onUnauthorized;
  Timer? _midnight;

  /* ------------------------ midnight auto attendance-out ------------------------ */

  /// Call on start, on app resume and at every midnight.
  ///
  /// Any record from a previous day that is still open gets an automatic
  /// OUT at 12:00 AM (start of the next day).
  Future<void> sync() async {
    final now = DateTime.now();
    final today = dateKey(now);

    for (final r in _store.all()) {
      if (r.isOpen && r.date != today) {
        final d = DateTime.parse(r.date);
        final midnight = DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
        await _store.upsert(r.copyWith(outAt: midnight, autoOut: true));
      }
    }

    final rec = _store.forDate(today);
    if (isClosed) return;
    final shelf = _shelf.isDone(today);
    emit(rec == null
        ? state.copyWith(clearToday: true, shelfDone: shelf)
        : state.copyWith(today: rec, shelfDone: shelf));
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () async {
      final wasOn = state.isCheckedIn;
      await sync();
      if (wasOn && !isClosed) {
        emit(state.copyWith(
          message: 'You were automatically marked OUT at 12:00 AM.',
          messageIsError: false,
        ));
      }
    });
  }

  /* ------------------------------ IN / OUT ------------------------------ */

  Future<bool> checkIn({
    required double lat,
    required double lng,
      required int locationId,
    required Uint8List selfie,
    String? locationName,
  }) async {
    if (state.busy) return false;
    final token = _token();
    if (token == null) return false;
    if (state.today != null && !(kAllowReCheckIn && state.isCompletedToday)) {
      return false;
    }

    emit(state.copyWith(busy: true));
    try {
      final msg = await _repo.attendanceIn(
          token: token,
          latitude: lat,
          longitude: lng,
          locationId: locationId,
          selfie: selfie);
      await _saveIn(lat, lng, locationName);
      emit(state.copyWith(
          busy: false, today: _store.forDate(dateKey(DateTime.now())),
          shelfDone: _shelf.isDone(dateKey(DateTime.now())),
          message: msg, messageIsError: false));
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        emit(state.copyWith(busy: false));
        _onUnauthorized();
        return false;
      }
      // Server says it is already marked (e.g. other phone) -> sync locally.
      if (e.message.toLowerCase().contains('already')) {
        await _saveIn(lat, lng, locationName);
        emit(state.copyWith(
            busy: false, today: _store.forDate(dateKey(DateTime.now())),
            shelfDone: _shelf.isDone(dateKey(DateTime.now())),
            message: e.message, messageIsError: false));
        return true;
      }
      emit(state.copyWith(busy: false, message: e.message));
      return false;
    }
  }

  Future<void> _saveIn(double lat, double lng, String? name) async {
    final now = DateTime.now();
    await _store.upsert(AttendanceRecord(
      date: dateKey(now),
      inAt: now,
      inLat: lat,
      inLng: lng,
      locationName: name,
    ));
  }

  Future<bool> checkOut({
    required double lat,
    required double lng,
    required int locationId,
    required Uint8List selfie,
    required Uint8List shelf,
  }) async {
    if (state.busy || !state.isCheckedIn) return false;
    final token = _token();
    if (token == null) return false;

    emit(state.copyWith(busy: true));
    try {
      final msg = await _repo.attendanceOut(
          token: token,
          latitude: lat,
          longitude: lng,
          locationId: locationId,
          selfie: selfie,
          shelf: shelf);
      await _saveOut();
      emit(state.copyWith(
          busy: false, today: _store.forDate(dateKey(DateTime.now())),
          message: msg, messageIsError: false));
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        emit(state.copyWith(busy: false));
        _onUnauthorized();
        return false;
      }
      if (e.message.toLowerCase().contains('already')) {
        await _saveOut();
        emit(state.copyWith(
            busy: false, today: _store.forDate(dateKey(DateTime.now())),
            message: e.message, messageIsError: false));
        return true;
      }
      emit(state.copyWith(busy: false, message: e.message));
      return false;
    }
  }

  Future<void> _saveOut() async {
    final cur = _store.forDate(dateKey(DateTime.now()));
    if (cur != null) await _store.upsert(cur.copyWith(outAt: DateTime.now()));
  }

  /* --------------------------- shelf picture --------------------------- */

  /// Uploads today's shelf picture. On success sales are unlocked.
  Future<bool> uploadShelfPicture({
    required int userId,
    required int locationId,
    required double latitude,
    required double longitude,
    required String fileName,
    required Uint8List bytes,
    String remarks = '',
  }) async {
    if (state.busy || !state.isCheckedIn) return false;
    final token = _token();
    if (token == null) return false;

    emit(state.copyWith(busy: true));
    try {
      final id = await _repo.uploadShelfPicture(
        token: token,
        userId: userId,
        locationId: locationId,
        latitude: latitude,
        longitude: longitude,
        fileName: fileName,
        bytes: bytes,
        remarks: remarks,
      );
      await _shelf.markDone(dateKey(DateTime.now()), serverId: id);
      emit(state.copyWith(
        busy: false,
        shelfDone: true,
        message: 'Shelf picture uploaded. You can now enter sales.',
        messageIsError: false,
      ));
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        emit(state.copyWith(busy: false));
        _onUnauthorized();
        return false;
      }
      emit(state.copyWith(busy: false, message: e.message));
      return false;
    }
  }

  List<AttendanceRecord> history() => _store.all();

  /// Never throws if a request finishes after logout / dispose.
  @override
  void emit(AttendanceState state) {
    if (isClosed) return;
    super.emit(state);
  }

  @override
  Future<void> close() {
    _midnight?.cancel();
    return super.close();
  }
}

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:ords_ba/Repository/repository.dart';

/// Thin wrapper over [Repository]: supplies the token and signs the BA out
/// when the server says the session is no longer valid.
class ComplaintService {
  ComplaintService({
    required this.repo,
    required this.tokenProvider,
    required this.onUnauthorized,
  });

  final Repository repo;
  final String? Function() tokenProvider;
  final VoidCallback onUnauthorized;

  Future<T> _run<T>(Future<T> Function(String token) call) async {
    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      onUnauthorized();
      throw const ApiException('Please login again.', 401);
    }
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.isUnauthorized) onUnauthorized();
      rethrow;
    }
  }

  Future<List<Complaint>> list() => _run((t) => repo.fetchComplaints(token: t));

  Future<ComplaintThread> thread(int id) =>
      _run((t) => repo.fetchComplaintThread(token: t, id: id));

  Future<int> create(
          {required String title,
          required String description,
          Uint8List? image}) =>
      _run((t) => repo.createComplaint(
          token: t, title: title, description: description, image: image));

  Future<String> reply(int id, {String message = '', Uint8List? image}) =>
      _run((t) => repo.replyToComplaint(
          token: t, id: id, message: message, image: image));

  Future<String> setStatus(int id, String status) =>
      _run((t) => repo.setComplaintStatus(token: t, id: id, status: status));

  Future<Uint8List> image(int messageId) =>
      _run((t) => repo.fetchComplaintImage(token: t, messageId: messageId));
}

enum ComplaintsLoad { initial, loading, ready, error }

class ComplaintsState extends Equatable {
  final ComplaintsLoad load;
  final List<Complaint> complaints;
  final String? error;

  const ComplaintsState({
    this.load = ComplaintsLoad.initial,
    this.complaints = const [],
    this.error,
  });

  /// Conversations with a new reply the BA has not read yet.
  int get unreadCount => complaints.where((c) => c.unread).length;
  int get openCount => complaints.where((c) => c.isOpen).length;
  int get resolvedCount => complaints.where((c) => !c.isOpen).length;

  ComplaintsState copyWith({
    ComplaintsLoad? load,
    List<Complaint>? complaints,
    String? error,
    bool clearError = false,
  }) =>
      ComplaintsState(
        load: load ?? this.load,
        complaints: complaints ?? this.complaints,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [
        load,
        error,
        [
          for (final c in complaints)
            '${c.id}|${c.status}|${c.unread}|${c.messageCount}|${c.lastMessageAt}'
        ],
      ];
}

/// The complaints inbox. Lives as long as the BA is logged in, so the home
/// screen can show an unread badge.
class ComplaintsCubit extends Cubit<ComplaintsState> {
  ComplaintsCubit({required this.service}) : super(const ComplaintsState()) {
    // Keeps the unread badge on the home screen fresh.
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  final ComplaintService service;
  Timer? _poll;

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }

  /// First load / retry: shows the spinner when there is nothing on screen.
  Future<void> load() async {
    if (state.complaints.isEmpty) {
      emit(state.copyWith(load: ComplaintsLoad.loading, clearError: true));
    }
    await _fetch();
  }

  /// Pull-to-refresh, resume and polling: never replaces the list with a
  /// spinner, and keeps the old list if the call fails.
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    try {
      final list = await service.list();
      if (isClosed) return;
      emit(ComplaintsState(load: ComplaintsLoad.ready, complaints: list));
    } on ApiException catch (e) {
      if (isClosed) return;
      if (state.complaints.isEmpty) {
        emit(state.copyWith(load: ComplaintsLoad.error, error: e.message));
      }
    }
  }

  /// Raises a new complaint. Returns its id; throws [ApiException] on failure
  /// so the form can show the message.
  Future<int> create({
    required String title,
    required String description,
    Uint8List? image,
  }) async {
    final id = await service.create(
        title: title, description: description, image: image);
    refresh();
    return id;
  }
}

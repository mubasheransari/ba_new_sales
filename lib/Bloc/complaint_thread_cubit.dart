import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:ords_ba/Repository/repository.dart';

enum ThreadLoad { loading, ready, error }

class ThreadState extends Equatable {
  final ThreadLoad load;
  final ComplaintThread? thread;
  final bool sending;
  final bool changingStatus;
  final String? error; // full-screen error (first load failed)
  final String? message; // toast
  final bool messageIsError;
  final int messageId;

  const ThreadState({
    this.load = ThreadLoad.loading,
    this.thread,
    this.sending = false,
    this.changingStatus = false,
    this.error,
    this.message,
    this.messageIsError = true,
    this.messageId = 0,
  });

  ThreadState copyWith({
    ThreadLoad? load,
    ComplaintThread? thread,
    bool? sending,
    bool? changingStatus,
    String? error,
    bool clearError = false,
    String? message,
    bool messageIsError = true,
  }) =>
      ThreadState(
        load: load ?? this.load,
        thread: thread ?? this.thread,
        sending: sending ?? this.sending,
        changingStatus: changingStatus ?? this.changingStatus,
        error: clearError ? null : (error ?? this.error),
        message: message,
        messageIsError: messageIsError,
        messageId: message == null ? messageId : messageId + 1,
      );

  @override
  List<Object?> get props => [
        load,
        sending,
        changingStatus,
        error,
        messageId,
        thread == null
            ? null
            : [
                thread!.status,
                thread!.messages.length,
                thread!.messages.isEmpty ? 0 : thread!.messages.last.id,
              ],
      ];
}

/// One open conversation. Polls the server every few seconds so a reply from
/// support appears without leaving the screen.
class ComplaintThreadCubit extends Cubit<ThreadState> {
  ComplaintThreadCubit({
    required this.service,
    required this.inbox,
    required this.complaintId,
  }) : super(const ThreadState()) {
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!state.sending && !state.changingStatus) load(silent: true);
    });
  }

  final ComplaintService service;
  final ComplaintsCubit inbox;
  final int complaintId;

  Timer? _timer;
  final Map<int, Future<Uint8List>> _images = {};

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent && state.thread == null) {
      emit(state.copyWith(load: ThreadLoad.loading, clearError: true));
    }
    try {
      final t = await service.thread(complaintId);
      if (isClosed) return;
      final changed = state.thread == null ||
          state.thread!.messages.length != t.messages.length ||
          state.thread!.status != t.status;
      emit(state.copyWith(
          load: ThreadLoad.ready, thread: t, clearError: true));
      // Opening a conversation marks it read -> refresh the inbox dot.
      if (changed) inbox.refresh();
    } on ApiException catch (e) {
      if (isClosed) return;
      if (state.thread == null) {
        emit(state.copyWith(load: ThreadLoad.error, error: e.message));
      } else if (!silent) {
        emit(state.copyWith(message: e.message));
      }
    }
  }

  /// Sends a text and/or a picture. Returns true on success.
  Future<bool> send({String text = '', Uint8List? image}) async {
    final msg = text.trim();
    if (msg.isEmpty && image == null) return false;
    emit(state.copyWith(sending: true));
    try {
      await service.reply(complaintId, message: msg, image: image);
      if (isClosed) return true;
      emit(state.copyWith(sending: false));
      await load(silent: true);
      inbox.refresh();
      return true;
    } on ApiException catch (e) {
      if (!isClosed) emit(state.copyWith(sending: false, message: e.message));
      return false;
    }
  }

  /// Marks the complaint resolved, or reopens it.
  Future<void> setResolved(bool resolved) async {
    emit(state.copyWith(changingStatus: true));
    try {
      await service.setStatus(complaintId, resolved ? 'RESOLVED' : 'OPEN');
      if (isClosed) return;
      emit(state.copyWith(
        changingStatus: false,
        message: resolved ? 'Marked as resolved.' : 'Complaint reopened.',
        messageIsError: false,
      ));
      await load(silent: true);
      inbox.refresh();
    } on ApiException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(changingStatus: false, message: e.message));
      }
    }
  }

  /// Picture of one message. Cached; a failed download is retried next time.
  Future<Uint8List> imageFor(int messageId) {
    return _images.putIfAbsent(messageId, () {
      final f = service.image(messageId);
      f.catchError((_) {
        _images.remove(messageId);
        return Uint8List(0);
      });
      return f;
    });
  }
}

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';

/* ------------------------------- events ------------------------------- */

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  const AuthLoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}

class AuthSignupRequested extends AuthEvent {
  final String fullName;
  final String email;
  final String cnic;
  final String password;
  final String confirmPassword;
  final int locationId;
  const AuthSignupRequested({
    required this.fullName,
    required this.email,
    required this.cnic,
    required this.password,
    required this.confirmPassword,
    required this.locationId,
  });
  @override
  List<Object?> get props =>
      [fullName, email, cnic, password, confirmPassword, locationId];
}

class AuthProfileRefreshRequested extends AuthEvent {
  const AuthProfileRefreshRequested();
}

class AuthLogoutRequested extends AuthEvent {
  final String? reason;
  const AuthLogoutRequested({this.reason});
  @override
  List<Object?> get props => [reason];
}

/* -------------------------------- state -------------------------------- */

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends Equatable {
  final AuthStatus status;
  final bool busy;
  final AppUser? user;
  final String? token;

  /// One-shot message for the UI (snackbar). [messageId] changes every time
  /// so the same text can be shown twice.
  final String? message;
  final bool messageIsError;
  final int messageId;

  /// Increments after a successful signup so the UI can switch to Login.
  final int signupDoneId;
  final String? signupEmail;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.busy = false,
    this.user,
    this.token,
    this.message,
    this.messageIsError = true,
    this.messageId = 0,
    this.signupDoneId = 0,
    this.signupEmail,
  });

  String? get userName => user?.fullName;

  AuthState copyWith({
    AuthStatus? status,
    bool? busy,
    AppUser? user,
    String? token,
    bool clearSession = false,
    String? message,
    bool messageIsError = true,
    int? signupDoneId,
    String? signupEmail,
  }) {
    return AuthState(
      status: status ?? this.status,
      busy: busy ?? this.busy,
      user: clearSession ? null : (user ?? this.user),
      token: clearSession ? null : (token ?? this.token),
      message: message,
      messageIsError: messageIsError,
      messageId: message == null ? messageId : messageId + 1,
      signupDoneId: signupDoneId ?? this.signupDoneId,
      signupEmail: signupEmail ?? this.signupEmail,
    );
  }

  @override
  List<Object?> get props => [
        status,
        busy,
        user?.toJson().toString(),
        token,
        message,
        messageIsError,
        messageId,
        signupDoneId,
        signupEmail,
      ];
}

/* --------------------------------- bloc --------------------------------- */

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo, this._session) : super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginRequested>(_onLogin);
    on<AuthSignupRequested>(_onSignup);
    on<AuthProfileRefreshRequested>(_onRefresh);
    on<AuthLogoutRequested>(_onLogout);
  }

  final Repository _repo;
  final SessionStore _session;

  Future<void> _onStarted(AuthStarted e, Emitter<AuthState> emit) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400)); // splash
    final token = _session.readToken();
    final user = _session.readUser();
    if (token != null && user != null) {
      emit(state.copyWith(
          status: AuthStatus.authenticated, user: user, token: token));
      add(const AuthProfileRefreshRequested());
    } else {
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onLogin(AuthLoginRequested e, Emitter<AuthState> emit) async {
    emit(state.copyWith(busy: true));
    final email = e.email.trim();

    // A BA account works only on the phone it was registered on.
    final check = await _repo.checkDevice(email: email);
    if (!check.allowed) {
      emit(state.copyWith(busy: false, message: check.message));
      return;
    }

    try {
      final res = await _repo.login(email: email, password: e.password);
      var user = res.user;

      // The profile API is the source of truth for location_id etc.
      try {
        final p = await _repo.fetchProfile(res.token);
        user = user.mergeWith(p);
      } catch (_) {/* login still valid, profile will refresh later */}

      // An older account that is not linked to a phone yet is linked now.
      await _repo.bindDevice(token: res.token, email: email);

      await _session.save(res.token, user);
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        busy: false,
        user: user,
        token: res.token,
      ));
    } on ApiException catch (ex) {
      // The server also refuses another phone by itself. If the login failed,
      // see whether that is the reason and say so clearly.
      final again = await _repo.checkDevice(email: email);
      emit(state.copyWith(
          busy: false, message: again.allowed ? ex.message : again.message));
    } catch (_) {
      emit(state.copyWith(busy: false, message: 'Something went wrong. Try again.'));
    }
  }

  Future<void> _onSignup(AuthSignupRequested e, Emitter<AuthState> emit) async {
    emit(state.copyWith(busy: true));
    final email = e.email.trim();

    // One phone can only have one account.
    final check = await _repo.checkDevice(email: email, signup: true);
    if (!check.allowed) {
      emit(state.copyWith(busy: false, message: check.message));
      return;
    }

    try {
      final msg = await _repo.signup(
        fullName: e.fullName.trim(),
        email: e.email.trim(),
        cnic: e.cnic,
        password: e.password,
        confirmPassword: e.confirmPassword,
        locationId: e.locationId,
      );
      // Link the new account to this phone (the server only allows this in
      // the first minutes after registration).
      final bindProblem = await _repo.bindDevice(email: email);

      emit(state.copyWith(
        busy: false,
        message: bindProblem == null
            ? msg
            : '$msg\nYour phone could not be linked yet ($bindProblem). '
                'It will be linked when you log in.',
        messageIsError: bindProblem != null,
        signupDoneId: state.signupDoneId + 1,
        signupEmail: email,
      ));
    } on ApiException catch (ex) {
      final again = await _repo.checkDevice(email: email, signup: true);
      emit(state.copyWith(
          busy: false, message: again.allowed ? ex.message : again.message));
    } catch (_) {
      emit(state.copyWith(busy: false, message: 'Something went wrong. Try again.'));
    }
  }

  Future<void> _onRefresh(
      AuthProfileRefreshRequested e, Emitter<AuthState> emit) async {
    final token = state.token;
    if (token == null) return;
    try {
      final p = await _repo.fetchProfile(token);
      final merged = (state.user ?? p).mergeWith(p);
      await _session.saveUser(merged);
      emit(state.copyWith(user: merged));
    } on ApiException catch (ex) {
      if (ex.isUnauthorized) {
        add(const AuthLogoutRequested(
            reason: 'Session expired. Please login again.'));
      }
    } catch (_) {/* offline - keep cached user */}
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    // A logout with a reason was triggered by the app after a request was
    // rejected (401). Do not trust one request: ask the server whether the
    // login is really gone. Only then sign the BA out. If the server still
    // accepts the login, or cannot be reached, the BA stays logged in.
    // (The Logout button on the profile screen has no reason, so it always
    // logs out at once.)
    final token = state.token;
    if (e.reason != null && token != null) {
      try {
        await _repo.fetchProfile(token);
        return; // the login still works: stay signed in
      } on ApiException catch (ex) {
        if (!ex.isUnauthorized) return; // server/network trouble: stay signed in
      } catch (_) {
        return;
      }
    }
    await _session.clear();
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearSession: true,
      busy: false,
      message: e.reason,
    ));
  }
}

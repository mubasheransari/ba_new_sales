import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Bloc/dashboard_cubit.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/history_screen.dart';
import 'package:ords_ba/Screens/home_screen.dart';
import 'package:ords_ba/Screens/profile_screen.dart';
import 'package:ords_ba/Widgets/bottom_bar.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/shelf_dialog.dart';

/// Shown only while logged in. Creates the [AttendanceCubit] for this BA.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>();
    final k = auth.state.user?.storageKey;
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendanceCubit>(
          // New cubit per login: attendance data is namespaced by BA.
          key: ValueKey('attendance_$k'),
          create: (ctx) => AttendanceCubit(
            repo: ctx.read<Repository>(),
            store: AttendanceStore(auth.state.user!.storageKey),
            shelfStore: ShelfStore(auth.state.user!.storageKey),
            tokenProvider: () => auth.state.token,
            onUnauthorized: () => auth.add(const AuthLogoutRequested(
                reason: 'Session expired. Please login again.')),
          ),
        ),
        // Home chart: selected filter + data loaded from the server.
        BlocProvider<DashboardCubit>(
          key: ValueKey('dashboard_$k'),
          create: (ctx) => DashboardCubit(
            repo: ctx.read<Repository>(),
            tokenProvider: () => auth.state.token,
            onUnauthorized: () => auth.add(const AuthLogoutRequested(
                reason: 'Session expired. Please login again.')),
          ),
        ),
        // Complaints inbox: also feeds the unread badge on the home screen.
        BlocProvider<ComplaintsCubit>(
          key: ValueKey('complaints_$k'),
          lazy: false,
          create: (ctx) => ComplaintsCubit(
            service: ComplaintService(
              repo: ctx.read<Repository>(),
              tokenProvider: () => auth.state.token,
              onUnauthorized: () => auth.add(const AuthLogoutRequested(
                  reason: 'Session expired. Please login again.')),
            ),
          )..load(),
        ),
      ],
      child: const _ShellBody(),
    );
  }
}

class _ShellBody extends StatefulWidget {
  const _ShellBody();
  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody> with WidgetsBindingObserver {
  BottomTab _tab = BottomTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App (re)opened while checked in but no shelf picture yet -> popup.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowShelf());
  }

  bool _shelfOpen = false;

  /// Shows the blocking shelf-picture popup when it is needed. It is shown on
  /// the root navigator, so it appears on top of whatever screen is open
  /// (e.g. the attendance map right after marking IN).
  Future<void> _maybeShowShelf() async {
    if (!mounted || _shelfOpen) return;
    // never pop the dialog up while logging out
    if (context.read<AuthBloc>().state.status != AuthStatus.authenticated) return;
    if (!context.read<AttendanceCubit>().state.needsShelf) return;
    _shelfOpen = true;
    await showShelfDialog(context);
    _shelfOpen = false;
    // e.g. dialog closed by midnight/logout but still needed -> re-check
    if (mounted) _maybeShowShelf();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App came back to foreground: catch a missed 12:00 AM auto-out and
  /// refresh the profile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AttendanceCubit>().sync().then((_) => _maybeShowShelf());
      context.read<ComplaintsCubit>().refresh();
      context.read<DashboardCubit>().refreshCurrent();
      context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <BottomTab, Widget>{
      BottomTab.home: HomeScreen(key: UniqueKey()),
      BottomTab.history: const HistoryScreen(),
      BottomTab.profile: const ProfileScreen(),
    };

    return PopScope(
      canPop: _tab == BottomTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = BottomTab.home);
      },
      child: BlocListener<AttendanceCubit, AttendanceState>(
        // attendance IN just succeeded (or app state changed) -> shelf popup
        listenWhen: (a, b) => b.needsShelf && !a.needsShelf,
        listener: (context, st) => _maybeShowShelf(),
        child: BlocListener<AttendanceCubit, AttendanceState>(
        // messages raised outside a screen (e.g. midnight auto-out)
        listenWhen: (a, b) =>
            a.messageId != b.messageId && b.message != null && b.messageIsError == false &&
            b.message!.contains('automatically'),
        listener: (context, st) => showToast(context, st.message!, error: false),
        child: Scaffold(
          extendBody: true,
          body: pages[_tab]!,
          bottomNavigationBar: BottomBar(
            active: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        ),
      ),
    );
  }
}

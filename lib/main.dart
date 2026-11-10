import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_storage/get_storage.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/device_id.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/app_shell.dart';
import 'package:ords_ba/Screens/auth_screen.dart';
import 'package:ords_ba/Screens/splash_screen.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No debug logging (locations, errors, stack traces) in release builds.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  await GetStorage.init();
  await DeviceId.load(); // the phone's ID, sent with every request
  runApp(const BaApp());
}

class BaApp extends StatelessWidget {
  const BaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<Repository>(
      create: (_) => Repository(),
      child: BlocProvider<AuthBloc>(
        create: (ctx) =>
            AuthBloc(ctx.read<Repository>(), SessionStore())..add(const AuthStarted()),
        child: MaterialApp(
          title: 'BA Sales',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const _Root(),
        ),
      ),
    );
  }
}

/// Chooses Splash / Login / Home from the auth state.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      // e.g. "Session expired" after being logged out by the server
      listenWhen: (a, b) =>
          a.status == AuthStatus.authenticated &&
          b.status == AuthStatus.unauthenticated &&
          b.message != null,
      listener: (context, st) => showToast(context, st.message!),
      child: BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (a, b) => a.status != b.status,
        builder: (context, st) {
          final Widget page = switch (st.status) {
            AuthStatus.unknown => const SplashScreen(),
            AuthStatus.unauthenticated => const AuthScreen(),
            AuthStatus.authenticated => const AppShell(),
          };
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey(st.status), child: page),
          );
        },
      ),
    );
  }
}

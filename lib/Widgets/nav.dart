import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Repository/repository.dart';

/// Pushes [page] on the root navigator while keeping the Auth / Attendance
/// blocs and the Repository available inside it.
Future<T?> pushWithBlocs<T>(BuildContext context, Widget page) {
  final auth = context.read<AuthBloc>();
  final att = context.read<AttendanceCubit>();
  final complaints = context.read<ComplaintsCubit>();
  final repo = context.read<Repository>();
  return Navigator.of(context, rootNavigator: true).push<T>(
    MaterialPageRoute(
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: auth),
          BlocProvider.value(value: att),
          BlocProvider.value(value: complaints),
          RepositoryProvider.value(value: repo),
        ],
        child: page,
      ),
    ),
  );
}

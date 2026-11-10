
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Blocking popup: the BA must upload today's shelf picture after marking
/// attendance IN. It cannot be dismissed (no back button, no tap outside);
/// it closes itself after a successful upload, when the BA is checked out
/// (e.g. 12:00 AM auto-out) or when the session ends.
///
/// Shown on the ROOT navigator, so it appears above any open screen.
/// [context] must be able to read [AttendanceCubit].
Future<void> showShelfDialog(BuildContext context) {
  final cubit = context.read<AttendanceCubit>();
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => BlocProvider<AttendanceCubit>.value(
      value: cubit,
      child: const _ShelfDialog(),
    ),
  );
}

class _ShelfDialog extends StatefulWidget {
  const _ShelfDialog();

  @override
  State<_ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<_ShelfDialog> {
  final _picker = ImagePicker();
  final _remarks = TextEditingController();

  Uint8List? _bytes;
  String? _fileName;
  String? _error;
  bool _picking = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _takePhoto() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      // Camera only - gallery is not allowed for shelf pictures.
      final XFile? pic = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        imageQuality: 75,
      );
      if (pic == null) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final bytes = await pic.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileName = pic.name.isEmpty
            ? 'shelf_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : pic.name;
        _picking = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = e.code.contains('denied')
            ? 'Camera permission is required. Allow camera access in '
                'phone Settings, then try again.'
            : 'Could not open the camera. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = 'Could not open the camera. Please try again.';
      });
    }
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    final name = _fileName;
    if (bytes == null || name == null) {
      setState(() => _error = 'Please take the shelf picture first.');
      return;
    }
    // The server stores which BA / outlet / GPS position the picture is for.
    final user = context.read<AuthBloc>().state.user;
    final cubit = context.read<AttendanceCubit>();
    final userId = int.tryParse(user?.id ?? '');
    final locationId = user?.locationId;
    final today = cubit.state.today;
    final lat = today?.inLat ?? user?.latitude;
    final lng = today?.inLng ?? user?.longitude;
    if (userId == null || locationId == null || lat == null || lng == null) {
      setState(() => _error =
          'Your user, location or GPS details are missing. '
          'Please login again or mark attendance again.');
      return;
    }
    setState(() => _error = null);
    // Success closes the dialog through the BlocListener below.
    await cubit.uploadShelfPicture(
          userId: userId,
          locationId: locationId,
          latitude: lat,
          longitude: lng,
          fileName: name,
          bytes: bytes,
          remarks: _remarks.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // Upload done, or BA no longer checked in (midnight auto-out).
        BlocListener<AttendanceCubit, AttendanceState>(
          listenWhen: (a, b) =>
              (!a.shelfDone && b.shelfDone) ||
              (a.isCheckedIn && !b.isCheckedIn),
          listener: (_, __) => _close(),
        ),
        // Upload error from the server -> show inside the popup.
        BlocListener<AttendanceCubit, AttendanceState>(
          listenWhen: (a, b) =>
              a.messageId != b.messageId &&
              b.message != null &&
              b.messageIsError,
          listener: (_, st) => setState(() => _error = st.message),
        ),
        // Logged out (e.g. session expired) -> never leave it over login.
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (a, b) => b.status != AuthStatus.authenticated,
          listener: (_, __) => _close(),
        ),
      ],
      child: PopScope(
        canPop: false, // back button cannot close it
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: BlocBuilder<AttendanceCubit, AttendanceState>(
            buildWhen: (a, b) => a.busy != b.busy,
            builder: (context, st) => _card(st.busy),
          ),
        ),
      ),
    );
  }

  Widget _card(bool uploading) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.redDeep.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: const BoxDecoration(gradient: AppGradients.primary),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shelf picture',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Required to continue',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attendance marked. Take a clear photo of your shelf to '
                    'unlock sales and the app.',
                    style: TextStyle(
                        color: AppColors.textDim, height: 1.35, fontSize: 14),
                  ),
                  const SizedBox(height: 14),

                  // Preview / capture area
                  GestureDetector(
                    onTap: (uploading || _picking) ? null : _takePhoto,
                    child: Container(
                      height: 190,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.redTint,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.redLight, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _picking
                          ? const Center(child: CircularProgressIndicator())
                          : _bytes == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_rounded,
                                        size: 44, color: AppColors.red),
                                    SizedBox(height: 8),
                                    Text('Tap to open camera',
                                        style: TextStyle(
                                            color: AppColors.redDeep,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                )
                              : Image.memory(_bytes!,
                                  fit: BoxFit.cover, width: double.infinity),
                    ),
                  ),

                  if (_bytes != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: (uploading || _picking) ? null : _takePhoto,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retake'),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 12),

                  TextField(
                    controller: _remarks,
                    enabled: !uploading,
                    maxLines: 2,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.redTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.redDeep, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.redDeep, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  if (_bytes == null)
                    GradientButton(
                      text: 'TAKE PHOTO',
                      icon: Icons.photo_camera_rounded,
                      onPressed: _picking ? null : _takePhoto,
                    )
                  else
                    GradientButton(
                      text: 'UPLOAD & CONTINUE',
                      icon: Icons.cloud_upload_rounded,
                      loading: uploading,
                      onPressed: uploading ? null : _upload,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

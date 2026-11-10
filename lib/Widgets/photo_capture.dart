
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Tells the BA what to photograph, then opens the CAMERA (never the gallery).
/// Returns the compressed JPEG bytes, or null if the BA cancelled or the
/// camera failed (a message is shown in that case).
Future<Uint8List?> capturePhoto(
  BuildContext context, {
  required String title,
  required String message,
  bool selfie = false,
}) async {
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Open camera'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return null;

  try {
    final XFile? pic = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 1024,
      imageQuality: 70,
    );
    if (pic == null) return null;
    return await pic.readAsBytes();
  } on PlatformException catch (e) {
    if (context.mounted) {
      showToast(
        context,
        e.code.contains('denied')
            ? 'Camera permission is required. Allow camera access in '
                'phone Settings, then try again.'
            : 'Could not open the camera. Please try again.',
      );
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      showToast(context, 'Could not open the camera. Please try again.');
    }
    return null;
  }
}

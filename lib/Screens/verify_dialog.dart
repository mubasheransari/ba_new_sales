
import 'package:flutter/material.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';

/// Shows the CNIC verification popup.
///
/// 1. Opens with a loading spinner.
/// 2. Calls Repository.checkBaCnic().
/// 3. Displays the registered FULL_NAME when the CNIC is authorized.
/// 4. Displays the server error/message when the CNIC is not authorized.
///
/// Returns CnicCheckResult when the user taps CONTINUE or CLOSE.
/// Returns null if the dialog is dismissed.
Future<CnicCheckResult?> showCnicVerifyDialog(
  BuildContext context, {
  required Repository repository,
  required String cnic,
}) {
  return showDialog<CnicCheckResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CnicVerifyDialog(
      repository: repository,
      cnic: cnic,
    ),
  );
}

enum _Phase {
  verifying,
  verified,
  failed,
}

class _CnicVerifyDialog extends StatefulWidget {
  const _CnicVerifyDialog({
    required this.repository,
    required this.cnic,
  });

  final Repository repository;
  final String cnic;

  @override
  State<_CnicVerifyDialog> createState() => _CnicVerifyDialogState();
}

class _CnicVerifyDialogState extends State<_CnicVerifyDialog> {
  _Phase _phase = _Phase.verifying;

  String _message = '';
  CnicCheckResult? _result;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    if (!mounted) return;

    setState(() {
      _phase = _Phase.verifying;
      _message = '';
      _result = null;
    });

    CnicCheckResult result;

    try {
      result = await widget.repository.checkBaCnic(
        cnic: widget.cnic,
      );
    } on ApiException catch (e) {
      result = CnicCheckResult(
        allowed: false,
        message: e.message,
      );
    } catch (_) {
      result = const CnicCheckResult(
        allowed: false,
        message: 'Unable to verify CNIC. Please try again.',
      );
    }

    if (!mounted) return;

    setState(() {
      _result = result;
      _message = result.message;
      _phase = result.allowed ? _Phase.verified : _Phase.failed;
    });
  }

  /// Formats 13 digits as 12345-1234567-1.
  String get _prettyCnic {
    final digits = widget.cnic.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 13) return widget.cnic;

    return '${digits.substring(0, 5)}-'
        '${digits.substring(5, 12)}-'
        '${digits.substring(12)}';
  }

  void _close() {
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    final verifying = _phase == _Phase.verifying;
    final registeredName = _result?.fullName?.trim();

    return PopScope(
      canPop: !verifying,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(phase: _phase),

                const SizedBox(height: 20),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    switch (_phase) {
                      _Phase.verifying => 'Verifying your CNIC',
                      _Phase.verified => 'CNIC verified',
                      _Phase.failed => 'CNIC not verified',
                    },
                    key: ValueKey(_phase),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),

                // Registered employee name returned by ORDS.
                if (_phase == _Phase.verified &&
                    registeredName != null &&
                    registeredName.isNotEmpty) ...[
                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.success,
                          size: 22,
                        ),

                        const SizedBox(height: 7),

                        const Text(
                          'REGISTERED EMPLOYEE NAME',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppColors.textDim,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          registeredName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.redTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 18,
                        color: AppColors.red,
                      ),

                      const SizedBox(width: 8),

                      Text(
                        _prettyCnic,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  switch (_phase) {
                    _Phase.verifying =>
                      'Please wait while we check that this CNIC is '
                          'authorized for BA registration.',
                    _ => _message,
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textDim,
                  ),
                ),

                const SizedBox(height: 22),

                if (_phase == _Phase.verified)
                  _PrimaryButton(
                    text: 'CONTINUE',
                    icon: Icons.arrow_forward_rounded,
                    gradient: AppGradients.success,
                    onPressed: _close,
                  ),

                if (_phase == _Phase.failed) ...[
                  _PrimaryButton(
                    text: 'TRY AGAIN',
                    icon: Icons.refresh_rounded,
                    gradient: AppGradients.horizontal,
                    onPressed: _verify,
                  ),

                  const SizedBox(height: 8),

                  TextButton(
                    onPressed: _close,
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round badge: spinner -> green tick / red cross.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.phase,
  });

  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (phase) {
      _Phase.verifying => AppColors.red,
      _Phase.verified => AppColors.success,
      _Phase.failed => AppColors.redDeep,
    };

    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.10),
      ),
      alignment: Alignment.center,
      child: switch (phase) {
        _Phase.verifying => const SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 3.4,
            ),
          ),

        _Phase.verified => _PopIcon(
            key: const ValueKey('ok'),
            icon: Icons.check_circle_rounded,
            color: color,
          ),

        _Phase.failed => _PopIcon(
            key: const ValueKey('fail'),
            icon: Icons.cancel_rounded,
            color: color,
          ),
      },
    );
  }
}

/// Icon that pops in with a small bounce.
class _PopIcon extends StatelessWidget {
  const _PopIcon({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.2, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.elasticOut,
      builder: (_, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Icon(
        icon,
        size: 56,
        color: color,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.text,
    required this.icon,
    required this.gradient,
    required this.onPressed,
  });

  final String text;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),

              const SizedBox(width: 8),

              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

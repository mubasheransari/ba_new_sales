import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/device_id.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/verify_dialog.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _obscure = true;
  bool _obscure2 = true;
  bool _checkingCnic = false;
  bool _cnicVerified = false;
  String? _verifiedCnic;
  String? _cnicCheckMessage;

  final _loginForm = GlobalKey<FormState>();
  final _signupForm = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _password = TextEditingController();

  final _name = TextEditingController();
  final _sEmail = TextEditingController();
  final _cnic = TextEditingController();
  final _sPass = TextEditingController();
  final _sConfirm = TextEditingController();

  List<MartLocation> _locations = const [];
  int? _locationId;
  bool _locLoading = false;
  String? _locError;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _sEmail, _cnic, _sPass, _sConfirm]) {
      c.dispose();
    }
    super.dispose();
  }


Future<void> _loadLocations() async {
  if (!mounted) return;

  setState(() {
    _locLoading = true;
    _locError = null;
  });

  final repo = context.read<Repository>();
  final cache = CacheStore();

  try {
    debugPrint('========== BA SALES LOCATIONS ==========');
    debugPrint('Fetching locations from API...');

    final List<MartLocation> locations = await repo.fetchLocations();

    debugPrint('API locations count: ${locations.length}');

    for (final location in locations) {
      debugPrint(
        'Location ID: ${location.id}, '
        'Location Name: ${location.name}',
      );
    }

    // Save successfully fetched locations locally.
    await cache.saveLocations(locations);

    if (!mounted) return;

    setState(() {
      _locations = locations;
      // Reset the selected location if it no longer exists.
      if (_locationId != null &&
          !_locations.any((location) => location.id == _locationId)) {
        _locationId = null;
      }

      if (_locations.isEmpty) {
        _locError = 'The API returned no locations.';
      }
    });

    debugPrint('Locations loaded successfully: ${_locations.length}');
  } catch (e, stackTrace) {
    debugPrint('Failed to fetch locations: $e');
    debugPrintStack(stackTrace: stackTrace);

    // Fall back to previously cached locations.
    try {
      final List<MartLocation> cachedLocations = cache.readLocations();

      debugPrint('Cached locations count: ${cachedLocations.length}');

      if (!mounted) return;

      setState(() {
        _locations = cachedLocations;

        if (_locationId != null &&
            !_locations.any((location) => location.id == _locationId)) {
          _locationId = null;
        }

        _locError = cachedLocations.isEmpty
            ? 'Unable to load locations. Please check your connection and retry.'
            : null;
      });
    } catch (cacheError) {
      debugPrint('Failed to read cached locations: $cacheError');

      if (!mounted) return;

      setState(() {
        _locations = [];
        _locationId = null;
        _locError = 'Unable to load locations. Please retry.';
      });
    }
  } finally {
    if (mounted) {
      setState(() {
        _locLoading = false;
      });
    }
  }
}

  void _submitLogin() {
    if (!_loginForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(AuthLoginRequested(_email.text, _password.text));
  }

  /// Opens the verification popup (spinner -> authorized / not authorized).
  /// The server checks whether the CNIC exists in our BA data.
  /// Returns true only when the CNIC is authorized to create an account.
  Future<bool> _verifyCnic() async {
    if (_checkingCnic) return false; // popup already open
    final cnic = _cnic.text.replaceAll(RegExp(r'\D'), '');
    if (cnic.length != 13) {
      showToast(context, 'Enter a valid 13-digit CNIC.');
      return false;
    }

    FocusScope.of(context).unfocus();
    setState(() => _checkingCnic = true);

    final result = await showCnicVerifyDialog(
      context,
      repository: context.read<Repository>(),
      cnic: cnic,
    );

    if (!mounted) return false;

    // Ignore the answer if the CNIC was edited while the popup was open.
    final stillSame = _cnic.text.replaceAll(RegExp(r'\D'), '') == cnic;
    final ok = result?.allowed == true && stillSame;
    setState(() {
      _checkingCnic = false;
      _cnicVerified = ok;
      _verifiedCnic = ok ? cnic : null;
      _cnicCheckMessage = stillSame ? result?.message : null;
    });
    return ok;
  }

  Future<void> _submitSignup() async {
    if (!_signupForm.currentState!.validate()) return;
    final cnic = _cnic.text.replaceAll(RegExp(r'\D'), '');

    // Only a CNIC found in our data may create an account.
    if (!_cnicVerified || _verifiedCnic != cnic) {
      final ok = await _verifyCnic();
      if (!ok || !mounted) return;
    }

    if (_locationId == null) {
      showToast(context, 'Please select your mart location.');
      return;
    }
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(AuthSignupRequested(
          fullName: _name.text,
          email: _sEmail.text,
          cnic: cnic,
          password: _sPass.text,
          confirmPassword: _sConfirm.text,
          locationId: _locationId!,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (a, b) =>
          a.messageId != b.messageId || a.signupDoneId != b.signupDoneId,
      listener: (context, st) {
        if (st.message != null) {
          showToast(context, st.message!, error: st.messageIsError);
        }
        // Signup finished -> flip to Login with email pre-filled.
        if (st.signupDoneId > 0 && st.signupEmail != null && !_isLogin) {
          setState(() {
            _isLogin = true;
            _email.text = st.signupEmail!;
            _password.clear();
          });
        }
      },
      builder: (context, st) {
        return Scaffold(
          body: Stack(
            children: [
              // Red header
              Container(
                height: 300,
                decoration: const BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(42)),
                ),
              ),
              Positioned(
                top: -50,
                right: -40,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Container(
                          //   width: 46,
                          //   height: 46,
                          //   decoration: BoxDecoration(
                          //     color: Colors.white,
                          //     borderRadius: BorderRadius.circular(14),
                          //   ),
                          //   child: const Icon(Icons.storefront_rounded,
                          //       color: AppColors.red),
                          // ),
                          // const SizedBox(width: 12),
                           Image.asset(
          'assets/ba_logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          color: Colors.white,
        ),
                          // const Text('BA Sales',
                          //     style: TextStyle(
                          //         color: Colors.white,
                          //         fontSize: 22,
                          //         fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          // This phone's Device ID, top right
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _DeviceChip(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        _isLogin ? 'Welcome\nback' : 'Create your\nBA account',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Login to mark attendance and enter sales.'
                            : 'Pick your mart and get started.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14.5),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: cardDecoration(radius: 26),
                        child: Column(
                          children: [
                            _Toggle(
                              isLogin: _isLogin,
                              onChanged: (v) => setState(() => _isLogin = v),
                            ),
                            const SizedBox(height: 20),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _isLogin
                                  ? _loginFields(st)
                                  : _signupFields(st),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /* ------------------------------ login ------------------------------ */

  Widget _loginFields(AuthState st) {
    return Form(
      key: _loginForm,
      child: Column(
        key: const ValueKey('login'),
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitLogin(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          const SizedBox(height: 22),
          GradientButton(
            text: 'LOGIN',
            icon: Icons.login_rounded,
            loading: st.busy,
            onPressed: st.busy ? null : _submitLogin,
          ),
          const SizedBox(height: 14),
          _FooterSwitch(
            text: "Don't have an account? ",
            action: 'Sign up',
            onTap: () => setState(() => _isLogin = false),
          ),
        ],
      ),
    );
  }

  /* ------------------------------ signup ------------------------------ */

  Widget _signupFields(AuthState st) {
    return Form(
      key: _signupForm,
      child: Column(
        key: const ValueKey('signup'),
        children: [
          // Device ID of this phone, top right of the registration tab
          const Align(
            alignment: Alignment.centerRight,
            child: _DeviceTag(),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.redTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_android_rounded, size: 18, color: AppColors.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your account will be linked to this phone (its Device ID '
                    'is shown above). It cannot be used on any other phone, '
                    'and this phone cannot be used for another account.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.text, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Enter your full name'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _sEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cnic,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(13),
            ],
            decoration: InputDecoration(
              labelText: 'CNIC (13 digits, no dashes)',
              prefixIcon: const Icon(Icons.badge_outlined),
              suffixIcon: _cnicVerified && _verifiedCnic == _cnic.text
                  ? const Icon(Icons.verified_rounded, color: Colors.green)
                  : null,
            ),
            onChanged: (v) {
              if (_cnicVerified || _cnicCheckMessage != null) {
                setState(() {
                  _cnicVerified = false;
                  _verifiedCnic = null;
                  _cnicCheckMessage = null;
                });
              }
              // 13th digit typed -> check it straight away in the popup.
              if (v.length == 13 && !_checkingCnic) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _verifyCnic();
                });
              }
            },
            validator: (v) => (v == null || v.length != 13)
                ? 'CNIC must be 13 digits'
                : null,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkingCnic || _cnic.text.length != 13
                  ? null
                  : () => _verifyCnic(),
              icon: _checkingCnic
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_cnicVerified ? Icons.verified_rounded : Icons.verified_user_outlined),
              label: Text(_checkingCnic
                  ? 'CHECKING CNIC...'
                  : _cnicVerified && _verifiedCnic == _cnic.text
                      ? 'CNIC VERIFIED'
                      : 'VERIFY CNIC'),
            ),
          ),
          if (_cnicCheckMessage != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _cnicCheckMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: _cnicVerified ? Colors.green.shade700 : AppColors.red,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _locationDropdown(),
          const SizedBox(height: 14),
          TextFormField(
            controller: _sPass,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.length < 6)
                ? 'At least 6 characters'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _sConfirm,
            obscureText: _obscure2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_reset_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure2
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
            validator: (v) =>
                v != _sPass.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 22),
          GradientButton(
            text: 'CREATE ACCOUNT',
            icon: Icons.person_add_alt_1_rounded,
            loading: st.busy,
            onPressed: st.busy ? null : _submitSignup,
          ),
          const SizedBox(height: 14),
          _FooterSwitch(
            text: 'Already have an account? ',
            action: 'Login',
            onTap: () => setState(() => _isLogin = true),
          ),
        ],
      ),
    );
  }

  Widget _locationDropdown() {
    if (_locLoading) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.redTint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2)),
            SizedBox(width: 10),
            Text('Loading locations...',
                style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      );
    }

    if (_locations.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.redTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.redLight),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _locError ?? 'No locations available.',
                style: const TextStyle(color: AppColors.redDeep),
              ),
            ),
            TextButton(onPressed: _loadLocations, child: const Text('Retry')),
          ],
        ),
      );
    }

    return DropdownButtonFormField<int>(
      value: _locationId,
      isExpanded: true,
      borderRadius: BorderRadius.circular(14),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.red),
      decoration: const InputDecoration(
        labelText: 'Mart location',
        prefixIcon: Icon(Icons.place_outlined),
      ),
      items: [
        for (final l in _locations)
          DropdownMenuItem<int>(
            value: l.id,
            child: Text('${l.name}-${l.areaName}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _locationId = v),
      validator: (v) => v == null ? 'Select your mart location' : null,
    );
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Enter a valid email';
    }
    return null;
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.isLogin, required this.onChanged});
  final bool isLogin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? AppGradients.horizontal : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.red,
                ),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          tab('Login', isLogin, () => onChanged(true)),
          tab('Sign up', !isLogin, () => onChanged(false)),
        ],
      ),
    );
  }
}

class _FooterSwitch extends StatelessWidget {
  const _FooterSwitch(
      {required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: const TextStyle(color: AppColors.textDim)),
        GestureDetector(
          onTap: onTap,
          child: Text(action,
              style: const TextStyle(
                  color: AppColors.red, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}


/// This phone's Device ID, shown at the top right. Long IDs are shortened;
/// tap it to see and copy the full ID.
class _DeviceChip extends StatelessWidget {
  const _DeviceChip();

  static String _short(String id) => id.length > 18
      ? '${id.substring(0, 8)}...${id.substring(id.length - 4)}'
      : id;

  @override
  Widget build(BuildContext context) {
    final id = DeviceId.value;
    if (id.isEmpty) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showFullId(context, id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smartphone_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _short(id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullId(BuildContext context, String id) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Device ID of this phone',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.redTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  id,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.text),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'A BA account works only on the phone it was registered on. '
                'If you changed your phone, give this ID to your admin to '
                'move your account.',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textDim, height: 1.3),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: id));
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      showToast(context, 'Device ID copied.', error: false);
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Device ID'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// The full Device ID, shown inside the registration tab (tap to copy).
class _DeviceTag extends StatelessWidget {
  const _DeviceTag();

  @override
  Widget build(BuildContext context) {
    final id = DeviceId.value;
    if (id.isEmpty) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: id));
        if (context.mounted) {
          showToast(context, 'Device ID copied.', error: false);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.redTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.redLight),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smartphone_rounded,
                  size: 14, color: AppColors.red),
              const SizedBox(width: 5),
              Text(
                'Device ID: $id',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 13, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
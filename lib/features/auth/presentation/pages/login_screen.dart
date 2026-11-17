import 'dart:async';

import 'package:bhromon/core/theme/colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/widgets/bouncy_button.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF050C08); // deepest dark green-black
const Color _kCardBg = AppColors.forestScaffold; // dark card, fully opaque
const Color _kBorder = Color(0xFF1E3A26); // subtle border
const Color _kGreen = AppColors.freshGreen; // vibrant mint-green
const Color _kGreenDark = AppColors.darkGreen;
const Color _kGold = AppColors.gold;
const Color _kWhite = Color(0xFFECF0F1);
const Color _kWhite54 = Color(0x8AECF0F1);
const Color _kWhite30 = Color(0x4DECF0F1);

/// What the user reads when sign-in fails. The technical message only goes to
/// the log, so no raw exception text reaches the screen.
String _authErrorText(BuildContext context, AuthFailureReason reason) {
  final key = switch (reason) {
    AuthFailureReason.network => 'auth_error_network',
    AuthFailureReason.googlePlayServices => 'auth_error_google_play_services',
    AuthFailureReason.popupBlocked => 'auth_error_popup_blocked',
    AuthFailureReason.invalidCredentials => 'auth_error_invalid_credentials',
    AuthFailureReason.tooManyRequests => 'auth_error_too_many_requests',
    AuthFailureReason.userDisabled => 'auth_error_user_disabled',
    AuthFailureReason.emailAlreadyInUse => 'auth_error_email_already_in_use',
    AuthFailureReason.weakPassword => 'auth_error_weak_password',
    AuthFailureReason.otpInvalid => 'auth_error_otp_invalid',
    AuthFailureReason.otpExpired => 'auth_error_otp_expired',
    AuthFailureReason.otpNotFound => 'auth_error_otp_not_found',
    AuthFailureReason.otpCooldown => 'auth_error_otp_cooldown',
    AuthFailureReason.emailOtpUnavailable => 'auth_error_email_otp_unavailable',
    AuthFailureReason.unknown || AuthFailureReason.cancelled => 'error_generic',
  };
  return context.l10n.translate(key);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  String _appVersion = 'v1.0';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _slide = Tween<Offset>(
      begin: const Offset(0, .14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
    final currentAuthState = context.read<AuthCubit>().state;
    if (currentAuthState is! Unauthenticated) {
      context.read<AuthCubit>().checkAuthStatus();
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}+${info.buildNumber}';
        });
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final authState = context.read<AuthCubit>().state;
        if (authState is Authenticated) {
          final redirect =
              GoRouterState.of(context).uri.queryParameters['redirect'];
          if (redirect != null && redirect.isNotEmpty) {
            context.go(redirect);
          } else {
            context.go('/group-hub');
          }
        }
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: BlocConsumer<AuthCubit, AuthState>(
          listener: (ctx, state) {
            if (state is Authenticated) {
              final redirect =
                  GoRouterState.of(ctx).uri.queryParameters['redirect'];
              if (redirect != null && redirect.isNotEmpty) {
                ctx.go(redirect);
              } else {
                ctx.go('/group-hub');
              }
            }
            if (state is AuthError) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_authErrorText(ctx, state.reason))),
                    ],
                  ),
                  backgroundColor: const Color(0xFFD32F2F),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          },
          builder: (ctx, state) => Stack(
            children: [
              // ── Aurora glows ────────────────────────────────────────────────────
              _aurora(
                top: -180,
                right: -120,
                size: 360,
                color: _kGreen.withValues(alpha: .13),
              ),
              _aurora(
                bottom: -220,
                left: -160,
                size: 440,
                color: _kGold.withValues(alpha: .07),
              ),
              _aurora(
                top: 200,
                left: -80,
                size: 200,
                color: _kGreenDark.withValues(alpha: .18),
              ),

              // ── Content ─────────────────────────────────────────────────────────
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(
                            position: _slide,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _BrandHeader(),
                                const SizedBox(height: 36),
                                _loginCard(ctx, state),
                                const SizedBox(height: 20),
                                Center(
                                  child: Text(
                                    'Powered by Bhromon $_appVersion',
                                    style: const TextStyle(
                                      color: _kWhite30,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Aurora helper ──────────────────────────────────────────────────────────
  Widget _aurora({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * .8,
              spreadRadius: size * .3,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Login card ─────────────────────────────────────────────────────────────
  Widget _loginCard(BuildContext ctx, AuthState state) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .5),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: _kGreen.withValues(alpha: .04),
            blurRadius: 16,
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: _LoginForm(loading: state is AuthLoading),
    );
  }
}

// ─── Brand header ───────────────────────────────────────────────────────────
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo with glow ring
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _kGreen.withValues(alpha: .25),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: SizedBox(
            width: 110,
            height: 110,
            child: Image.asset(
              'assets/bhromon_emblem.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.explore_rounded, color: _kGreen, size: 54),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Bangla brand name
        const Text(
          'ভ্রমণ',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w700,
            color: _kWhite,
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: Colors.black45,
                offset: Offset(0, 3),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Decorative subtitle line
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DotLine(),
            SizedBox(width: 10),
            Text(
              'BHROMON',
              style: TextStyle(
                color: _kGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
              ),
            ),
            SizedBox(width: 10),
            _DotLine(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.translate('login_tagline'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kWhite,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _DotLine extends StatelessWidget {
  const _DotLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, _kGreen.withValues(alpha: .6)],
        ),
      ),
    );
  }
}

enum _AuthFormMode { options, emailSignIn, emailSignUp, emailSignUpOtp }

// ─── Sign-in form ───────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.loading});

  final bool loading;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _otpFormKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  _AuthFormMode _mode = _AuthFormMode.options;
  bool _obscurePassword = true;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _showTermsDialog(context);
    _privacyRecognizer = TapGestureRecognizer()..onTap = _openPrivacyPolicy;
  }

  Future<void> _openPrivacyPolicy() async {
    final Uri url = Uri.parse('https://bhromon.fun/privacy-policy.html');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch $url');
      }
    } catch (error, stackTrace) {
      logWarning('Login: could not open the privacy policy', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('auth_privacy_open_failed')),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  void _switchMode(_AuthFormMode mode) {
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = mode;
      if (mode != _AuthFormMode.emailSignUpOtp) {
        _otpController.clear();
      }
    });
  }

  void _submitEmailPassword() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    context.read<AuthCubit>().signInWithEmailPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _submitSendSignUpOtp() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    context.read<AuthCubit>().requestSignUpOtp(_emailController.text.trim());
  }

  void _submitVerifySignUpOtp() {
    final form = _otpFormKey.currentState;
    if (form == null || !form.validate()) return;
    context.read<AuthCubit>().registerWithEmailOtp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          otp: _otpController.text.trim(),
          displayName: _nameController.text.trim(),
        );
  }

  InputDecoration _emailFieldDecoration({
    required String label,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _kWhite54, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF111D15),
      prefixIcon: Icon(prefixIcon, color: _kGreen, size: 20),
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBorder, width: 1.3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1.3),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1.5),
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kCardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _kBorder, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: _kGreen),
            SizedBox(width: 10),
            Text(
              'Terms & Privacy Policy',
              style: TextStyle(
                  color: _kWhite, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const SizedBox(
          width: 400,
          height: 350,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to Bhromon, the app for every group you belong to in Bangladesh. By using this app, you agree to the following terms:',
                  style: TextStyle(color: _kWhite, fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 16),
                Text(
                  '1. Group Safety Disclaimer',
                  style: TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Bhromon helps your group share alerts, locations and notices. Alerts depend on signal, battery and the phones involved. In an emergency, contact local emergency services first. The SOS siren coordinates your group; it does not replace emergency services.',
                  style: TextStyle(color: _kWhite54, fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 16),
                Text(
                  '2. User Contributions & Trust Rating',
                  style: TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'When you post in a group, log a trip or add a note, you commit to providing accurate information. Spam or abusive posts violate community standards and can lead to removal from a group, a lower explorer score, or account suspension.',
                  style: TextStyle(color: _kWhite54, fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 16),
                Text(
                  '3. Location & Data Usage Policy',
                  style: TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'To deliver background safety notifications and map overlays, Bhromon accesses your location. Your coordinates are processed on-device and synced securely via SQLite and Firestore outboxes. We never share your physical history with third-party networks.',
                  style: TextStyle(color: _kWhite54, fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 16),
                Text(
                  '4. Revisions & Updates',
                  style: TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Terms may be updated periodically to match dynamic security patches. Continued use of the app signifies agreement with revised policies.',
                  style: TextStyle(color: _kWhite54, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (_, state) => state is AuthOtpSent,
      listener: (_, state) {
        if (state is AuthOtpSent && _mode != _AuthFormMode.emailSignIn) {
          setState(() => _mode = _AuthFormMode.emailSignUpOtp);
          _startResendCooldown();
        }
      },
      child: widget.loading
          ? const _LoadingView()
          : Column(
              key: const ValueKey('login_form'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _kGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Welcome Explorer',
                      style: TextStyle(
                        color: _kWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.translate('login_welcome_subtitle'),
                  style: const TextStyle(
                      color: _kWhite54, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                if (_mode == _AuthFormMode.options) ...[
                  _GoogleButton(
                    onTap: () {
                      context.read<AuthCubit>().signInWithGoogle();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                          child: Divider(color: _kBorder, height: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          l10n.translate('auth_or'),
                          style: const TextStyle(
                            color: _kWhite54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Expanded(
                          child: Divider(color: _kBorder, height: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SecondaryAuthButton(
                    key: const Key('login_open_email_signin_button'),
                    icon: Icons.email_outlined,
                    label: l10n.translate('auth_sign_in_with_email'),
                    onTap: () => _switchMode(_AuthFormMode.emailSignIn),
                  ),
                  const SizedBox(height: 12),
                  _SecondaryAuthButton(
                    key: const Key('login_open_create_account_button'),
                    icon: Icons.person_add_alt_1_outlined,
                    label: l10n.translate('auth_create_account'),
                    onTap: () => _switchMode(_AuthFormMode.emailSignUp),
                  ),
                ] else if (_mode == _AuthFormMode.emailSignIn) ...[
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('login_email_field'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          style: const TextStyle(color: _kWhite, fontSize: 15),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_email_label'),
                            prefixIcon: Icons.email_outlined,
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty || !v.contains('@')) {
                              return l10n.translate('auth_email_required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('login_password_field'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          style: const TextStyle(color: _kWhite, fontSize: 15),
                          onFieldSubmitted: (_) => _submitEmailPassword(),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_password_label'),
                            prefixIcon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: _kWhite54,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return l10n.translate('auth_password_required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            key: const Key('login_email_submit_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: _kBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _submitEmailPassword,
                            child: Text(
                              l10n.translate('auth_sign_in_button'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              _switchMode(_AuthFormMode.emailSignUp),
                          child: Text(
                            l10n.translate('auth_no_account_create'),
                            style:
                                const TextStyle(color: _kGreen, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _switchMode(_AuthFormMode.options),
                          child: Text(
                            l10n.translate('auth_back_to_options'),
                            style:
                                const TextStyle(color: _kWhite54, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_mode == _AuthFormMode.emailSignUp) ...[
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('signup_name_field'),
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          style: const TextStyle(color: _kWhite, fontSize: 15),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_full_name_label'),
                            prefixIcon: Icons.person_outline_rounded,
                          ),
                          validator: (value) {
                            if ((value?.trim() ?? '').isEmpty) {
                              return l10n.translate('auth_full_name_required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('signup_email_field'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          style: const TextStyle(color: _kWhite, fontSize: 15),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_email_label'),
                            prefixIcon: Icons.email_outlined,
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty || !v.contains('@')) {
                              return l10n.translate('auth_email_required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('signup_password_field'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          style: const TextStyle(color: _kWhite, fontSize: 15),
                          onFieldSubmitted: (_) => _submitSendSignUpOtp(),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_password_label'),
                            prefixIcon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: _kWhite54,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            final v = value ?? '';
                            if (v.isEmpty) {
                              return l10n.translate('auth_password_required');
                            }
                            if (v.length < 6) {
                              return l10n.translate('auth_password_min_length');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            key: const Key('signup_send_otp_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: _kBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _submitSendSignUpOtp,
                            child: Text(
                              l10n.translate('auth_send_verification_code'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              _switchMode(_AuthFormMode.emailSignIn),
                          child: Text(
                            l10n.translate('auth_have_account_sign_in'),
                            style:
                                const TextStyle(color: _kGreen, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _switchMode(_AuthFormMode.options),
                          child: Text(
                            l10n.translate('auth_back_to_options'),
                            style:
                                const TextStyle(color: _kWhite54, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Form(
                    key: _otpFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111D15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Text(
                            l10n.translate('auth_otp_sent_to').replaceAll(
                                  '{email}',
                                  _emailController.text.trim(),
                                ),
                            style: const TextStyle(
                                color: _kWhite, fontSize: 13, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('signup_otp_field'),
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onFieldSubmitted: (_) => _submitVerifySignUpOtp(),
                          style: const TextStyle(
                            color: _kWhite,
                            fontSize: 18,
                            letterSpacing: 6,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _emailFieldDecoration(
                            label: l10n.translate('auth_otp_label'),
                            prefixIcon: Icons.mark_email_read_outlined,
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                              return l10n.translate('auth_otp_required');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            key: const Key('signup_verify_otp_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: _kBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _submitVerifySignUpOtp,
                            child: Text(
                              l10n.translate('auth_verify_and_create'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                              key: const Key('signup_resend_otp_button'),
                              onPressed: _resendSeconds > 0
                                  ? null
                                  : () => context
                                      .read<AuthCubit>()
                                      .requestSignUpOtp(
                                          _emailController.text.trim()),
                              child: Text(
                                _resendSeconds > 0
                                    ? l10n
                                        .translate('auth_resend_in_seconds')
                                        .replaceAll(
                                            '{seconds}', '$_resendSeconds')
                                    : l10n.translate('auth_resend_code'),
                                style: TextStyle(
                                  color:
                                      _resendSeconds > 0 ? _kWhite30 : _kGreen,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _switchMode(_AuthFormMode.emailSignUp),
                              child: Text(
                                l10n.translate('auth_change_email'),
                                style: const TextStyle(
                                    color: _kWhite54, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Terms & Privacy statement
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'By continuing, you agree to our ',
                      style: const TextStyle(color: _kWhite54, fontSize: 12),
                      children: [
                        TextSpan(
                          text: 'Terms of Use',
                          style: const TextStyle(
                            color: _kGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: _termsRecognizer,
                        ),
                        const TextSpan(text: ' & '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                            color: _kGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: _privacyRecognizer,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SecondaryAuthButton extends StatelessWidget {
  const _SecondaryAuthButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF111D15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _kGreen, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading view ────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('loading'),
      height: 200,
      child: Center(
        child: CircularProgressIndicator(
          color: _kGreen,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GoogleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF111D15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: _kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

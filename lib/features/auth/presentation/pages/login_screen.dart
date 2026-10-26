import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/widgets/bouncy_button.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF050C08); // deepest dark green-black
const Color _kCardBg = Color(0xFF0D1A12); // dark card, fully opaque
const Color _kBorder = Color(0xFF1E3A26); // subtle border
const Color _kGreen = Color(0xFF52B788); // vibrant mint-green
const Color _kGreenDark = Color(0xFF1B4332);
const Color _kGold = Color(0xFFF4A261);
const Color _kWhite = Color(0xFFECF0F1);
const Color _kWhite54 = Color(0x8AECF0F1);
const Color _kWhite30 = Color(0x4DECF0F1);

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
    context.read<AuthCubit>().checkAuthStatus();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/feed');
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: BlocConsumer<AuthCubit, AuthState>(
          listener: (ctx, state) {
            if (state is Authenticated) {
              ctx.go('/feed');
            }
            if (state is AuthError) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(child: Text(state.message)),
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
                                      fontSize: 11,
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: state is AuthLoading ? const _LoadingView() : const _LoginForm(),
      ),
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
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kCardBg,
              border:
                  Border.all(color: _kGreen.withValues(alpha: .35), width: 2),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.explore, color: _kGreen, size: 54),
              ),
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
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 5,
              ),
            ),
            SizedBox(width: 10),
            _DotLine(),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'পথ যেখানে গল্প বলে',
          textAlign: TextAlign.center,
          style: TextStyle(
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

// ─── Google form ────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open Privacy Policy: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
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
                  'Welcome to Bhromon, your offline-first travel companion in Bangladesh. By using this app, you agree to the following terms:',
                  style: TextStyle(color: _kWhite, fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 16),
                Text(
                  '1. Outdoor Trekking Safety Disclaimer',
                  style: TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Bhromon provides offline GPS assistance and hazard maps. However, outdoor terrains, especially in hilly zones like Sajek or Bandarban, are highly unpredictable. Always prioritize local directives and physical assessments over app-indicated routes.',
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
                  'When you log a trip or suggest pins, you commit to providing accurate information. Malicious pins or spam updates violate community standards and will result in a decrease of your explorer score or account suspension.',
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
    return Column(
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
        const Text(
          'Sign in with Google to explore Bangladesh, coordinate tour groups, and share verified journey logs.',
          style: TextStyle(color: _kWhite54, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 28),

        // Google button
        _GoogleButton(
          onTap: () {
            context.read<AuthCubit>().signInWithGoogle();
          },
        ),

        const SizedBox(height: 24),

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
          borderRadius: BorderRadius.circular(14),
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

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ─── URL constants ────────────────────────────────────────────────────────────
const String _kTermsUrl = 'https://bhromon.com/terms';
const String _kPrivacyUrl = 'https://bhromon.com/privacy';

// ─── Brand colours ────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF050C08);
const Color _kGreen = Color(0xFF52B788);
const Color _kWhite = Color(0xFFECF0F1);
const Color _kWhite54 = Color(0x8AECF0F1);
const Color _kCardBg = Color(0xFF0D1A12);

/// Full-screen Terms of Service / Privacy Policy viewer.
///
/// Push this page before completing sign-up. Pop returns `true` if the user
/// tapped "I Accept", or `false`/`null` if they navigated back.
///
/// Usage:
/// ```dart
/// final accepted = await Navigator.push<bool>(
///   context,
///   MaterialPageRoute(builder: (_) => const TermsPage()),
/// );
/// ```
class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _tosLoading = true;
  bool _ppLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCardBg,
        foregroundColor: _kWhite,
        title: const Text(
          'Legal',
          style: TextStyle(
            color: _kWhite,
            fontWeight: FontWeight.w600,
            letterSpacing: .4,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kGreen,
          unselectedLabelColor: _kWhite54,
          indicatorColor: _kGreen,
          tabs: const [
            Tab(text: 'Terms of Service'),
            Tab(text: 'Privacy Policy'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── WebView tabs ────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _WebTab(
                  url: _kTermsUrl,
                  isLoading: _tosLoading,
                  onLoadStart: () => setState(() => _tosLoading = true),
                  onLoadStop: () => setState(() => _tosLoading = false),
                ),
                _WebTab(
                  url: _kPrivacyUrl,
                  isLoading: _ppLoading,
                  onLoadStart: () => setState(() => _ppLoading = true),
                  onLoadStop: () => setState(() => _ppLoading = false),
                ),
              ],
            ),
          ),

          // ── Accept button ───────────────────────────────────────────────
          _AcceptBar(
            onAccept: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}

// ─── Internal widgets ─────────────────────────────────────────────────────────

class _WebTab extends StatelessWidget {
  const _WebTab({
    required this.url,
    required this.isLoading,
    required this.onLoadStart,
    required this.onLoadStop,
  });

  final String url;
  final bool isLoading;
  final VoidCallback onLoadStart;
  final VoidCallback onLoadStop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: Uri.parse(url)),
          initialOptions: InAppWebViewGroupOptions(
            crossPlatform: InAppWebViewOptions(
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              transparentBackground: true,
            ),
          ),
          onLoadStart: (controller, url) => onLoadStart(),
          onLoadStop: (controller, url) => onLoadStop(),
          onLoadError: (controller, url, code, message) => onLoadStop(),
        ),
        if (isLoading)
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
            ),
          ),
      ],
    );
  }
}

class _AcceptBar extends StatelessWidget {
  const _AcceptBar({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kCardBg,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'By tapping "I Accept" you agree to the Terms of Service and '
            'Privacy Policy above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kWhite54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: const Color(0xFF050C08),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onAccept,
            child: const Text(
              'I Accept',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

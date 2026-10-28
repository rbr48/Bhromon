import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/colors.dart';
import '../../domain/models/newspaper_models.dart';
import 'adfree_article_reader_screen.dart';

/// Ad-Free and Ad-Blocker Enabled In-App Web Browser for reading newspapers
/// without annoying popups, video ads, or banner clutter.
class AdBlockBrowserScreen extends StatefulWidget {
  final String initialUrl;
  final String? initialTitle;
  final Newspaper? paper;

  const AdBlockBrowserScreen({
    super.key,
    required this.initialUrl,
    this.initialTitle,
    this.paper,
  });

  @override
  State<AdBlockBrowserScreen> createState() => _AdBlockBrowserScreenState();
}

class _AdBlockBrowserScreenState extends State<AdBlockBrowserScreen> {
  InAppWebViewController? _webViewController;
  late String _currentUrl;
  final List<String> _historyStack = [];
  String _pageTitle = '';
  double _progress = 0;
  bool _isLoading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isAdBlockEnabled = true;
  bool _isDesktopMode = false;
  int _blockedAdsCount = 0;
  bool _hasLoadError = false;
  Timer? _adCleanupTimer;

  String get _effectiveUrl {
    if (kIsWeb) {
      // Route through our VPS Ad-Free and frame-unrestricted proxy
      return 'https://bhromon.fun/api/news/proxy?url=${Uri.encodeComponent(_currentUrl)}';
    }
    return _currentUrl;
  }

  final TextEditingController _urlInputCtrl = TextEditingController();

  // Injected CSS Cosmetic Filtering to strip banners, overlays and interstitials
  static const String _adBlockCss = '''
    html, body {
      background-color: #ffffff !important;
      color: #111111 !important;
    }
    .ads, .ad, .ad-banner, .advertisement, .ad-container, .ad-wrapper,
    .ad-box, .ad-slot, .ad-placeholder, .adsbygoogle, [id^="google_ads_"],
    [id^="div-gpt-ad"], iframe[src*="doubleclick"], iframe[src*="adservice"],
    iframe[src*="googlesyndication"], .taboola, .outbrain, .interstitial-ad,
    .sticky-ad, .floating-ad, .popup-overlay, .ad-flyout, #leaderboard-ad,
    .top-ad, .bottom-sticky-ad, .modal-ad, [class*="advertisement"],
    [class*="ad-unit"], [id*="ad_holder"], [id*="ad-container"],
    .ads-placeholder, [aria-label*="advertisement" i], .native-ad-unit {
      display: none !important;
      visibility: hidden !important;
      height: 0 !important;
      width: 0 !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
  ''';

  // Injected JS to remove ad elements and prevent popup windows
  static const String _adBlockJs = '''
    (function() {
      // Suppress unrequested popup windows
      window.open = function(url) {
        console.log('[AdBlock] Blocked popup window:', url);
        return null;
      };

      function removeAds() {
        var count = 0;
        var adSelectors = [
          '.ads', '.ad-banner', '.advertisement', '.adsbygoogle',
          'iframe[src*="doubleclick"]', 'iframe[src*="adservice"]',
          'iframe[src*="googlesyndication"]', '[id^="google_ads_"]',
          '[id^="div-gpt-ad"]', '.taboola', '.outbrain', '.interstitial-ad',
          '.sticky-ad', '.floating-ad', '.popup-overlay'
        ];
        
        adSelectors.forEach(function(sel) {
          try {
            var els = document.querySelectorAll(sel);
            els.forEach(function(el) {
              el.remove();
              count++;
            });
          } catch(e) {}
        });

        if (window.flutter_inappwebview && count > 0) {
          window.flutter_inappwebview.callHandler('onAdsBlocked', count);
        }
      }

      // Initial cleanup
      removeAds();

      // Observe dynamic insertions (mutation observer)
      var observer = new MutationObserver(function(mutations) {
        removeAds();
      });
      observer.observe(document.body || document.documentElement, {
        childList: true,
        subtree: true
      });
    })();
  ''';

  // ContentBlocker rules for network-level ad domain blocking
  List<ContentBlocker> get _contentBlockers => [
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter:
                '.*(doubleclick|googleadservices|googlesyndication|adservice|taboola|outbrain|criteo|adnxs|pubmatic|rubiconproject|casalemedia|scorecardresearch|smartadserver|adroll|popads|adcash|exponential|inmobi|adcolony|chartbeat|mgid|revcontent).*',
          ),
          action: ContentBlockerAction(
            type: ContentBlockerActionType.BLOCK,
          ),
        ),
      ];

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _historyStack.add(widget.initialUrl);
    _pageTitle = widget.initialTitle ?? widget.paper?.name ?? 'Web Browser';
    _urlInputCtrl.text = _currentUrl;
  }

  void _pushHistory(String url) {
    if (url.isEmpty || url.startsWith('about:')) return;
    if (_historyStack.isEmpty || _historyStack.last != url) {
      _historyStack.add(url);
    }
    if (mounted) {
      setState(() {
        _canGoBack = _historyStack.length > 1;
      });
    }
  }

  Future<void> _handleBackPress() async {
    // 1. Try native webview controller if supported (mobile)
    if (!kIsWeb) {
      final controller = _webViewController;
      if (controller != null && await controller.canGoBack()) {
        await controller.goBack();
        return;
      }
    }

    // 2. Fall back to internal history stack (web + mobile fallback)
    if (_historyStack.length > 1) {
      _historyStack.removeLast(); // pop current page
      final prev = _historyStack.last;
      setState(() {
        _currentUrl = prev;
        _canGoBack = _historyStack.length > 1;
        _isLoading = true;
      });
      final targetToLoad = _effectiveUrl;
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(targetToLoad)),
      );
      return;
    }

    // 3. At initial page: exit back to Newspaper Hub
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _adCleanupTimer?.cancel();
    _urlInputCtrl.dispose();
    super.dispose();
  }

  void _triggerAdCleanup() {
    if (!_isAdBlockEnabled || _webViewController == null) return;
    _webViewController?.injectCSSCode(source: _adBlockCss);
    _webViewController?.evaluateJavascript(source: _adBlockJs);
  }

  String _cleanDisplayUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return url;
    }
  }

  void _loadUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.contains('.') && !url.contains(' ')) {
        url = 'https://$url';
      } else {
        url = 'https://www.google.com/search?q=${Uri.encodeComponent(url)}';
      }
    }

    setState(() {
      _currentUrl = url;
      _pushHistory(url);
      _blockedAdsCount = 0;
      _hasLoadError = false;
    });

    final targetToLoad = _effectiveUrl;
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetToLoad)));
  }

  void _openInReaderMode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdFreeArticleReaderScreen(
          articleUrl: _currentUrl,
        ),
      ),
    );
  }

  void _toggleAdBlock() {
    setState(() {
      _isAdBlockEnabled = !_isAdBlockEnabled;
    });

    if (_isAdBlockEnabled) {
      _triggerAdCleanup();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛡️ AdBlock Enabled — Clean & ad-free browsing active'),
          backgroundColor: Color(0xFF1B4332),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ AdBlock Disabled for this session'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
      _webViewController?.reload();
    }
  }

  void _toggleDesktopMode() async {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
    });

    final settings = await _webViewController?.getSettings();
    if (settings != null) {
      settings.preferredContentMode = _isDesktopMode
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.MOBILE;
      settings.userAgent = _isDesktopMode
          ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
          : '';
      await _webViewController?.setSettings(settings: settings);
      _webViewController?.reload();
    }
  }

  void _showShieldInfoDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14181E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isAdBlockEnabled
                            ? AppColors.mintGreen.withValues(alpha: 0.15)
                            : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shield_rounded,
                        color: _isAdBlockEnabled
                            ? AppColors.mintGreen
                            : Colors.white54,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAdBlockEnabled
                                ? 'AdBlock Shield Active'
                                : 'AdBlock Paused',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isAdBlockEnabled
                                ? '$_blockedAdsCount ads & trackers stripped'
                                : 'Ads are currently shown on this page',
                            style: TextStyle(
                              color: _isAdBlockEnabled
                                  ? AppColors.mintGreen
                                  : Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isAdBlockEnabled,
                      activeThumbColor: AppColors.mintGreen,
                      onChanged: (val) {
                        Navigator.pop(ctx);
                        _toggleAdBlock();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                _buildShieldFeatureRow(
                  Icons.block_rounded,
                  'Banner & Video Ad Blocking',
                  'Removes Google AdSense, DoubleClick, Taboola, and Outbrain networks.',
                ),
                const SizedBox(height: 10),
                _buildShieldFeatureRow(
                  Icons.layers_clear_rounded,
                  'Cosmetic Element Hiding',
                  'Cleans up sticky bottom ads, popups, and floating modal takeovers.',
                ),
                const SizedBox(height: 10),
                _buildShieldFeatureRow(
                  Icons.speed_rounded,
                  'Fast & Data Saving',
                  'Saves bandwidth by stopping heavy media scripts from downloading.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B232D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.chrome_reader_mode_rounded,
                        color: AppColors.mintGreen, size: 18),
                    label: const Text(
                      'Open in Distraction-Free Text Reader',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openInReaderMode();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShieldFeatureRow(
      IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.mintGreen, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanHost = _cleanDisplayUrl(_currentUrl);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1216),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: AppBar(
            backgroundColor: const Color(0xFF14181E),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: _handleBackPress,
            ),
          titleSpacing: 0,
          title: Container(
            height: 38,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isAdBlockEnabled
                    ? AppColors.mintGreen.withValues(alpha: 0.35)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    color: AppColors.mintGreen, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cleanHost.isNotEmpty ? cleanHost : _currentUrl,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Shield Badge Button
                GestureDetector(
                  onTap: _showShieldInfoDialog,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isAdBlockEnabled
                          ? AppColors.mintGreen.withValues(alpha: 0.18)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          color: _isAdBlockEnabled
                              ? AppColors.mintGreen
                              : Colors.white38,
                          size: 13,
                        ),
                        if (_blockedAdsCount > 0) ...[
                          const SizedBox(width: 3),
                          Text(
                            '$_blockedAdsCount',
                            style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Prominent Clean Reader Mode button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: const Color(0xFF0F1E14),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.chrome_reader_mode_rounded, size: 14),
                label: const Text(
                  'Reader',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _openInReaderMode,
              ),
            ),
            const SizedBox(width: 2),
            // Popup Menu with additional options
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white70, size: 20),
              color: const Color(0xFF1B232D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (val) {
                switch (val) {
                  case 'adblock':
                    _showShieldInfoDialog();
                    break;
                  case 'desktop':
                    _toggleDesktopMode();
                    break;
                  case 'reader':
                    _openInReaderMode();
                    break;
                  case 'share':
                    SharePlus.instance.share(
                      ShareParams(
                        text: _currentUrl,
                        subject: _pageTitle,
                      ),
                    );
                    break;
                  case 'external':
                    launchUrl(Uri.parse(_currentUrl),
                        mode: LaunchMode.externalApplication);
                    break;
                  case 'copy':
                    Clipboard.setData(ClipboardData(text: _currentUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied to clipboard')),
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'adblock',
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: AppColors.mintGreen, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _isAdBlockEnabled ? 'AdBlock Settings' : 'Enable AdBlock',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reader',
                  child: Row(
                    children: [
                      Icon(Icons.article_outlined,
                          color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text(
                        'Distraction-Free Reader',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'desktop',
                  child: Row(
                    children: [
                      Icon(
                        _isDesktopMode
                            ? Icons.phone_android_rounded
                            : Icons.desktop_windows_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isDesktopMode ? 'Mobile View' : 'Desktop View',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 1),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text('Share Link',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text('Copy URL',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'external',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser_rounded,
                          color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text('Open in System Browser',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Loading Progress Bar
          if (_isLoading)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
              minHeight: 2.5,
            ),

          // Main Web Browser View
          Expanded(
            child: _hasLoadError
                ? _buildWebFallback()
                : Container(
                    color: Colors.white,
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_effectiveUrl)),
                      initialSettings: InAppWebViewSettings(
                        transparentBackground: false,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        useWideViewPort: true,
                        loadWithOverviewMode: true,
                        contentBlockers:
                            (!kIsWeb && _isAdBlockEnabled) ? _contentBlockers : null,
                        userAgent: _isDesktopMode
                            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                            : '',
                      ),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        // JS Handler for blocked ads reporting
                        controller.addJavaScriptHandler(
                          handlerName: 'onAdsBlocked',
                          callback: (args) {
                            if (args.isNotEmpty && args[0] is int) {
                              if (mounted) {
                                setState(() {
                                  _blockedAdsCount += (args[0] as int);
                                });
                              }
                            }
                          },
                        );
                      },
                      onLoadStart: (controller, url) {
                        if (mounted) {
                          final urlStr = url?.toString() ?? _currentUrl;
                          String resolved = urlStr;
                          if (urlStr.contains('/api/news/proxy?url=')) {
                            final uri = Uri.parse(urlStr);
                            final orig = uri.queryParameters['url'];
                            if (orig != null && orig.isNotEmpty) {
                              resolved = orig;
                            }
                          }
                          setState(() {
                            _isLoading = true;
                            _hasLoadError = false;
                            _currentUrl = resolved;
                          });
                          _pushHistory(resolved);
                        }
                        if (_isAdBlockEnabled) {
                          controller.injectCSSCode(source: _adBlockCss);
                        }
                      },
                      onProgressChanged: (controller, progress) {
                        if (mounted) {
                          setState(() {
                            _progress = progress / 100;
                          });
                        }
                        if (_isAdBlockEnabled && progress > 30) {
                          _triggerAdCleanup();
                        }
                      },
                      onLoadStop: (controller, url) async {
                        if (mounted) {
                          bool canBack = false;
                          bool canFwd = false;
                          if (!kIsWeb) {
                            canBack = await controller.canGoBack();
                            canFwd = await controller.canGoForward();
                          }
                          final title = await controller.getTitle();
                          final urlStr = url?.toString() ?? _currentUrl;
                          String resolved = urlStr;
                          if (urlStr.contains('/api/news/proxy?url=')) {
                            final uri = Uri.parse(urlStr);
                            final orig = uri.queryParameters['url'];
                            if (orig != null && orig.isNotEmpty) {
                              resolved = orig;
                            }
                          }
                          _pushHistory(resolved);
                          setState(() {
                            _isLoading = false;
                            _canGoBack = canBack || _historyStack.length > 1;
                            _canGoForward = canFwd;
                            if (title != null && title.isNotEmpty) {
                              _pageTitle = title;
                            }
                            _currentUrl = resolved;
                          });
                        }
                        if (_isAdBlockEnabled) {
                          _triggerAdCleanup();
                        }
                      },
                      onReceivedError: (controller, request, error) {
                        if (mounted) {
                          setState(() {
                            _isLoading = false;
                            if (kIsWeb) {
                              _hasLoadError = true;
                            }
                          });
                        }
                      },
                      onReceivedHttpError: (controller, request, errorResponse) {
                        if (mounted && (errorResponse.statusCode ?? 0) >= 400) {
                          setState(() {
                            _isLoading = false;
                            if (kIsWeb) {
                              _hasLoadError = true;
                            }
                          });
                        }
                      },
                    ),
                  ),
          ),

          // Bottom Browser Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF14181E),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
                  color: _canGoBack ? Colors.white : Colors.white24,
                  onPressed: _canGoBack ? _handleBackPress : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  color: _canGoForward ? Colors.white : Colors.white24,
                  onPressed: _canGoForward
                      ? () => _webViewController?.goForward()
                      : null,
                ),
                IconButton(
                  icon: Icon(
                    _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    if (_isLoading) {
                      _webViewController?.stopLoading();
                    } else {
                      _webViewController?.reload();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.home_outlined,
                      color: Colors.white70, size: 20),
                  tooltip: 'Newspaper Front Page',
                  onPressed: () {
                    if (widget.paper != null &&
                        widget.paper!.websiteUrl.isNotEmpty) {
                      _loadUrl(widget.paper!.websiteUrl);
                    } else {
                      _loadUrl(widget.initialUrl);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined,
                      color: Colors.white70, size: 19),
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: _currentUrl,
                        subject: _pageTitle,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildWebFallback() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF14181E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.public_rounded,
                  color: AppColors.mintGreen, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              _pageTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _cleanDisplayUrl(_currentUrl),
              style: const TextStyle(color: AppColors.mintGreen, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'To bypass external web security headers (X-Frame-Options) on browser platforms, you can read this newspaper in Clean Distraction-Free Reader mode, or launch in a dedicated tab.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: const Color(0xFF0F1E14),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.chrome_reader_mode_rounded, size: 18),
                    label: const Text('Clean Reader',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _openInReaderMode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open Website'),
                    onPressed: () => launchUrl(Uri.parse(_currentUrl),
                        mode: LaunchMode.externalApplication),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/active_group.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/invite_code.dart';

/// Direct group invitation and join landing screen.
/// Supports deep-linking and browser navigation via `/join/:code`.
class JoinGroupScreen extends StatefulWidget {
  final String inviteCode;
  final bool autoJoin;
  final TourGroupRepository? repository;

  const JoinGroupScreen({
    super.key,
    required this.inviteCode,
    this.autoJoin = false,
    this.repository,
  });

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  late final TourGroupRepository _repo;
  bool _isLoading = false;
  String? _errorMessage;
  TourGroup? _joinedGroup;
  bool _autoJoinTriggered = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? TourGroupRepository();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authState = context.read<AuthCubit>().state;
      if (authState is Authenticated &&
          widget.autoJoin &&
          !_autoJoinTriggered) {
        _autoJoinTriggered = true;
        _handleJoin();
      }
    });
  }

  String get _normalizedCode => widget.inviteCode.trim().toUpperCase();

  bool get _isCodeFormatValid =>
      _normalizedCode.isNotEmpty && isValidInviteCode(_normalizedCode);

  Future<void> _handleJoin() async {
    final l10n = context.l10n;
    final authState = context.read<AuthCubit>().state;

    if (authState is! Authenticated) {
      final target = '/join/$_normalizedCode?auto=true';
      try {
        context.go('/login?redirect=${Uri.encodeComponent(target)}');
      } catch (_) {}
      return;
    }

    if (!_isCodeFormatValid) {
      setState(() {
        _errorMessage = l10n.translate('hub_join_invalid_code');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final joined = await _repo.joinGroupWithCode(_normalizedCode);
      try {
        await ActiveGroup.instance.select(joined.id);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _joinedGroup = joined;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(l10n.translate('hub_joined', args: {'name': joined.name})),
          backgroundColor: AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Smooth auto-transition to group channels after confirmation
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      try {
        context.go('/group/${joined.id}/channels');
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is FormatException ? e.message : e.toString();
      });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _normalizedCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: context.forest.accentText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.translate('hub_invite_code_copied',
                    args: {'code': _normalizedCode}),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: context.forest.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyInviteLink() {
    final link = 'https://app.bhromon.fun/#/join/$_normalizedCode';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.link_rounded,
                color: context.forest.accentText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.translate('hub_invite_link_copied'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: context.forest.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final authState = context.watch<AuthCubit>().state;
    final isAuthenticated = authState is Authenticated;

    return Scaffold(
      backgroundColor: context.forest.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.forest.text70),
          onPressed: () {
            try {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            } catch (_) {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Brand Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.mintGreen.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.explore_rounded,
                          color: AppColors.mintGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bhromon',
                            style: TextStyle(
                              color: context.forest.text,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Travel with life',
                            style: TextStyle(
                              color: context.forest.text54,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Main Invitation Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.forest.card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _joinedGroup != null
                            ? AppColors.mintGreen
                            : context.forest.divider10,
                        width: _joinedGroup != null ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Badge Icon
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _joinedGroup != null
                                ? AppColors.mintGreen.withValues(alpha: 0.2)
                                : context.forest
                                    .surfaceFor(const Color(0xFF1D3B2A)),
                            border: Border.all(
                              color: _joinedGroup != null
                                  ? AppColors.mintGreen
                                  : context.forest.divider12,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: _joinedGroup != null
                                ? const Icon(Icons.check_circle_rounded,
                                    size: 38, color: AppColors.mintGreen)
                                : const Icon(Icons.group_add_rounded,
                                    size: 34, color: AppColors.mintGreen),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Invitation Title
                        Text(
                          _joinedGroup != null
                              ? l10n.translate('hub_join_success_title')
                              : l10n.translate('hub_join_invitation_title'),
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          _joinedGroup != null
                              ? l10n.translate('hub_join_success_subtitle',
                                  args: {'name': _joinedGroup!.name})
                              : l10n.translate('hub_join_invitation_subtitle'),
                          style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Invite Code Container
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: context.forest
                                .surfaceFor(const Color(0xFF102117)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.forest.divider10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.translate('hub_join_code_label'),
                                    style: TextStyle(
                                      color: context.forest.text54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _normalizedCode.isNotEmpty
                                        ? _normalizedCode
                                        : '--------',
                                    style: TextStyle(
                                      color: _isCodeFormatValid
                                          ? AppColors.mintGreen
                                          : Colors.redAccent,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.copy_rounded,
                                        size: 18, color: context.forest.text70),
                                    tooltip:
                                        isBn ? 'কোড কপি করুন' : 'Copy Code',
                                    onPressed: _normalizedCode.isNotEmpty
                                        ? _copyCode
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.link_rounded,
                                        size: 20, color: context.forest.text70),
                                    tooltip: isBn
                                        ? 'ইনভাইট লিংক কপি করুন'
                                        : 'Copy Invite Link',
                                    onPressed: _normalizedCode.isNotEmpty
                                        ? _copyInviteLink
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // User account state badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isAuthenticated
                                ? AppColors.mintGreen.withValues(alpha: 0.08)
                                : Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isAuthenticated
                                  ? AppColors.mintGreen.withValues(alpha: 0.25)
                                  : Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAuthenticated
                                    ? Icons.account_circle_rounded
                                    : Icons.info_outline_rounded,
                                size: 15,
                                color: isAuthenticated
                                    ? AppColors.mintGreen
                                    : Colors.amberAccent,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  isAuthenticated
                                      ? (isBn
                                          ? 'লগইন আছেন: ${_repo.currentEmail}'
                                          : 'Signed in: ${_repo.currentEmail}')
                                      : l10n.translate(
                                          'hub_join_sign_in_required'),
                                  style: TextStyle(
                                    color: isAuthenticated
                                        ? context.forest.text
                                        : Colors.amberAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Error message
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 18, color: Colors.redAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Action Buttons
                        if (_joinedGroup != null) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.mintGreen,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 18),
                              label: Text(
                                l10n.translate('hub_join_enter_group'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                try {
                                  context.go(
                                      '/group/${_joinedGroup!.id}/channels');
                                } catch (_) {}
                              },
                            ),
                          ),
                        ] else if (!isAuthenticated) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.midGreen,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: Text(
                                l10n.translate('hub_join_sign_in_button'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                final target =
                                    '/join/$_normalizedCode?auto=true';
                                try {
                                  context.go(
                                      '/login?redirect=${Uri.encodeComponent(target)}');
                                } catch (_) {}
                              },
                            ),
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.mintGreen,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_rounded,
                                      size: 18),
                              label: Text(
                                _isLoading
                                    ? l10n.translate('hub_join_joining')
                                    : l10n.translate('hub_join_confirm_button'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _isLoading ? null : _handleJoin,
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Secondary Action: Go to Hub
                        TextButton(
                          onPressed: () {
                            try {
                              context.go('/group-hub');
                            } catch (_) {
                              Navigator.of(context).maybePop();
                            }
                          },
                          child: Text(
                            l10n.translate('hub_join_back_to_hub'),
                            style: TextStyle(
                              color: context.forest.text54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

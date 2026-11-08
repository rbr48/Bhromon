import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/utils/logger.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/chat/data/e2ee/e2ee_chat_controller.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_service.dart';
import 'package:bhromon/features/chat/domain/e2ee/peer_key_state.dart';
import 'package:bhromon/features/chat/domain/e2ee/safety_number.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr/qr.dart';

/// The safety number of one contact, to compare in person or on a call, and the
/// encryption setup of this device (E2EE_DESIGN.md, sections 6 and 9).
///
/// Nothing here changes a key without the user's own tap. A changed identity is
/// shown as a warning, and the chat keeps working until the user decides.
class E2eeVerificationScreen extends StatefulWidget {
  const E2eeVerificationScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
    this.service,
  });

  /// The contact whose safety number this shows.
  final String otherUid;
  final String otherName;

  /// The service to use. By default, the signed-in user's own.
  final E2eeService? service;

  @override
  State<E2eeVerificationScreen> createState() => _E2eeVerificationScreenState();
}

class _E2eeVerificationScreenState extends State<E2eeVerificationScreen> {
  E2eeService? _service;
  E2eeSetupStatus? _status;
  PeerKeyState _peer = const PeerKeyState();
  String? _number;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? _signedInService();
    unawaited(_load());
  }

  E2eeService? _signedInService() {
    final authState = context.read<AuthCubit>().state;
    final uid = authState is Authenticated ? authState.profile.uid : '';
    return E2eeChatController.instance.serviceFor(uid);
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final status = await service.status();
      final peer = await service.peerState(widget.otherUid);
      String? number;
      if (status == E2eeSetupStatus.ready && peer.pinned != null) {
        number = await service.safetyNumber(
          widget.otherUid,
          pending: peer.hasChange,
        );
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _peer = peer;
        _number = number;
        _loaded = true;
      });
    } catch (error, stackTrace) {
      logWarning('Could not load the safety number', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _message = context.l10n.translate('e2ee_setup_failed');
      });
    }
  }

  /// Runs one action, then shows the state it left behind.
  Future<void> _run(Future<void> Function(E2eeService service) action) async {
    final service = _service;
    if (service == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(service);
    } catch (error, stackTrace) {
      logWarning('Encryption action failed', error, stackTrace);
      if (mounted) {
        setState(() => _message = context.l10n.translate('e2ee_setup_failed'));
      }
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _confirmSetUp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          title: Text(l10n.translate('e2ee_setup_confirm_title')),
          content: Text(l10n.translate('e2ee_setup_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.translate('e2ee_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.translate('e2ee_setup_action')),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _run((service) => service.setUpThisDevice());
    }
  }

  Future<void> _markVerified() {
    return _run((service) async {
      final identity = _peer.hasChange ? _peer.pending : _peer.pinned;
      if (identity == null) return;
      await service.markVerified(widget.otherUid, identity.identityBlock);
    });
  }

  Future<void> _trustNewKey() {
    return _run((service) async {
      await service.acceptKeyChange(widget.otherUid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final Widget body;
    if (!_loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_service == null) {
      body = _Notice(text: l10n.translate('e2ee_unavailable'));
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: _content(context),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('e2ee_verify_title'))),
      body: body,
    );
  }

  List<Widget> _content(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.chat;
    final status = _status;
    final children = <Widget>[];

    if (status != null && status != E2eeSetupStatus.ready) {
      children.add(
        _Card(
          title: l10n.translate('e2ee_setup_title'),
          body: l10n.translate('e2ee_setup_body'),
          action: FilledButton(
            key: const Key('setUpHere'),
            onPressed: _busy ? null : _confirmSetUp,
            child: Text(l10n.translate('e2ee_setup_action')),
          ),
        ),
      );
    }

    if (status == E2eeSetupStatus.ready && _peer.hasChange) {
      children.add(
        _Card(
          title: l10n.translate('e2ee_key_changed_title'),
          body: l10n.translate(
            'e2ee_key_changed_body',
            args: {'name': widget.otherName},
          ),
          action: OutlinedButton(
            key: const Key('trustNewKey'),
            onPressed: _busy ? null : _trustNewKey,
            child: Text(l10n.translate('e2ee_trust_new_key')),
          ),
        ),
      );
    }

    if (status == E2eeSetupStatus.ready) {
      final shown = _peer.hasChange ? _peer.pending : _peer.pinned;
      final verified =
          shown != null && _peer.verifiedFingerprint == shown.fingerprint;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            l10n.translate('e2ee_verify_intro',
                args: {'name': widget.otherName}),
            style: TextStyle(color: palette.text70, fontSize: 14),
          ),
        ),
      );
      final number = _number;
      if (number == null) {
        children.add(_Notice(
          text: l10n.translate(
            'e2ee_verify_no_number',
            args: {'name': widget.otherName},
          ),
        ));
      } else {
        children.add(
          Text(
            SafetyNumber.grouped(number),
            key: const Key('safetyNumber'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 1.2,
            ),
          ),
        );
        children.add(const SizedBox(height: 16));
        children.add(Center(child: _SafetyQr(digits: number)));
        children.add(const SizedBox(height: 16));
        children.add(
          Row(
            children: [
              Icon(
                verified
                    ? Icons.verified_user_outlined
                    : Icons.gpp_maybe_outlined,
                size: 18,
                color: palette.text70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate(
                    verified ? 'e2ee_verified' : 'e2ee_not_verified',
                  ),
                  key: const Key('verificationState'),
                  style: TextStyle(color: palette.text, fontSize: 15),
                ),
              ),
            ],
          ),
        );
        if (!verified) {
          children.add(const SizedBox(height: 12));
          children.add(
            FilledButton(
              key: const Key('markVerified'),
              onPressed: _busy ? null : _markVerified,
              child: Text(l10n.translate('e2ee_mark_verified')),
            ),
          );
        }
      }
    }

    if (_message != null) {
      children.add(const SizedBox(height: 16));
      children.add(
        Text(
          _message!,
          key: const Key('verificationMessage'),
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    return children;
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, required this.action});

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final palette = context.chat;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: palette.text70, fontSize: 14)),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.chat.text70, fontSize: 14),
      ),
    );
  }
}

/// The digits as a QR code, black on white with a quiet zone, so a second phone can
/// read it.
class _SafetyQr extends StatelessWidget {
  const _SafetyQr({required this.digits});

  final String digits;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode.fromData(data: digits, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    return SizedBox.square(
      dimension: 220,
      child: CustomPaint(painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  static const int _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final modules = image.moduleCount;
    final cell = size.width / (modules + 2 * _quietZone);
    final dark = Paint()..color = Colors.black;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (col + _quietZone) * cell,
              (row + _quietZone) * cell,
              cell,
              cell,
            ),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}

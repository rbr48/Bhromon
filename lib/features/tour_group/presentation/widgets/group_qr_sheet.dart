import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/invite_join_link.dart';
import '../tour_pdf_download.dart';
import 'invite_qr_code.dart';

/// The file name of a join code picture, when it is saved or shared.
const String kJoinQrFileName = 'bhromon_join_qr.png';

/// Shows a group's join code as a QR code to any member. The picture can be shared (saved on the
/// web), and the link can be copied. The code is the group's current one, so a renewed code shows
/// here at once.
Future<void> showGroupQrSheet(BuildContext context, TourGroup group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _GroupQrSheet(group: group),
  );
}

class _GroupQrSheet extends StatefulWidget {
  final TourGroup group;

  const _GroupQrSheet({required this.group});

  @override
  State<_GroupQrSheet> createState() => _GroupQrSheetState();
}

class _GroupQrSheetState extends State<_GroupQrSheet> {
  /// The outcome of the last action. It is shown inside the sheet, because a snackbar would appear
  /// behind the sheet.
  String? _message;
  bool _busy = false;

  String get _link => inviteJoinLink(widget.group.inviteCode);

  void _say(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _link));
    _say(context.l10n.translate('hub_invite_link_copied'));
  }

  Future<void> _shareOrSave() async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final png = await renderInviteQrPng(_link);
      if (kIsWeb) {
        await downloadWebFile(png, kJoinQrFileName, mimeType: 'image/png');
        _say(l10n.translate('hub_group_qr_saved'));
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                png,
                mimeType: 'image/png',
                name: kJoinQrFileName,
              ),
            ],
            fileNameOverrides: const [kJoinQrFileName],
            text: l10n.translate(
              'hub_group_qr_share_text',
              args: {'name': widget.group.name, 'link': _link},
            ),
          ),
        );
      }
    } catch (error, stack) {
      logError('Group QR share failed: $error\n$stack');
      _say(l10n.translate('hub_group_qr_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final f = context.forest;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.group.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: f.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.translate('hub_group_qr_title'),
              textAlign: TextAlign.center,
              style: TextStyle(color: f.text70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            // The white card keeps the modules dark on light, which scanners read most reliably.
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InviteQrCode(data: _link, size: 220),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                widget.group.inviteCode,
                style: TextStyle(
                  color: f.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('hub_group_qr_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: f.text70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l10n.translate('hub_copy_invite_link')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                    ),
                    onPressed: _busy ? null : _shareOrSave,
                    icon: const Icon(
                      kIsWeb ? Icons.download_rounded : Icons.share_rounded,
                    ),
                    label: Text(
                      l10n.translate(
                        kIsWeb ? 'hub_group_qr_save' : 'hub_group_qr_share',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: f.accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

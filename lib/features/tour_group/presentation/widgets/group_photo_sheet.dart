import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/tour_group_repository.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/media_rules.dart';
import 'group_avatar.dart';
import 'group_type.dart';

/// Opens the group's photo sheet. Everyone sees the photo there; the owner or an admin
/// may choose a new one or remove it.
Future<void> showGroupPhotoSheet(
  BuildContext context, {
  required TourGroup group,
  required TourGroupRepository repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.forest.card,
    isScrollControlled: true,
    builder: (_) => _GroupPhotoSheet(group: group, repository: repository),
  );
}

class _GroupPhotoSheet extends StatefulWidget {
  const _GroupPhotoSheet({required this.group, required this.repository});

  final TourGroup group;
  final TourGroupRepository repository;

  @override
  State<_GroupPhotoSheet> createState() => _GroupPhotoSheetState();
}

class _GroupPhotoSheetState extends State<_GroupPhotoSheet> {
  /// Null until the viewer's role has loaded; the change controls wait for it.
  bool? _canChange;
  bool _busy = false;
  double _progress = 0;
  String? _photoUrl;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.group.photoUrl;
    unawaited(_loadRole());
  }

  Future<void> _loadRole() async {
    bool canChange;
    try {
      final role = await widget.repository.myRole(widget.group.id);
      canChange = role?.isAdminOrOwner ?? false;
    } catch (_) {
      canChange = false;
    }
    if (mounted) setState(() => _canChange = canChange);
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<XFile?> _pick() async {
    try {
      return await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      _fail(context.l10n.translate('group_photo_failed'));
      return null;
    }
  }

  Future<void> _pickAndUpload() async {
    final l10n = context.l10n;
    final file = await _pick();
    if (file == null) return;
    if (imageContentType(file.name) == null) {
      _fail(l10n.translate('group_photo_bad_type'));
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = null;
      _error = null;
    });
    try {
      final url = await widget.repository.changeGroupPhoto(
        tourId: widget.group.id,
        file: file,
        previousUrl: _photoUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _status = l10n.translate('group_photo_done');
      });
    } catch (error) {
      _fail(error is TourUploadException
          ? error.toString()
          : l10n.translate('group_photo_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      await widget.repository.removeGroupPhoto(
        tourId: widget.group.id,
        previousUrl: _photoUrl,
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = null;
        _status = l10n.translate('group_photo_removed');
      });
    } catch (_) {
      _fail(l10n.translate('group_photo_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canChange = _canChange ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('group_photo_title'),
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GroupAvatar(
              typeIcon: groupTypeIcon(widget.group),
              photoUrl: _photoUrl,
              size: 128,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate(
                  canChange ? 'group_photo_hint' : 'group_photo_members_see'),
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: palette.text70, fontSize: 12, height: 1.4),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 6),
              Text(
                l10n.translate('group_photo_uploading'),
                style: TextStyle(color: palette.text70, fontSize: 12),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(color: palette.accentText, fontSize: 13),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            if (canChange && !_busy) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen,
                  ),
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(l10n.translate('group_photo_change')),
                ),
              ),
              if (_photoUrl != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _remove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.translate('group_photo_remove')),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

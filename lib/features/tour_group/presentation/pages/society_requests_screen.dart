import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_journal.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/service_request_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/media_rules.dart';
import '../../domain/services/service_request_rules.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);
const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
);

/// The service requests a housing society's residents raise and the committee follows
/// to the end. Any resident raises one. Its author may correct its words while it is
/// open; the owner or an admin moves it on with a note for the residents. The author or
/// an admin removes it.
class SocietyRequestsScreen extends StatefulWidget {
  const SocietyRequestsScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<SocietyRequestsScreen> createState() => _SocietyRequestsScreenState();
}

class _SocietyRequestsScreenState extends State<SocietyRequestsScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<ServiceRequest>> _requests =
      _repository.watchServiceRequests(widget.tourId);
  ServiceRequestStatus? _filter;
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _raise() async {
    final l10n = context.l10n;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.surfaceFor(_card),
      shape: _sheetShape,
      builder: (_) => _RequestSheet(
        repository: _repository,
        tourId: widget.tourId,
      ),
    );
    if (saved == true) _toast(l10n.translate('society_request_saved'));
  }

  Future<void> _open(ServiceRequest request) async {
    final l10n = context.l10n;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.surfaceFor(_card),
      shape: _sheetShape,
      builder: (_) => _RequestDetailSheet(
        repository: _repository,
        tourId: widget.tourId,
        request: request,
        isAdmin: _isAdmin,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case 'edit':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.forest.surfaceFor(_card),
          shape: _sheetShape,
          builder: (_) => _RequestSheet(
            repository: _repository,
            tourId: widget.tourId,
            existing: request,
          ),
        );
        if (saved == true) _toast(l10n.translate('society_request_updated'));
      case 'status':
        _toast(l10n.translate('society_request_status_saved'));
      case 'deleted':
        _toast(l10n.translate('society_request_deleted'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: context.forest.surfaceFor(_bg),
      appBar: AppBar(
        title: Text(l10n.translate('society_requests_title'),
            style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        backgroundColor: context.forest.surfaceFor(_card),
        foregroundColor: context.forest.text,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        onPressed: _raise,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.translate('society_request_new')),
      ),
      body: StreamBuilder<List<ServiceRequest>>(
        stream: _requests,
        builder: (context, snap) {
          if (snap.hasError) {
            return _message(l10n.translate('society_load_failed'));
          }
          final all = snap.data;
          if (all == null) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.mintGreen));
          }
          final counts = countServiceRequests(all);
          final shown = filterServiceRequests(all, status: _filter);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text(
                  l10n.translate('society_requests_summary', args: {
                    'open': l10n.number(counts.open),
                    'progress': l10n.number(counts.inProgress),
                    'done': l10n.number(counts.resolved),
                  }),
                  style: TextStyle(color: context.forest.text70, fontSize: 13),
                ),
              ),
              _filters(l10n),
              const SizedBox(height: 8),
              if (all.isEmpty)
                _message(l10n.translate('society_requests_empty')),
              for (final request in shown) _tile(request, l10n),
            ],
          );
        },
      ),
    );
  }

  Widget _filters(AppLocalizations l10n) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ChoiceChip(
          label: Text(l10n.translate('society_request_filter_all'),
              style: const TextStyle(fontSize: 12)),
          selected: _filter == null,
          selectedColor: AppColors.mintGreen,
          backgroundColor: context.forest.surfaceFor(const Color(0xFF1E3326)),
          onSelected: (_) => setState(() => _filter = null),
        ),
        for (final status in ServiceRequestStatus.values)
          ChoiceChip(
            label: Text(_statusLabel(l10n, status),
                style: const TextStyle(fontSize: 12)),
            selected: _filter == status,
            selectedColor: AppColors.mintGreen,
            backgroundColor: context.forest.surfaceFor(const Color(0xFF1E3326)),
            onSelected: (_) => setState(() => _filter = status),
          ),
      ],
    );
  }

  Widget _tile(ServiceRequest request, AppLocalizations l10n) {
    final who = request.createdByName.isEmpty
        ? request.createdByEmail
        : request.createdByName;
    return Card(
      color: context.forest.surfaceFor(_card),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _open(request),
        leading: Icon(_categoryIcon(request.category),
            color: context.forest.accentText),
        title: Text(request.title,
            style: TextStyle(
                color: context.forest.text, fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                [
                  _categoryLabel(l10n, request.category),
                  if (who.isNotEmpty)
                    l10n.translate('society_request_by', args: {'name': who}),
                ].join(' · '),
                style: TextStyle(color: context.forest.text54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (request.photoUrls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: context.forest.accentText,
                ),
              ),
          ],
        ),
        trailing: _StatusChip(
          label: _statusLabel(l10n, request.status),
          color: _statusColor(request.status),
        ),
      ),
    );
  }

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text60)),
      );
}

String _statusLabel(AppLocalizations l10n, ServiceRequestStatus status) {
  switch (status) {
    case ServiceRequestStatus.open:
      return l10n.translate('society_request_status_open');
    case ServiceRequestStatus.inProgress:
      return l10n.translate('society_request_status_in_progress');
    case ServiceRequestStatus.resolved:
      return l10n.translate('society_request_status_resolved');
  }
}

Color _statusColor(ServiceRequestStatus status) {
  switch (status) {
    case ServiceRequestStatus.open:
      return const Color(0xFFF59E0B);
    case ServiceRequestStatus.inProgress:
      return const Color(0xFF38BDF8);
    case ServiceRequestStatus.resolved:
      return AppColors.mintGreen;
  }
}

String _categoryLabel(AppLocalizations l10n, ServiceRequestCategory category) {
  switch (category) {
    case ServiceRequestCategory.lift:
      return l10n.translate('society_cat_lift');
    case ServiceRequestCategory.water:
      return l10n.translate('society_cat_water');
    case ServiceRequestCategory.power:
      return l10n.translate('society_cat_power');
    case ServiceRequestCategory.security:
      return l10n.translate('society_cat_security');
    case ServiceRequestCategory.cleaning:
      return l10n.translate('society_cat_cleaning');
    case ServiceRequestCategory.other:
      return l10n.translate('society_cat_other');
  }
}

IconData _categoryIcon(ServiceRequestCategory category) {
  switch (category) {
    case ServiceRequestCategory.lift:
      return Icons.elevator_rounded;
    case ServiceRequestCategory.water:
      return Icons.water_drop_rounded;
    case ServiceRequestCategory.power:
      return Icons.bolt_rounded;
    case ServiceRequestCategory.security:
      return Icons.shield_rounded;
    case ServiceRequestCategory.cleaning:
      return Icons.cleaning_services_rounded;
    case ServiceRequestCategory.other:
      return Icons.handyman_rounded;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Raises a new request, or corrects the words of one the signed-in resident wrote
/// while it is open. Saves and closes with true.
class _RequestSheet extends StatefulWidget {
  const _RequestSheet({
    required this.repository,
    required this.tourId,
    this.existing,
  });

  final TourGroupRepository repository;
  final String tourId;
  final ServiceRequest? existing;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _details =
      TextEditingController(text: widget.existing?.details ?? '');
  late ServiceRequestCategory _category =
      widget.existing?.category ?? ServiceRequestCategory.lift;
  bool _saving = false;
  String? _error;
  // Photos already on the request. The resident may take one off while editing it.
  late final List<String> _savedPhotos = [...?widget.existing?.photoUrls];
  // Photos picked here, in the order they were picked. They upload when the request is saved.
  final List<XFile> _pickedImages = [];
  final List<Uint8List> _pickedBytes = [];

  int get _photoCount => _savedPhotos.length + _pickedImages.length;
  bool get _canAddPhoto => _photoCount < kServiceRequestPhotosMax;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (!_canAddPhoto) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      // The picker and the read take time, so check the room and the screen again.
      if (!mounted || !_canAddPhoto) return;
      setState(() {
        _pickedImages.add(file);
        _pickedBytes.add(bytes);
      });
    } catch (err) {
      logError('Service request photo pick error: $err');
    }
  }

  /// Takes a photo already on the request off it. The change is kept when the request is saved.
  VoidCallback _removeSavedPhoto(int index) => () {
        setState(() => _savedPhotos.removeAt(index));
      };

  /// Drops a photo picked here before it is uploaded.
  VoidCallback _removePickedPhoto(int index) => () {
        setState(() {
          _pickedImages.removeAt(index);
          _pickedBytes.removeAt(index);
        });
      };

  /// One photo in the form, with a button to take it off the request.
  Widget _photoThumb({required Widget image, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: _saving ? null : onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final title = _title.text.trim();
    if (!isValidServiceRequestTitle(title)) {
      setState(() => _error = l10n.translate('society_request_title_short'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The photos already on the request stay, and the picked ones upload one after another.
      final photos = <String>[..._savedPhotos];
      for (final file in _pickedImages) {
        final ext = storedExtension(file.name, 'jpg');
        final cType = imageContentType(file.name) ?? 'image/jpeg';
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'media',
          file: file,
          contentType: cType,
          extension: ext,
          maxBytes: kMaxImageBytes,
          // A request keeps its photos for as long as the request lives. The journal's
          // orphan sweep would otherwise delete them, since no post refers to them.
          journal: TourMediaJournal.untracked,
        );
        photos.add(await upload.finish());
      }

      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.addServiceRequest(
          widget.tourId,
          title: title,
          details: _details.text,
          category: _category,
          photoUrls: photos,
        );
      } else {
        await widget.repository.editServiceRequestText(
          widget.tourId,
          existing.id,
          title: title,
          details: _details.text,
          category: _category,
          photoUrls: photos,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      logError('Service request save failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.translate('society_save_failed', args: {'error': err});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.existing != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      editing
                          ? l10n.translate('society_request_edit')
                          : l10n.translate('society_request_new'),
                      style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    maxLength: kServiceRequestTitleMax,
                    style: TextStyle(color: context.forest.text),
                    decoration: InputDecoration(
                      labelText: l10n.translate('society_request_title_label'),
                      hintText: l10n.translate('society_request_title_hint'),
                      hintStyle: TextStyle(color: context.forest.text38),
                      labelStyle: TextStyle(color: context.forest.text70),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _details,
                    maxLines: 3,
                    maxLength: kServiceRequestDetailsMax,
                    style: TextStyle(color: context.forest.text),
                    decoration: InputDecoration(
                      labelText:
                          l10n.translate('society_request_details_label'),
                      hintText: l10n.translate('society_request_details_hint'),
                      hintStyle: TextStyle(color: context.forest.text38),
                      labelStyle: TextStyle(color: context.forest.text70),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.translate('society_request_category_label'),
                      style: TextStyle(
                          color: context.forest.text70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in ServiceRequestCategory.values)
                        ChoiceChip(
                          label: Text(_categoryLabel(l10n, category),
                              style: const TextStyle(fontSize: 12)),
                          selected: _category == category,
                          selectedColor: AppColors.mintGreen,
                          backgroundColor: context.forest
                              .surfaceFor(const Color(0xFF1E3326)),
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_photoCount > 0) ...[
                    SizedBox(
                      height: 96,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _savedPhotos.length; i++)
                            _photoThumb(
                              image: Image.network(_savedPhotos[i],
                                  fit: BoxFit.cover),
                              onRemove: _removeSavedPhoto(i),
                            ),
                          for (var i = 0; i < _pickedBytes.length; i++)
                            _photoThumb(
                              image: Image.memory(_pickedBytes[i],
                                  fit: BoxFit.cover),
                              onRemove: _removePickedPhoto(i),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_canAddPhoto)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(_photoCount == 0
                          ? 'সমস্যার ছবি যুক্ত করুন (ঐচ্ছিক)'
                          : 'আরেকটি ছবি যুক্ত করুন'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.forest.text,
                        side: BorderSide(color: context.forest.text24),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: TextStyle(
                            color: context.forest.readable(Colors.redAccent),
                            fontSize: 12)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                    ),
                    onPressed: _saving ? null : _submit,
                    child: Text(editing
                        ? l10n.translate('society_request_save')
                        : l10n.translate('society_request_submit')),
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

/// One request in full. The committee moves it on here, with a note; the author corrects
/// it while it is open; the author or an admin removes it. Closes with 'status',
/// 'edit' or 'deleted' so the list can say what happened.
class _RequestDetailSheet extends StatefulWidget {
  const _RequestDetailSheet({
    required this.repository,
    required this.tourId,
    required this.request,
    required this.isAdmin,
  });

  final TourGroupRepository repository;
  final String tourId;
  final ServiceRequest request;
  final bool isAdmin;

  @override
  State<_RequestDetailSheet> createState() => _RequestDetailSheetState();
}

class _RequestDetailSheetState extends State<_RequestDetailSheet> {
  late ServiceRequestStatus _status = widget.request.status;
  late final TextEditingController _note =
      TextEditingController(text: widget.request.adminNote);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _saveStatus() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.setServiceRequestStatus(
        widget.tourId,
        widget.request.id,
        status: _status,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context, 'status');
    } catch (err) {
      logError('Service request status failed: $err');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.translate('society_save_failed', args: {'error': err});
      });
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.surfaceFor(_card),
        title: Text(l10n.translate('society_request_delete'),
            style: TextStyle(color: context.forest.text)),
        content: Text(l10n.translate('society_request_delete_body'),
            style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('fd_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('fd_delete')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteServiceRequest(
        widget.tourId,
        widget.request.id,
      );
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (err) {
      logError('Service request delete failed: $err');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.translate('society_save_failed', args: {'error': err});
      });
    }
  }

  /// One photo of a request, cropped to fill the space it is given.
  Widget _requestPhoto(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black26,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.broken_image_rounded,
                color: context.forest.text38, size: 36),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(BuildContext context, ServiceRequest request) {
    final dateFormat = localizedDateFormat('d MMM, h:mm a');
    final isProgress = request.status == ServiceRequestStatus.inProgress ||
        request.status == ServiceRequestStatus.resolved;
    final isDone = request.status == ServiceRequestStatus.resolved;

    Widget node({
      required String title,
      required String time,
      required bool active,
      required Color activeColor,
      required IconData icon,
    }) {
      final color = active ? activeColor : context.forest.text38;
      return Expanded(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withValues(alpha: 0.15)
                    : context.forest.surfaceFor(const Color(0xFF1E3326)),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: active ? 2 : 1),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? context.forest.text : context.forest.text54,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
            if (time.isNotEmpty)
              Text(
                time,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text54, fontSize: 10),
              ),
          ],
        ),
      );
    }

    Widget connector({required bool active}) {
      return Container(
        width: 24,
        height: 2,
        margin: const EdgeInsets.only(bottom: 24),
        color: active ? AppColors.mintGreen : context.forest.divider10,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF162B20)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.forest.divider10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'অগ্রগতি টাইমলাইন',
            style: TextStyle(
              color: context.forest.accentText,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              node(
                title: 'অনুরোধ গৃহীত',
                time: request.createdAt != null
                    ? dateFormat.format(request.createdAt!)
                    : '',
                active: true,
                activeColor: AppColors.mintGreen,
                icon: Icons.assignment_turned_in_rounded,
              ),
              connector(active: isProgress),
              node(
                title: 'কাজ চলমান',
                time: request.inProgressAt != null
                    ? dateFormat.format(request.inProgressAt!)
                    : (isProgress ? 'চলমান' : 'অপেক্ষমান'),
                active: isProgress,
                activeColor: isDone ? AppColors.mintGreen : AppColors.gold,
                icon: Icons.engineering_rounded,
              ),
              connector(active: isDone),
              node(
                title: 'সমাধান সম্পন্ন',
                time: request.resolvedAt != null
                    ? dateFormat.format(request.resolvedAt!)
                    : (isDone ? 'সম্পন্ন' : 'অপেক্ষমান'),
                active: isDone,
                activeColor: AppColors.mintGreen,
                icon: Icons.check_circle_rounded,
              ),
            ],
          ),
          if (request.resolvedByName != null &&
              request.resolvedByName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'সমাধানকারী: ${request.resolvedByName}',
                style: TextStyle(
                  color: context.forest.readable(AppColors.gold),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final request = widget.request;
    final me = widget.repository.currentEmail;
    final canEdit = canEditServiceRequestText(request, me);
    final canDelete =
        canDeleteServiceRequest(request, me, isAdmin: widget.isAdmin);
    final who = request.createdByName.isEmpty
        ? request.createdByEmail
        : request.createdByName;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(_categoryIcon(request.category),
                          color: context.forest.accentText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(request.title,
                            style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      _categoryLabel(l10n, request.category),
                      if (who.isNotEmpty)
                        l10n.translate('society_request_by',
                            args: {'name': who}),
                    ].join(' · '),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  _StatusChip(
                    label: _statusLabel(l10n, request.status),
                    color: _statusColor(request.status),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusTimeline(context, request),
                  if (request.details.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(request.details,
                        style: TextStyle(
                            color: context.forest.text70, height: 1.4)),
                  ],
                  if (request.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('সমস্যার ছবি',
                        style: TextStyle(
                            color: context.forest.accentText,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    // One photo fills the width; more than one scroll sideways.
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: request.photoUrls.length == 1
                          ? _requestPhoto(context, request.photoUrls.first)
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: request.photoUrls.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) => SizedBox(
                                width: 240,
                                height: 180,
                                child: _requestPhoto(
                                    context, request.photoUrls[index]),
                              ),
                            ),
                    ),
                  ],
                  if (!widget.isAdmin && request.adminNote.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(l10n.translate('society_request_note_label'),
                        style: TextStyle(
                            color: context.forest.accentText,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(request.adminNote,
                        style: TextStyle(color: context.forest.text)),
                  ],
                  if (widget.isAdmin) ...[
                    const SizedBox(height: 16),
                    Text(l10n.translate('society_request_status'),
                        style: TextStyle(
                            color: context.forest.text70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final status in ServiceRequestStatus.values)
                          ChoiceChip(
                            label: Text(_statusLabel(l10n, status),
                                style: const TextStyle(fontSize: 12)),
                            selected: _status == status,
                            selectedColor: AppColors.mintGreen,
                            backgroundColor: context.forest
                                .surfaceFor(const Color(0xFF1E3326)),
                            onSelected: _busy
                                ? null
                                : (_) => setState(() => _status = status),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      maxLength: kServiceRequestNoteMax,
                      style: TextStyle(color: context.forest.text),
                      decoration: InputDecoration(
                        labelText: l10n.translate('society_request_note_label'),
                        hintText: l10n.translate('society_request_note_hint'),
                        hintStyle: TextStyle(color: context.forest.text38),
                        labelStyle: TextStyle(color: context.forest.text70),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.mintGreen,
                        foregroundColor: AppColors.darkGreen,
                      ),
                      onPressed: _busy ? null : _saveStatus,
                      child:
                          Text(l10n.translate('society_request_save_status')),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: TextStyle(
                            color: context.forest.readable(Colors.redAccent),
                            fontSize: 12)),
                  ],
                  if (canEdit)
                    TextButton.icon(
                      onPressed:
                          _busy ? null : () => Navigator.pop(context, 'edit'),
                      icon: Icon(Icons.edit_rounded,
                          color: context.forest.accentText),
                      label: Text(l10n.translate('society_request_edit'),
                          style: TextStyle(color: context.forest.accentText)),
                    ),
                  if (canDelete)
                    TextButton.icon(
                      onPressed: _busy ? null : _remove,
                      icon: Icon(Icons.delete_outline_rounded,
                          color: context.forest.readable(Colors.redAccent)),
                      label: Text(l10n.translate('society_request_delete'),
                          style: TextStyle(
                              color:
                                  context.forest.readable(Colors.redAccent))),
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

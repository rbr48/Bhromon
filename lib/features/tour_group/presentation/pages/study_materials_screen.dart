import 'package:bhromon/core/widgets/skeleton.dart';
import '../widgets/group_back_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/media/media_access.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/study_material_models.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/media_rules.dart';
import '../../domain/services/study_material_rules.dart';
import '../widgets/study/study_material_composer.dart';
import 'markdown_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'study_graph_atlas_screen.dart';

/// The materials of one book: notes, files, links and recordings the members filed. An admin approves
/// the waiting ones and decides the reported ones. A report hides a material at once, from everyone but
/// its uploader. Opening a material is recorded once for each member.
class StudyMaterialsScreen extends StatefulWidget {
  const StudyMaterialsScreen({
    super.key,
    required this.tourId,
    required this.book,
    this.repository,
  });

  final String tourId;
  final StudyBook book;
  final TourGroupRepository? repository;

  @override
  State<StudyMaterialsScreen> createState() => _StudyMaterialsScreenState();
}

enum _MaterialAction { open, report, edit, remove, publish, restore }

class _StudyMaterialsScreenState extends State<StudyMaterialsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();

  TourRole? _myRole;
  List<StudyMaterial> _materials = const [];
  List<StudyChapter> _chapters = const [];
  StudyMaterialPolicy _policy = const StudyMaterialPolicy();
  bool _loaded = false;
  String? _chapterId;

  StreamSubscription<List<StudyMaterial>>? _materialsSub;
  StreamSubscription<List<StudyChapter>>? _chaptersSub;
  StreamSubscription<StudyMaterialPolicy>? _policySub;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    });
    _materialsSub = _repository
        .watchStudyMaterials(widget.tourId, widget.book.id)
        .listen((materials) {
      if (mounted) {
        setState(() {
          _materials = materials;
          _loaded = true;
        });
      }
    }, onError: (Object error, StackTrace stackTrace) {
      logWarning('Study materials could not be read', error, stackTrace);
      if (mounted) setState(() => _loaded = true);
    });
    _chaptersSub = _repository
        .watchStudyChapters(widget.tourId, widget.book.id)
        .listen((chapters) {
      if (mounted) setState(() => _chapters = chapters);
    });
    _policySub =
        _repository.watchMaterialPolicy(widget.tourId).listen((policy) {
      if (mounted) setState(() => _policy = policy);
    });
  }

  bool get _isPoeBook {
    final title = widget.book.title.toLowerCase();
    return widget.book.id == 'ah9qgOp1e7uA2qcV6a7B' ||
        title.contains('economics') ||
        title.contains('poe') ||
        widget.book.title.contains('অর্থনীতি');
  }

  @override
  void dispose() {
    _materialsSub?.cancel();
    _chaptersSub?.cancel();
    _policySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = [
      for (final material in _materials)
        if (isStudyMaterialVisibleTo(material,
            viewerEmail: _me, isAdmin: _isAdmin))
          material,
    ];
    final inChapter = studyMaterialsInChapter(visible, _chapterId);
    final review =
        _isAdmin ? studyReviewQueue(_materials) : const <StudyMaterial>[];
    final approval =
        _isAdmin ? studyApprovalQueue(_materials) : const <StudyMaterial>[];
    // An admin's own waiting and hidden material is in the queues above.
    final yours = _isAdmin
        ? const <StudyMaterial>[]
        : sortStudyMaterials(
            inChapter.where((m) => !m.isPublished && m.createdByEmail == _me));
    final published = sortStudyMaterials(inChapter.where((m) => m.isPublished));
    final empty = review.isEmpty &&
        approval.isEmpty &&
        yours.isEmpty &&
        published.isEmpty;
    final now = DateTime.now();

    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('study_material_title')),
          actions: [
            if (_isPoeBook)
              IconButton(
                tooltip: 'Dynamic SVG Graph Atlas (ডাইনামিক গ্রাফ)',
                icon: const Icon(Icons.auto_graph_rounded),
                onPressed: () => StudyGraphAtlasScreen.open(
                  context,
                  tourId: widget.tourId,
                ),
              ),
            if (_isAdmin)
              IconButton(
                tooltip: l10n.translate('study_material_policy_title'),
                icon: const Icon(Icons.tune_rounded),
                onPressed: _editPolicy,
              ),
          ],
        ),
        floatingActionButton: canFileStudyMaterial(
          isAdmin: _isAdmin,
          onlyAdminsPost: _policy.onlyAdminsPost,
        )
            ? FloatingActionButton.extended(
                onPressed: _addMaterial,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate('study_material_add')),
              )
            : null,
        body: !_loaded
            ? const ListRowsSkeleton()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (_isPoeBook) _buildAtlasBanner(context),
                  _chapterFilter(context),
                  if (!_isAdmin && _policy.onlyAdminsPost)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        l10n.translate('study_material_only_admins_note'),
                        style: TextStyle(color: context.forest.text70),
                      ),
                    ),
                  if (review.isNotEmpty)
                    _section(
                      context,
                      l10n.translate('study_material_review_heading'),
                      [
                        for (final m in review)
                          _tile(context, m,
                              overdue: isStudyReportOverdue(m, now: now)),
                      ],
                    ),
                  if (approval.isNotEmpty)
                    _section(
                      context,
                      l10n.translate('study_material_approval_heading'),
                      [for (final m in approval) _tile(context, m)],
                    ),
                  if (yours.isNotEmpty)
                    _section(
                      context,
                      l10n.translate('study_material_yours_heading'),
                      [for (final m in yours) _tile(context, m)],
                    ),
                  // With every chapter shown, the shared materials are grouped by chapter, in chapter order.
                  if (published.isNotEmpty &&
                      _chapterId == null &&
                      _chapters.isNotEmpty)
                    for (final group in groupStudyMaterialsByChapter(
                      published,
                      [for (final chapter in _chapters) chapter.id],
                    ))
                      _section(
                        context,
                        _chapterHeading(context, group.chapterId),
                        [for (final m in group.materials) _tile(context, m)],
                      )
                  else if (published.isNotEmpty)
                    _section(
                      context,
                      l10n.translate('study_material_shared_heading'),
                      [for (final m in published) _tile(context, m)],
                    ),
                  if (empty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        l10n.translate('study_material_empty'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildAtlasBanner(BuildContext context) {
    final palette = context.forest;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.accentText.withValues(alpha: 0.12),
            palette.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.accentText.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => StudyGraphAtlasScreen.open(
            context,
            tourId: widget.tourId,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.accentText.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_graph_rounded,
                    color: palette.accentText,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Dynamic SVG Graph Atlas',
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accentText,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '95 Graphs',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'সকল ৮টি পরীক্ষার ডাইনামিক অর্থনীতি ভেক্টর গ্রাফ (PPC, IC, AC/MC)',
                        style: TextStyle(
                          color: palette.text70,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: palette.accentText,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chapterFilter(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(l10n.translate('study_material_all')),
          selected: _chapterId == null,
          onSelected: (_) => setState(() => _chapterId = null),
        ),
        for (final chapter in _chapters)
          ChoiceChip(
            label: Text('${l10n.number(chapter.number)}. ${chapter.title}'),
            selected: _chapterId == chapter.id,
            onSelected: (_) => setState(() => _chapterId = chapter.id),
          ),
      ],
    );
  }

  /// The heading of a chapter's group: its number and title, or "Whole book" for materials under no chapter.
  String _chapterHeading(BuildContext context, String? chapterId) {
    final l10n = context.l10n;
    for (final chapter in _chapters) {
      if (chapter.id == chapterId) {
        return '${l10n.number(chapter.number)}. ${chapter.title}';
      }
    }
    return l10n.translate('study_material_whole_book');
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, StudyMaterial m, {bool overdue = false}) {
    final l10n = context.l10n;
    final canReport = canReportStudyMaterial(m, viewerEmail: _me);
    final canManage =
        canManageStudyMaterial(m, viewerEmail: _me, isAdmin: _isAdmin);
    final isBangla = m.title.contains('বাংলা') ||
        m.title.contains('সমাধান') ||
        (m.fileName?.toLowerCase().contains('bangla') ?? false);
    final isNoteOrDoc = m.kind == StudyMaterialKind.note ||
        (m.fileName?.endsWith('.md') ?? false);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconFor(m.kind)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                m.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isNoteOrDoc) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isBangla
                      ? const Color(0xFF193B28)
                      : const Color(0xFF1E3A2B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isBangla
                        ? const Color(0xFF81C784).withValues(alpha: 0.4)
                        : AppColors.mintGreen.withValues(alpha: 0.4),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  isBangla ? 'বাংলা' : 'English',
                  style: TextStyle(
                    color: isBangla
                        ? const Color(0xFF81C784)
                        : AppColors.mintGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(_subtitle(context, m, overdue: overdue)),
        onTap: () => _onAction(m, _MaterialAction.open),
        trailing: PopupMenuButton<_MaterialAction>(
          tooltip: l10n.translate('study_material_actions'),
          onSelected: (action) => _onAction(m, action),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _MaterialAction.open,
              child: Text(l10n.translate('study_material_open')),
            ),
            if (canReport)
              PopupMenuItem(
                value: _MaterialAction.report,
                child: Text(l10n.translate('study_material_report')),
              ),
            if (canManage)
              PopupMenuItem(
                value: _MaterialAction.edit,
                child: Text(l10n.translate('study_material_edit_title')),
              ),
            if (canManage)
              PopupMenuItem(
                value: _MaterialAction.remove,
                child: Text(l10n.translate('study_remove')),
              ),
            if (_isAdmin && m.status == StudyMaterialStatus.pending)
              PopupMenuItem(
                value: _MaterialAction.publish,
                child: Text(l10n.translate('study_material_publish')),
              ),
            if (_isAdmin && m.status == StudyMaterialStatus.hidden)
              PopupMenuItem(
                value: _MaterialAction.restore,
                child: Text(l10n.translate('study_material_restore')),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, StudyMaterial m,
      {required bool overdue}) {
    final l10n = context.l10n;
    final parts = <String>[
      l10n.translate('study_material_kind_${m.kind.name}'),
    ];
    for (final chapter in _chapters) {
      if (chapter.id == m.chapterId) {
        parts.add('${l10n.number(chapter.number)}. ${chapter.title}');
        break;
      }
    }
    final url = m.url;
    if (m.kind == StudyMaterialKind.link && url != null) {
      parts.add(studyLinkDomain(url));
    }
    switch (m.status) {
      case StudyMaterialStatus.pending:
        parts.add(l10n.translate('study_material_waiting'));
      case StudyMaterialStatus.hidden:
        parts.add(l10n.translate('study_material_hidden_label'));
      case StudyMaterialStatus.published:
        break;
    }
    if (overdue) parts.add(l10n.translate('study_material_review_overdue'));
    return parts.join(' · ');
  }

  IconData _iconFor(StudyMaterialKind kind) => switch (kind) {
        StudyMaterialKind.file => Icons.description_rounded,
        StudyMaterialKind.image => Icons.image_rounded,
        StudyMaterialKind.audio => Icons.graphic_eq_rounded,
        StudyMaterialKind.video => Icons.movie_rounded,
        StudyMaterialKind.link => Icons.link_rounded,
        StudyMaterialKind.note => Icons.sticky_note_2_rounded,
      };

  Future<void> _onAction(StudyMaterial m, _MaterialAction action) async {
    switch (action) {
      case _MaterialAction.open:
        await _open(m);
      case _MaterialAction.report:
        await _report(m);
      case _MaterialAction.edit:
        await _editTitle(m);
      case _MaterialAction.remove:
        await _remove(m);
      case _MaterialAction.publish:
        await _run(
          () => _repository.publishStudyMaterial(widget.tourId, m.id),
          'study_material_published',
        );
      case _MaterialAction.restore:
        await _run(
          () => _repository.publishStudyMaterial(widget.tourId, m.id),
          'study_material_restored',
        );
    }
  }

  /// Opens a note or document in fullscreen reader, or opens a file/link in-app or externally.
  /// Then records the open for a published material that someone else filed.
  Future<void> _open(StudyMaterial m) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (m.kind == StudyMaterialKind.note) {
      // Find paired alternate language note if exists for this chapter
      StudyMaterial? alternate;
      if (m.chapterId != null && m.chapterId!.isNotEmpty) {
        final isBangla = m.title.contains('বাংলা') ||
            m.title.contains('সমাধান') ||
            (m.fileName?.toLowerCase().contains('bangla') ?? false);
        for (final other in _materials) {
          if (other.id != m.id && other.chapterId == m.chapterId) {
            final otherBangla = other.title.contains('বাংলা') ||
                other.title.contains('সমাধান') ||
                (other.fileName?.toLowerCase().contains('bangla') ?? false);
            if (otherBangla != isBangla) {
              alternate = other;
              break;
            }
          }
        }
      }

      await MarkdownViewerScreen.open(
        context,
        title: m.title,
        rawContent: m.body ?? '',
        tourId: widget.tourId,
        alternateRawContent: alternate?.body,
        alternateTitle: alternate?.title,
      );
    } else {
      final url = m.url;
      if (url == null) return;
      final target = m.kind.isUpload ? signedMediaUrl(url) : url;
      final name = (m.fileName ?? url).toLowerCase();
      final isMd = name.endsWith('.md') ||
          name.endsWith('.txt') ||
          name.endsWith('.log');
      final isPdf = name.endsWith('.pdf');

      try {
        if (isMd) {
          await MarkdownViewerScreen.open(
            context,
            title: m.title.isNotEmpty
                ? m.title
                : (m.fileName ?? l10n.translate('study_document_untitled')),
            fileUrl: target,
            tourId: widget.tourId,
          );
        } else if (isPdf) {
          await PdfViewerScreen.open(
            context,
            title: m.title.isNotEmpty
                ? m.title
                : (m.fileName ?? l10n.translate('study_document_untitled')),
            fileUrl: target,
            tourId: widget.tourId,
          );
        } else {
          final opened = await launchUrl(
            Uri.parse(target),
            mode: LaunchMode.externalApplication,
          );
          if (!opened) {
            messenger.showSnackBar(SnackBar(
              content: Text(l10n.translate('study_material_open_failed')),
              backgroundColor: AppColors.amber,
            ));
            return;
          }
        }
      } catch (error, stackTrace) {
        logWarning('A study material could not be opened', error, stackTrace);
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.translate('study_material_open_failed')),
          backgroundColor: AppColors.amber,
        ));
        return;
      }
    }
    if (m.isPublished && m.createdByEmail != _me) {
      try {
        await _repository.markStudyMaterialOpened(widget.tourId, m.id);
      } catch (error, stackTrace) {
        logWarning(
            'A study material open could not be recorded', error, stackTrace);
      }
    }
  }

  Future<void> _report(StudyMaterial m) async {
    final l10n = context.l10n;
    final reason = await showDialog<StudyMaterialReportReason>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.translate('study_material_report_title')),
        children: [
          for (final reason in StudyMaterialReportReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(reason),
              child:
                  Text(l10n.translate('study_material_report_${reason.name}')),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _run(
      () =>
          _repository.reportStudyMaterial(widget.tourId, m.id, reason: reason),
      'study_material_reported',
    );
  }

  Future<void> _editTitle(StudyMaterial m) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: m.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('study_material_edit_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.translate('study_save')),
          ),
        ],
      ),
    );
    // The dialog's field may still be on screen while it closes, so the controller goes after this frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (title == null || title.isEmpty || !mounted) return;
    await _run(
      () => _repository.setStudyMaterialTitle(widget.tourId, m.id, title),
      'study_material_saved',
    );
  }

  Future<void> _remove(StudyMaterial m) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.translate('study_material_remove_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () =>
          _repository.removeStudyMaterial(widget.tourId, m, isAdmin: _isAdmin),
      'study_material_removed',
    );
  }

  Future<void> _editPolicy() async {
    final l10n = context.l10n;
    var needs = _policy.needsApproval;
    var onlyAdmins = _policy.onlyAdminsPost;
    final result = await showDialog<({bool needs, bool onlyAdmins})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.translate('study_material_policy_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: needs,
                title: Text(l10n.translate('study_material_approval_switch')),
                subtitle: Text(l10n.translate('study_material_approval_hint')),
                onChanged: (value) => setDialogState(() => needs = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: onlyAdmins,
                title:
                    Text(l10n.translate('study_material_only_admins_switch')),
                subtitle:
                    Text(l10n.translate('study_material_only_admins_hint')),
                onChanged: (value) => setDialogState(() => onlyAdmins = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.translate('study_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop((needs: needs, onlyAdmins: onlyAdmins)),
              child: Text(l10n.translate('study_save')),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      if (result.needs != _policy.needsApproval) {
        await _repository.setMaterialsNeedApproval(widget.tourId,
            needsApproval: result.needs);
      }
      if (result.onlyAdmins != _policy.onlyAdminsPost) {
        await _repository.setMaterialsOnlyAdmins(widget.tourId,
            onlyAdmins: result.onlyAdmins);
      }
    }, 'study_material_saved');
  }

  /// A member files a material: the file, when there is one, is uploaded first, then the record is saved,
  /// and the upload is committed so the media journal leaves it alone. A failure discards the upload.
  Future<void> _addMaterial() async {
    final draft = await showStudyMaterialComposer(context, chapters: _chapters);
    if (draft == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    TourMediaUpload? upload;
    try {
      var url = draft.url;
      final file = draft.file;
      if (file != null) {
        upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: 'study',
          file: file,
          contentType: draft.contentType ?? 'application/octet-stream',
          extension: storedExtension(draft.fileName ?? '', 'bin'),
          maxBytes: studyMaterialMaxBytes(draft.kind) ?? kMaxDocBytes,
        );
        url = await upload.finish();
      }
      await _repository.addStudyMaterial(
        widget.tourId,
        bookId: widget.book.id,
        kind: draft.kind,
        title: draft.title,
        isAdmin: _isAdmin,
        needsApproval: _policy.needsApproval,
        chapterId: draft.chapterId,
        url: url,
        fileName: draft.fileName,
        sizeBytes: draft.sizeBytes,
        body: draft.body,
      );
      await upload?.commit();
      final waits = initialStudyMaterialStatus(
            isAdmin: _isAdmin,
            needsApproval: _policy.needsApproval,
          ) ==
          StudyMaterialStatus.pending;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate(
            waits ? 'study_material_waiting_snack' : 'study_material_added')),
      ));
    } catch (error, stackTrace) {
      logWarning('A study material could not be filed', error, stackTrace);
      await upload?.discard();
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_material_error')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  /// Runs a change and says so, or says it failed.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study material change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }
}

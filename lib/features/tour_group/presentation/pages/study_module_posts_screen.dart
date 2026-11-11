import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/media/media_access.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_file_reader_rules.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_post_editor.dart';

import '../widgets/study/study_rich_text.dart';
import 'markdown_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'package:bhromon/core/theme/colors.dart';

/// The posts in one module of a subject: exam tips, or suggestions with a link. Members add
/// posts where the module lets them, mark posts helpful, and see the most helpful first. An
/// admin shows posts that wait for approval, and pins the best ones.
class StudyModulePostsScreen extends StatefulWidget {
  const StudyModulePostsScreen({
    super.key,
    required this.tourId,
    required this.subject,
    required this.moduleKey,
    required this.settings,
    this.repository,
  });

  final String tourId;
  final StudySubject subject;
  final StudyModuleKey moduleKey;
  final StudyModuleSettings settings;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudyModulePostsScreen> createState() => _StudyModulePostsScreenState();
}

class _StudyModulePostsScreenState extends State<StudyModulePostsScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<List<StudyPost>> _posts = _repository.watchStudyPosts(
      widget.tourId, widget.subject.id, widget.moduleKey);
  TourRole? _myRole;

  String get _me => _repository.currentEmail;
  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  /// Suggestions carry a title and a link; tips are text only.
  /// A suggestion and a past paper carry a link; a past paper's words are the paper's.
  bool get _withLink =>
      widget.moduleKey == StudyModuleKey.suggestions ||
      widget.moduleKey == StudyModuleKey.papers;

  bool get _paper => widget.moduleKey == StudyModuleKey.papers;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  Future<void> _add() async {
    final draft = await showStudyPostEditor(
      context,
      withLink: _withLink,
      paper: _paper,
      tourId: widget.tourId,
    );
    if (draft == null || !mounted) return;
    final shown = postShownAtOnce(settings: widget.settings, isAdmin: _isAdmin);
    await _run(
      () => _saveWithFile(
        draft,
        () => _repository.addStudyPost(
          widget.tourId,
          widget.subject.id,
          widget.moduleKey,
          text: draft.text,
          title: draft.title,
          url: draft.url,
          shown: shown,
        ),
      ),
      shown ? 'study_post_saved' : 'study_post_waiting',
    );
  }

  /// Saves a post with the file it was given, if any: the file is kept when the post is saved, and discarded when
  /// the save fails, so a file that no post names is not left on the server.
  Future<void> _saveWithFile(
    StudyPostDraft draft,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (_) {
      await draft.upload?.discard();
      rethrow;
    }
    await draft.upload?.commit();
  }

  /// Opens a link of a post. A Markdown or PDF file in this group's study folder opens in the app, as the study
  /// materials do. Any other link opens outside the app. A media-server link opens with its signed address.
  Future<void> _openLink(String url, String title) async {
    final reader = studyFileReader(url);
    if (reader != StudyFileReader.none &&
        isStudyFolderFile(url, widget.tourId)) {
      final name = title.isNotEmpty
          ? title
          : context.l10n.translate('study_document_untitled');
      if (reader == StudyFileReader.pdf) {
        await PdfViewerScreen.open(
          context,
          title: name,
          fileUrl: url,
          tourId: widget.tourId,
        );
      } else {
        await MarkdownViewerScreen.open(
          context,
          title: name,
          fileUrl: url,
          tourId: widget.tourId,
        );
      }
      return;
    }
    final target = signedMediaUrl(url);
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      logWarning('A study link could not be opened', error, stackTrace);
    }
  }

  Future<void> _edit(StudyPost post) async {
    final draft = await showStudyPostEditor(
      context,
      withLink: _withLink,
      existing: post,
      paper: _paper,
      tourId: widget.tourId,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => _saveWithFile(
        draft,
        () => _repository.editStudyPost(
          widget.tourId,
          widget.subject.id,
          widget.moduleKey,
          post,
          text: draft.text,
          title: draft.title,
          url: draft.url,
        ),
      ),
      'study_post_saved',
    );
  }

  Future<void> _remove(StudyPost post) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('study_post_delete_title')),
        content: Text(l10n.translate('study_post_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('study_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('study_remove')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(
      () => _repository.deleteStudyPost(
          widget.tourId, widget.subject.id, widget.moduleKey, post.id),
      'study_post_deleted',
    );
  }

  /// Marks a post helpful, or takes the mark back. The count changes with the mark.
  Future<void> _toggleHelpful(StudyPost post) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final marked = await _repository.toggleStudyPostHelpful(
          widget.tourId, widget.subject.id, widget.moduleKey, post.id);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate(
            marked ? 'study_post_helpful_done' : 'study_post_unhelpful_done')),
      ));
    } catch (error, stackTrace) {
      logWarning('A study post vote failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  Future<void> _setFlags(StudyPost post, {bool? shown, bool? pinned}) async {
    await _run(
      () => _repository.setStudyPostFlags(
        widget.tourId,
        widget.subject.id,
        widget.moduleKey,
        post.id,
        shown: shown,
        pinned: pinned,
      ),
      shown == true ? 'study_post_shown_done' : 'study_post_saved',
    );
  }

  /// Runs one change and says how it went. A failure is logged and shown, and the list keeps
  /// what it had.
  Future<void> _run(Future<void> Function() change, String doneKey) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(l10n.translate(doneKey))));
    } catch (error, stackTrace) {
      logWarning('A study post change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: AppColors.amber,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final canPost =
        canPostInStudyModule(settings: widget.settings, isAdmin: _isAdmin);
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(widget.settings.name,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
        ),
        floatingActionButton: canPost
            ? FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.translate(_paper
                    ? 'study_paper_add'
                    : _withLink
                        ? 'study_post_add_suggestion'
                        : 'study_post_add_tip')),
              )
            : null,
        body: StreamBuilder<List<StudyPost>>(
          stream: _posts,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(l10n.translate('study_failed'),
                    style: TextStyle(color: palette.text70)),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = sortStudyPosts(visibleStudyPosts(
              posts: snap.data!,
              viewerEmail: _me,
              isAdmin: _isAdmin,
            ));
            if (posts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.translate('study_post_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text70),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [for (final post in posts) _postCard(post)],
            );
          },
        ),
      ),
    );
  }

  Widget _postCard(StudyPost post) {
    final l10n = context.l10n;
    final palette = context.forest;
    final mine = post.createdByEmail == _me;
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l10n.translate('study_post_pinned_label'),
                    style: TextStyle(
                        color: palette.accentText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            if (post.title.isNotEmpty)
              Text(post.title,
                  style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            if (post.title.isNotEmpty) const SizedBox(height: 4),
            StudyRichText(post.text, style: TextStyle(color: palette.text)),
            if (post.url.isNotEmpty) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => _openLink(post.url, post.title),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.translate('study_material_open')),
              ),
            ],
            if (!post.shown) ...[
              const SizedBox(height: 6),
              Text(l10n.translate('study_post_waiting_label'),
                  style: TextStyle(
                      color: palette.text54, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed:
                      post.shown && !mine ? () => _toggleHelpful(post) : null,
                  icon: Icon(Icons.thumb_up_alt_outlined,
                      size: 18, color: palette.accentText),
                  label: Text(l10n.translate('study_post_helpful_label',
                      args: {'count': l10n.number(post.helpfulCount)})),
                ),
                const Spacer(),
                if (mine || _isAdmin)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: palette.text54),
                    tooltip: l10n.translate('study_post_menu'),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _edit(post);
                        case 'show':
                          _setFlags(post, shown: true);
                        case 'pin':
                          _setFlags(post, pinned: !post.pinned);
                        default:
                          _remove(post);
                      }
                    },
                    itemBuilder: (_) => [
                      if (mine)
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Text(l10n.translate('study_edit')),
                        ),
                      if (_isAdmin && !post.shown)
                        PopupMenuItem<String>(
                          value: 'show',
                          child: Text(l10n.translate('study_post_show')),
                        ),
                      if (_isAdmin)
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Text(l10n.translate(post.pinned
                              ? 'study_post_unpin'
                              : 'study_post_pin')),
                        ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(l10n.translate('study_remove')),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

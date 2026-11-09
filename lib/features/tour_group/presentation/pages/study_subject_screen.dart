import '../widgets/group_back_button.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_subject_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/study_subject_rules.dart';
import '../widgets/study/study_labels.dart';
import '../widgets/study/study_module_sheet.dart';
import '../widgets/study/study_today_card.dart';
import 'study_challenge_screen.dart';
import 'study_findings_screen.dart';
import 'study_problems_screen.dart';
import 'study_module_posts_screen.dart';

/// One subject: its modules. Members see the modules an admin has turned on. An admin sees
/// every module, and customises them.
class StudySubjectScreen extends StatefulWidget {
  const StudySubjectScreen({
    super.key,
    required this.tourId,
    required this.subject,
    this.repository,
  });

  final String tourId;
  final StudySubject subject;

  /// The data source. Null in the app, where the screen makes its own; tests pass one.
  final TourGroupRepository? repository;

  @override
  State<StudySubjectScreen> createState() => _StudySubjectScreenState();
}

class _StudySubjectScreenState extends State<StudySubjectScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final Stream<Map<StudyModuleKey, StudyModuleSettings>> _modules =
      _repository.watchStudyModules(widget.tourId, widget.subject.id);
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  /// An admin turns modules on and off, renames them, and chooses who may post in each.
  Future<void> _customise() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final current = await _repository
        .watchStudyModules(widget.tourId, widget.subject.id)
        .first;
    if (!mounted) return;
    final saved = await showStudyModuleSheet(context, current: current);
    if (saved == null || !mounted) return;
    try {
      for (final settings in saved) {
        final before = current[settings.key];
        final changed = before == null ||
            before.enabled != settings.enabled ||
            before.name != settings.name ||
            before.postPolicy != settings.postPolicy;
        if (changed) {
          await _repository.setStudyModule(
              widget.tourId, widget.subject.id, settings);
        }
      }
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.translate('study_module_saved'))));
    } catch (error, stackTrace) {
      logWarning('A study module change failed', error, stackTrace);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.translate('study_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  void _open(StudyModuleSettings settings) {
    final page = switch (settings.key) {
      StudyModuleKey.findings => StudyFindingsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      StudyModuleKey.problems => StudyProblemsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      StudyModuleKey.challenges => StudyChallengeScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          settings: settings,
          repository: _repository,
        ),
      _ => StudyModulePostsScreen(
          tourId: widget.tourId,
          subject: widget.subject,
          moduleKey: settings.key,
          settings: settings,
          repository: _repository,
        ),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => page,
    ));
  }

  /// The exam, when it is still to come: how many days away, or today.
  String? _examLine() {
    final exam = widget.subject.examDate;
    if (exam == null) return null;
    final l10n = context.l10n;
    final days = daysUntilExam(exam, DateTime.now());
    if (days < 0) return null;
    if (days == 0) return l10n.translate('study_subject_exam_today');
    return l10n
        .translate('study_subject_exam_in', args: {'days': l10n.number(days)});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final subject = widget.subject;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(subject.title,
              style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          iconTheme: IconThemeData(color: palette.text),
          elevation: 0,
          actions: [
            if (_isAdmin)
              IconButton(
                tooltip: l10n.translate('study_subject_customise'),
                icon: const Icon(Icons.tune_rounded),
                onPressed: _customise,
              ),
          ],
        ),
        body: StreamBuilder<Map<StudyModuleKey, StudyModuleSettings>>(
          stream: _modules,
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
            final settings = snap.data!;
            final keys =
                visibleStudyModules(settings: settings, isAdmin: _isAdmin);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _overview(),
                StudyTodayCard(
                  tourId: widget.tourId,
                  subject: widget.subject,
                  repository: _repository,
                  findingsModule:
                      _liveModule(settings, StudyModuleKey.findings),
                  challengeModule:
                      _liveModule(settings, StudyModuleKey.challenges),
                  onOpenModule: _open,
                ),
                if (keys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.translate(_isAdmin
                          ? 'study_subject_no_modules_admin'
                          : 'study_subject_no_modules'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.text70),
                    ),
                  ),
                for (final key in keys) _moduleTile(key, settings[key]),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The subject's code, what it covers, and the exam, when there is one.
  Widget _overview() {
    final palette = context.forest;
    final subject = widget.subject;
    final exam = _examLine();
    final lines = <String>[
      if (subject.code.isNotEmpty) subject.code,
      if (subject.description.isNotEmpty) subject.description,
      if (exam != null) exam,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: TextStyle(color: palette.text)),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(StudyModuleKey key) => switch (key) {
        StudyModuleKey.tips => Icons.lightbulb_rounded,
        StudyModuleKey.suggestions => Icons.thumb_up_rounded,
        StudyModuleKey.findings => Icons.fact_check_rounded,
        StudyModuleKey.problems => Icons.assignment_rounded,
        StudyModuleKey.challenges => Icons.flag_rounded,
        _ => Icons.extension_rounded,
      };

  /// A module's settings when an admin has turned it on, or null when it is off or not set up.
  StudyModuleSettings? _liveModule(
    Map<StudyModuleKey, StudyModuleSettings> settings,
    StudyModuleKey key,
  ) {
    final module = settings[key];
    return module != null && module.enabled ? module : null;
  }

  /// One module. A live module that is on opens its posts. An admin also sees the modules
  /// that are off, and which are still coming.
  Widget _moduleTile(StudyModuleKey key, StudyModuleSettings? settings) {
    final l10n = context.l10n;
    final palette = context.forest;
    final on = settings?.enabled ?? false;
    final openable = key.isLive && on && settings != null;
    final name = settings?.name ?? l10n.translate(studyModuleLabelKey(key));
    String? note;
    if (!on && _isAdmin) {
      note = l10n.translate(
          key.isLive ? 'study_module_off' : 'study_module_coming_soon');
    }
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: openable ? () => _open(settings) : null,
        leading: Icon(_iconFor(key), color: palette.accentText),
        title: Text(name,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
        subtitle: note == null
            ? null
            : Text(note, style: TextStyle(color: palette.text54)),
        trailing: openable
            ? Icon(Icons.chevron_right_rounded, color: palette.text54)
            : null,
      ),
    );
  }
}

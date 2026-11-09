import 'package:flutter/material.dart';
import 'study_modal.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/services/study_chapter_rules.dart';

/// The reading pace an admin chose: the day the first chapters start, and how many chapters a
/// week the group reads.
class StudyPace {
  const StudyPace({required this.start, required this.perWeek});

  final DateTime start;
  final int perWeek;
}

/// Opens the reading-pace sheet for a book with [chapterCount] chapters. Returns the pace the
/// admin chose, or null when cancelled.
Future<StudyPace?> showStudyPaceSheet(
  BuildContext context, {
  required int chapterCount,
}) {
  return showStudyModal<StudyPace>(
    context: context,
    builder: (_) => StudyPaceSheet(chapterCount: chapterCount),
  );
}

class StudyPaceSheet extends StatefulWidget {
  const StudyPaceSheet({super.key, required this.chapterCount});

  final int chapterCount;

  @override
  State<StudyPaceSheet> createState() => _StudyPaceSheetState();
}

class _StudyPaceSheetState extends State<StudyPaceSheet> {
  late DateTime _start = _today();
  int _perWeek = 2;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final initial = _start;
    final earliest = DateTime(now.year - 1);
    final latest = DateTime(now.year + 3);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // The picker asserts that its initial date is in range, so a date outside the usual
      // span widens it.
      firstDate: initial.isBefore(earliest) ? initial : earliest,
      lastDate: initial.isAfter(latest) ? initial : latest,
    );
    if (picked == null || !mounted) return;
    setState(() => _start = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    final count = widget.chapterCount;
    final dues =
        chapterDueDates(start: _start, perWeek: _perWeek, count: count);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('study_pace_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                count == 0
                    ? l10n.translate('study_pace_no_chapters')
                    : l10n.translate('study_pace_intro',
                        args: {'count': l10n.number(count)}),
                style: TextStyle(color: palette.text70),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      '${l10n.translate('study_pace_start_label')}: '
                      '${localizedDateFormat('d MMM yyyy').format(_start)}',
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _perWeek,
                      dropdownColor: palette.sheet,
                      style: TextStyle(color: palette.text),
                      items: [
                        for (var n = kPaceMin; n <= kPaceMax; n++)
                          DropdownMenuItem<int>(
                            value: n,
                            child: Text(l10n.translate(
                              'study_pace_per_week',
                              args: {'count': l10n.number(n)},
                            )),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _perWeek = value);
                      },
                    ),
                  ),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.translate('study_pace_summary', args: {
                    'date': localizedDateFormat('d MMM yyyy').format(dues.last),
                  }),
                  style: TextStyle(color: palette.text),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: count == 0
                      ? null
                      : () => Navigator.of(context)
                          .pop(StudyPace(start: _start, perWeek: _perWeek)),
                  child: Text(l10n.translate('study_pace_apply')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

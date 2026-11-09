import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../domain/models/study_subject_models.dart';
import 'study_labels.dart';

/// Opens the sheet an admin uses to turn the live modules on, rename them, and choose who may
/// post in each. Returns one settings entry per live module, or null when cancelled.
Future<List<StudyModuleSettings>?> showStudyModuleSheet(
  BuildContext context, {
  required Map<StudyModuleKey, StudyModuleSettings> current,
}) {
  return showModalBottomSheet<List<StudyModuleSettings>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StudyModuleSheet(current: current),
  );
}

class StudyModuleSheet extends StatefulWidget {
  const StudyModuleSheet({super.key, required this.current});

  /// The settings each module has now. A module with none is off.
  final Map<StudyModuleKey, StudyModuleSettings> current;

  @override
  State<StudyModuleSheet> createState() => _StudyModuleSheetState();
}

class _StudyModuleSheetState extends State<StudyModuleSheet> {
  final Map<StudyModuleKey, bool> _enabled = {};
  final Map<StudyModuleKey, TextEditingController> _names = {};
  final Map<StudyModuleKey, StudyPostPolicy> _policies = {};

  /// The modules an admin can turn on in this version.
  List<StudyModuleKey> get _live =>
      StudyModuleKey.values.where((key) => key.isLive).toList();

  /// The modules that are not built yet, listed so the group knows what is coming.
  List<StudyModuleKey> get _coming =>
      StudyModuleKey.values.where((key) => !key.isLive).toList();

  @override
  void initState() {
    super.initState();
    for (final key in StudyModuleKey.values) {
      final settings = widget.current[key];
      _enabled[key] = settings?.enabled ?? false;
      _names[key] = TextEditingController(text: settings?.name ?? '');
      _policies[key] = settings?.postPolicy ?? StudyPostPolicy.members;
    }
  }

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _defaultName(StudyModuleKey key) =>
      context.l10n.translate(studyModuleLabelKey(key));

  void _save() {
    final result = <StudyModuleSettings>[];
    for (final key in _live) {
      final typed = _names[key]!.text.trim();
      result.add(StudyModuleSettings(
        key: key,
        enabled: _enabled[key]!,
        name: typed.isEmpty ? _defaultName(key) : typed,
        postPolicy: _policies[key]!,
      ));
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
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
                l10n.translate('study_module_sheet_title'),
                style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final key in _live) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate(studyModuleLabelKey(key)),
                      style: TextStyle(color: palette.text)),
                  value: _enabled[key]!,
                  onChanged: (value) => setState(() => _enabled[key] = value),
                ),
                TextField(
                  controller: _names[key],
                  maxLength: 40,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: l10n.translate('study_module_name_label'),
                    hintText: _defaultName(key),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.translate('study_module_policy_label'),
                  style: TextStyle(color: palette.text70),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final policy in StudyPostPolicy.values)
                      ChoiceChip(
                        label: Text(l10n.translate(studyPolicyKey(policy))),
                        selected: _policies[key] == policy,
                        onSelected: (_) =>
                            setState(() => _policies[key] = policy),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              for (final key in _coming)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l10n.translate('study_module_coming_item',
                        args: {'name': _defaultName(key)}),
                    style: TextStyle(color: palette.text54),
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.translate('study_save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/dependent_models.dart';
import '../../domain/models/tour_group.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// The people in a family who have no account, such as children and grandparents.
/// Each one is listed under the member who looks after them, and that member's
/// family size counts them. Only that member adds or removes them.
class FamilyDependentsScreen extends StatefulWidget {
  const FamilyDependentsScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<FamilyDependentsScreen> createState() => _FamilyDependentsScreenState();
}

class _FamilyDependentsScreenState extends State<FamilyDependentsScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<TourMember>> _members =
      _repository.watchMembers(widget.tourId);
  late final Stream<List<Dependent>> _dependents =
      _repository.watchDependents(widget.tourId);

  String get _me => _repository.currentEmail;

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final entry = await showDialog<({String name, String relation})>(
      context: context,
      builder: (_) => const _DependentPrompt(),
    );
    if (entry == null || !mounted) return;
    try {
      await _repository.addDependent(
        widget.tourId,
        name: entry.name,
        relation: entry.relation,
      );
    } catch (err) {
      logError('Dependent add failed: $err');
      _toast(l10n.translate('dp_save_failed'), error: true);
    }
  }

  Future<void> _remove(Dependent dependent) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(l10n.translate('dp_remove_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('dp_remove_body'),
            style: const TextStyle(color: Colors.white70)),
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
    try {
      await _repository.removeDependent(widget.tourId, dependent);
    } catch (err) {
      logError('Dependent remove failed: $err');
      _toast(l10n.translate('dp_remove_failed'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(l10n.translate('dp_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.translate('dp_add')),
        onPressed: _add,
      ),
      body: StreamBuilder<List<TourMember>>(
        stream: _members,
        builder: (context, memberSnap) {
          final members = memberSnap.data;
          if (members == null) return _spinner();
          return StreamBuilder<List<Dependent>>(
            stream: _dependents,
            builder: (context, depSnap) {
              if (depSnap.hasError) {
                return _message(l10n.translate('dp_load_failed'));
              }
              final dependents = depSnap.data;
              if (dependents == null) return _spinner();
              return _list(members, dependents, l10n);
            },
          );
        },
      ),
    );
  }

  Widget _list(List<TourMember> members, List<Dependent> dependents,
      AppLocalizations l10n) {
    // The signed-in member first, then the others by name.
    final active = [
      for (final m in members)
        if (m.status == TourMemberStatus.active) m,
    ]..sort((a, b) {
        if (a.email == _me) return -1;
        if (b.email == _me) return 1;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        Text(l10n.translate('dp_intro'),
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 10),
        for (final member in active) _memberCard(member, dependents, l10n),
      ],
    );
  }

  Widget _memberCard(
      TourMember member, List<Dependent> dependents, AppLocalizations l10n) {
    final mine = member.email == _me;
    final listed = [
      for (final d in dependents)
        if (d.parentEmail == member.email) d,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final name = member.displayName.isEmpty ? member.email : member.displayName;

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mine ? '$name · ${l10n.translate('dp_you')}' : name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
                Text(
                  l10n.translate('dp_family_size',
                      args: {'count': l10n.number(member.familyCount)}),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            if (listed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.translate('dp_none'),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              )
            else
              for (final d in listed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF1E3326),
                    child: Text(
                      String.fromCharCode(d.name.runes.first).toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title:
                      Text(d.name, style: const TextStyle(color: Colors.white)),
                  subtitle: d.relation.isEmpty
                      ? null
                      : Text(d.relation,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                  trailing: mine
                      ? IconButton(
                          tooltip: l10n.translate('dp_remove_tip'),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white54),
                          onPressed: () => _remove(d),
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  Widget _spinner() => const Center(
      child: CircularProgressIndicator(color: AppColors.mintGreen));

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      );
}

/// The dialog that takes a name and a relation. It owns its controllers, so they
/// are disposed with it.
class _DependentPrompt extends StatefulWidget {
  const _DependentPrompt();

  @override
  State<_DependentPrompt> createState() => _DependentPromptState();
}

class _DependentPromptState extends State<_DependentPrompt> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _relation = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: _card,
      title: Text(l10n.translate('dp_add_title'),
          style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: kMaxDependentNameLength,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.translate('dp_name_label'),
            ),
          ),
          TextField(
            controller: _relation,
            maxLength: kMaxDependentRelationLength,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.translate('dp_relation_label'),
              hintText: l10n.translate('dp_relation_hint'),
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('fd_cancel')),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
                context, (name: name, relation: _relation.text.trim()));
          },
          child: Text(l10n.translate('fd_save')),
        ),
      ],
    );
  }
}

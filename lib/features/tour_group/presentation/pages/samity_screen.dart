import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/samity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/samity_engine.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../samity_pdf_export.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);
const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
);

/// A rotating savings group's schedule and records: what each member pays in each
/// cycle, who takes the pot, and who still owes. The app keeps the records; no money
/// moves through it. The owner or an admin sets the schedule and records a handover;
/// members record what they have paid.
class SamityScreen extends StatefulWidget {
  const SamityScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<SamityScreen> createState() => _SamityScreenState();
}

class _SamityScreenState extends State<SamityScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];

  TourGroup? _group;
  bool _loaded = false;
  bool _failed = false;
  List<TourMember> _members = const [];
  List<SamityPayment> _payments = const [];
  List<SamityPayout> _payouts = const [];
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _subs.add(_repository.watchGroup(widget.tourId).listen(
          (group) => setState(() {
            _group = group;
            _loaded = true;
          }),
          onError: (Object _) => setState(() => _failed = true),
        ));
    _subs.add(_repository.watchMembers(widget.tourId).listen(
          (members) => setState(() => _members = members),
          onError: (Object _) {},
        ));
    _subs.add(_repository.watchSamityPayments(widget.tourId).listen(
          (payments) => setState(() => _payments = payments),
          onError: (Object _) => setState(() => _failed = true),
        ));
    _subs.add(_repository.watchSamityPayouts(widget.tourId).listen(
          (payouts) => setState(() => _payouts = payouts),
          onError: (Object _) => setState(() => _failed = true),
        ));
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  SamityLedger _ledgerFor(SamityConfig config) => SamityLedger(
        config: config,
        payments: _payments,
        payouts: _payouts,
        today: DateTime.now(),
      );

  Future<void> _openSetup() async {
    final l10n = context.l10n;
    final group = _group;
    if (group == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      backgroundColor: context.forest.surfaceFor(_card),
      shape: _sheetShape,
      builder: (_) => _SetupSheet(
        repository: _repository,
        tourId: widget.tourId,
        config: group.samity,
        members: _members,
      ),
    );
    if (saved == true) _toast(l10n.translate('samity_setup_saved'));
  }

  Future<void> _openCycle(SamityCycle cycle) async {
    final group = _group;
    if (group == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      backgroundColor: context.forest.surfaceFor(_card),
      shape: _sheetShape,
      builder: (_) => _CycleSheet(
        repository: _repository,
        tourId: widget.tourId,
        config: group.samity,
        cycleIndex: cycle.index,
        members: _members,
        isAdmin: _isAdmin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = _group;
    final samityOn = group != null && group.isSamity;
    return Scaffold(
      backgroundColor: context.forest.surfaceFor(_bg),
      appBar: AppBar(
        title: Text(l10n.translate('samity_title'),
            style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        backgroundColor: context.forest.surfaceFor(_card),
        foregroundColor: context.forest.text,
        elevation: 0,
        actions: [
          if (samityOn && group.samity.isSetUp)
            IconButton(
              tooltip: l10n.translate('samity_export_pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => exportSamityPdf(
                context,
                group: group,
                members: _members,
                payments: _payments,
                payouts: _payouts,
              ),
            ),
          if (_isAdmin && samityOn)
            IconButton(
              tooltip: l10n.translate('samity_setup'),
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openSetup,
            ),
        ],
      ),
      body: _body(l10n, group, samityOn),
    );
  }

  Widget _body(AppLocalizations l10n, TourGroup? group, bool samityOn) {
    if (_failed) return _message(l10n.translate('samity_load_failed'));
    if (!_loaded) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.mintGreen));
    }
    if (group == null || !samityOn) {
      return _message(l10n.translate('samity_not_set_up'));
    }
    final config = group.samity;
    if (!config.isSetUp) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _message(l10n.translate('samity_not_set_up')),
          if (_isAdmin)
            Center(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                ),
                onPressed: _openSetup,
                child: Text(l10n.translate('samity_setup')),
              ),
            ),
        ],
      );
    }
    final ledger = _ledgerFor(config);
    final me = _myEmail;
    final current = ledger.currentCycle;
    final next = ledger.nextPayout;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _panel(
          children: [
            Text(
                l10n.translate('samity_pot', args: {
                  'amount': _taka(config.potTaka),
                }),
                style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(
                l10n.translate('samity_monthly_amount', args: {
                  'amount': _taka(config.contributionTaka),
                }),
                style: TextStyle(color: context.forest.text70, fontSize: 12)),
            if (current != null) ...[
              const SizedBox(height: 10),
              Text(
                  l10n.translate('samity_progress', args: {
                    'current': l10n.number(current.number),
                    'total': l10n.number(config.cycleCount),
                  }),
                  style: TextStyle(
                      color: context.forest.accentText,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                  '${_collectedText(l10n, ledger.collectedFor(current.index), current.potTaka)} · '
                  '${_dueText(l10n, current.dueOn)}',
                  style: TextStyle(color: context.forest.text54, fontSize: 12)),
            ],
            const SizedBox(height: 6),
            Text(
                next == null
                    ? l10n.translate('samity_no_next_payout')
                    : l10n.translate('samity_next_payout', args: {
                        'name': _nameOf(next.recipientEmail),
                      }),
                style: TextStyle(color: context.forest.text70, fontSize: 12)),
          ],
        ),
        if (config.payoutOrder.contains(me)) ...[
          const SizedBox(height: 10),
          _mine(l10n, config, ledger, me),
        ],
        const SizedBox(height: 16),
        _sectionTitle(l10n.translate('samity_cycles_title')),
        for (final cycle in ledger.schedule) _cycleTile(cycle, ledger, l10n),
        const SizedBox(height: 16),
        _sectionTitle(l10n.translate('samity_owed_title')),
        for (final standing in ledger.standings())
          _standingTile(standing, l10n),
      ],
    );
  }

  String get _myEmail => _repository.currentEmail;

  Widget _mine(AppLocalizations l10n, SamityConfig config, SamityLedger ledger,
      String me) {
    final owed = ledger.owedBy(me);
    final due = _nextUnpaidFor(me, config, ledger);
    return _panel(
      children: [
        Text(l10n.translate('samity_my_standing'),
            style: TextStyle(
                color: context.forest.accentText,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        const SizedBox(height: 6),
        Text(
            owed == 0
                ? l10n.translate('samity_all_paid_up')
                : l10n
                    .translate('samity_my_owed', args: {'amount': _taka(owed)}),
            style: TextStyle(
                color: owed == 0
                    ? context.forest.accentText
                    : context.forest.readable(Colors.redAccent),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
            l10n.translate('samity_my_paid',
                args: {'amount': _taka(ledger.paidAcross(me))}),
            style: TextStyle(color: context.forest.text70, fontSize: 12)),
        if (due != null) ...[
          const SizedBox(height: 2),
          Text(
              l10n.translate('samity_my_next', args: {
                'number': l10n.number(due.number),
                'date': _dateLabel(due.dueOn),
              }),
              style: TextStyle(color: context.forest.text70, fontSize: 12)),
        ],
      ],
    );
  }

  /// The first cycle the member has not paid in full, or null when all are paid.
  SamityCycle? _nextUnpaidFor(
      String email, SamityConfig config, SamityLedger ledger) {
    for (final cycle in ledger.schedule) {
      if (ledger.paidBy(email, cycle.index) < config.contributionTaka) {
        return cycle;
      }
    }
    return null;
  }

  Widget _cycleTile(
      SamityCycle cycle, SamityLedger ledger, AppLocalizations l10n) {
    final status = ledger.statusOf(cycle);
    return Card(
      color: context.forest.surfaceFor(_card),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openCycle(cycle),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.mintGreen.withValues(alpha: 0.2),
          child: Text(l10n.number(cycle.number),
              style: TextStyle(
                  color: context.forest.accentText,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(
            l10n.translate('samity_cycle_title',
                args: {'number': l10n.number(cycle.number)}),
            style: TextStyle(
                color: context.forest.text, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${_recipientText(l10n, _nameOf(cycle.recipientEmail))}\n'
          '${_dueText(l10n, cycle.dueOn)} · '
          '${_collectedText(l10n, ledger.collectedFor(cycle.index), cycle.potTaka)}',
          style: TextStyle(color: context.forest.text54, fontSize: 12),
        ),
        isThreeLine: true,
        trailing: _StatusChip(
          label: _statusText(l10n, status),
          color: _statusTone(context, status),
        ),
      ),
    );
  }

  Widget _standingTile(SamityStanding standing, AppLocalizations l10n) {
    return Card(
      color: context.forest.surfaceFor(_card),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text(_nameOf(standing.email),
            style: TextStyle(color: context.forest.text)),
        trailing: Text(
          standing.isUpToDate
              ? l10n.translate('samity_all_paid_up')
              : l10n.translate('samity_owes',
                  args: {'amount': _taka(standing.owedTaka)}),
          style: TextStyle(
              color: standing.isUpToDate
                  ? context.forest.accentText
                  : context.forest.readable(Colors.redAccent),
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _panel({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.forest.surfaceFor(_card),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Text(text,
            style: TextStyle(
                color: context.forest.accentText,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text60)),
      );

  String _nameOf(String email) => _displayName(_members, email);
}

String _displayName(List<TourMember> members, String email) {
  for (final member in members) {
    if (member.email == email) {
      return member.displayName.isEmpty ? email : member.displayName;
    }
  }
  return email;
}

/// A whole-taka amount, with the app's money format.
String _taka(int taka) => TripLedgerEngine.formatTaka(taka * 100);

String _dateLabel(DateTime date) =>
    localizedDateFormat('d MMM yyyy').format(date);

String _collectedText(AppLocalizations l10n, int paid, int due) =>
    l10n.translate('samity_collected_of', args: {
      'paid': _taka(paid),
      'due': _taka(due),
    });

String _dueText(AppLocalizations l10n, DateTime due) =>
    l10n.translate('samity_cycle_due', args: {'date': _dateLabel(due)});

String _recipientText(AppLocalizations l10n, String name) =>
    l10n.translate('samity_cycle_recipient', args: {'name': name});

String _statusText(AppLocalizations l10n, SamityCycleStatus status) {
  switch (status) {
    case SamityCycleStatus.upcoming:
      return l10n.translate('samity_status_upcoming');
    case SamityCycleStatus.due:
      return l10n.translate('samity_status_due');
    case SamityCycleStatus.overdue:
      return l10n.translate('samity_status_overdue');
    case SamityCycleStatus.collected:
      return l10n.translate('samity_status_collected');
    case SamityCycleStatus.paidOut:
      return l10n.translate('samity_status_paid_out');
  }
}

Color _statusTone(BuildContext context, SamityCycleStatus status) {
  switch (status) {
    case SamityCycleStatus.upcoming:
      return context.forest.text54;
    case SamityCycleStatus.due:
      return const Color(0xFFF59E0B);
    case SamityCycleStatus.overdue:
      return Colors.redAccent;
    case SamityCycleStatus.collected:
      return const Color(0xFF38BDF8);
    case SamityCycleStatus.paidOut:
      return AppColors.mintGreen;
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

/// One cycle in full: who has paid in, and who takes the pot. A member records their own
/// payment; an owner or admin records anyone's, and records the handover of the pot.
class _CycleSheet extends StatefulWidget {
  const _CycleSheet({
    required this.repository,
    required this.tourId,
    required this.config,
    required this.cycleIndex,
    required this.members,
    required this.isAdmin,
  });

  final TourGroupRepository repository;
  final String tourId;
  final SamityConfig config;
  final int cycleIndex;
  final List<TourMember> members;
  final bool isAdmin;

  @override
  State<_CycleSheet> createState() => _CycleSheetState();
}

class _CycleSheetState extends State<_CycleSheet> {
  late final Stream<List<SamityPayment>> _payments =
      widget.repository.watchSamityPayments(widget.tourId);
  late final Stream<List<SamityPayout>> _payouts =
      widget.repository.watchSamityPayouts(widget.tourId);

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.darkGreen));
  }

  Future<void> _recordPayment(String email, int paid) async {
    final l10n = context.l10n;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l10n.translate('samity_record_for', args: {
          'name': _displayName(widget.members, email),
        }),
        initial: paid,
        max: widget.config.contributionTaka,
      ),
    );
    if (amount == null || !mounted) return;
    try {
      if (amount == 0) {
        if (paid > 0) {
          await widget.repository.deleteSamityPayment(
            widget.tourId,
            SamityPayment.paymentId(widget.cycleIndex, email),
          );
        }
      } else {
        await widget.repository.saveSamityPayment(
          widget.tourId,
          SamityPayment(
            cycle: widget.cycleIndex,
            email: email,
            amountTaka: amount,
          ),
        );
      }
      _toast(l10n.translate(
          amount == 0 ? 'samity_record_removed' : 'samity_record_saved'));
    } catch (err) {
      logError('Samity payment save failed: $err');
      _toast(l10n.translate('samity_save_failed', args: {'error': err}),
          error: true);
    }
  }

  Future<void> _recordPayout(SamityCycle cycle, int collected) async {
    final l10n = context.l10n;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l10n.translate('samity_record_payout'),
        initial: collected,
        max: cycle.potTaka,
      ),
    );
    if (amount == null || !mounted) return;
    if (amount < 1) {
      _toast(
          l10n.translate('samity_amount_invalid', args: {
            'max': l10n.number(cycle.potTaka),
          }),
          error: true);
      return;
    }
    try {
      await widget.repository.saveSamityPayout(
        widget.tourId,
        SamityPayout(
          cycle: cycle.index,
          recipientEmail: cycle.recipientEmail,
          amountTaka: amount,
        ),
      );
      _toast(l10n.translate('samity_payout_saved', args: {
        'name': _displayName(widget.members, cycle.recipientEmail),
      }));
    } catch (err) {
      logError('Samity payout save failed: $err');
      _toast(l10n.translate('samity_save_failed', args: {'error': err}),
          error: true);
    }
  }

  Future<void> _removePayout(SamityCycle cycle) async {
    final l10n = context.l10n;
    try {
      await widget.repository.deleteSamityPayout(
        widget.tourId,
        samityCycleKey(cycle.index),
      );
      _toast(l10n.translate('samity_payout_removed'));
    } catch (err) {
      logError('Samity payout delete failed: $err');
      _toast(l10n.translate('samity_save_failed', args: {'error': err}),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = widget.repository.currentEmail;
    return StreamBuilder<List<SamityPayment>>(
      stream: _payments,
      builder: (context, paySnap) {
        return StreamBuilder<List<SamityPayout>>(
          stream: _payouts,
          builder: (context, outSnap) {
            final ledger = SamityLedger(
              config: widget.config,
              payments: paySnap.data ?? const [],
              payouts: outSnap.data ?? const [],
              today: DateTime.now(),
            );
            if (widget.cycleIndex >= ledger.schedule.length) {
              return const SizedBox.shrink();
            }
            final cycle = ledger.schedule[widget.cycleIndex];
            final collected = ledger.collectedFor(cycle.index);
            final payout = ledger.payoutFor(cycle.index);
            final status = ledger.statusOf(cycle);
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              l10n.translate('samity_cycle_title', args: {
                                'number': l10n.number(cycle.number),
                              }),
                              style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ),
                        _StatusChip(
                          label: _statusText(l10n, status),
                          color: _statusTone(context, status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        '${_recipientText(l10n, _displayName(widget.members, cycle.recipientEmail))} · '
                        '${_dueText(l10n, cycle.dueOn)}',
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(_collectedText(l10n, collected, cycle.potTaka),
                        style: TextStyle(
                            color: context.forest.accentText,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    for (final email in widget.config.payoutOrder)
                      _memberRow(
                        email: email,
                        paid: ledger.paidBy(email, cycle.index),
                        contribution: widget.config.contributionTaka,
                        isRecipient: email == cycle.recipientEmail,
                        canRecord: widget.isAdmin || email == me,
                        onTap: () => _recordPayment(
                            email, ledger.paidBy(email, cycle.index)),
                        l10n: l10n,
                      ),
                    if (widget.isAdmin) ...[
                      const SizedBox(height: 14),
                      if (payout == null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.mintGreen,
                            foregroundColor: AppColors.darkGreen,
                          ),
                          onPressed: collected == 0
                              ? null
                              : () => _recordPayout(cycle, collected),
                          icon: const Icon(Icons.payments_rounded),
                          label: Text(l10n.translate('samity_record_payout')),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  '${l10n.translate('samity_payout_amount')}: '
                                  '${_taka(payout.amountTaka)}',
                                  style: TextStyle(
                                      color: context.forest.accentText,
                                      fontWeight: FontWeight.w600)),
                            ),
                            TextButton(
                              onPressed: () => _removePayout(cycle),
                              child: Text(l10n.translate('fd_delete'),
                                  style: TextStyle(
                                      color: context.forest
                                          .readable(Colors.redAccent))),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _memberRow({
    required String email,
    required int paid,
    required int contribution,
    required bool isRecipient,
    required bool canRecord,
    required VoidCallback onTap,
    required AppLocalizations l10n,
  }) {
    final name = _displayName(widget.members, email);
    return Card(
      color: context.forest.surfaceFor(const Color(0xFF1B3A2F)),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: canRecord ? onTap : null,
        title: Text(name, style: TextStyle(color: context.forest.text)),
        subtitle: isRecipient
            ? Text(
                l10n.translate('samity_cycle_recipient', args: {'name': name}),
                style: TextStyle(color: context.forest.text54, fontSize: 12))
            : null,
        trailing: Text(
          l10n.translate('samity_members_paid', args: {
            'paid': _taka(paid),
            'due': _taka(contribution),
          }),
          style: TextStyle(
              color: paid >= contribution
                  ? context.forest.accentText
                  : context.forest.text70,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Asks for a whole-taka amount between zero and [max]. Closes with the amount.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.initial,
    required this.max,
  });

  final String title;
  final int initial;
  final int max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.initial == 0 ? '' : widget.initial.toString());
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final text = _controller.text.trim();
    final value = text.isEmpty ? 0 : int.tryParse(text);
    if (value == null || value < 0 || value > widget.max) {
      setState(() => _error = l10n.translate('samity_amount_invalid', args: {
            'max': l10n.number(widget.max),
          }));
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: context.forest.surfaceFor(_card),
      title: Text(widget.title, style: TextStyle(color: context.forest.text)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(color: context.forest.text),
        decoration: InputDecoration(
          labelText: l10n.translate('samity_paid_so_far'),
          errorText: _error,
          labelStyle: TextStyle(color: context.forest.text70),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('tour_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.translate('tour_save')),
        ),
      ],
    );
  }
}

class _SetupSlot {
  _SetupSlot({required this.email, required this.name, required this.included});

  final String email;
  final String name;
  bool included;
}

/// The schedule: the amount each member pays, the first month, the due day, and the
/// payout order. Members left out of the order are not in the rotation. Saves and closes
/// with true.
class _SetupSheet extends StatefulWidget {
  const _SetupSheet({
    required this.repository,
    required this.tourId,
    required this.config,
    required this.members,
  });

  final TourGroupRepository repository;
  final String tourId;
  final SamityConfig config;
  final List<TourMember> members;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late final TextEditingController _amount = TextEditingController(
      text: widget.config.contributionTaka == 0
          ? ''
          : widget.config.contributionTaka.toString());
  late DateTime _month = widget.config.firstMonth ??
      DateTime(DateTime.now().year, DateTime.now().month + 1);
  late int _dueDay = widget.config.dueDay;
  late final List<_SetupSlot> _order = _initialOrder();
  bool _saving = false;
  String? _error;

  List<_SetupSlot> _initialOrder() {
    final inRotation = [
      for (final email in widget.config.payoutOrder)
        _SetupSlot(
          email: email,
          name: _displayName(widget.members, email),
          included: true,
        ),
    ];
    final rest = [
      for (final member in widget.members)
        if (!widget.config.payoutOrder.contains(member.email))
          _SetupSlot(
            email: member.email,
            name:
                member.displayName.isEmpty ? member.email : member.displayName,
            included: false,
          ),
    ];
    return [...inRotation, ...rest];
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount < 1 || amount > kSamityMaxContributionTaka) {
      setState(() => _error = l10n.translate('samity_amount_invalid', args: {
            'max': l10n.number(kSamityMaxContributionTaka),
          }));
      return;
    }
    final included = [
      for (final slot in _order)
        if (slot.included) slot.email,
    ];
    if (included.isEmpty) {
      setState(() => _error = l10n.translate('samity_no_members_chosen'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveSamityConfig(
        widget.tourId,
        SamityConfig(
          contributionTaka: amount,
          startMonth: samityMonthKey(_month),
          dueDay: _dueDay,
          payoutOrder: included,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      logError('Samity schedule save failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.translate('samity_save_failed', args: {'error': err});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.translate('samity_setup_title'),
                  style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('samity_contribution_label'),
                  labelStyle: TextStyle(color: context.forest.text70),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.translate('samity_start_month_label'),
                    style:
                        TextStyle(color: context.forest.text70, fontSize: 13)),
                subtitle: Text(localizedDateFormat('MMMM yyyy').format(_month),
                    style: TextStyle(color: context.forest.text, fontSize: 15)),
                trailing: Icon(Icons.calendar_month_rounded,
                    color: context.forest.accentText),
                onTap: _pickMonth,
              ),
              DropdownButtonFormField<int>(
                initialValue: _dueDay,
                dropdownColor:
                    context.forest.surfaceFor(const Color(0xFF1B4332)),
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                  labelText: l10n.translate('samity_due_day_label'),
                  labelStyle: TextStyle(color: context.forest.text70),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (var day = 1; day <= kSamityMaxDueDay; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text(l10n.number(day)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _dueDay = value);
                },
              ),
              const SizedBox(height: 14),
              Text(l10n.translate('samity_order_label'),
                  style: TextStyle(
                      color: context.forest.accentText,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text(l10n.translate('samity_order_hint'),
                  style: TextStyle(color: context.forest.text54, fontSize: 12)),
              const SizedBox(height: 6),
              SizedBox(
                height: 320,
                child: ReorderableListView(
                  buildDefaultDragHandles: true,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final slot = _order.removeAt(oldIndex);
                      _order.insert(newIndex, slot);
                    });
                  },
                  children: [
                    for (final slot in _order)
                      CheckboxListTile(
                        key: ValueKey(slot.email),
                        value: slot.included,
                        activeColor: AppColors.mintGreen,
                        contentPadding: const EdgeInsets.only(left: 4),
                        title: Text(slot.name,
                            style: TextStyle(color: context.forest.text)),
                        subtitle: Text(
                            slot.included
                                ? l10n.translate('samity_in_rotation')
                                : slot.email,
                            style: TextStyle(
                                color: context.forest.text54, fontSize: 12)),
                        onChanged: (value) =>
                            setState(() => slot.included = value ?? false),
                      ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(
                        color: context.forest.readable(Colors.redAccent),
                        fontSize: 12)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                ),
                onPressed: _saving ? null : _save,
                child: Text(l10n.translate('samity_save_setup')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

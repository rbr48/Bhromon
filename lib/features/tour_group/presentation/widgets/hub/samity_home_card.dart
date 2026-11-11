import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/samity_models.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/samity_engine.dart';

const _card = Color(0xFF142428);

/// Purpose-driven hero status card for a Rotating Savings Group (Samity / ROSCA).
/// Displays active cycle, current pot recipient, member's payment status, and quick actions.
class SamityHomeCard extends StatefulWidget {
  const SamityHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  State<SamityHomeCard> createState() => _SamityHomeCardState();
}

class _SamityHomeCardState extends State<SamityHomeCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<SamityPayment> _payments = const [];
  List<SamityPayout> _payouts = const [];
  List<TourMember> _members = const [];
  List<TourNotice> _notices = const [];

  @override
  void initState() {
    super.initState();
    final id = widget.group.id;
    _subs.addAll([
      _repository
          .watchSamityPayments(id)
          .listen((v) => _update(() => _payments = v), onError: (Object _) {}),
      _repository
          .watchSamityPayouts(id)
          .listen((v) => _update(() => _payouts = v), onError: (Object _) {}),
      _repository
          .watchMembers(id)
          .listen((v) => _update(() => _members = v), onError: (Object _) {}),
      _repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}),
    ]);
    _dayTick = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _dayTick?.cancel();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final samity = widget.group.samity;
    final base = '/group/${widget.group.id}';

    return Container(
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(_card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: context.forest.accentText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('samity_home_title'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                localizedDateFormat('EEE, d MMM').format(now),
                style: TextStyle(color: context.forest.text54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!samity.isSetUp) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.forest.inset26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.forest.divider10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 20, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.translate('samity_home_setup_needed'),
                      style: TextStyle(
                        color: context.forest.text70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            () {
              final ledger = SamityLedger(
                config: samity,
                payments: _payments,
                payouts: _payouts,
                today: now,
              );
              final current = ledger.currentCycle;
              final nextPayout = ledger.nextPayout;
              final recipientEmail =
                  current?.recipientEmail ?? nextPayout?.recipientEmail ?? '';

              String recipientName = recipientEmail;
              for (final m in _members) {
                if (m.email.toLowerCase().trim() ==
                    recipientEmail.toLowerCase().trim()) {
                  recipientName = m.displayName;
                  break;
                }
              }

              final myEmail = _repository.currentEmail.toLowerCase().trim();
              final cycleIndex = current?.index ?? 1;
              final paid = ledger.paidBy(myEmail, cycleIndex);
              final isPaid = paid >= samity.contributionTaka;

              final totalCycles = samity.cycleCount;
              final cycleMonth = current != null
                  ? localizedDateFormat('MMMM yyyy').format(current.dueOn)
                  : '';

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.forest.inset26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.forest.divider10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.translate('samity_home_cycle_info', args: {
                              'current': l10n.number(cycleIndex),
                              'total': l10n.number(totalCycles),
                              'month': cycleMonth,
                            }),
                            style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? context.forest
                                    .surfaceFor(const Color(0xFF1B4D3E))
                                : AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPaid
                                ? l10n.translate('samity_home_paid')
                                : l10n.translate('samity_home_due', args: {
                                    'amount': l10n
                                        .number(samity.contributionTaka - paid)
                                  }),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isPaid
                                  ? context.forest
                                      .readable(const Color(0xFF52B788))
                                  : AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (recipientName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.translate('samity_home_payout_to',
                            args: {'name': recipientName}),
                        style: TextStyle(
                          color: context.forest.text70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }(),
          ],
          if (_notices.isNotEmpty) ...[
            const SizedBox(height: 8),
            _row(
              icon: Icons.campaign_outlined,
              text: l10n.translate('fh_notice_latest',
                  args: {'title': _notices.first.title}),
              onTap: () => context.push('$base/notices'),
            ),
          ],
          const SizedBox(height: 8),
          // Quick actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: AppColors.mintGreen.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => context.push('$base/samity'),
                  icon: Icon(Icons.list_alt_rounded,
                      size: 14,
                      color: context.forest.readable(const Color(0xFF52B788))),
                  label: Text(
                    l10n.translate('samity_home_view_btn'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: AppColors.mintGreen.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => context.push('$base/ledger'),
                  icon: Icon(Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: context.forest.readable(const Color(0xFF52B788))),
                  label: Text(
                    l10n.translate('samity_home_fund_btn'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: context.forest.text60, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.forest.text70, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.forest.text38, size: 16),
          ],
        ),
      ),
    );
  }
}

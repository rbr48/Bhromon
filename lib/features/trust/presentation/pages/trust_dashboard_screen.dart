import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../bloc/trust_bloc.dart';
import '../bloc/trust_event.dart';
import '../bloc/trust_state.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

class TrustDashboardScreen extends StatefulWidget {
  const TrustDashboardScreen({super.key});

  @override
  State<TrustDashboardScreen> createState() => _TrustDashboardScreenState();
}

class _TrustDashboardScreenState extends State<TrustDashboardScreen> {
  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthCubit>().state;
    final uid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    context.read<TrustBloc>().add(SubscribeScoreEvent(uid));
  }

  Color _getTierColor(TrustTier tier) {
    switch (tier) {
      case TrustTier.community:
        return AppColors.tierCommunity;
      case TrustTier.verified:
        return AppColors.tierVerifiedExplorer;
      case TrustTier.regionExpert:
        return AppColors.tierRegionExpert;
      case TrustTier.pioneer:
        return AppColors.tierPioneer;
      default:
        return AppColors.tierUnverified;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Trust & Moderation Dashboard'),
        backgroundColor: AppColors.cardDark,
        elevation: 0,
        centerTitle: true,
      ),
      body: BlocConsumer<TrustBloc, TrustState>(
        listener: (context, state) {
          if (state.appealStatus == AppealStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Appeal submitted successfully! Under review.')),
            );
          } else if (state.appealStatus == AppealStatus.error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(state.errorMessage ?? 'Appeal submission failed.')),
            );
          }
        },
        builder: (context, state) {
          if (state.status == TrustStatus.loading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.mintGreen),
            );
          }

          if (state.status == TrustStatus.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.errorMessage ?? 'Failed to load trust data.',
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final authState = context.read<AuthCubit>().state;
                      final uid = authState is Authenticated
                          ? authState.profile.uid
                          : 'explorer_user';
                      context.read<TrustBloc>().add(SubscribeScoreEvent(uid));
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.mintGreen),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final color = _getTierColor(state.tier);
          final scoreValue = state.score;

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Interactive Gauge Card
                Card(
                  color: AppColors.cardDark,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 32.0, horizontal: 16.0),
                    child: Column(
                      children: [
                        // Styled Circular Progress Ring representing score
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 140,
                              child: CircularProgressIndicator(
                                value: scoreValue / 1000.0,
                                strokeWidth: 10,
                                backgroundColor: Colors.white10,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  scoreValue.toString(),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const Text(
                                  'TRUST SCORE',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Tier: ${state.tier.displayName}',
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Moderation authority is active. Maintain your score above 500 to keep verified status.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 2. Score Breakdown Card
                const Text(
                  'SCORE FORMULA & CONTRIBUTIONS',
                  style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),
                Card(
                  color: AppColors.cardDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        _buildFormulaRow('Base Score', '+100', Colors.white70),
                        const Divider(color: Colors.white10),
                        _buildFormulaRow(
                            'Verified Contributions',
                            '+${(scoreValue - 100).clamp(0, 900)}',
                            AppColors.mintGreen),
                        const Divider(color: Colors.white10),
                        _buildFormulaRow(
                            'Community Flags', '-0', Colors.redAccent),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 3. Flags and Appeals section
                const Text(
                  'ACTIVE PENALTIES & APPEALS',
                  style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),
                Card(
                  color: AppColors.cardDark,
                  child: ListTile(
                    leading:
                        const Icon(Icons.warning_amber, color: AppColors.amber),
                    title: const Text('Spam Flag on Sajek TipLog',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                        'Penalty weight: -5 points • 3 days ago',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () => _showAppealSheet(context),
                      child: const Text('Appeal',
                          style: TextStyle(color: AppColors.gold)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormulaRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showAppealSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom +
              MediaQuery.of(modalContext).padding.bottom +
              24,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Submit Flag Appeal',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Justify why this content flag is inaccurate. A moderator will review it within 24 hours.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Describe the validity of your post...',
                hintStyle: const TextStyle(color: Colors.white54),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.mintGreen),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isNotEmpty) {
                  context.read<TrustBloc>().add(SubmitAppealEvent(
                      targetId: 'flag_sajek_1', justification: reason));
                  Navigator.pop(modalContext);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.midGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Submit Appeal',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

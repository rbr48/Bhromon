import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
    return PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          context.go('/group-hub');
        },
        child: Scaffold(
          backgroundColor: context.forest.surfaceFor(AppColors.backgroundDark),
          appBar: AppBar(
            title: const Text('Trust & Moderation Dashboard'),
            backgroundColor: context.forest.surfaceFor(AppColors.cardDark),
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: context.forest.text70, size: 18),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/group-hub');
                }
              },
            ),
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
                      content: Text(
                          state.errorMessage ?? 'Appeal submission failed.')),
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
                        style: TextStyle(
                            color: context.forest.readable(Colors.redAccent)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          final authState = context.read<AuthCubit>().state;
                          final uid = authState is Authenticated
                              ? authState.profile.uid
                              : 'explorer_user';
                          context
                              .read<TrustBloc>()
                              .add(SubscribeScoreEvent(uid));
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
                      color: context.forest.surfaceFor(AppColors.cardDark),
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
                                    backgroundColor: context.forest.divider10,
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
                                    Text(
                                      'TRUST SCORE',
                                      style: TextStyle(
                                        color: context.forest.text54,
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
                            Text(
                              'Moderation authority is active. Maintain your score above 500 to keep verified status.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 11,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 2. Score Breakdown Card
                    Text(
                      'SCORE FORMULA & CONTRIBUTIONS',
                      style: TextStyle(
                          color: context.forest.text70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: context.forest.surfaceFor(AppColors.cardDark),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            _buildFormulaRow(
                                'Base Score', '+100', context.forest.text70),
                            Divider(color: context.forest.divider10),
                            _buildFormulaRow(
                                'Verified Contributions',
                                '+${(scoreValue - 100).clamp(0, 900)}',
                                AppColors.mintGreen),
                            Divider(color: context.forest.divider10),
                            _buildFormulaRow(
                                'Community Flags', '-0', Colors.redAccent),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ));
  }

  Widget _buildFormulaRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.forest.text70)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../../core/theme/theme_context.dart';

class GuideCreateScreen extends StatelessWidget {
  const GuideCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final bool isEligible = authState is Authenticated &&
        authState.profile.tier.index >= TrustTier.verified.index;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'CREATE PREMIUM GUIDE',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: isEligible
              ? _buildCreationForm(context)
              : _buildLockedBanner(context),
        ),
      ),
    );
  }

  Widget _buildLockedBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, size: 64, color: AppColors.gold),
          const SizedBox(height: 16),
          const Text(
            'FEATURE LOCKED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Creating Premium Guides is gated to Verified Explorer, Region Expert, or Pioneer trust tiers only. Post helpful tips, confirm info, and gain helpful votes to elevate your status.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Back to Discovery'),
          ),
        ],
      ),
    );
  }

  Widget _buildCreationForm(BuildContext context) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Guide Details',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: titleController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Guide Title',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.mintGreen)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: descriptionController,
          style: const TextStyle(color: Colors.white),
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.mintGreen)),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            // Save & publish premium guide logic
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Premium guide published!'),
                backgroundColor: AppColors.mintGreen,
              ),
            );
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.mintGreen,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Publish Premium Guide'),
        ),
      ],
    );
  }
}

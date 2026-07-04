import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';

class PremiumGuidePurchaseScreen extends StatelessWidget {
  final String id;

  const PremiumGuidePurchaseScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'UNLOCK GUIDE',
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.payment_outlined,
                size: 64, color: AppColors.mintGreen),
            const SizedBox(height: 24),
            const Text(
              'Purchase Guide Access',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Curated expert guides are compensated directly. Pay safely using mobile banking APIs (bKash/Nagad) to unlock permanent offline cache.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Successfully purchased premium guide access!'),
                    backgroundColor: AppColors.mintGreen,
                  ),
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Pay with bKash / Nagad'),
            ),
          ],
        ),
      ),
    );
  }
}

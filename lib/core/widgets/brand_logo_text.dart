import 'package:flutter/material.dart';

/// Renders the BHROMON brand text logo in pure Flutter code.
/// Bold letters with custom map-pin icons replacing the two "O"s.
class BhromonBrandLogo extends StatelessWidget {
  final double height;
  final Color color;

  const BhromonBrandLogo({
    super.key,
    this.height = 38,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/Bhromon.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}

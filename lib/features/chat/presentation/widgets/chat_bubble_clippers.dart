import 'package:flutter/material.dart';

// The tailed shapes of a sent and a received text bubble.

class SenderBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(12, 0);
    path.lineTo(size.width - 12, 0);
    // top-right tail shape
    path.lineTo(size.width, 0);
    path.lineTo(size.width - 6, 8);
    path.lineTo(size.width - 6, size.height - 12);
    path.quadraticBezierTo(
        size.width - 6, size.height, size.width - 18, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, 12);
    path.quadraticBezierTo(0, 0, 12, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class ReceiverBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(18, 0);
    // top-left tail shape
    path.lineTo(6, 0);
    path.lineTo(0, 0);
    path.lineTo(6, 8);
    path.lineTo(6, size.height - 12);
    path.quadraticBezierTo(6, size.height, 18, size.height);
    path.lineTo(size.width - 12, size.height);
    path.quadraticBezierTo(
        size.width, size.height, size.width, size.height - 12);
    path.lineTo(size.width, 12);
    path.quadraticBezierTo(size.width, 0, size.width - 12, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

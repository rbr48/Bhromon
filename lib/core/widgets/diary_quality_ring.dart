import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/trip_log_quality_scorer.dart';
import '../theme/colors.dart';

/// 🔵 Animated circular quality ring shown in the diary editor toolbar.
/// Displays the live quality score (0–100) with grade label.
/// Uses [TripLogQualityScorer] computed in background isolate.
class DiaryQualityRingWidget extends StatefulWidget {
  final QualityResult? result;
  final double size;

  const DiaryQualityRingWidget({
    super.key,
    this.result,
    this.size = 48,
  });

  @override
  State<DiaryQualityRingWidget> createState() => _DiaryQualityRingWidgetState();
}

class _DiaryQualityRingWidgetState extends State<DiaryQualityRingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnim;
  double _prevProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progressAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(DiaryQualityRingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newProgress = (widget.result?.score ?? 0) / 100.0;
    if (newProgress != _prevProgress) {
      _progressAnim = Tween<double>(
        begin: _prevProgress,
        end: newProgress,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
      _prevProgress = newProgress;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorFor(int score) {
    if (score >= 70) return AppColors.mintGreen;
    if (score >= 40) return AppColors.gold;
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.result?.score ?? 0;
    final grade = widget.result?.grade ?? '?';
    final color = _colorFor(score);

    return Tooltip(
      message: widget.result == null
          ? 'Diary quality: start writing'
          : '${widget.result!.gradeLabel} ($score/100)\n'
              '${widget.result!.tips.take(2).join('\n')}',
      child: AnimatedBuilder(
        animation: _progressAnim,
        builder: (context, _) {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _RingPainter(
                progress: _progressAnim.value,
                color: color,
              ),
              child: Center(
                child: Text(
                  grade,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: widget.size * 0.3,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 6) / 2;
    final bgPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

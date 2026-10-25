import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/services/discovery_score_service.dart';

class ArCompassScreen extends StatefulWidget {
  final List<LocationPin> nearbyPins;
  final Position? currentPosition;
  const ArCompassScreen(
      {super.key, required this.nearbyPins, this.currentPosition});

  @override
  State<ArCompassScreen> createState() => _ArCompassScreenState();
}

class _ArCompassScreenState extends State<ArCompassScreen>
    with SingleTickerProviderStateMixin {
  double _heading = 0;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  dynamic _magSubscription;

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Listen to magnetometer events
    _magSubscription = magnetometerEventStream().listen((event) {
      if (!mounted) return;
      final angle = atan2(event.y, event.x) * (180 / pi);
      setState(() => _heading = (angle + 360) % 360);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _magSubscription?.cancel();
    super.dispose();
  }

  String _bearingLabel(double bearing) {
    if (bearing < 22.5 || bearing >= 337.5) return 'N';
    if (bearing < 67.5) return 'NE';
    if (bearing < 112.5) return 'E';
    if (bearing < 157.5) return 'SE';
    if (bearing < 202.5) return 'S';
    if (bearing < 247.5) return 'SW';
    if (bearing < 292.5) return 'W';
    return 'NW';
  }

  double _bearingToPin(LocationPin pin) {
    if (widget.currentPosition == null) return 0;
    final lat1 = widget.currentPosition!.latitude * pi / 180;
    final lat2 = pin.lat * pi / 180;
    final dLng = (pin.lng - widget.currentPosition!.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _distanceToPin(LocationPin pin) {
    if (widget.currentPosition == null) return 0;
    return Geolocator.distanceBetween(
          widget.currentPosition!.latitude,
          widget.currentPosition!.longitude,
          pin.lat,
          pin.lng,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final closePins = widget.nearbyPins
        .where((p) => _distanceToPin(p) < 150)
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AR Compass',
            style: TextStyle(
                color: AppColors.mintGreen, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_heading.toStringAsFixed(0)}° ${_bearingLabel(_heading)}',
                style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Starfield background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Color(0xFF0A1628), Color(0xFF000010)],
              ),
            ),
          ),

          // Compass rose
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (ctx, _) => Transform.scale(
                scale: _pulseAnim.value,
                child: Transform.rotate(
                  angle: -_heading * pi / 180,
                  child: CustomPaint(
                    size: Size(size.width * 0.7, size.width * 0.7),
                    painter: _CompassPainter(),
                  ),
                ),
              ),
            ),
          ),

          // N indicator (fixed, always at top)
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text('N',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ),
          ),

          // Pin direction indicators around the compass
          ...closePins.asMap().entries.map((entry) {
            final pin = entry.value;
            final bearing = _bearingToPin(pin);
            final relBearing = (bearing - _heading + 360) % 360;
            final radians = relBearing * pi / 180;
            final radius = size.width * 0.42;
            final cx = size.width / 2 + radius * sin(radians);
            final cy = size.height / 2 - radius * cos(radians);
            final dist = _distanceToPin(pin);
            final isGem = DiscoveryScoreService.isHiddenGem(pin);

            return Positioned(
              left: cx - 30,
              top: cy - 20,
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isGem
                          ? AppColors.mintGreen.withValues(alpha: 0.85)
                          : Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.mintGreen.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            pin.name.length > 12
                                ? '${pin.name.substring(0, 12)}...'
                                : pin.name,
                            style: TextStyle(
                              color: isGem ? Colors.black : Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            )),
                        Text('${dist.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: isGem ? Colors.black54 : Colors.white54,
                              fontSize: 8,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 10,
                    color: AppColors.mintGreen.withValues(alpha: 0.5),
                  ),
                ],
              ),
            );
          }),

          // Bottom info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
              color: Colors.black.withValues(alpha: 0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoChip('🧭 Heading',
                      '${_heading.toStringAsFixed(0)}° ${_bearingLabel(_heading)}'),
                  _infoChip('📍 Nearby', '${closePins.length} pins'),
                  if (widget.currentPosition != null)
                    _infoChip('🌍 Location', 'GPS Active')
                  else
                    _infoChip('🌍 Location', 'No GPS'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: AppColors.mintGreen,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF1A3A4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Inner ring
    canvas.drawCircle(
      center,
      radius * 0.7,
      Paint()
        ..color = const Color(0xFF52B788).withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius * 0.7,
      Paint()
        ..color = const Color(0xFF52B788).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Tick marks every 30 degrees
    final tickPaint = Paint()
      ..color = const Color(0xFF52B788).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final angle = i * 30 * pi / 180;
      final outerPt = Offset(
        center.dx + radius * 0.92 * sin(angle),
        center.dy - radius * 0.92 * cos(angle),
      );
      final innerPt = Offset(
        center.dx + radius * 0.82 * sin(angle),
        center.dy - radius * 0.82 * cos(angle),
      );
      canvas.drawLine(
          outerPt, innerPt, tickPaint..strokeWidth = i % 3 == 0 ? 2 : 1);
    }

    // North arrow
    final northPath = Path();
    northPath.moveTo(center.dx, center.dy - radius * 0.6);
    northPath.lineTo(center.dx - 8, center.dy);
    northPath.lineTo(center.dx + 8, center.dy);
    northPath.close();
    canvas.drawPath(northPath, Paint()..color = Colors.redAccent);

    // South arrow
    final southPath = Path();
    southPath.moveTo(center.dx, center.dy + radius * 0.6);
    southPath.lineTo(center.dx - 8, center.dy);
    southPath.lineTo(center.dx + 8, center.dy);
    southPath.close();
    canvas.drawPath(southPath, Paint()..color = Colors.white38);

    // Center dot
    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFF52B788));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

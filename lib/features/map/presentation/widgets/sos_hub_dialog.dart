import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/colors.dart';

class SosHubDialog extends StatefulWidget {
  final Position? currentPosition;
  const SosHubDialog({super.key, this.currentPosition});

  @override
  State<SosHubDialog> createState() => _SosHubDialogState();
}

class _SosHubDialogState extends State<SosHubDialog> {
  Position? _position;
  bool _loadingGPS = false;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _position = widget.currentPosition;
    _checkConnectivity();
    if (_position == null) {
      _fetchGPS();
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivity = await Connectivity().checkConnectivity();
    setState(() {
      _isOffline =
          connectivity.isEmpty || connectivity.first == ConnectivityResult.none;
    });
  }

  Future<void> _fetchGPS() async {
    setState(() {
      _loadingGPS = true;
    });
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition()
            .timeout(const Duration(seconds: 4));
        setState(() {
          _position = pos;
        });
      }
    } catch (_) {}
    setState(() {
      _loadingGPS = false;
    });
  }

  Future<void> _triggerCall(String number) async {
    final url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _triggerSMS(String number) async {
    final lat = _position?.latitude ?? 23.6850;
    final lng = _position?.longitude ?? 90.3563;
    final message =
        'Bhromon SOS: I need emergency assistance! My coordinates are: Lat $lat, Lng $lng.';
    final url = Uri.parse('sms:$number?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latStr = _position?.latitude.toStringAsFixed(5) ?? 'Unknown';
    final lngStr = _position?.longitude.toStringAsFixed(5) ?? 'Unknown';

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.redAccent, size: 32),
                const SizedBox(width: 12),
                Text(
                  'SOS EMERGENCY HUB',
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Share your details or contact emergency support. In remote areas, SMS fallback will operate even without internet coverage.',
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Location info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location,
                      color: AppColors.mintGreen, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR COORDINATES',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        _loadingGPS
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.mintGreen),
                              )
                            : Text(
                                'Lat: $latStr, Lng: $lngStr',
                                style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: AppColors.mintGreen, size: 20),
                    onPressed: _fetchGPS,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Connectivity status indicator
            Row(
              children: [
                Icon(
                  _isOffline
                      ? Icons.signal_cellular_connected_no_internet_4_bar
                      : Icons.wifi,
                  color: _isOffline ? Colors.orangeAccent : AppColors.mintGreen,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOffline
                      ? 'Offline Mode (SMS Fallback recommended)'
                      : 'Online Mode (Data call/message active)',
                  style: TextStyle(
                    color:
                        _isOffline ? Colors.orangeAccent : AppColors.mintGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Emergency Action Options
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _triggerCall('999'),
                    icon: const Icon(Icons.phone),
                    label: const Text('Call Helpline',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _triggerSMS('999'),
                    icon: const Icon(Icons.sms),
                    label: const Text('Send SOS SMS',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                child: Text('Dismiss',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

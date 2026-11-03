import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../localization/app_localizations.dart';
import '../utils/app_logger.dart';

/// Whether to show the battery guidance now. Android only, and never when the
/// app is already exempt from battery limits. It shows at most once a week.
bool shouldShowBatteryGuidance({
  required bool isAndroid,
  required bool alreadyExempt,
  required DateTime? lastShown,
  required DateTime now,
}) {
  if (!isAndroid || alreadyExempt) return false;
  if (lastShown == null) return true;
  return now.difference(lastShown) >= const Duration(days: 7);
}

/// The translation key of the tip for a phone maker's battery settings, or null
/// for a maker with no special tip.
String? batteryTipKeyFor(String manufacturer) {
  final maker = manufacturer.toLowerCase();
  if (maker.contains('xiaomi') ||
      maker.contains('redmi') ||
      maker.contains('poco')) {
    return 'battery_tip_xiaomi';
  }
  if (maker.contains('oppo') ||
      maker.contains('realme') ||
      maker.contains('oneplus')) {
    return 'battery_tip_oppo';
  }
  if (maker.contains('vivo') || maker.contains('iqoo')) {
    return 'battery_tip_vivo';
  }
  if (maker.contains('samsung')) return 'battery_tip_samsung';
  return null;
}

/// The guidance on keeping calls ringing: the phone can stop an app in the
/// background, and then its calls do not ring.
///
/// A call that connects marks the guidance as due. It is shown the next time the
/// chat list opens, so it never interrupts a call. The system settings page is
/// opened without a special permission.
class BatteryGuidance {
  BatteryGuidance._();

  static const MethodChannel _channel =
      MethodChannel('com.bhromon.app/battery');
  static const String _boxName = 'app_prefs';
  static const String _lastShownKey = 'battery_guidance_last_shown';
  static const String _dueKey = 'battery_guidance_due';

  /// Called when a call connects.
  static Future<void> markCallAnswered() async {
    if (!_isAndroid) return;
    try {
      final box = await _openBox();
      await box.put(_dueKey, true);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// Shows the guidance if it is due and the weekly rule allows it.
  static Future<void> maybeShowDue(BuildContext context) async {
    if (!_isAndroid) return;
    try {
      final box = await _openBox();
      if (box.get(_dueKey) != true) return;
      await box.put(_dueKey, false);

      final exempt =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
              true;
      final last = box.get(_lastShownKey);
      final now = DateTime.now();
      final shouldShow = shouldShowBatteryGuidance(
        isAndroid: true,
        alreadyExempt: exempt,
        lastShown:
            last is int ? DateTime.fromMillisecondsSinceEpoch(last) : null,
        now: now,
      );
      if (!shouldShow || !context.mounted) return;

      await box.put(_lastShownKey, now.millisecondsSinceEpoch);
      final maker = await _channel.invokeMethod<String>('manufacturer') ?? '';
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => BatteryGuidanceDialog(tipKey: batteryTipKeyFor(maker)),
      );
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// Opens the battery settings list for this app. Returns false when the phone
  /// has no such page.
  static Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
      return false;
    }
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }
}

/// The battery guidance dialog. [tipKey] is the maker's tip, if there is one.
class BatteryGuidanceDialog extends StatelessWidget {
  const BatteryGuidanceDialog({super.key, required this.tipKey});

  final String? tipKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.translate('battery_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate('battery_body')),
          if (tipKey != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.translate(tipKey!),
              key: const ValueKey('battery-tip'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('battery_later')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(BatteryGuidance.openSettings());
          },
          child: Text(l10n.translate('battery_open_settings')),
        ),
      ],
    );
  }
}

import 'package:intl/intl.dart';

enum TideType {
  high,
  low;

  String get banglaName =>
      this == TideType.high ? 'জোয়ার (High Tide)' : 'ভাটা (Low Tide)';
}

enum SwimSafetyStatus {
  safe,
  caution,
  danger;

  String get banglaTitle {
    switch (this) {
      case SwimSafetyStatus.safe:
        return 'স্নানের নিরাপদ সময় (Safe Swim)';
      case SwimSafetyStatus.caution:
        return 'সতর্কতা প্রয়োজন (Caution)';
      case SwimSafetyStatus.danger:
        return 'পানিতে নামা নিষিদ্ধ (Danger / No Swim)';
    }
  }
}

/// One tide window. [startMinutes] and [endMinutes] are minutes after midnight;
/// a window may run past midnight, in which case end is earlier than start.
class TideWindow {
  final String name;
  final int startMinutes; // Minutes from midnight
  final int endMinutes;
  final TideType type;
  final String description;

  const TideWindow({
    required this.name,
    required this.startMinutes,
    required this.endMinutes,
    required this.type,
    required this.description,
  });

  /// Whether [minutes] after midnight falls inside this window.
  bool contains(int minutes) {
    if (endMinutes >= startMinutes) {
      return minutes >= startMinutes && minutes <= endMinutes;
    }
    return minutes >= startMinutes || minutes <= endMinutes;
  }

  String formatTimeRange() {
    final startH = (startMinutes ~/ 60).toString().padLeft(2, '0');
    final startM = (startMinutes % 60).toString().padLeft(2, '0');
    final endH = (endMinutes ~/ 60).toString().padLeft(2, '0');
    final endM = (endMinutes % 60).toString().padLeft(2, '0');
    return '$startH:$startM - $endH:$endM';
  }
}

/// Swim-safety guidance from estimated tide windows.
///
/// These are estimates, not an official tide table. The curated day is the
/// only one with hand-entered times; other days are shifted by a fixed amount
/// and ignore the beach's location. Local lifeguards and administration always
/// take priority.
class TideScheduleEngine {
  static const bool isEstimate = true;

  static final Map<String, List<TideWindow>> _curatedSchedule = {
    '2026-10-24': [
      const TideWindow(
        name: 'ভোরের জোয়ার (Morning High Tide)',
        startMinutes: 320,
        endMinutes: 530,
        type: TideType.high,
        description: 'সকালের জোয়ার। হালকা স্নান ও ফটোসেশনের সুন্দর সময়।',
      ),
      const TideWindow(
        name: 'দুপুরের ভাটা (Noon Low Tide)',
        startMinutes: 650,
        endMinutes: 870,
        type: TideType.low,
        description:
            'দুপুরের তীব্র ভাটা! পানিতে নামা ঝুঁকিপূর্ণ। চোরাবালির ঝুঁকি থাকে।',
      ),
      const TideWindow(
        name: 'বিকেলের জোয়ার (Sunset High Tide)',
        startMinutes: 990,
        endMinutes: 1210,
        type: TideType.high,
        description:
            'সূর্যাস্তকালীন জোয়ার। সাগরে গোসল ও ঢেউ উপভোগের সেরা সময়।',
      ),
      const TideWindow(
        name: 'রাতের ভাটা (Night Low Tide)',
        startMinutes: 1290,
        endMinutes: 1439,
        type: TideType.low,
        description: 'রাতের অন্ধকার ও ভাটা। কোনো অবস্থাতেই সাগরে নামবেন না।',
      ),
    ],
  };

  static final DateTime _baseDate = DateTime(2026, 10, 24);

  static List<TideWindow> getTidesForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (_curatedSchedule.containsKey(dateKey)) {
      return _curatedSchedule[dateKey]!;
    }

    final daysDiff =
        DateTime(date.year, date.month, date.day).difference(_baseDate).inDays;
    final shiftMinutes = (daysDiff * 50) % 720;

    int wrap(int m) => (m + shiftMinutes) % 1440;

    return [
      TideWindow(
        name: 'সকালের জোয়ার (High Tide 1)',
        startMinutes: wrap(320),
        endMinutes: wrap(530),
        type: TideType.high,
        description:
            'জোয়ারের সময় স্রোত কূলের দিকে থাকে, লাইফগার্ড জোনে গোসল করা যায়।',
      ),
      TideWindow(
        name: 'দুপুরের ভাটা (Low Tide 1)',
        startMinutes: wrap(650),
        endMinutes: wrap(870),
        type: TideType.low,
        description:
            'ভাটার সময় তীব্র টান ও চোরাবালির ঝুঁকি থাকে। পানিতে নামা অনুচিত।',
      ),
      TideWindow(
        name: 'বিকেলের জোয়ার (High Tide 2)',
        startMinutes: wrap(990),
        endMinutes: wrap(1210),
        type: TideType.high,
        description: 'বিকেলের জোয়ার। সূর্যাস্ত দেখা ও গোসল করার অনুকূল সময়।',
      ),
      TideWindow(
        name: 'রাতের ভাটা (Low Tide 2)',
        startMinutes: wrap(1290),
        endMinutes: wrap(1439),
        type: TideType.low,
        description: 'রাতের বেলা সমুদ্রে নামা সম্পূর্ণ নিষিদ্ধ।',
      ),
    ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  }

  /// The swim advice for [currentTime], with the window it falls in and the
  /// next window (which may be tomorrow's first window).
  static ({
    SwimSafetyStatus status,
    String advisory,
    TideWindow? currentWindow,
    TideWindow? nextWindow,
  }) evaluateCurrentSafety([DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final tides = getTidesForDate(now);

    TideWindow? active;
    for (final t in tides) {
      if (t.contains(minutes)) {
        active = t;
        break;
      }
    }

    TideWindow? next;
    for (final t in tides) {
      if (t.startMinutes > minutes) {
        next = t;
        break;
      }
    }
    next ??= getTidesForDate(now.add(const Duration(days: 1))).first;

    if (now.hour >= 18 || now.hour < 5) {
      return (
        status: SwimSafetyStatus.danger,
        advisory:
            'সন্ধ্যার পর বা রাতে সমুদ্রে নামা আইনত নিষিদ্ধ ও অত্যন্ত ঝুঁকিপূর্ণ।',
        currentWindow: active,
        nextWindow: next,
      );
    }

    if (active != null) {
      if (active.type == TideType.high) {
        return (
          status: SwimSafetyStatus.safe,
          advisory:
              'আনুমানিক জোয়ার চলছে। লাইফগার্ড নির্ধারিত সীমানার ভেতরে গোসল করুন।',
          currentWindow: active,
          nextWindow: next,
        );
      }
      return (
        status: SwimSafetyStatus.danger,
        advisory:
            'আনুমানিক ভাটা চলছে। পানিতে নামবেন না, চোরাবালি ও গুপ্ত গর্তে ডুবে যাওয়ার ঝুঁকি।',
        currentWindow: active,
        nextWindow: next,
      );
    }

    return (
      status: SwimSafetyStatus.caution,
      advisory: 'জোয়ার ও ভাটার মাঝের সময়। কোমর পানির বেশি নামবেন না।',
      currentWindow: null,
      nextWindow: next,
    );
  }
}

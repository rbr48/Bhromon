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

  String formatTimeRange() {
    final startH = (startMinutes ~/ 60).toString().padLeft(2, '0');
    final startM = (startMinutes % 60).toString().padLeft(2, '0');
    final endH = (endMinutes ~/ 60).toString().padLeft(2, '0');
    final endM = (endMinutes % 60).toString().padLeft(2, '0');
    return '$startH:$startM - $endH:$endM';
  }
}

class TideScheduleEngine {
  /// Base tidal progression for Bay of Bengal (approx ~50 minutes shift per day)
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

  /// Returns tide windows for a given date.
  /// If the date is not hardcoded, dynamically projects tidal shifts.
  static List<TideWindow> getTidesForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (_curatedSchedule.containsKey(dateKey)) {
      return _curatedSchedule[dateKey]!;
    }

    // Dynamic lunar tide calculation:
    // Earth-Moon gravitational progression shifts tidal peaks by ~50 minutes per day.
    final baseDate = DateTime(2026, 10, 24);
    final daysDiff = date.difference(baseDate).inDays;
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

  /// Evaluates current swimming safety status right now.
  static ({
    SwimSafetyStatus status,
    String advisory,
    TideWindow? currentWindow,
    TideWindow? nextWindow,
  }) evaluateCurrentSafety([DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final tides = getTidesForDate(now);

    TideWindow? active;
    TideWindow? next;

    for (int i = 0; i < tides.length; i++) {
      final t = tides[i];
      if (currentMinutes >= t.startMinutes && currentMinutes <= t.endMinutes) {
        active = t;
        next = (i + 1 < tides.length) ? tides[i + 1] : tides.first;
        break;
      } else if (currentMinutes < t.startMinutes) {
        next = t;
        break;
      }
    }

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
              'এখন জোয়ার চলছে! লাইফগার্ড নির্ধারিত লাল-হলুদ সীমানার ভেতরে গোসল করুন।',
          currentWindow: active,
          nextWindow: next,
        );
      } else {
        return (
          status: SwimSafetyStatus.danger,
          advisory:
              'সৈকতে ভাটা চলছে! পানিতে নামবেন না, চোরাবালি ও গুপ্ত গর্তে ডুবে যাওয়ার প্রবল ঝুঁকি।',
          currentWindow: active,
          nextWindow: next,
        );
      }
    }

    return (
      status: SwimSafetyStatus.caution,
      advisory:
          'জোয়ার ও ভাটার মধ্যবর্তী পরিবর্তনকালীন সময়। কোমর পানির বেশি নামবেন না।',
      currentWindow: null,
      nextWindow: next,
    );
  }
}

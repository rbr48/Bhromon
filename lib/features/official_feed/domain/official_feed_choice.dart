import 'package:hive/hive.dart';

import '../../../core/utils/app_logger.dart';

/// Whether this person has chosen to follow the official feed.
enum OfficialFeedChoice { unanswered, follow, notNow }

/// The stored form of [choice], as kept in the `app_prefs` box.
String officialFeedChoiceName(OfficialFeedChoice choice) => switch (choice) {
      OfficialFeedChoice.follow => 'follow',
      OfficialFeedChoice.notNow => 'notNow',
      OfficialFeedChoice.unanswered => 'unanswered',
    };

/// The choice read back from storage. Anything unknown counts as not answered, so the
/// question is asked again rather than a wrong answer being kept.
OfficialFeedChoice parseOfficialFeedChoice(Object? stored) => switch (stored) {
      'follow' => OfficialFeedChoice.follow,
      'notNow' => OfficialFeedChoice.notNow,
      _ => OfficialFeedChoice.unanswered,
    };

/// Keeps the choice on this device, in the `app_prefs` box. A storage failure is logged,
/// and the question is asked again next time.
class OfficialFeedPreference {
  static const String _boxName = 'app_prefs';
  static const String _key = 'official_feed_choice';

  static Future<OfficialFeedChoice> load() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      return parseOfficialFeedChoice(box.get(_key));
    } catch (error, stackTrace) {
      logWarning('[OfficialFeed] Could not read the choice', error, stackTrace);
      return OfficialFeedChoice.unanswered;
    }
  }

  static Future<void> save(OfficialFeedChoice choice) async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      await box.put(_key, officialFeedChoiceName(choice));
    } catch (error, stackTrace) {
      logWarning('[OfficialFeed] Could not save the choice', error, stackTrace);
    }
  }
}

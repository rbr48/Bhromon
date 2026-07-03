import 'package:freezed_annotation/freezed_annotation.dart';

/// The emotional tone/type of a travel diary entry.
enum TripMood {
  @JsonValue('adventure')
  adventure,

  @JsonValue('peaceful')
  peaceful,

  @JsonValue('spiritual')
  spiritual,

  @JsonValue('thrilling')
  thrilling,

  @JsonValue('family')
  family,

  @JsonValue('romantic')
  romantic;

  String get label => switch (this) {
        TripMood.adventure => 'রোমাঞ্চ',
        TripMood.peaceful => 'প্রশান্তি',
        TripMood.spiritual => 'আধ্যাত্মিক',
        TripMood.thrilling => 'দু:সাহস',
        TripMood.family => 'পারিবারিক',
        TripMood.romantic => 'রোমান্টিক',
      };

  String get emoji => switch (this) {
        TripMood.adventure => '🏕️',
        TripMood.peaceful => '🌿',
        TripMood.spiritual => '🕌',
        TripMood.thrilling => '⛰️',
        TripMood.family => '👨‍👩‍👧',
        TripMood.romantic => '💑',
      };
}

/// Travel companion/style tags for a diary entry.
enum TripTag {
  @JsonValue('solo')
  solo,

  @JsonValue('family')
  family,

  @JsonValue('friends')
  friends,

  @JsonValue('couple')
  couple,

  @JsonValue('budget')
  budget,

  @JsonValue('luxury')
  luxury,

  @JsonValue('nature')
  nature,

  @JsonValue('heritage')
  heritage,

  @JsonValue('food')
  food,

  @JsonValue('winter')
  winter,

  @JsonValue('monsoon')
  monsoon,

  @JsonValue('summer')
  summer;

  String get label => switch (this) {
        TripTag.solo => '#সোলো',
        TripTag.family => '#পরিবার',
        TripTag.friends => '#বন্ধু',
        TripTag.couple => '#দম্পতি',
        TripTag.budget => '#কম খরচ',
        TripTag.luxury => '#বিলাসী',
        TripTag.nature => '#প্রকৃতি',
        TripTag.heritage => '#ঐতিহ্য',
        TripTag.food => '#খাবার',
        TripTag.winter => '#শীতকাল',
        TripTag.monsoon => '#বর্ষা',
        TripTag.summer => '#গরম',
      };
}

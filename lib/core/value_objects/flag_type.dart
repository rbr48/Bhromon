import 'package:freezed_annotation/freezed_annotation.dart';

enum FlagType {
  @JsonValue('outdated')
  outdated,
  @JsonValue('inaccurate')
  inaccurate,
  @JsonValue('spam')
  spam,
  @JsonValue('safety')
  safety;

  String get displayName => switch (this) {
    FlagType.outdated => 'Outdated Info',
    FlagType.inaccurate => 'Inaccurate',
    FlagType.spam => 'Spam',
    FlagType.safety => 'Safety Hazard',
  };
}

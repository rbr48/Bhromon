import '../models/channel_models.dart';
import '../models/tour_group.dart';

/// The title a text channel shows in [group]. The channels screen and the share sheet both
/// read it from here, so they always name a channel the same way.
///
/// [translate] turns a translation key into text. An admin's title for a built-in channel
/// replaces its standard title for everyone. A built-in channel's standard title depends on
/// the kind of group: a food channel in an office is named differently from one on a trip.
/// A channel with no standard title shows its name.
String channelTitleText({
  required TourChannel channel,
  TourGroup? group,
  required String Function(String key) translate,
}) {
  if (channel.id == kBuiltInVoiceChannelId) {
    return translate('chan_voice_lounge');
  }
  // An admin's title for a built-in channel replaces the standard one for everyone.
  final override = channel.titleOverride;
  if (override.isNotEmpty) return override;
  if (channel.kind == ChannelKind.voice) {
    return channel.name.isEmpty ? '🔊 Voice' : '🔊 ${channel.name}';
  }
  final friends = group?.isFriends ?? false;
  final office = group?.isOffice ?? false;
  final campus = group?.isCampus ?? false;
  final mess = group?.isMess ?? false;
  final society = group?.isSociety ?? false;
  final samity = group?.isSamity ?? false;
  final school = group?.isSchool ?? false;
  final sports = group?.isSports ?? false;
  final study = group?.isStudy ?? false;
  final committee = group?.isCommittee ?? false;
  final family = group?.isFamily ?? false;
  switch (channel.id) {
    case 'general':
      return translate('tour_channel_general');
    case 'food':
      return translate(friends
          ? 'friends_channel_food'
          : office
              ? 'office_channel_food'
              : campus
                  ? 'campus_channel_food'
                  : mess
                      ? 'mess_channel_food'
                      : society
                          ? 'society_channel_food'
                          : samity
                              ? 'samity_channel_food'
                              : school
                                  ? 'school_channel_food'
                                  : sports
                                      ? 'sports_channel_food'
                                      : study
                                          ? 'study_channel_food'
                                          : committee
                                              ? 'committee_channel_food'
                                              : family
                                                  ? 'family_channel_food'
                                                  : 'tour_channel_food');
    case 'sightseeing':
      return translate(friends
          ? 'friends_channel_events'
          : office
              ? 'office_channel_events'
              : campus
                  ? 'campus_channel_events'
                  : mess
                      ? 'mess_channel_bills'
                      : society
                          ? 'society_channel_events'
                          : samity
                              ? 'samity_channel_events'
                              : school
                                  ? 'school_channel_events'
                                  : sports
                                      ? 'sports_channel_events'
                                      : study
                                          ? 'study_channel_events'
                                          : committee
                                              ? 'committee_channel_events'
                                              : family
                                                  ? 'family_channel_sightseeing'
                                                  : 'tour_channel_places');
    case 'home':
      return translate('family_channel_home');
    case 'kids':
      return translate('family_channel_kids');
    case 'shopping':
      return translate('family_channel_shopping');
    case 'emergency':
      return translate('tour_channel_safety');
    default:
      return channel.name.isEmpty ? '#${channel.id}' : '# ${channel.name}';
  }
}

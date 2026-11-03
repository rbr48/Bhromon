import 'package:bhromon/features/tour_group/presentation/tour_routes.dart';
import 'package:flutter_test/flutter_test.dart';

// The route table from the UI work plan (section 5.4, decision D-6 and D-7).
//
// `/group-hub` with no id is the groups list. `/group-hub?tourId=X` is the group page
// for X. Every call site that goes to the hub with no id is listed below, so a later
// change to the hub has to say which of them it changes.
const Map<String, String> callSitesWithNoId = {
  'app/route_not_found_screen.dart': 'the groups list',
  'app/router.dart: initialLocation and both redirects': 'the groups list',
  'main.dart: notification tap': 'the groups list',
  'features/auth/presentation/pages/login_screen.dart': 'the groups list',
  'features/chat/presentation/pages/chats_list_screen.dart': 'the groups list',
  'features/explorer/presentation/pages/explorer_profile_screen.dart':
      'the groups list',
  'features/newspaper/presentation/pages/newspaper_hub_screen.dart':
      'the groups list',
  'features/notifications/presentation/pages/notification_settings_screen.dart':
      'the groups list',
  'features/trust/presentation/pages/trust_dashboard_screen.dart':
      'the groups list',
  'features/game_zone/game_zone_hub_screen.dart': 'the groups list',
  'tour_group/widgets/bhromon_bottom_nav.dart: the Groups tab':
      'the groups list',
  'tour_group/widgets/tour_membership_guard.dart: removed while viewing':
      'the groups list',
  'tour_group/widgets/trip_shell.dart: first tab path (kept, see P3.4)':
      'the groups list',
  'tour_group/tour_routes.dart: tourHubPath() with no id': 'the groups list',
};

void main() {
  test('no id goes to the groups list', () {
    expect(tourHubPath(), '/group-hub');
    expect(tourHubPath(null), '/group-hub');
    expect(tourHubPath(''), '/group-hub');
  });

  test('an id goes to that group\'s page, on the same URL as before', () {
    expect(tourHubPath('tour_123'), '/group-hub?tourId=tour_123');
  });

  test('the id is encoded in the URL', () {
    expect(tourHubPath('a b&c'), '/group-hub?tourId=a+b%26c');
  });

  test('the call-site table covers every route that goes to the hub with no id',
      () {
    expect(callSitesWithNoId.values.toSet(), {'the groups list'});
    expect(callSitesWithNoId, hasLength(14));
  });
}

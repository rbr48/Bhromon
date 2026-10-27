import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/member_profile/tour_member_profile_modal.dart';

void main() {
  group('Tour Member Profile - Unit & Logic Tests', () {
    test('Translation keys for member profile exist in TourTranslationKeys', () {
      final en = TourTranslationKeys.localizedValues['en']!;
      final bn = TourTranslationKeys.localizedValues['bn']!;

      final expectedKeys = [
        'prof_posts',
        'prof_likes',
        'prof_tagged',
        'prof_balance',
        'prof_role_owner',
        'prof_role_admin',
        'prof_role_member',
        'prof_hotel_room',
        'prof_transport_seat',
        'prof_blood_group',
        'prof_note',
        'prof_note_add',
        'prof_edit',
        'prof_send_message',
        'prof_share',
        'prof_all_posts',
        'prof_achievements',
        'prof_achieve_photographer',
        'prof_achieve_reels_director',
        'prof_achieve_star_traveler',
        'prof_achieve_life_saver',
        'prof_achieve_explorer',
        'prof_achieve_top_spender',
        'prof_tab_posts',
        'prof_tab_reels',
        'prof_tab_tagged',
        'prof_tab_info',
        'prof_no_posts',
        'prof_no_reels',
        'prof_no_tagged',
        'prof_info_email',
        'prof_copied_link',
      ];

      for (final key in expectedKeys) {
        expect(en.containsKey(key), isTrue,
            reason: 'Missing EN translation for key: $key');
        expect(bn.containsKey(key), isTrue,
            reason: 'Missing BN translation for key: $key');
      }
    });

    test('TripLedgerEngine formats balance cleanly without NaN', () {
      // 15000 paisa = 150 BDT
      expect(TripLedgerEngine.formatTaka(15000), '৳150');
      // 0 paisa = 0 BDT
      expect(TripLedgerEngine.formatTaka(0), '৳0');
      // -5000 paisa abs = 50 BDT
      expect(TripLedgerEngine.formatTaka((-5000).abs()), '৳50');
    });

    testWidgets('TourMemberProfileModal builds and renders core components',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
          ],
          home: Scaffold(
            body: TourMemberProfileModal(
              tourId: 'tour_test_123',
              memberEmail: 'traveler@bhromon.fun',
              memberName: 'Ahsan Habib',
              seatNumber: 'A1',
              roomNumber: '302',
              bloodGroup: 'B+',
              statusNote: 'Loving Coxs Bazar sunset!',
              familyCount: 2,
              members: [
                TourMember(
                  tourId: 'tour_test_123',
                  email: 'traveler@bhromon.fun',
                  displayName: 'Ahsan Habib',
                  role: TourRole.member,
                  status: TourMemberStatus.active,
                  joinedAt: DateTime(2026),
                  familyCount: 2,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top bar header handle
      expect(find.text('@Ahsan_Habib'), findsOneWidget);

      // Verify action buttons exist
      expect(find.byIcon(Icons.share_outlined), findsWidgets);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Verify category circles are present
      expect(find.byIcon(Icons.wb_sunny_rounded), findsWidgets);
      expect(find.byIcon(Icons.beach_access_rounded), findsWidgets);
    });
  });
}

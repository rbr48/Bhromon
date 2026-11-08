import 'package:bhromon/features/tour_group/data/itinerary_pdf.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/emergency_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItineraryPdfGenerator tests', () {
    final checkpoints = [
      const RouteCheckpoint(
        id: 'cp_1',
        name: 'কুমিল্লা হাইওয়ে ইন',
        kmFromStart: 95,
        kind: CheckpointKind.food,
        notes: 'রাতের খাবার ও ফ্রেশ হওয়া',
      ),
      const RouteCheckpoint(
        id: 'cp_2',
        name: 'বাঘাইহাট সেনা ক্যাম্প',
        kmFromStart: 210,
        kind: CheckpointKind.checkpost,
        notes: 'এসকর্টের জন্য এন্ট্রি ও অপেক্ষা',
      ),
    ];

    final group = TourGroup(
      id: 'tour_itinerary_test',
      name: 'সাজেকের মেঘ ও পাহাড় ভ্রমণ ২০২৬',
      destination: 'Sajek Valley',
      originCity: 'ঢাকা',
      ownerEmail: 'admin@bhromon.fun',
      inviteCode: 'SJ2026BD',
      startDate: DateTime(2026, 11, 15),
      endDate: DateTime(2026, 11, 18),
      createdAt: DateTime(2026, 11, 1),
      meetingPointTitle: 'সায়দাবাদ বাস টার্মিনাল',
      meetingPointNote: 'রাত ১০:৩০ মিনিটে কাউন্টারের সামনে জমায়েত।',
      emergencyContacts: const [
        EmergencyContact(name: 'মেহেদী হাসান', phone: '01711223344'),
      ],
      stops: [
        TourStop(
          id: 'stop_1',
          name: 'খাগড়াছড়ি',
          arrive: DateTime(2026, 11, 15),
          leave: DateTime(2026, 11, 16),
          stay: 'হোটেল গায়রিং',
          notes: 'সকালে চান্দের গাড়িতে সাজেকের উদ্দেশে যাত্রা।',
        ),
        TourStop(
          id: 'stop_2',
          name: 'সাজেক ভ্যালি',
          arrive: DateTime(2026, 11, 16),
          leave: DateTime(2026, 11, 18),
          stay: 'মেঘমাচা রিসোর্ট',
          notes: 'কংলাক পাহাড়ে সূর্যাস্ত ও হ্যালিপ্যাডে আড্ডা।',
        ),
      ],
      legPlans: const {
        'origin>stop_1': LegPlan(
          mode: TransportMode.road,
          distanceKm: 280,
        ),
        'stop_1>stop_2': LegPlan(
          mode: TransportMode.jeep,
          distanceKm: 70,
        ),
      },
    );

    test('generate builds valid non-empty PDF bytes', () async {
      final generator = ItineraryPdfGenerator();
      final bytes = await generator.generate(
        group: group,
        checkpoints: checkpoints,
        preparedByName: 'ট্যুর কো-অর্ডিনেটর',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // Valid PDF magic header %PDF-
      expect(bytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('BanglaItineraryFormatter converts numbers and labels properly', () {
      expect(BanglaItineraryFormatter.toBanglaDigits('12345'), '১২৩৪৫');
      expect(BanglaItineraryFormatter.modeBangla(TransportMode.jeep),
          'চান্দের গাড়ি / জিপ');
      expect(BanglaItineraryFormatter.checkpointKindBangla(CheckpointKind.fuel),
          'ফুয়েল স্টেশন');
    });
  });
}

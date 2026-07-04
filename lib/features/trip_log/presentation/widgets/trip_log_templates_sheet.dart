import 'package:flutter/material.dart';

class TripTemplate {
  final String name;
  final String emoji;
  final String description;
  final List<String> suggestedSections;
  final Map<String, dynamic> defaultCosts;
  final String sampleSafetyNote;

  const TripTemplate({
    required this.name,
    required this.emoji,
    required this.description,
    required this.suggestedSections,
    required this.defaultCosts,
    required this.sampleSafetyNote,
  });
}

class TripLogTemplatesSheet extends StatelessWidget {
  const TripLogTemplatesSheet({super.key});

  static Future<TripTemplate?> show(BuildContext context) {
    return showModalBottomSheet<TripTemplate>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TripLogTemplatesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Custom list of templates with actual correct types
    final List<TripTemplate> templates = [
      const TripTemplate(
        name: 'Day Trip',
        emoji: '☀️',
        description: 'A quick one-day escape to a nearby destination',
        suggestedSections: [
          'Morning departure',
          'Getting there',
          'The destination',
          'Food & costs',
          'Tips for visitors'
        ],
        defaultCosts: {'Transport': 300, 'Food': 200, 'Entry': 50},
        sampleSafetyNote:
            'Start early to avoid afternoon heat. Carry enough water.',
      ),
      const TripTemplate(
        name: 'Weekend Escape',
        emoji: '🏕️',
        description: 'A 2-3 day trip with overnight stay',
        suggestedSections: [
          'Day 1: Journey',
          'Day 1: Arrival & exploration',
          'Day 2: Main experience',
          'Accommodation review',
          'Day 3: Return',
          'Total budget breakdown'
        ],
        defaultCosts: {
          'Transport': 800,
          'Hotel': 1200,
          'Food': 600,
          'Misc': 200
        },
        sampleSafetyNote:
            'Book accommodation in advance during peak season. Keep emergency contacts handy.',
      ),
      const TripTemplate(
        name: 'Budget Travel',
        emoji: '💰',
        description: 'How to explore on a tight budget',
        suggestedSections: [
          'How I kept costs low',
          'Budget transport options',
          'Cheap eats',
          'Free attractions',
          'Hidden savings tips'
        ],
        defaultCosts: {'Total Budget': 1500},
        sampleSafetyNote:
            'Avoid travelling alone at night to save on transport costs.',
      ),
      const TripTemplate(
        name: 'Trekking / Hiking',
        emoji: '⛰️',
        description: 'Adventure trek or hill station visit',
        suggestedSections: [
          'Trail overview',
          'Difficulty level',
          'What to pack',
          'Route waypoints',
          'Dangerous sections',
          'Viewpoints',
          'Return journey'
        ],
        defaultCosts: {'Guide fee': 500, 'Transport': 600, 'Food': 300},
        sampleSafetyNote:
            'Inform someone of your trek plan. Carry a first aid kit, torch, and extra water. Do not trek alone.',
      ),
      const TripTemplate(
        name: 'Beach Holiday',
        emoji: '🏖️',
        description: 'Sea, sun and sand experience',
        suggestedSections: [
          'Getting to the beach',
          'Beach overview',
          'Water activities',
          'Sunset spots',
          'Seafood guide',
          'Where to stay'
        ],
        defaultCosts: {
          'Transport': 1000,
          'Hotel': 2000,
          'Food': 800,
          'Activities': 500
        },
        sampleSafetyNote:
            'Swim only in designated areas. Watch tide times. Protect against sunburn.',
      ),
      const TripTemplate(
        name: 'Heritage & Culture',
        emoji: '🏛️',
        description: 'Temples, mosques, historical sites',
        suggestedSections: [
          'Historical background',
          'Getting there',
          'What to see',
          'Photography spots',
          'Local customs',
          'Best time to visit'
        ],
        defaultCosts: {
          'Transport': 400,
          'Entry': 100,
          'Guide': 300,
          'Food': 200
        },
        sampleSafetyNote:
            'Dress modestly at religious sites. Remove footwear where required.',
      ),
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Text('Choose a Template',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Text('(optional)',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Templates pre-fill sections and cost items to help you write a high-quality log faster.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 0,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              itemCount: templates.length + 1, // +1 for "blank" option
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        children: [
                          Text('✏️', style: TextStyle(fontSize: 24)),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Start Blank',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                Text('Write your trip log from scratch',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final t = templates[i - 1];
                return GestureDetector(
                  onTap: () => Navigator.pop(context, t),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Text(t.emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(t.description,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

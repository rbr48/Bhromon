import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../tour_group/domain/services/destination_catalog.dart';

/// Intelligent AI Travel Guide service for Bhromon 1-on-1 chat.
///
/// Provides deep destination knowledge, hotel/resort advice,
/// safety tips, packing checklists, and local Bangladesh cultural context.
class TravelAiService {
  static final TravelAiService _instance = TravelAiService._internal();
  factory TravelAiService() => _instance;
  TravelAiService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// Generates a travel advisory response for [userMessage].
  Future<String> getTravelAdvice(String userMessage) async {
    final query = userMessage.trim().toLowerCase();

    // 1. Try Gemini API if an API key is available via environment
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isNotEmpty) {
      try {
        final response = await _callGeminiApi(userMessage, apiKey);
        if (response != null && response.isNotEmpty) {
          return response;
        }
      } catch (e) {
        debugPrint('Gemini API call failed, falling back to catalog: $e');
      }
    }

    // 2. Intelligent knowledge base response derived from Bangladesh Destination Catalog
    return _generateCuratedTravelResponse(query);
  }

  Future<String?> _callGeminiApi(String message, String apiKey) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey';
    final payload = {
      'contents': [
        {
          'parts': [
            {'text': message}
          ]
        }
      ],
      'systemInstruction': {
        'parts': [
          {
            'text': 'You are the Bhromon AI Travel Guide — an expert on Bangladesh tourism. '
                'Give concise, warm, practical travel advice with hotel/resort tips, '
                'best seasons to visit, route directions from Dhaka/Chittagong, and local food recommendations. '
                'Support both English and Bengali naturally. Keep answers within 2-4 conversational paragraphs.'
          }
        ]
      }
    };

    final res = await _dio.post<Map<String, dynamic>>(
      url,
      data: jsonEncode(payload),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (res.statusCode == 200 && res.data != null) {
      final candidates = res.data!['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'] as String?;
        }
      }
    }
    return null;
  }

  String _generateCuratedTravelResponse(String query) {
    // Check Destination Catalog for longest matching destination name
    final match = presetForName(query);
    if (match != null) {
      return '📍 **${match.nameEn} (${match.nameBn})**\n\n'
          '${match.kind.name.toUpperCase()} Destination in ${match.region}.\n\n'
          '• **Overview**: One of Bangladesh\'s top travel gems, known for its breathtaking landscapes and scenic routes.\n'
          '• **Coordinates**: ${match.lat.toStringAsFixed(4)}°N, ${match.lng.toStringAsFixed(4)}°E.\n'
          '• **Best Season**: Winter (Nov - Feb) for cool treks and beaches; Monsoon (Jun - Sep) for roaring waterfalls and lush haors.\n'
          '• **Pro-Tip**: Carry BDT cash (ATMs can be sparse in hill tracks/remote islands) and verify local entry checkpoints.';
    }

    // Curated topical triggers
    if (query.contains('sajek') || query.contains('মেঘের রাজ্য')) {
      return '☁️ **Sajek Valley (Queen of Hills)**\n\n'
          '• **Altitude**: 1,800 ft above sea level in Rangamati, accessed via Dighinala, Khagrachhari.\n'
          '• **Top Spots**: Konglak Para (highest point), Ruilui Para, Helipad for cloud sunset.\n'
          '• **Army Escort**: Vehicles enter only with military convoy at 10:00 AM & 3:00 PM from Dighinala.\n'
          '• **Food**: Try authentic bamboo chicken and papaya juice!';
    }

    if (query.contains('cox') ||
        query.contains('beach') ||
        query.contains('সমুদ্র')) {
      return '🌊 **Cox\'s Bazar (World\'s Longest Sea Beach - 120km)**\n\n'
          '• **Highlights**: Laboni Beach (night market), Sugandha (street food), Kolatoli, and tranquil Inani coral beach.\n'
          '• **Must-Do**: Scenic drive down Marine Drive Road, visit Himchari national park & waterfalls.\n'
          '• **Seafood**: Fresh Rupchanda fry, Loitta fry, and dried fish (shukti) near fish market.';
    }

    if (query.contains('st. martin') ||
        query.contains('martin') ||
        query.contains('সেন্ট মার্টিন')) {
      return '🏝️ **St. Martin\'s Island (Narikel Jinjira)**\n\n'
          '• **Getting There**: Ferry or ship from Teknaf / Nuniar Chhara jetty.\n'
          '• **Chera Dwip**: Uninhabited coral islet south of St. Martin, reachable by boat or low-tide walk.\n'
          '• **Sustainability**: Avoid plastic waste, do not step on live corals, and enjoy fresh green coconuts.';
    }

    if (query.contains('sylhet') ||
        query.contains('jaflong') ||
        query.contains('ratargul') ||
        query.contains('সিলেট')) {
      return '🌿 **Sylhet & Greater Surma Valley**\n\n'
          '• **Ratargul**: Bangladesh\'s only freshwater swamp forest. Best explored on quiet non-motorized wooden dinghies.\n'
          '• **Jaflong & Lalakhal**: Clear turquoise waters flowing from the Khasi hills.\n'
          '• **Tea Gardens**: Malnicherra (oldest in the subcontinent) and Lakkatura.\n'
          '• **Local Delicacy**: Seven-layer tea in Sreemangal and Shatkora beef curry!';
    }

    if (query.contains('sundarban') || query.contains('সুন্দরবন')) {
      return '🐅 **Sundarbans Mangrove Forest (UNESCO World Heritage)**\n\n'
          '• **Home of**: The Royal Bengal Tiger, spotted deer, estuarine crocodiles, and river dolphins.\n'
          '• **Tour**: 3-day boat cruises departing from Khulna or Mongla with armed forest guard escorts.\n'
          '• **Key Points**: Kotka beach, Hiron Point, and Karamjal wildlife breeding center.';
    }

    if (query.contains('budget') ||
        query.contains('খরচ') ||
        query.contains('cost')) {
      return '💰 **Estimated Bangladesh Travel Budgets (Per Person)**\n\n'
          '• **Backpacker / Student**: 1,200 - 1,800 BDT/day (Local buses, non-AC guesthouses, local meals).\n'
          '• **Comfort / Family**: 3,500 - 6,000 BDT/day (AC coach/train, standard 3-star hotel, private transport).\n'
          '• **Luxury / Resort**: 9,000+ BDT/day (Eco-resorts in Sajek/Sreemangal, private flights, rental Chander Gari).\n\n'
          '💡 *Tip: You can use the `/split` command right here in Bhromon to manage shared trip expenses!*';
    }

    if (query.contains('packing') ||
        query.contains('checklist') ||
        query.contains('ব্যাগ')) {
      return '🎒 **Essential Bangladesh Travel Checklist**\n\n'
          '1. **Documents**: National ID card (mandatory for Army checkposts in CHT) & hotel booking vouchers.\n'
          '2. **Health**: Odomos mosquito repellent, ORS oral saline, power bank (essential during power cuts).\n'
          '3. **Footwear**: Sturdy grip sandals or hiking shoes (slippery clay trails in monsoon).\n'
          '4. **Cash**: Keep 5,000–10,000 BDT in small denominations.';
    }

    return '🌏 **Hello, Explorer!** I am your **Bhromon Travel Assistant**.\n\n'
        'You can ask me anything about traveling across Bangladesh! For example:\n'
        '• *"What is the best route to Sajek Valley?"*\n'
        '• *"Top attractions in Cox\'s Bazar and Inani"*\n'
        '• *"Budget and hotel recommendations for Sreemangal"*\n'
        '• *"What should I pack for a Bandarban trek?"*\n\n'
        'How can I help you plan your next adventure?';
  }
}

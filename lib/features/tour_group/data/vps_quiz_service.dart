import 'dart:async';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../../../../core/utils/app_logger.dart';

/// Represents a single travel quiz question rendered from the server.
class ServerQuizQuestion {
  final int id;
  final String category;
  final String destinationTag;
  final String difficulty;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const ServerQuizQuestion({
    required this.id,
    required this.category,
    required this.destinationTag,
    required this.difficulty,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory ServerQuizQuestion.fromJson(Map<String, dynamic> json) {
    final optsRaw = json['options_bn'] ?? json['options'];
    final List<String> opts = (optsRaw is List)
        ? optsRaw.map((e) => e.toString()).toList()
        : <String>[];

    return ServerQuizQuestion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? 'general_travel',
      destinationTag: json['destination_tag']?.toString() ?? 'all',
      difficulty: json['difficulty']?.toString() ?? 'medium',
      question: (json['question_bn'] ?? json['question'])?.toString() ?? '',
      options: opts,
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      explanation:
          (json['explanation_bn'] ?? json['explanation'])?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'destination_tag': destinationTag,
        'difficulty': difficulty,
        'question_bn': question,
        'options_bn': options,
        'correct_index': correctIndex,
        'explanation_bn': explanation,
      };
}

/// Service providing access to 1000+ travel quizzes hosted on the Bhromon VPS.
class VpsQuizService {
  static final VpsQuizService _instance = VpsQuizService._internal();
  factory VpsQuizService() => _instance;
  VpsQuizService._internal();

  static const String baseUrl = 'https://bhromon.fun/api/quiz/';
  static const String _kQuizCacheBox = 'quiz_cache_box';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Box<dynamic>? _cacheBox;

  Future<Box<dynamic>> _getBox() async {
    if (_cacheBox != null && _cacheBox!.isOpen) return _cacheBox!;
    try {
      _cacheBox = await Hive.openBox<dynamic>(_kQuizCacheBox);
    } catch (_) {
      _cacheBox = await Hive.openBox<dynamic>(_kQuizCacheBox);
    }
    return _cacheBox!;
  }

  /// Fetches randomized quiz questions for a destination or category.
  /// Seamlessly loads from local cache if offline, and updates cache when online.
  Future<List<ServerQuizQuestion>> fetchQuestions({
    String? destination,
    String? category,
    String? difficulty,
    int limit = 10,
  }) async {
    final cacheKey = 'q_${destination ?? "all"}_${category ?? "all"}_$limit';

    // 1. Try remote fetch from Bhromon VPS
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'questions',
        queryParameters: {
          if (destination != null && destination.isNotEmpty)
            'destination': destination.toLowerCase().trim(),
          if (category != null && category.isNotEmpty) 'category': category,
          if (difficulty != null && difficulty.isNotEmpty)
            'difficulty': difficulty,
          'limit': limit,
        },
      );

      final rawList = res.data?['questions'] as List? ?? [];
      final questions = rawList
          .map((e) =>
              ServerQuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (questions.isNotEmpty) {
        // Cache for offline resilience
        final box = await _getBox();
        final serialized = questions.map((q) => q.toJson()).toList();
        await box.put(cacheKey, serialized);
        return questions;
      }
    } catch (e) {
      logDebug('[VpsQuiz] Remote fetch failed, falling back to cache: $e');
    }

    // 2. Fallback to cached questions
    try {
      final box = await _getBox();
      final cached = box.get(cacheKey) as List?;
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map((e) => ServerQuizQuestion.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e, st) {
      logWarning('[VpsQuiz] Cache read error', e, st);
    }

    // 3. Fallback to built-in verified questions
    return _getBuiltinFallbackQuestions(destination);
  }

  /// Submits the user's score to the VPS leaderboard.
  Future<Map<String, dynamic>?> submitQuizAttempt({
    required String userUid,
    String? userName,
    String? tourId,
    required int score,
    required int total,
    String? category,
    String? destination,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'submit',
        data: {
          'user_uid': userUid,
          'user_name': userName ?? 'ভ্রমণকারী',
          'tour_id': tourId,
          'score': score,
          'total': total,
          'category': category,
          'destination': destination,
        },
      );
      return res.data;
    } catch (e, st) {
      logWarning('[VpsQuiz] Failed to submit attempt', e, st);
      return null;
    }
  }

  /// Fetches top quiz champions leaderboard.
  Future<List<Map<String, dynamic>>> fetchLeaderboard({int limit = 20}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'leaderboard',
        queryParameters: {'limit': limit},
      );
      final raw = res.data?['leaderboard'] as List? ?? [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      logWarning('[VpsQuiz] Failed to fetch leaderboard', e, st);
      return [];
    }
  }

  /// Built-in fallback questions if the app is brand new and completely offline.
  List<ServerQuizQuestion> _getBuiltinFallbackQuestions(String? destination) {
    final dest = destination?.toLowerCase() ?? '';
    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return const [
        ServerQuizQuestion(
          id: 1,
          category: 'hills_trek',
          destinationTag: 'sajek',
          difficulty: 'easy',
          question: 'সাজেক ভ্যালি কোন জেলায় অবস্থিত?',
          options: ['রাঙ্গামাটি', 'খাগড়াছড়ি', 'বান্দরবান', 'কক্সবাজার'],
          correctIndex: 0,
          explanation:
              'সাজেক ভ্যালি ভৌগোলিকভাবে রাঙ্গামাটি জেলার বাঘাইছড়ি উপজেলায় অবস্থিত, তবে সেখানে যেতে হয় খাগড়াছড়ির দীঘিনালা হয়ে।',
        ),
        ServerQuizQuestion(
          id: 2,
          category: 'hills_trek',
          destinationTag: 'sajek',
          difficulty: 'medium',
          question: 'সাজেক ভ্যালির সবচেয়ে উঁচু চূড়া বা শীর্ষ বিন্দুর নাম কী?',
          options: ['কংলাক পাহাড়', 'রুইলুই পাড়া', 'হেলিপ্যাড', 'মারায়ন তং'],
          correctIndex: 0,
          explanation:
              'কংলাক পাড়া সাজেকের সর্বোচ্চ বিন্দু (উচ্চতা প্রায় ১৮০০ ফুট)।',
        ),
      ];
    }

    return const [
      ServerQuizQuestion(
        id: 101,
        category: 'beaches',
        destinationTag: 'coxs_bazar',
        difficulty: 'easy',
        question: 'পৃথিবীর দীর্ঘতম প্রাকৃতিক বালুকাময় সমুদ্র সৈকত কোনটি?',
        options: ['কক্সবাজার', 'কুয়াকাটা', 'গোয়া', 'মায়ামি বিচ'],
        correctIndex: 0,
        explanation:
            'কক্সবাজার প্রায় ১২০ কিলোমিটার দীর্ঘ বিশ্বের দীর্ঘতম অবিচ্ছিন্ন প্রাকৃতিক বালুকাময় সৈকত।',
      ),
      ServerQuizQuestion(
        id: 102,
        category: 'nature',
        destinationTag: 'sundarbans',
        difficulty: 'easy',
        question: 'বিশ্বের বৃহত্তম ম্যানগ্রোভ বন কোনটি?',
        options: ['সুন্দরবন', 'আমাজন বন', 'ভাওয়াল শালবন', 'লাউয়াছড়া'],
        correctIndex: 0,
        explanation:
            'সুন্দরবন প্রায় ১০,০০০ বর্গ কিলোমিটার আয়তনের বিশ্বের একক বৃহত্তম উপকূলীয় ম্যানগ্রোভ বনভূমি।',
      ),
      ServerQuizQuestion(
        id: 103,
        category: 'travel_safety',
        destinationTag: 'all',
        difficulty: 'easy',
        question:
            'বাংলাদেশে যেকোনো জরুরি প্রয়োজনে জাতীয় জরুরি সেবা নম্বর কত?',
        options: ['৯৯৯ (999)', '১০০', '১১১', '৭৭৭'],
        correctIndex: 0,
        explanation:
            '৯৯৯-এ বিনামূল্যে কল করে তাৎক্ষণিক পুলিশ, অ্যাম্বুলেন্স ও ফায়ার সার্ভিস সেবা পাওয়া যায়।',
      ),
    ];
  }
}

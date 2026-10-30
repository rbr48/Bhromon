import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import '../../../../core/utils/app_logger.dart';
import '../domain/models/newspaper_models.dart';

/// Service for fetching live headlines, newspapers directory, and ad-free reader content.
class NewspaperService {
  static final NewspaperService _instance = NewspaperService._internal();
  factory NewspaperService() => _instance;

  static const String _kBaseUrl = 'https://bhromon.fun/api/news';
  static const String _kPrefsBox = 'newspaper_prefs';

  late final Dio _dio;
  Box<dynamic>? _box;

  NewspaperService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _kBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'BhromonApp/2.1.0 (Flutter)',
        },
      ),
    );
  }

  Future<Box<dynamic>> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    try {
      _box = await Hive.openBox<dynamic>(_kPrefsBox);
      return _box!;
    } catch (e, st) {
      logWarning('NewspaperService box warning', e, st);
      return await Hive.openBox<dynamic>(_kPrefsBox);
    }
  }

  // -------------------------------------------------------------------------
  // Local Favorites & Continue Reading History
  // -------------------------------------------------------------------------

  Future<Set<String>> getFavoritePaperIds() async {
    final box = await _getBox();
    final raw = box.get('favorite_paper_ids');
    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }
    return {'prothom_alo', 'daily_star', 'bbc_bangla'};
  }

  Future<void> toggleFavoritePaper(String paperId) async {
    final box = await _getBox();
    final current = await getFavoritePaperIds();
    if (current.contains(paperId)) {
      current.remove(paperId);
    } else {
      current.add(paperId);
    }
    await box.put('favorite_paper_ids', current.toList());
  }

  Future<List<String>> getContinueReadingIds() async {
    final box = await _getBox();
    final raw = box.get('continue_reading_ids');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    // Sensible defaults
    return [
      'samakal',
      'kaler_kantho',
      'prothom_alo',
      'daily_star',
      'al_jazeera'
    ];
  }

  Future<void> recordPaperRead(String paperId) async {
    final box = await _getBox();
    final current = await getContinueReadingIds();
    current.remove(paperId);
    current.insert(0, paperId);
    if (current.length > 15) {
      current.removeRange(15, current.length);
    }
    await box.put('continue_reading_ids', current);
  }

  Future<Map<String, NewsHeadline>> getBookmarkedHeadlines() async {
    final box = await _getBox();
    final raw = box.get('bookmarked_headlines');
    if (raw is Map) {
      final map = <String, NewsHeadline>{};
      raw.forEach((k, v) {
        if (v is Map) {
          map[k.toString()] =
              NewsHeadline.fromJson(Map<String, dynamic>.from(v));
        }
      });
      return map;
    }
    return {};
  }

  Future<void> toggleBookmarkHeadline(NewsHeadline headline) async {
    final box = await _getBox();
    final current = await getBookmarkedHeadlines();
    if (current.containsKey(headline.id)) {
      current.remove(headline.id);
    } else {
      current[headline.id] = headline;
    }
    final rawMap = current.map((k, v) => MapEntry(k, v.toJson()));
    await box.put('bookmarked_headlines', rawMap);
  }

  // -------------------------------------------------------------------------
  // Remote Network Calls with Offline Cache Fallback
  // -------------------------------------------------------------------------

  /// Fetches live aggregated headlines.
  Future<NewsFeedResult> fetchHeadlines({
    String? category,
    String? paperId,
    String? query,
    bool refresh = false,
  }) async {
    final box = await _getBox();
    final cacheKey =
        'cached_feed_${category ?? "all"}_${paperId ?? ""}_${query ?? ""}';

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/headlines',
        queryParameters: {
          if (category != null && category != 'all') 'category': category,
          if (paperId != null && paperId.isNotEmpty) 'paper_id': paperId,
          if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
          if (refresh) 'refresh': true,
        },
      );

      if (res.data != null) {
        final feedResult = NewsFeedResult.fromJson(res.data!);
        // Save to cache
        await box.put(cacheKey, jsonEncode(res.data));
        return feedResult;
      }
    } catch (e, st) {
      logWarning('NewspaperService fetchHeadlines error', e, st);
    }

    // Offline cache fallback
    final cachedStr = box.get(cacheKey);
    if (cachedStr is String && cachedStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        return NewsFeedResult.fromJson(decoded);
      } catch (_) {}
    }

    return const NewsFeedResult(
      count: 0,
      updatedAt: 0,
      isSyncing: false,
      clusters: [],
      items: [],
    );
  }

  /// Fetches the newspaper directory catalog.
  Future<List<Newspaper>> fetchNewspapers({
    String? category,
    bool forceRefresh = false,
  }) async {
    final box = await _getBox();
    const cacheKey = 'cached_papers_directory';

    if (!forceRefresh) {
      final cachedStr = box.get(cacheKey);
      if (cachedStr is String && cachedStr.isNotEmpty) {
        // Discard any legacy mojibake encoding corruption
        if (cachedStr.contains('à¦') || cachedStr.contains('â€')) {
          await box.delete(cacheKey);
        } else {
          try {
            final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
            final raw = decoded['papers'] as List<dynamic>? ?? [];
            final cachedPapers = raw
                .whereType<Map<String, dynamic>>()
                .map((m) => Newspaper.fromJson(m))
                .toList();
            if (cachedPapers.isNotEmpty) {
              if (category != null && category != 'all') {
                return cachedPapers
                    .where((p) => p.category == category)
                    .toList();
              }
              return cachedPapers;
            }
          } catch (_) {}
        }
      }
    }

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/papers',
        queryParameters: {
          if (category != null && category != 'all') 'category': category,
        },
      );

      if (res.data != null) {
        final raw = res.data!['papers'] as List<dynamic>? ?? [];
        final papers = raw
            .whereType<Map<String, dynamic>>()
            .map((m) => Newspaper.fromJson(m))
            .toList();
        await box.put(cacheKey, jsonEncode(res.data));
        return papers;
      }
    } catch (e, st) {
      logWarning('NewspaperService fetchNewspapers error', e, st);
    }

    // Cache fallback
    final cachedStr = box.get(cacheKey);
    if (cachedStr is String &&
        cachedStr.isNotEmpty &&
        !cachedStr.contains('à¦')) {
      try {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        final raw = decoded['papers'] as List<dynamic>? ?? [];
        return raw
            .whereType<Map<String, dynamic>>()
            .map((m) => Newspaper.fromJson(m))
            .toList();
      } catch (_) {}
    }

    return [];
  }

  /// Fetches clean ad-free readable article content.
  Future<CleanArticle> fetchCleanArticle(String articleUrl) async {
    final box = await _getBox();
    final cacheKey = 'article_${articleUrl.hashCode}';

    // Local cache check
    final cachedStr = box.get(cacheKey);
    if (cachedStr is String && cachedStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        return CleanArticle.fromJson(decoded);
      } catch (_) {}
    }

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/reader',
        queryParameters: {'url': articleUrl},
      );

      if (res.data != null) {
        final article = CleanArticle.fromJson(res.data!);
        await box.put(cacheKey, jsonEncode(article.toJson()));
        return article;
      }
    } catch (e, st) {
      logError('NewspaperService fetchCleanArticle error', e, st);
      rethrow;
    }

    throw Exception('Failed to load clean article view');
  }
}

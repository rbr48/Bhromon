import 'package:equatable/equatable.dart';

/// Represents a newspaper in the directory catalog.
class Newspaper extends Equatable {
  final String id;
  final String name;
  final String nameBn;
  final String domain;
  final String category;
  final String? rssUrl;
  final String websiteUrl;
  final String language;
  final bool isPopular;

  const Newspaper({
    required this.id,
    required this.name,
    required this.nameBn,
    required this.domain,
    required this.category,
    this.rssUrl,
    required this.websiteUrl,
    this.language = 'bn',
    this.isPopular = false,
  });

  factory Newspaper.fromJson(Map<String, dynamic> json) {
    return Newspaper(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      nameBn: json['nameBn'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      category: json['category'] as String? ?? 'bangla_dailies',
      rssUrl: json['rssUrl'] as String?,
      websiteUrl: json['websiteUrl'] as String? ?? '',
      language: json['language'] as String? ?? 'bn',
      isPopular: json['isPopular'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameBn': nameBn,
        'domain': domain,
        'category': category,
        'rssUrl': rssUrl,
        'websiteUrl': websiteUrl,
        'language': language,
        'isPopular': isPopular,
      };

  @override
  List<Object?> get props => [id, name, domain, category];
}

/// Represents a single live news headline.
class NewsHeadline extends Equatable {
  final String id;
  final String paperId;
  final String paperName;
  final String paperLogo;
  final String title;
  final String snippet;
  final String? imageUrl;
  final String articleUrl;
  final int publishedAt;
  final String relativeTime;
  final String category;

  const NewsHeadline({
    required this.id,
    required this.paperId,
    required this.paperName,
    required this.paperLogo,
    required this.title,
    required this.snippet,
    this.imageUrl,
    required this.articleUrl,
    required this.publishedAt,
    required this.relativeTime,
    required this.category,
  });

  factory NewsHeadline.fromJson(Map<String, dynamic> json) {
    return NewsHeadline(
      id: json['id'] as String? ?? '',
      paperId: json['paperId'] as String? ?? '',
      paperName: json['paperName'] as String? ?? '',
      paperLogo: json['paperLogo'] as String? ?? '',
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      imageUrl: (json['imageUrl'] as String?)?.isNotEmpty == true
          ? json['imageUrl'] as String?
          : null,
      articleUrl: json['articleUrl'] as String? ?? '',
      publishedAt: (json['publishedAt'] as num?)?.toInt() ?? 0,
      relativeTime: json['relativeTime'] as String? ?? '',
      category: json['category'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'paperId': paperId,
        'paperName': paperName,
        'paperLogo': paperLogo,
        'title': title,
        'snippet': snippet,
        'imageUrl': imageUrl,
        'articleUrl': articleUrl,
        'publishedAt': publishedAt,
        'relativeTime': relativeTime,
        'category': category,
      };

  @override
  List<Object?> get props => [id, articleUrl, title];
}

/// A cluster of headlines representing "Same story, different papers".
class StoryCluster extends Equatable {
  final String topic;
  final int headlineCount;
  final List<String> papers;
  final List<NewsHeadline> items;

  const StoryCluster({
    required this.topic,
    required this.headlineCount,
    required this.papers,
    required this.items,
  });

  factory StoryCluster.fromJson(Map<String, dynamic> json) {
    final rawPapers = json['papers'] as List<dynamic>? ?? [];
    final rawItems = json['items'] as List<dynamic>? ?? [];

    return StoryCluster(
      topic: json['topic'] as String? ?? '',
      headlineCount: (json['headlineCount'] as num?)?.toInt() ?? rawItems.length,
      papers: rawPapers.map((e) => e.toString()).toList(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((m) => NewsHeadline.fromJson(m))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [topic, headlineCount, papers];
}

/// Aggregated news feed response payload.
class NewsFeedResult {
  final int count;
  final int updatedAt;
  final bool isSyncing;
  final List<StoryCluster> clusters;
  final List<NewsHeadline> items;

  const NewsFeedResult({
    required this.count,
    required this.updatedAt,
    required this.isSyncing,
    required this.clusters,
    required this.items,
  });

  factory NewsFeedResult.fromJson(Map<String, dynamic> json) {
    final rawClusters = json['clusters'] as List<dynamic>? ?? [];
    final rawItems = json['items'] as List<dynamic>? ?? [];

    return NewsFeedResult(
      count: (json['count'] as num?)?.toInt() ?? rawItems.length,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      isSyncing: json['isSyncing'] as bool? ?? false,
      clusters: rawClusters
          .whereType<Map<String, dynamic>>()
          .map((m) => StoryCluster.fromJson(m))
          .toList(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((m) => NewsHeadline.fromJson(m))
          .toList(),
    );
  }
}

/// An ad-free, distraction-free readable representation of an article.
class CleanArticle extends Equatable {
  final String title;
  final String sourceName;
  final String author;
  final String publishedDate;
  final String? heroImageUrl;
  final List<String> paragraphs;
  final String cleanHtml;
  final int wordCount;
  final int readingTimeMinutes;
  final String originalUrl;
  final bool isCached;

  const CleanArticle({
    required this.title,
    required this.sourceName,
    required this.author,
    required this.publishedDate,
    this.heroImageUrl,
    required this.paragraphs,
    required this.cleanHtml,
    required this.wordCount,
    required this.readingTimeMinutes,
    required this.originalUrl,
    this.isCached = false,
  });

  factory CleanArticle.fromJson(Map<String, dynamic> json) {
    final rawP = json['paragraphs'] as List<dynamic>? ?? [];
    return CleanArticle(
      title: json['title'] as String? ?? 'Untitled',
      sourceName: json['sourceName'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publishedDate: json['publishedDate'] as String? ?? '',
      heroImageUrl: (json['heroImageUrl'] as String?)?.isNotEmpty == true
          ? json['heroImageUrl'] as String?
          : null,
      paragraphs: rawP.map((e) => e.toString()).toList(),
      cleanHtml: json['cleanHtml'] as String? ?? '',
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      readingTimeMinutes: (json['readingTimeMinutes'] as num?)?.toInt() ?? 1,
      originalUrl: json['originalUrl'] as String? ?? '',
      isCached: json['isCached'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'sourceName': sourceName,
        'author': author,
        'publishedDate': publishedDate,
        'heroImageUrl': heroImageUrl,
        'paragraphs': paragraphs,
        'cleanHtml': cleanHtml,
        'wordCount': wordCount,
        'readingTimeMinutes': readingTimeMinutes,
        'originalUrl': originalUrl,
        'isCached': isCached,
      };

  @override
  List<Object?> get props => [originalUrl, title];
}

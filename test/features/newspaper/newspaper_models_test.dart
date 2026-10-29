import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/newspaper/domain/models/newspaper_models.dart';

void main() {
  group('Newspaper Models Tests', () {
    test('Newspaper serialization roundtrip', () {
      final json = {
        'id': 'prothom_alo',
        'name': 'Prothom Alo',
        'nameBn': 'প্রথম আলো',
        'domain': 'prothomalo.com',
        'category': 'bangla_dailies',
        'rssUrl': 'https://www.prothomalo.com/feed',
        'websiteUrl': 'https://www.prothomalo.com',
        'language': 'bn',
        'isPopular': true,
      };

      final paper = Newspaper.fromJson(json);
      expect(paper.id, 'prothom_alo');
      expect(paper.name, 'Prothom Alo');
      expect(paper.nameBn, 'প্রথম আলো');
      expect(paper.domain, 'prothomalo.com');
      expect(paper.category, 'bangla_dailies');
      expect(paper.isPopular, isTrue);

      final outJson = paper.toJson();
      expect(outJson['id'], 'prothom_alo');
      expect(outJson['name'], 'Prothom Alo');
    });

    test('NewsHeadline serialization and fallback handling', () {
      final json = {
        'id': 'hd_123',
        'paperId': 'daily_star',
        'paperName': 'The Daily Star',
        'paperLogo': 'https://google.com/favicon.ico',
        'title': 'Historic Cricket Victory for Tigers',
        'snippet':
            'Bangladesh won the series by 5 wickets in an exciting finish.',
        'imageUrl': 'https://example.com/tiger.jpg',
        'articleUrl': 'https://thedailystar.net/sports/cricket/123',
        'publishedAt': 1793180000000,
        'relativeTime': '15m ago',
        'category': 'sports',
      };

      final headline = NewsHeadline.fromJson(json);
      expect(headline.id, 'hd_123');
      expect(headline.paperName, 'The Daily Star');
      expect(headline.title, 'Historic Cricket Victory for Tigers');
      expect(headline.imageUrl, 'https://example.com/tiger.jpg');
      expect(headline.relativeTime, '15m ago');

      final outJson = headline.toJson();
      expect(outJson['id'], 'hd_123');
      expect(
          outJson['articleUrl'], 'https://thedailystar.net/sports/cricket/123');
    });

    test('StoryCluster parsing ("Same story, different papers")', () {
      final json = {
        'topic': 'Severe weather alert in coastal districts',
        'headlineCount': 2,
        'papers': ['Prothom Alo', 'Daily Star'],
        'items': [
          {
            'id': '1',
            'paperId': 'prothom_alo',
            'paperName': 'Prothom Alo',
            'paperLogo': '',
            'title': 'উপকূলীয় অঞ্চলে সতর্ক সংকেত',
            'snippet': 'সমুদ্রবন্দরে ৪ নম্বর সতর্কতা সংকেত জারি।',
            'imageUrl': null,
            'articleUrl': 'https://prothomalo.com/news/1',
            'publishedAt': 1793180000000,
            'relativeTime': '20m ago',
            'category': 'bangla_dailies',
          },
          {
            'id': '2',
            'paperId': 'daily_star',
            'paperName': 'Daily Star',
            'paperLogo': '',
            'title': 'Cautionary signal 4 hoisted at seaports',
            'snippet':
                'Deep depression in Bay of Bengal prompts weather warning.',
            'imageUrl': null,
            'articleUrl': 'https://thedailystar.net/news/2',
            'publishedAt': 1793180000000,
            'relativeTime': '25m ago',
            'category': 'english_dailies',
          }
        ],
      };

      final cluster = StoryCluster.fromJson(json);
      expect(cluster.topic, 'Severe weather alert in coastal districts');
      expect(cluster.headlineCount, 2);
      expect(cluster.papers, contains('Prothom Alo'));
      expect(cluster.papers, contains('Daily Star'));
      expect(cluster.items.length, 2);
      expect(cluster.items.first.paperName, 'Prothom Alo');
    });

    test('CleanArticle reader model serialization', () {
      final json = {
        'title': 'Eco-Tourism Guidelines for Sajek Valley',
        'sourceName': 'Dhaka Tribune',
        'author': 'Staff Reporter',
        'publishedDate': '2026-10-28',
        'heroImageUrl': 'https://example.com/sajek.jpg',
        'paragraphs': [
          'Sajek Valley has introduced new environmental rules for travelers.',
          'Visitors are encouraged to carry reusable water bottles and avoid plastic waste.',
          'Local tribal communities will manage green checkpoints.',
        ],
        'cleanHtml': '<article>...</article>',
        'wordCount': 350,
        'readingTimeMinutes': 2,
        'originalUrl': 'https://dhakatribune.com/travel/sajek',
        'isCached': true,
      };

      final article = CleanArticle.fromJson(json);
      expect(article.title, 'Eco-Tourism Guidelines for Sajek Valley');
      expect(article.sourceName, 'Dhaka Tribune');
      expect(article.paragraphs.length, 3);
      expect(article.wordCount, 350);
      expect(article.readingTimeMinutes, 2);
      expect(article.isCached, isTrue);

      final outJson = article.toJson();
      expect(outJson['title'], article.title);
      expect(outJson['paragraphs'].length, 3);
    });

    test('NewsFeedResult aggregation payload parsing', () {
      final json = {
        'count': 1,
        'updatedAt': 1793180000000,
        'isSyncing': false,
        'clusters': <Map<String, dynamic>>[],
        'items': [
          {
            'id': '10',
            'paperId': 'bbc_bangla',
            'paperName': 'BBC News Bangla',
            'paperLogo': '',
            'title': 'বিশ্ব রাজনীতিতে নতুন মোড়',
            'snippet': 'মধ্যপ্রাচ্যে নতুন আলোচনার সূচনা।',
            'articleUrl': 'https://bbc.com/bengali/10',
            'publishedAt': 1793180000000,
            'relativeTime': '1h ago',
            'category': 'world_tech',
          }
        ],
      };

      final result = NewsFeedResult.fromJson(json);
      expect(result.count, 1);
      expect(result.items.length, 1);
      expect(result.items.first.paperName, 'BBC News Bangla');
      expect(result.clusters, isEmpty);
    });
  });
}

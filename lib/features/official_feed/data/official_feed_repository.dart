import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/utils/app_logger.dart';
import '../domain/official_reel.dart';

/// Reads the official feed, and keeps this device subscribed to its new-post pushes.
class OfficialFeedRepository {
  OfficialFeedRepository({FirebaseFirestore? firestore, http.Client? client})
      : _firestore = firestore,
        _client = client;

  /// The topic the server pushes new official posts to.
  static const String topic = 'official_instafeed';

  final FirebaseFirestore? _firestore;
  final http.Client? _client;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// The newest official posts, newest first. A post whose video or image is not an official file
  /// is left out.
  Stream<List<OfficialReel>> watchReels({int limit = 50}) {
    return _db
        .collection('official_instafeed')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                if (OfficialReel.fromMap(doc.id, doc.data()) case final reel?)
                  reel,
            ]);
  }

  /// Publishes a new official reel or photo post via the media server.
  /// Requires platform admin bearer token or official publish key.
  Future<Map<String, dynamic>> publishOfficialPost({
    required List<int> fileBytes,
    required String fileName,
    String caption = '',
    int? durationSeconds,
    List<int>? coverBytes,
    String? coverName,
    required String idToken,
    String? baseUrl,
  }) async {
    final mediaBase = baseUrl ?? 'https://bhromon.fun/api/media';
    final uri = Uri.parse('$mediaBase/official/posts');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $idToken';
    request.fields['caption'] = caption;
    if (durationSeconds != null && durationSeconds > 0) {
      request.fields['durationSeconds'] = durationSeconds.toString();
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    if (coverBytes != null && coverName != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'cover',
          coverBytes,
          filename: coverName,
        ),
      );
    }

    final client = _client;
    final http.StreamedResponse streamedResponse;
    if (client != null) {
      streamedResponse = await client.send(request);
    } else {
      streamedResponse = await request.send();
    }
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Subscribes this device to new-post pushes, or unsubscribes it. Mobile only: the web
  /// has no push topics here, so this does nothing there. A failure is logged.
  Future<void> setFollowing(bool follow) async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (follow) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (error, stackTrace) {
      logWarning('[OfficialFeed] Could not change the push subscription', error,
          stackTrace);
    }
  }
}

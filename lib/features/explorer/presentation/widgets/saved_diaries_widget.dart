import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../feed/presentation/widgets/trip_log_detail_sheet.dart';

/// 🔖 Saved Diaries tab for the Explorer Profile.
/// Shows diary entries the user has bookmarked from the community.
class SavedDiariesWidget extends StatelessWidget {
  final String uid;
  final List<String> savedTripLogIds;

  const SavedDiariesWidget({
    super.key,
    required this.uid,
    required this.savedTripLogIds,
  });

  @override
  Widget build(BuildContext context) {
    if (savedTripLogIds.isEmpty) {
      return _EmptySaved();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: savedTripLogIds.length,
      itemBuilder: (context, index) {
        final tripId = savedTripLogIds[index];
        return _SavedDiaryCard(tripId: tripId);
      },
    );
  }
}

class _SavedDiaryCard extends StatelessWidget {
  final String tripId;

  const _SavedDiaryCard({required this.tripId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('trip_logs').doc(tripId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.mintGreen,
                strokeWidth: 2,
              ),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Entry was deleted — show offline placeholder
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 32),
                SizedBox(height: 8),
                Text(
                  'উপলব্ধ নেই',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final TripLog tripLog;
        try {
          tripLog = TripLog.fromJson({'id': tripId, ...data});
        } catch (_) {
          return const SizedBox.shrink();
        }

        // Find first image block for thumbnail
        String? thumbnailUrl;
        for (final block in tripLog.blocks) {
          final url = block.when(
            text: (_, __, ___) => null,
            image: (_, url, ___, ____) => url.isNotEmpty ? url : null,
            video: (_, __, ___, ____) => null,
            costEntry: (_, __, ___) => null,
            route: (_, __, ___) => null,
            safetyNote: (_, __, ___) => null,
            voiceNote: (_, __, ___, ____, _____) => null,
          );
          if (url != null) {
            thumbnailUrl = url;
            break;
          }
        }

        return GestureDetector(
          onTap: () => TripLogDetailSheet.show(context, tripLog),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  Expanded(
                    child: thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: thumbnailUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _PlaceholderThumb(),
                          )
                        : _PlaceholderThumb(),
                  ),
                  // Card info
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tripLog.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tripLog.district}, ${tripLog.division}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.bookmark_rounded,
                                color: AppColors.gold, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'সংরক্ষিত',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.photo_library_outlined,
          color: Colors.white12, size: 40),
    );
  }
}

class _EmptySaved extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🔖', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text(
            'কোনো ডায়েরি সংরক্ষণ করেননি',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'ফিডে ডায়েরি সংরক্ষণ করতে 🔖 আইকনে ট্যাপ করুন',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

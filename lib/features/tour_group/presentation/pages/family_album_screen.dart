import 'package:flutter/material.dart';
import '../widgets/group_back_button.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_post_models.dart';
import '../../domain/services/family_album.dart';
import '../widgets/instafeed/tour_safe_network_image.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// The circle's photos, grouped by the month they were posted. Photos come from
/// the Moments feed, so anything shared there appears here too. Tapping a photo
/// shows it full size.
class FamilyAlbumScreen extends StatefulWidget {
  const FamilyAlbumScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<FamilyAlbumScreen> createState() => _FamilyAlbumScreenState();
}

class _FamilyAlbumScreenState extends State<FamilyAlbumScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<TourPostItem>> _posts =
      _repository.watchPosts(widget.tourId, limit: 300);

  void _open(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: TourSafeNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: context.forest.surfaceFor(_bg),
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          title: Text(l10n.translate('album_title'),
              style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          backgroundColor: context.forest.surfaceFor(_card),
          foregroundColor: context.forest.text,
          elevation: 0,
        ),
        body: StreamBuilder<List<TourPostItem>>(
          stream: _posts,
          builder: (context, snap) {
            if (snap.hasError) {
              return _message(l10n.translate('album_load_failed'));
            }
            final posts = snap.data;
            if (posts == null) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.mintGreen));
            }
            final months = familyAlbumMonths(posts);
            if (months.isEmpty) return _message(l10n.translate('album_empty'));
            return CustomScrollView(
              slivers: [
                for (final month in months) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              localizedDateFormat('MMMM yyyy')
                                  .format(month.month),
                              style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                          ),
                          Text(
                            l10n.translate('album_count', args: {
                              'count': l10n.number(month.photos.length),
                            }),
                            style: TextStyle(
                                color: context.forest.text54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: month.photos.length,
                      itemBuilder: (context, i) {
                        final url = month.photos[i];
                        return InkWell(
                          onTap: () => _open(url),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TourSafeNetworkImage(imageUrl: url),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text70, fontSize: 14)),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'hotel_room_map_screen.dart';
import 'transport_screen.dart';
import 'luggage_tracker_screen.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../tour_routes.dart';

class TourLogisticsHubScreen extends StatefulWidget {
  final String tourId;

  const TourLogisticsHubScreen({super.key, required this.tourId});

  @override
  State<TourLogisticsHubScreen> createState() => _TourLogisticsHubScreenState();
}

class _TourLogisticsHubScreenState extends State<TourLogisticsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
      appBar: AppBar(
        leading: BackButton(
          color: context.forest.text,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(tourHubPath(widget.tourId));
            }
          },
        ),
        backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
        elevation: 0,
        title: Text(
          context.l10n.translate('tour_logistics_title'),
          style: TextStyle(
              color: context.forest.text,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: context.forest.text60,
          tabs: [
            Tab(
                icon: const Icon(Icons.commute_rounded),
                text: context.l10n.translate('tour_tab_transport')),
            Tab(
                icon: const Icon(Icons.hotel_rounded),
                text: context.l10n.translate('tour_tab_hotel')),
            Tab(
                icon: const Icon(Icons.luggage_rounded),
                text: context.l10n.translate('tour_tab_luggage')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TransportScreen(tourId: widget.tourId, embedded: true),
          HotelRoomMapScreen(tourId: widget.tourId, embedded: true),
          LuggageTrackerScreen(tourId: widget.tourId, embedded: true),
        ],
      ),
    );
  }
}

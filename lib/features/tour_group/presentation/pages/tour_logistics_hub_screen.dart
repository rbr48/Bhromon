import 'package:flutter/material.dart';
import 'bus_seat_map_screen.dart';
import 'hotel_room_map_screen.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          context.l10n.translate('tour_logistics_title'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
                icon: const Icon(Icons.directions_bus_rounded),
                text: context.l10n.translate('tour_tab_bus')),
            Tab(
                icon: const Icon(Icons.hotel_rounded),
                text: context.l10n.translate('tour_tab_hotel')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          BusSeatMapScreen(tourId: widget.tourId, embedded: true),
          HotelRoomMapScreen(tourId: widget.tourId, embedded: true),
        ],
      ),
    );
  }
}

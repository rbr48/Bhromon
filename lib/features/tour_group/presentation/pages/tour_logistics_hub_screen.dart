import 'package:flutter/material.dart';
import 'bus_seat_map_screen.dart';
import 'hotel_room_map_screen.dart';
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
        title: const Text(
          'Logistics (সিট ও রুম বণ্টন)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(
                icon: Icon(Icons.directions_bus_rounded),
                text: 'Bus Seats (বাস)'),
            Tab(icon: Icon(Icons.hotel_rounded), text: 'Hotel Rooms (রুম)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          BusSeatMapScreen(tourId: widget.tourId),
          HotelRoomMapScreen(tourId: widget.tourId),
        ],
      ),
    );
  }
}

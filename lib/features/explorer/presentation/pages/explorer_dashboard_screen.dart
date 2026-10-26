import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/widgets/adaptive_columns.dart';

class ExplorerDashboardScreen extends StatefulWidget {
  const ExplorerDashboardScreen({super.key});

  @override
  State<ExplorerDashboardScreen> createState() =>
      _ExplorerDashboardScreenState();
}

class _ExplorerDashboardScreenState extends State<ExplorerDashboardScreen> {
  bool _loading = true;
  int _totalLogs = 0;
  int _districtsVisited = 0;
  double _totalKm = 0;
  int _trustScore = 0;
  List<FlSpot> _chartSpots = [];
  Map<String, int> _categoriesCount = {};
  List<Map<String, dynamic>> _earnedBadges = [];
  List<LocationPin> _undiscoveredPins = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is! Authenticated) return;
      final uid = authState.profile.uid;

      // 1. Fetch profile and trust score
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      _trustScore = userData['trustScore'] as int? ??
          userData['explorerScore'] as int? ??
          10;

      // 2. Fetch logs for stats
      final logsQuery = await FirebaseFirestore.instance
          .collection('trip_logs')
          .where('authorId', isEqualTo: uid)
          .get();

      _totalLogs = logsQuery.docs.length;
      final Set<String> districts = {};
      double kmCount = 0.0;
      final Map<String, int> categoryCounts = {};

      for (final doc in logsQuery.docs) {
        final data = doc.data();
        final district = data['district'] as String? ?? '';
        if (district.isNotEmpty) districts.add(district);

        final km = (data['totalKm'] as num? ?? 0.0).toDouble();
        kmCount += km;

        final category = data['category'] as String? ?? 'General';
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
      _districtsVisited = districts.length;
      _totalKm = kmCount;
      _categoriesCount = categoryCounts;

      // 3. Trust Score history
      final historyQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('trust_history')
          .orderBy('timestamp', descending: false)
          .get();

      if (historyQuery.docs.isNotEmpty) {
        int index = 0;
        _chartSpots = historyQuery.docs.map((doc) {
          final score = (doc.data()['score'] as num? ?? 0).toDouble();
          final spot = FlSpot(index.toDouble(), score);
          index++;
          return spot;
        }).toList();
      } else {
        // No history yet: show the real current score only — never a
        // fabricated trend.
        _chartSpots = [FlSpot(0, _trustScore.toDouble())];
      }

      // 4. Earned Badges
      final badgesQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('badges')
          .get();

      _earnedBadges = badgesQuery.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Achievement',
          'icon': data['icon'] ?? '🏆',
          'earnedAt': data['earnedAt'],
        };
      }).toList();

      // 5. Undiscovered Pins near user
      final pinsQuery = await FirebaseFirestore.instance
          .collection('location_pins')
          .limit(3)
          .get();

      _undiscoveredPins = pinsQuery.docs.map((doc) {
        final data = doc.data();
        data['pinId'] = doc.id;
        return LocationPin.fromJson(data);
      }).toList();

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14142B),
        elevation: 0,
        title: const Text(
          'Explorer Dashboard',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Stat Cards Grid
            GridView.count(
              // All four in one row on tablets, two by two on phones.
              crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildStatCard(
                    'Total Logs',
                    '$_totalLogs',
                    Icons.article_outlined,
                    [const Color(0xFF6366F1), const Color(0xFF4F46E5)]),
                _buildStatCard(
                    'Trust Score',
                    '$_trustScore',
                    Icons.verified_outlined,
                    [const Color(0xFF10B981), const Color(0xFF059669)]),
                _buildStatCard(
                    'Districts',
                    '$_districtsVisited',
                    Icons.map_outlined,
                    [const Color(0xFFF59E0B), const Color(0xFFD97706)]),
                _buildStatCard(
                    'Total Km',
                    '${_totalKm.toStringAsFixed(0)} km',
                    Icons.directions_run_outlined,
                    [const Color(0xFFEC4899), const Color(0xFFDB2777)]),
              ],
            ),
            const SizedBox(height: 24),

            // Line Chart Section
            const Text(
              'Trust Progression',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF14142B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    show: true,
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 30)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _chartSpots,
                      isCurved: true,
                      color: AppColors.mintGreen,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.mintGreen.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Category breakdown
            const Text(
              'Categories Visited',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            _categoriesCount.isEmpty
                ? const Text('No categories logged yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 12))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categoriesCount.entries.map((entry) {
                      return Chip(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        side: const BorderSide(color: Colors.white10),
                        label: Text(
                          '${entry.key} (${entry.value})',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 24),

            // Badges shelf
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Achievements & Badges',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                TextButton(
                  onPressed: () => context.push('/challenges'),
                  child: const Text('View All',
                      style:
                          TextStyle(color: AppColors.mintGreen, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _earnedBadges.isEmpty
                ? Container(
                    height: 70,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: const Text(
                      'No badges earned yet. Start exploring to unlock!',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  )
                : SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _earnedBadges.length,
                      itemBuilder: (context, index) {
                        final badge = _earnedBadges[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Text(badge['icon'] as String? ?? '🏆',
                                  style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 8),
                              Text(
                                badge['name'] as String? ?? 'Achievement',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
            const SizedBox(height: 24),

            // Explore more pins
            const Text(
              'Explore More Destinations',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            AdaptiveColumns(
              children: _undiscoveredPins.map((pin) {
                return Card(
                  color: Colors.white.withValues(alpha: 0.04),
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white10),
                  ),
                  child: ListTile(
                    title: Text(pin.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    subtitle: Text('${pin.category} • ${pin.district}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white54, size: 14),
                    onTap: () {
                      context.push('/map');
                    },
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, List<Color> gradientColors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              Icon(icon, color: Colors.white70, size: 18),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

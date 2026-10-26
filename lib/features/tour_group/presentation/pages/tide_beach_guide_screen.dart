import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/services/tide_schedule_engine.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/localization/app_localizations.dart';

class TideBeachGuideScreen extends StatefulWidget {
  final String tourId;

  const TideBeachGuideScreen({super.key, required this.tourId});

  @override
  State<TideBeachGuideScreen> createState() => _TideBeachGuideScreenState();
}

class _TideBeachGuideScreenState extends State<TideBeachGuideScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  bool _isBeachView = true;
  // Refreshes "now" each minute so the safety banner does not go stale.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _watchGroup();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (!mounted) return;
      setState(() {
        _tourGroup = g;
        _isBeachView = g?.tourType == TourType.beach ||
            (g?.destination.toLowerCase().contains('cox') ?? true) ||
            (g?.destination.toLowerCase().contains('kuakata') ?? false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final safety = TideScheduleEngine.evaluateCurrentSafety(now);
    final tides = TideScheduleEngine.getTidesForDate(now);
    final dest =
        _tourGroup?.destination ?? context.l10n.translate('tide_default_area');

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          _isBeachView
              ? context.l10n.translate('tide_title_beach')
              : context.l10n
                  .translate('tide_title_nature', args: {'dest': dest}),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(
                _isBeachView ? Icons.landscape_rounded : Icons.waves_rounded,
                color: AppColors.mintGreen),
            tooltip: _isBeachView
                ? context.l10n.translate('tide_view_hills')
                : context.l10n.translate('tide_view_beach'),
            onPressed: () {
              setState(() => _isBeachView = !_isBeachView);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mode Switcher Banner
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isBeachView = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isBeachView ? AppColors.mintGreen : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          context.l10n.translate('tide_tab_sea'),
                          style: TextStyle(
                            color: _isBeachView ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isBeachView = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            !_isBeachView ? Colors.tealAccent.shade700 : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          context.l10n.translate('tide_tab_hills'),
                          style: TextStyle(
                            color:
                                !_isBeachView ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isBeachView) ...[
            // ── Beach View ──
            _buildLiveSafetyBanner(safety),
            const SizedBox(height: 8),
            Text(
              context.l10n.translate('tide_schedule_disclaimer'),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
            const SizedBox(height: 20),

            Text(
              context.l10n.translate('tide_today_schedule'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),
            ...tides.map((t) => _buildTideCard(t, safety.currentWindow == t)),

            const SizedBox(height: 24),

            Text(
              context.l10n.translate('tide_beach_safety_title'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 12),
            _buildSafetyWarningCard(
              title: context.l10n.translate('tide_quicksand_title'),
              desc: context.l10n.translate('tide_quicksand_body'),
              icon: Icons.warning_amber_rounded,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: context.l10n.translate('tide_flag_title'),
              desc: context.l10n.translate('tide_flag_body'),
              icon: Icons.flag_rounded,
              color: AppColors.gold,
            ),
          ] else ...[
            // ── Mountain, Forest & Nature View ──
            _buildMountainSafetyBanner(dest),
            const SizedBox(height: 20),

            Text(
              context.l10n.translate('tide_sun_title'),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),
            _buildSunEventCard(
                context.l10n.translate('tide_dawn_time'),
                context.l10n.translate('tide_sunrise_clouds'),
                context.l10n.translate('tide_sunrise_tip'),
                Icons.wb_twilight_rounded,
                Colors.orangeAccent),
            const SizedBox(height: 8),
            _buildSunEventCard(
                context.l10n.translate('tide_evening_time'),
                context.l10n.translate('tide_golden_title'),
                context.l10n.translate('tide_golden_tip'),
                Icons.wb_sunny_rounded,
                Colors.amber),

            const SizedBox(height: 24),

            Text(
              context.l10n
                  .translate('tide_mountain_title', args: {'dest': dest}),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 12),
            _buildSafetyWarningCard(
              title: context.l10n.translate('tide_waterfall_title'),
              desc: context.l10n.translate('tide_waterfall_body'),
              icon: Icons.water_drop_rounded,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: context.l10n.translate('tide_flash_title'),
              desc: context.l10n.translate('tide_flash_body'),
              icon: Icons.thunderstorm_rounded,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: context.l10n.translate('tide_jeep_title'),
              desc: context.l10n.translate('tide_jeep_body'),
              icon: Icons.directions_bus_rounded,
              color: AppColors.gold,
            ),
          ],

          const SizedBox(height: 10),
          _buildSafetyWarningCard(
            title: context.l10n.translate('tide_contacts_title'),
            desc: context.l10n.translate('tide_contacts_body'),
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF38BDF8),
          ),
        ],
      ),
    );
  }

  Widget _buildSunEventCard(
      String time, String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Text(time,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMountainSafetyBanner(String dest) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.teal.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.tealAccent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration:
                const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
            child: const Icon(Icons.terrain_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n
                      .translate('tide_tracker_title', args: {'dest': dest}),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.translate('tide_weather_good'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSafetyBanner(
      ({
        SwimSafetyStatus status,
        String advisory,
        TideWindow? currentWindow,
        TideWindow? nextWindow
      }) safety) {
    Color bannerColor;
    IconData bannerIcon;

    switch (safety.status) {
      case SwimSafetyStatus.safe:
        bannerColor = AppColors.mintGreen;
        bannerIcon = Icons.check_circle_rounded;
        break;
      case SwimSafetyStatus.caution:
        bannerColor = AppColors.gold;
        bannerIcon = Icons.info_rounded;
        break;
      case SwimSafetyStatus.danger:
        bannerColor = Colors.redAccent;
        bannerIcon = Icons.dangerous_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: bannerColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bannerIcon, color: bannerColor, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      safety.status == SwimSafetyStatus.safe
                          ? context.l10n.translate('tide_safe_swim')
                          : (safety.status == SwimSafetyStatus.caution
                              ? context.l10n.translate('tide_caution')
                              : context.l10n.translate('tide_danger')),
                      style: TextStyle(
                          color: bannerColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  safety.advisory,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, height: 1.3),
                ),
                if (safety.currentWindow != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.translate('tide_current_state', args: {
                      'state': safety.currentWindow!.type == TideType.high
                          ? context.l10n.translate('tide_high_tide')
                          : context.l10n.translate('tide_low_tide')
                    }),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTideCard(TideWindow tide, bool isCurrent) {
    final isHigh = tide.type == TideType.high;
    final color = isHigh ? AppColors.mintGreen : const Color(0xFF38BDF8);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:
            isCurrent ? color.withValues(alpha: 0.12) : const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? color : Colors.white12,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHigh
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tide.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.l10n.translate('tide_running'),
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tide.formatTimeRange(),
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            isHigh
                ? context.l10n.translate('tide_swim_ok')
                : context.l10n.translate('tide_low_caution'),
            style: TextStyle(
              color: isHigh ? AppColors.mintGreen : Colors.orangeAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyWarningCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

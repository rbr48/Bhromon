import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/services/local_fare_guide.dart';

/// Opens the Bangladesh Local Transport Fare Guide & Calculator in an adaptive modal sheet.
Future<void> showLocalFareGuideSheet(
  BuildContext context, {
  int initialPassengers = 1,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LocalFareGuideSheet(initialPassengers: initialPassengers),
  );
}

/// Interactive sheet showing transit fare estimates and a calculator.
class LocalFareGuideSheet extends StatefulWidget {
  const LocalFareGuideSheet({
    super.key,
    this.initialPassengers = 1,
  });

  final int initialPassengers;

  @override
  State<LocalFareGuideSheet> createState() => _LocalFareGuideSheetState();
}

class _LocalFareGuideSheetState extends State<LocalFareGuideSheet> {
  static const _divisions = [
    ('All', 'সব অঞ্চল'),
    ('Chattogram', 'চট্টগ্রাম ও পাহাড়ি অঞ্চল'),
    ('Sylhet', 'সিলেট ও হাওড়'),
    ('Khulna', 'খুলনা ও সুন্দরবন'),
    ('Barishal', 'বরিশাল ও কুয়াকাটা'),
  ];

  final LocalFareGuide _guide = const LocalFareGuide();
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedDivision = 'All';
  String _searchQuery = '';
  late int _passengers;
  LocalTransitRoute? _selectedRoute;

  @override
  void initState() {
    super.initState();
    _passengers = widget.initialPassengers <= 0 ? 1 : widget.initialPassengers;
    _selectedRoute = LocalFareGuide.catalog.first;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  IconData _iconForVehicle(String vehicleType) {
    return switch (vehicleType) {
      'chander_gari' => Icons.airport_shuttle_rounded,
      'boat' => Icons.directions_boat_filled_rounded,
      'cng' => Icons.electric_rickshaw_rounded,
      'microbus' => Icons.directions_bus_rounded,
      'motorcycle' => Icons.two_wheeler_rounded,
      'ship' => Icons.sailing_rounded,
      'mahendra' => Icons.local_taxi_rounded,
      _ => Icons.directions_car_rounded,
    };
  }

  void _shareFare(FareCalculationResult calc) {
    final text = calc.formatSummary();
    SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: '${calc.route.destinationBn} লোকাল ভাড়া হিসাব',
      ),
    );
  }

  void _copyFare(FareCalculationResult calc) {
    Clipboard.setData(ClipboardData(text: calc.formatSummary()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ভাড়ার বিবরণ ক্লিপবোর্ডে কপি করা হয়েছে!'),
        backgroundColor: AppColors.darkGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = _guide.search(
      query: _searchQuery,
      division: _selectedDivision,
    );
    final selected =
        _selectedRoute ?? (routes.isNotEmpty ? routes.first : null);
    final calculation = selected != null
        ? _guide.calculate(route: selected, passengerCount: _passengers)
        : null;

    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 600;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          height: media.size.height * 0.88,
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(AppColors.forestCard),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border:
                isDesktop ? Border.all(color: context.forest.divider10) : null,
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _buildPassengerStepper(context),
                    const SizedBox(height: 12),
                    _buildSearchBar(context),
                    const SizedBox(height: 10),
                    _buildDivisionChips(context),
                    const SizedBox(height: 14),
                    if (calculation != null) ...[
                      _buildCalculationCard(context, calculation),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'জনপ্রিয় আঞ্চলিক রুট ও রেট তালিকা (${routes.length})',
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (routes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'কোনো রুট পাওয়া যায়নি',
                            style: TextStyle(color: context.forest.text54),
                          ),
                        ),
                      )
                    else
                      for (final route in routes)
                        _buildRouteItem(context, route,
                            isSelected: route.id == selected?.id),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.forest.divider10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calculate_outlined,
              color: AppColors.mintGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'লোকাল পরিবহন ভাড়া গাইড',
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'চাঁদের গাড়ি, ট্রলার, সিএনজি ও লোকাল ভাড়া যাচাই',
                  style: TextStyle(
                    color: context.forest.text54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: context.forest.text54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerStepper(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF1B3024)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.forest.divider10),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined,
              color: context.forest.accentText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ভ্রমণকারী যাত্রী সংখ্যা',
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'মাথাপিছু ও মোট খরচ হিসাব করতে ব্যবহার করুন',
                  style: TextStyle(color: context.forest.text54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.remove, size: 18),
            onPressed:
                _passengers > 1 ? () => setState(() => _passengers--) : null,
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$_passengers',
              style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => setState(() => _passengers++),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      onChanged: (val) => setState(() => _searchQuery = val),
      style: TextStyle(color: context.forest.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'স্থান, রুট বা বাহন খুঁজুন (সাজেক, হাওড়, জিপ...)',
        hintStyle: TextStyle(color: context.forest.text38, fontSize: 13),
        prefixIcon:
            Icon(Icons.search_rounded, color: context.forest.text54, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: context.forest.surfaceFor(AppColors.forestCard),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.forest.divider10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.forest.divider10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.mintGreen),
        ),
      ),
    );
  }

  Widget _buildDivisionChips(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _divisions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final (divKey, label) = _divisions[idx];
          final isSelected = _selectedDivision == divKey;
          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            selectedColor: AppColors.mintGreen,
            backgroundColor: context.forest.surfaceFor(const Color(0xFF1B3024)),
            labelStyle: TextStyle(
              color: isSelected ? AppColors.darkGreen : context.forest.text70,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(
              color:
                  isSelected ? AppColors.mintGreen : context.forest.divider10,
            ),
            onSelected: (_) {
              setState(() => _selectedDivision = divKey);
            },
          );
        },
      ),
    );
  }

  Widget _buildCalculationCard(
      BuildContext context, FareCalculationResult calc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF162B20)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForVehicle(calc.route.vehicleType),
                  color: context.forest.accentText, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${calc.route.destinationBn} — নির্বাচিত হিসাব',
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  calc.route.divisionBn,
                  style: TextStyle(
                    color: context.forest.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            calc.route.routeDescription,
            style: TextStyle(color: context.forest.text70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মোট আনুমানিক ভাড়া',
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '৳${calc.totalMinFare} – ৳${calc.totalMaxFare}',
                        style: TextStyle(
                          color: context.forest.readable(AppColors.gold),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${calc.vehiclesNeeded}টি ${calc.route.vehicleTitle}',
                        style: TextStyle(
                            color: context.forest.text70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: context.forest.divider10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মাথাপিছু খরচ (${calc.passengerCount} জন)',
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '৳${calc.perPersonMinFare} – ৳${calc.perPersonMaxFare}',
                        style: TextStyle(
                          color: context.forest.accentText,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        calc.route.fareTypeBn,
                        style: TextStyle(
                            color: context.forest.text70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 13, color: AppColors.mintGreen),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'উৎস: ${calc.route.source} (হালনাগাদ: ${calc.route.asOf})',
                  style: TextStyle(
                    color: context.forest.text54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          if (calc.route.tips.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final tip in calc.route.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(color: context.forest.accentText)),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(
                            color: context.forest.text70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyFare(calc),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('কপি করুন'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.forest.text,
                    side: BorderSide(color: context.forest.text24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _shareFare(calc),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('শেয়ার করুন'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteItem(
    BuildContext context,
    LocalTransitRoute route, {
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.mintGreen.withValues(alpha: 0.12)
            : context.forest.surfaceFor(const Color(0xFF1B3024)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.mintGreen : context.forest.divider10,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.mintGreen
                  : context.forest.surfaceFor(AppColors.forestCard),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconForVehicle(route.vehicleType),
              color:
                  isSelected ? AppColors.darkGreen : context.forest.accentText,
              size: 20,
            ),
          ),
          title: Text(
            route.routeDescription,
            style: TextStyle(
              color: context.forest.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${route.vehicleTitle} · ${route.fareTypeBn}',
                style: TextStyle(color: context.forest.text54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'উৎস: ${route.source} (${route.asOf})',
                style: TextStyle(
                  color: context.forest.text54.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '৳${route.minFare} – ৳${route.maxFare}',
                style: TextStyle(
                  color: context.forest.readable(AppColors.gold),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                'ধারণক্ষমতা: ${route.capacity} জন',
                style: TextStyle(color: context.forest.text54, fontSize: 11),
              ),
            ],
          ),
          onTap: () {
            setState(() => _selectedRoute = route);
          },
        ),
      ),
    );
  }
}

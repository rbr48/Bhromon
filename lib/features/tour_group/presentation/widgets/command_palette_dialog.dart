import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';

class CommandPaletteItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final String category;
  final Color? color;

  const CommandPaletteItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.category,
    this.color,
  });
}

class CommandPaletteDialog extends StatefulWidget {
  final String tourId;

  const CommandPaletteDialog({super.key, required this.tourId});

  static Future<void> show(BuildContext context, String tourId) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => CommandPaletteDialog(tourId: tourId),
    );
  }

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _selectedIndex = 0;

  List<CommandPaletteItem> _getItems(String tourId) {
    return [
      const CommandPaletteItem(
        title: 'ড্যাশবোর্ড (Dashboard)',
        subtitle: 'ট্যুর গ্রুপ হাব ও সারসংক্ষেপ',
        icon: Icons.dashboard_rounded,
        route: '/group-hub',
        category: 'নেভিগেশন',
        color: AppColors.mintGreen,
      ),
      CommandPaletteItem(
        title: 'ভ্রমণ সূচি (Itinerary & Route)',
        subtitle: 'দিনভিত্তিক প্ল্যান ও স্টপ বিবরণ',
        icon: Icons.calendar_month_rounded,
        route: '/group/$tourId/journey',
        category: 'নেভিগেশন',
        color: Colors.lightBlueAccent,
      ),
      CommandPaletteItem(
        title: 'ইন্সটাফিড (Moments & Reels)',
        subtitle: 'ট্যুর স্মৃতি, ছবি ও ভিডিও রিলস',
        icon: Icons.photo_library_rounded,
        route: '/group/$tourId/feed',
        category: 'নেভিগেশন',
        color: Colors.pinkAccent,
      ),
      CommandPaletteItem(
        title: 'ডিসকর্ড চ্যাট (Channels)',
        subtitle: 'গ্রুপ ভয়েস ও টেক্সট চ্যানেল',
        icon: Icons.forum_rounded,
        route: '/group/$tourId/channels',
        category: 'নেভিগেশন',
        color: Colors.indigoAccent,
      ),
      const CommandPaletteItem(
        title: 'গেমিং জোন (Family Game Zone)',
        subtitle: '২৯ কার্ড, দাবা, লুডো, তিন পাত্তি ও ক্যারাম',
        icon: Icons.sports_esports_rounded,
        route: '/game-zone',
        category: 'গেমস',
        color: Colors.purpleAccent,
      ),
      const CommandPaletteItem(
        title: 'সংবাদ হাব (Newspaper Hub)',
        subtitle: 'বিজ্ঞাপনমুক্ত লাইভ সংবাদপত্র ও খবর',
        icon: Icons.newspaper_rounded,
        route: '/newspaper-hub',
        category: 'সংবাদ ও তথ্য',
        color: Colors.lightBlueAccent,
      ),
      CommandPaletteItem(
        title: 'হিসাব ও স্প্লিট (Expense Ledger)',
        subtitle: 'ট্যুর ফান্ড, জমা, খরচ ও সেটেল-আপ',
        icon: Icons.account_balance_wallet_rounded,
        route: '/group/$tourId/ledger',
        category: 'নেভিগেশন',
        color: AppColors.mintGreen,
      ),
      CommandPaletteItem(
        title: 'সিট ও রুম প্ল্যান (Logistics)',
        subtitle: 'বাসের আসন ও হোটেল রুম বণ্টন',
        icon: Icons.airline_seat_recline_extra_rounded,
        route: '/group/$tourId/logistics',
        category: 'নেভিগেশন',
        color: Colors.orangeAccent,
      ),
      CommandPaletteItem(
        title: 'নোটিশ ও মিটিং (Notice Board)',
        subtitle: 'জরুরি ঘোষণা ও মিটিং শিডিউল',
        icon: Icons.campaign_rounded,
        route: '/group/$tourId/notices',
        category: 'নেভিগেশন',
        color: Colors.redAccent,
      ),
      CommandPaletteItem(
        title: 'চেকলিস্ট (Checklist)',
        subtitle: 'ব্যক্তিগত ও ফ্যামিলি প্যাকিং লিস্ট',
        icon: Icons.checklist_rounded,
        route: '/group/$tourId/checklist',
        category: 'নেভিগেশন',
        color: Colors.tealAccent,
      ),
      CommandPaletteItem(
        title: 'সুরক্ষা ও বিচ কম্পাস (Safety Hub)',
        subtitle: 'SOS সাইরেন ও জরুরি লাইভ জিপিএস অ্যালার্ট',
        icon: Icons.fmd_good_rounded,
        route: '/group/$tourId/safety',
        category: 'বিশেষ টুলস',
        color: Colors.redAccent,
      ),
      CommandPaletteItem(
        title: 'হাইওয়ে ট্র্যাকার (Highway Tracker)',
        subtitle: 'হাইওয়ে রুট, লাইভ চেকপয়েন্ট ও দূরত্ব',
        icon: Icons.alt_route_rounded,
        route: '/group/$tourId/journey',
        category: 'বিশেষ টুলস',
        color: Colors.amberAccent,
      ),
      CommandPaletteItem(
        title: 'সৈকত ও খাবার গাইড (Beach & Tide)',
        subtitle: 'জোয়ার-ভাটা সময়সূচি ও স্থানীয় খাবার তালিকা',
        icon: Icons.tsunami_rounded,
        route: '/group/$tourId/tide',
        category: 'বিশেষ টুলস',
        color: Colors.cyanAccent,
      ),
      CommandPaletteItem(
        title: 'ডিজিটাল স্ক্র্যাপবুক (Trip Scrapbook)',
        subtitle: 'ম্যাগাজিন ও সুন্দর স্মৃতির পিডিএফ রিক্যাপ',
        icon: Icons.menu_book_rounded,
        route: '/group/$tourId/scrapbook',
        category: 'বিশেষ টুলস',
        color: Colors.amberAccent,
      ),
      CommandPaletteItem(
        title: 'ফ্যামিলি কুইজ (Tour Quiz)',
        subtitle: '৮ রাউন্ড রোমাঞ্চকর ট্যুর কুইজ',
        icon: Icons.quiz_rounded,
        route: '/group/$tourId/quiz',
        category: 'বিশেষ টুলস',
        color: Colors.greenAccent,
      ),
    ];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _getItems(widget.tourId);
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allItems
        : allItems.where((item) {
            return item.title.toLowerCase().contains(query) ||
                item.subtitle.toLowerCase().contains(query) ||
                item.category.toLowerCase().contains(query);
          }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 540),
        child: Material(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Box
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF161616),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppColors.mintGreen, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText:
                              'কমান্ড খুঁজুন (যেমন: হিসাব, ইন্সটাফিড, সিট প্ল্যান...)',
                          hintStyle:
                              TextStyle(color: Colors.white38, fontSize: 13.5),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) {
                          setState(() {
                            _selectedIndex = 0;
                          });
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ESC',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Filtered list
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'কোনো কমান্ড খুঁজে পাওয়া যায়নি',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isSelected = index == _selectedIndex;
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              TourGroupRepository.lastActiveTourId =
                                  widget.tourId;
                              context.go(item.route);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.mintGreen
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(
                                        color: AppColors.mintGreen
                                            .withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (item.color ?? AppColors.mintGreen)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      item.icon,
                                      size: 18,
                                      color: item.color ?? AppColors.mintGreen,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        Text(
                                          item.subtitle,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Footer hints
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF161616),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.keyboard_return_rounded,
                        size: 14, color: Colors.white38),
                    SizedBox(width: 4),
                    Text('নির্বাচন করতে ক্লিক করুন',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                    Spacer(),
                    Text('ভ্রমণ অপারেটিং সিস্টেম • Bhromon OS',
                        style: TextStyle(
                            color: AppColors.mintGreen, fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

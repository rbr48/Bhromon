import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../data/active_group.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';

/// Reusable dialogs for joining and creating groups across desktop and mobile shells.
class TourGroupDialogs {
  TourGroupDialogs._();

  /// Prompts the user for an 8-character invite code and joins the group.
  static Future<void> showJoinDialog(
    BuildContext context, {
    TourGroupRepository? repository,
    void Function(TourGroup)? onJoined,
  }) async {
    final repo = repository ?? TourGroupRepository();
    final l10n = context.l10n;
    final codeCtrl = TextEditingController();
    bool isJoining = false;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                l10n.translate('hub_join_title'),
                style: TextStyle(
                    color: context.forest.text, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.translate('hub_join_hint'),
                    style:
                        TextStyle(color: context.forest.text70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      color: context.forest.accentText,
                      fontSize: 20,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: l10n.translate('hub_join_code_example'),
                      hintStyle: TextStyle(
                          color: context.forest.text54, letterSpacing: 2),
                      filled: true,
                      fillColor: context.forest.inset26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.mintGreen),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isJoining ? null : () => Navigator.pop(ctx),
                  child: Text(
                    l10n.translate('tour_cancel'),
                    style: TextStyle(color: context.forest.text54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.midGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isJoining
                      ? null
                      : () async {
                          final code = codeCtrl.text.trim();
                          if (code.isEmpty) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isJoining = true);
                          try {
                            final joinedGroup =
                                await repo.joinGroupWithCode(code);
                            await ActiveGroup.instance.select(joinedGroup.id);
                            if (ctx.mounted) navigator.pop();
                            if (onJoined != null) {
                              onJoined(joinedGroup);
                            } else if (context.mounted) {
                              context.go('/group/${joinedGroup.id}/channels');
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.translate('hub_joined',
                                      args: {'name': joinedGroup.name}),
                                ),
                                backgroundColor: AppColors.darkGreen,
                              ),
                            );
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() => isJoining = false);
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is FormatException
                                      ? e.message
                                      : e.toString(),
                                ),
                                backgroundColor: Colors.red[800],
                              ),
                            );
                          }
                        },
                  child: isJoining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          l10n.translate('hub_join'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
    codeCtrl.dispose();
  }

  /// Displays a modal dialog to quickly create a group of chosen kind.
  static Future<void> showCreateGroupChoiceDialog(
    BuildContext context, {
    TourGroupRepository? repository,
    void Function(TourGroup)? onCreated,
  }) async {
    final repo = repository ?? TourGroupRepository();
    final l10n = context.l10n;
    final isBn = l10n.locale.languageCode == 'bn';
    final screenHeight = MediaQuery.sizeOf(context).height;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: screenHeight * 0.82,
            ),
            child: Material(
              color: context.forest.card,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isBn ? 'নতুন গ্রুপ তৈরি করুন' : 'Create New Group',
                          style: TextStyle(
                            color: context.forest.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 16.5,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: context.forest.text54),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1, thickness: 1, color: context.forest.divider10),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GroupTypeOptionTile(
                            icon: '👨‍👩‍👧',
                            title: isBn
                                ? 'পরিবারের গ্রুপ তৈরি করুন'
                                : 'Create Family Circle',
                            subtitle: isBn
                                ? 'পরিবারের কেনাকাটা, ক্যালেন্ডার ও ফটো অ্যালবাম'
                                : 'Family tasks, dates & photo memories',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(
                                  context, repo, null, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '👥',
                            title: isBn
                                ? 'বন্ধু বা ফ্রেন্ডস সার্কেল তৈরি করুন'
                                : 'Create Friends Circle',
                            subtitle: isBn
                                ? 'বন্ধুদের আড্ডা, ট্যুর প্ল্যান ও ফটো শেয়ারিং'
                                : 'Friends hangout, plans & photo sharing',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.friendsPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '💼',
                            title: isBn
                                ? 'অফিস বা দলের গ্রুপ তৈরি করুন'
                                : 'Create Office or Team',
                            subtitle: isBn
                                ? 'অফিস নোটিশ বোর্ড, লাঞ্চ ও টিম আড্ডা'
                                : 'Official notices, lunch ledger & channels',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.officePreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🎓',
                            title: isBn
                                ? 'ক্যাম্পাস বা ব্যাচের গ্রুপ তৈরি করুন'
                                : 'Create Campus or Batch',
                            subtitle: isBn
                                ? 'ক্যাম্পাস নোটিশ, ব্যাচ ইভেন্টস ও ক্যান্টিন আড্ডা'
                                : 'Campus updates, batch events & tea chats',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.campusPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🍛',
                            title: isBn
                                ? 'মেস বা শেয়ার্ড বাসার গ্রুপ তৈরি করুন'
                                : 'Create Mess or Shared Flat',
                            subtitle: isBn
                                ? 'প্রতিদিনের মিল গণনা, বাজার খরচ ও মিল রেট'
                                : 'Daily meal tracking, grocery split & meal rates',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.messPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🏬',
                            title: isBn
                                ? 'হাউজিং সোসাইটি বা ভবনের গ্রুপ তৈরি করুন'
                                : 'Create Housing Society / Building',
                            subtitle: isBn
                                ? 'বিল্ডিং মেইনটেন্যান্স, সার্ভিস রিকোয়েস্ট ও নোটিশ'
                                : 'Building maintenance, service requests & notices',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.societyPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🪙',
                            title: isBn
                                ? 'ঘূর্ণায়মান সঞ্চয় গ্রুপ তৈরি করুন'
                                : 'Create Rotating Savings Group',
                            subtitle: isBn
                                ? 'মাসিক ঘূর্ণায়মান কিস্তি ও পে-আউট রোটেশন'
                                : 'Rotating monthly savings ledger & payouts',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.samityPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '📖',
                            title: isBn
                                ? 'স্কুল বা কোচিং ক্লাসের গ্রুপ তৈরি করুন'
                                : 'Create School or Coaching Class',
                            subtitle: isBn
                                ? 'ক্লাস রুটিন, অ্যাসাইনমেন্ট ও নোটিশ বোর্ড'
                                : 'Class schedule, assignments & notices',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.schoolPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '⚽',
                            title: isBn
                                ? 'খেলার দল বা জিমের গ্রুপ তৈরি করুন'
                                : 'Create Sports Team or Gym',
                            subtitle: isBn
                                ? 'ম্যাচ শিডিউল, প্লেয়ার লিস্ট ও টুর্নামেন্ট প্ল্যান'
                                : 'Match schedules, rosters & tournament plans',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.sportsPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '📚',
                            title: isBn
                                ? 'স্টাডি বা বুক ক্লাবের গ্রুপ তৈরি করুন'
                                : 'Create Study or Book Club',
                            subtitle: isBn
                                ? 'পড়ার তালিকা, গ্রুপ ডিসকাশন ও বুক রিভিউ'
                                : 'Reading lists, group discussions & reviews',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.studyPreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🗳️',
                            title: isBn
                                ? 'পাড়া-মহল্লা কমিটির গ্রুপ তৈরি করুন'
                                : 'Create Neighborhood Committee',
                            subtitle: isBn
                                ? 'মহল্লার উন্নয়ন, মিটিং ও সামাজিক উদ্যোগ'
                                : 'Community welfare, meetings & local initiatives',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateFamily(context, repo,
                                  TourGroup.committeePreset, onCreated);
                            },
                          ),
                          _GroupTypeOptionTile(
                            icon: '🌴',
                            title: isBn
                                ? 'নতুন ট্যুর গ্রুপ তৈরি করুন'
                                : 'Create New Tour Group',
                            subtitle: isBn
                                ? 'কক্সবাজার, সাজেক বা যেকোনো ভ্রমণের সূচি ও খরচ'
                                : 'Itinerary, tracking & expenses for any trip',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              _promptQuickCreateTour(context, repo, onCreated);
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(height: 1),
                          ),
                          _GroupTypeOptionTile(
                            icon: '🔑',
                            title: isBn
                                ? 'কোড দিয়ে যোগ দিন'
                                : 'Join with Invite Code',
                            subtitle: isBn
                                ? 'ইনভাইট কোড দিয়ে অন্য গ্রুপে যুক্ত হন'
                                : 'Enter an invite code to join an existing group',
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              showJoinDialog(context,
                                  repository: repo, onJoined: onCreated);
                            },
                          ),
                        ],
                      ),
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

  static Future<void> _promptQuickCreateTour(
    BuildContext context,
    TourGroupRepository repo,
    void Function(TourGroup)? onCreated,
  ) async {
    final nameCtrl = TextEditingController();
    final destCtrl = TextEditingController(text: "Cox's Bazar");
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          backgroundColor: context.forest.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            context.l10n.locale.languageCode == 'bn'
                ? 'নতুন ট্যুর গ্রুপ'
                : 'New Tour Group',
            style: TextStyle(
                color: context.forest.text, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                  labelText: context.l10n.locale.languageCode == 'bn'
                      ? 'গ্রুপের নাম'
                      : 'Group Name',
                  hintText: 'যেমন: কক্সবাজার ২০২৬',
                  hintStyle: TextStyle(color: context.forest.text38),
                  labelStyle: TextStyle(color: context.forest.text70),
                  filled: true,
                  fillColor: context.forest.inset26,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destCtrl,
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                  labelText: context.l10n.locale.languageCode == 'bn'
                      ? 'গন্তব্য'
                      : 'Destination',
                  hintText: "Cox's Bazar, Sajek, Sylhet...",
                  hintStyle: TextStyle(color: context.forest.text38),
                  labelStyle: TextStyle(color: context.forest.text70),
                  filled: true,
                  fillColor: context.forest.inset26,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(context.l10n.translate('tour_cancel'),
                  style: TextStyle(color: context.forest.text54)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      setDState(() => isSaving = true);
                      try {
                        final now = DateTime.now();
                        final newGroup = await repo.createGroup(
                          name: name,
                          description: 'Trip to ${destCtrl.text.trim()}',
                          destination: destCtrl.text.trim(),
                          startDate: now,
                          endDate: now.add(const Duration(days: 3)),
                          tourType: TourType.beach,
                          originCity: 'ঢাকা',
                        );
                        await ActiveGroup.instance.select(newGroup.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (onCreated != null) {
                          onCreated(newGroup);
                        } else if (context.mounted) {
                          context.go('/group/${newGroup.id}/channels');
                        }
                      } catch (e) {
                        if (ctx.mounted) setDState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red[800]),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      context.l10n.locale.languageCode == 'bn'
                          ? 'তৈরি করুন'
                          : 'Create',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    destCtrl.dispose();
  }

  static Future<void> _promptQuickCreateFamily(
    BuildContext context,
    TourGroupRepository repo,
    String? preset,
    void Function(TourGroup)? onCreated,
  ) async {
    final nameCtrl = TextEditingController();
    bool isSaving = false;
    final isBn = context.l10n.locale.languageCode == 'bn';

    String defaultTitle =
        isBn ? 'পরিবারের গ্রুপ তৈরি করুন' : 'Create Family Circle';
    String hint = isBn ? 'যেমন: রানা ফ্যামিলি...' : 'e.g., Rana Family...';
    if (preset == TourGroup.friendsPreset) {
      defaultTitle = isBn
          ? 'বন্ধু বা ফ্রেন্ডস সার্কেল তৈরি করুন'
          : 'Create Friends Circle';
      hint =
          isBn ? 'যেমন: নটরডেম ব্যাচ ফ্রেন্ডস...' : 'e.g., College Friends...';
    } else if (preset == TourGroup.officePreset) {
      defaultTitle =
          isBn ? 'অফিস বা দলের গ্রুপ তৈরি করুন' : 'Create Office or Team';
      hint = isBn
          ? 'যেমন: টেক টিম, মার্কেটিং ডিপার্টমেন্ট...'
          : 'e.g., Tech Team, Marketing...';
    } else if (preset == TourGroup.campusPreset) {
      defaultTitle = isBn
          ? 'ক্যাম্পাস বা ব্যাচের গ্রুপ তৈরি করুন'
          : 'Create Campus or Batch';
      hint = isBn ? 'যেমন: বুয়েট সিএসই ২১ ব্যাচ...' : 'e.g., CSE Batch 21...';
    } else if (preset == TourGroup.messPreset) {
      defaultTitle = isBn
          ? 'মেস বা শেয়ার্ড বাসার গ্রুপ তৈরি করুন'
          : 'Create Mess or Shared Flat';
      hint = isBn ? 'যেমন: বনশ্রী মেস...' : 'e.g., Green Valley Mess...';
    } else if (preset == TourGroup.societyPreset) {
      defaultTitle = isBn
          ? 'হাউজিং সোসাইটি বা ভবনের গ্রুপ তৈরি করুন'
          : 'Create Housing Society / Building';
      hint =
          isBn ? 'যেমন: রূপালী টাওয়ার সমিতি...' : 'e.g., Sunrise Apartments...';
    } else if (preset == TourGroup.samityPreset) {
      defaultTitle = isBn
          ? 'ঘূর্ণায়মান সঞ্চয় গ্রুপ তৈরি করুন'
          : 'Create Rotating Savings Group';
      hint = isBn
          ? 'যেমন: মাসিক সঞ্চয় সমিতি...'
          : 'e.g., Monthly Savings Circle...';
    } else if (preset == TourGroup.schoolPreset) {
      defaultTitle = isBn
          ? 'স্কুল বা কোচিং ক্লাসের গ্রুপ তৈরি করুন'
          : 'Create School or Coaching Class';
      hint =
          isBn ? 'যেমন: ম্যাথ কোচিং ব্যাচ ২০২৬...' : 'e.g., Math Batch 2026...';
    } else if (preset == TourGroup.sportsPreset) {
      defaultTitle = isBn
          ? 'খেলার দল বা জিমের গ্রুপ তৈরি করুন'
          : 'Create Sports Team or Gym';
      hint = isBn
          ? 'যেমন: সানরাইজ ফুটবল ক্লাব...'
          : 'e.g., Sunrise FC, Gym Squad...';
    } else if (preset == TourGroup.studyPreset) {
      defaultTitle = isBn
          ? 'স্টাডি বা বুক ক্লাবের গ্রুপ তৈরি করুন'
          : 'Create Study or Book Club';
      hint = isBn ? 'যেমন: সাহিত্য পাঠচক্র...' : 'e.g., Book Readers Club...';
    } else if (preset == TourGroup.committeePreset) {
      defaultTitle = isBn
          ? 'পাড়া-মহল্লা কমিটির গ্রুপ তৈরি করুন'
          : 'Create Neighborhood Committee';
      hint =
          isBn ? 'যেমন: শান্তিবাগ কল্যাণ সমিতি...' : 'e.g., Community Board...';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          backgroundColor: context.forest.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            defaultTitle,
            style: TextStyle(
                color: context.forest.text, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: nameCtrl,
            style: TextStyle(color: context.forest.text),
            decoration: InputDecoration(
              labelText: context.l10n.locale.languageCode == 'bn'
                  ? 'গ্রুপের নাম'
                  : 'Group Name',
              hintText: hint,
              hintStyle: TextStyle(color: context.forest.text38),
              labelStyle: TextStyle(color: context.forest.text70),
              filled: true,
              fillColor: context.forest.inset26,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(context.l10n.translate('tour_cancel'),
                  style: TextStyle(color: context.forest.text54)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      setDState(() => isSaving = true);
                      try {
                        final newGroup = await repo.createGroup(
                          name: name,
                          description: '',
                          destination: '',
                          startDate: DateTime.now(),
                          endDate: DateTime.now(),
                          tourType: TourType.nature,
                          kind: GroupKind.family,
                          preset: preset,
                        );
                        await ActiveGroup.instance.select(newGroup.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (onCreated != null) {
                          onCreated(newGroup);
                        } else if (context.mounted) {
                          context.go('/group/${newGroup.id}/channels');
                        }
                      } catch (e) {
                        if (ctx.mounted) setDState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red[800]),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      context.l10n.locale.languageCode == 'bn'
                          ? 'তৈরি করুন'
                          : 'Create',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }
}

class _GroupTypeOptionTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GroupTypeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(const Color(0xFF16251D)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.forest.divider10),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          TextStyle(color: context.forest.text54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.forest.text38),
            ],
          ),
        ),
      ),
    );
  }
}

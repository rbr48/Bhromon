import 'dart:async';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/family_date_models.dart';
import '../../domain/services/group_search_engine.dart';
import '../../domain/services/hub_modules.dart';
import '../../domain/services/tour_choice.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/tour_group_repository.dart';
import 'package:bhromon/core/config/feature_flags.dart';

import '../../data/active_group.dart';
import '../../data/tour_hub_preference.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/localization/locale_controller.dart';
import '../widgets/bhromon_bottom_nav.dart';
import '../widgets/groups/group_card.dart';
import '../widgets/groups/members_sheet.dart';
import '../widgets/groups/members_strip.dart';
import '../widgets/groups/next_step_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/groups/group_skeleton.dart';
import '../widgets/groups/member_avatar.dart';
import '../widgets/groups/sos_row.dart';
import '../widgets/tour_membership_guard.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_type.dart';
import '../widgets/group_photo_sheet.dart';
import '../widgets/hub/preset_home_card.dart';
import '../widgets/member_profile/tour_member_profile_modal.dart';
import '../widgets/google_play_action_button.dart';
import '../tour_pdf_export.dart';
import 'package:bhromon/features/official_feed/data/official_feed_repository.dart';
import 'package:bhromon/features/official_feed/presentation/official_feed_entry_card.dart';
import 'package:bhromon/features/official_feed/presentation/official_feed_prompt.dart';

class TourGroupHubScreen extends StatefulWidget {
  final TourGroupRepository? repository;

  /// The tour to open on, from the address (`?tourId=`). Null opens the tour
  /// the hub showed last, or the first tour.
  final String? initialTourId;

  /// Where the hub keeps its own pick. Tests pass a fake; the app leaves it null.
  final TourHubPreference? preference;

  /// Which layout to show. Null follows kGroupsV2; tests pass it to try both.
  final bool? groupsV2;

  const TourGroupHubScreen({
    super.key,
    this.repository,
    this.initialTourId,
    this.preference,
    this.groupsV2,
  });

  @override
  State<TourGroupHubScreen> createState() => _TourGroupHubScreenState();
}

class _TourGroupHubScreenState extends State<TourGroupHubScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();

  /// Whether to show the groups list and group page (kGroupsV2 unless a test sets it).
  bool get _useGroupsV2 => widget.groupsV2 ?? kGroupsV2;

  /// The group the hub is on. Tests pass their own preference, and get their own instance.
  late final ActiveGroup _active = widget.preference == null
      ? ActiveGroup.instance
      : ActiveGroup(preference: widget.preference);
  // The tour picked, created or joined during this visit. It is kept even
  // before the membership list includes it.
  TourGroup? _selectedGroup;
  // The tour the hub showed last time, read once when the hub opens.
  String? _rememberedTourId;

  /// The currently expanded group id on the groups list. Empty string means explicitly collapsed.
  String? _expandedGroupId;
  late Stream<List<TourGroup>> _groupsStream;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _groupsStream = _repository.watchMyGroups();
    _rememberedTourId = _active.current;
    final routeTourId = widget.initialTourId;
    if (routeTourId != null && routeTourId.isNotEmpty) {
      unawaited(_active.select(routeTourId));
      _expandedGroupId = routeTourId;
    } else {
      _expandedGroupId = null;
    }
    // Asks once, on mobile, whether to follow the official feed. A test that passes its own
    // repository never sees the question.
    if (!kIsWeb && widget.repository == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askAboutOfficialFeed());
      });
    }
  }

  /// Asks once whether to follow the official feed. The answer is kept on this device.
  Future<void> _askAboutOfficialFeed() {
    return showOfficialFeedPromptIfNeeded(
      context,
      onFollowChanged: OfficialFeedRepository().setFollowing,
    );
  }

  Stream<List<TourMember>> _membersOf(String tourId) =>
      _repository.watchMembers(tourId);

  /// Starts the groups list again after an error. The old listeners close, and the list
  /// is read from a new upstream. Called from the retry button, never from build.
  void _retryGroups() {
    setState(() {
      _groupsStream = _repository.restartMyGroups();
    });
  }

  bool _viewerIsOwner(TourGroup group, List<TourMember> members) =>
      group.ownerEmail == _repository.currentEmail ||
      members.any((m) =>
          m.email == _repository.currentEmail && m.role == TourRole.owner);

  bool _viewerIsAdmin(List<TourMember> members) => members
      .any((m) => m.email == _repository.currentEmail && m.role.isAdminOrOwner);

  /// Makes [group] the tour the hub shows, and remembers it for next time.
  /// Shares the group's invite code through the phone's share sheet.
  Future<void> _shareInvite(TourGroup group) async {
    final text = context.l10n.translate('hub_invite_share_text', args: {
      'name': group.name,
      'code': group.inviteCode,
    });
    if (group.ownerEmail == _repository.currentEmail &&
        group.inviteCode.isNotEmpty) {
      unawaited(_repository.syncInviteMetadata(group));
    }
    await SharePlus.instance
        .share(ShareParams(text: text, subject: group.name));
  }

  void _selectTour(TourGroup group) {
    unawaited(_active.select(group.id));
    setState(() => _selectedGroup = group);
  }

  /// Lists the family circles and the trips the person belongs to, in two sections.
  void _showCircleSwitcher(
    BuildContext context,
    List<TourGroup> allGroups,
    TourGroup current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.card,
      isScrollControlled: true,
      builder: (sheetContext) {
        String switcherQuery = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final l10n = context.l10n;
            final filtered = GroupSearchEngine.filter(
              groups: allGroups,
              rawQuery: switcherQuery,
            );
            final families = [
              for (final g in filtered)
                if (g.isHousehold) g
            ];
            final circles = [
              for (final g in filtered)
                if (g.isFamily && !g.isHousehold) g
            ];
            final trips = [
              for (final g in filtered)
                if (!g.isFamily) g
            ];

            Widget header(String text) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(text,
                      style: TextStyle(
                          color: context.forest.text54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                );
            Widget tile(TourGroup g) {
              final selected = g.id == current.id;
              return ListTile(
                leading: GroupAvatar(
                    typeIcon: groupTypeIcon(g), photoUrl: g.photoUrl, size: 40),
                title: Text(g.name,
                    style: TextStyle(
                        color: selected
                            ? context.forest.accentText
                            : context.forest.text,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(
                  l10n.translate(groupTypeKey(g)),
                  style: TextStyle(
                    color: context.forest.text54,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _selectTour(g);
                },
              );
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.75,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (allGroups.length > 3)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.forest.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.forest.divider10),
                          ),
                          child: TextField(
                            style: TextStyle(
                              color: context.forest.text,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  l10n.translate('hub_search_groups_hint'),
                              hintStyle: TextStyle(
                                color: context.forest.text54,
                                fontSize: 12,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: switcherQuery.isNotEmpty
                                    ? AppColors.midGreen
                                    : context.forest.text54,
                                size: 18,
                              ),
                              suffixIcon: switcherQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: context.forest.text54,
                                        size: 16,
                                      ),
                                      onPressed: () {
                                        setSheetState(() => switcherQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (val) {
                              setSheetState(() => switcherQuery = val);
                            },
                          ),
                        ),
                      ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 32, horizontal: 16),
                        child: Center(
                          child: Text(
                            l10n.translate(
                              'hub_no_groups_found_query',
                              args: {'query': switcherQuery.trim()},
                            ),
                            style: TextStyle(
                              color: context.forest.text54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      if (families.isNotEmpty) ...[
                        header(l10n.translate('hub_section_family')),
                        for (final g in families) tile(g),
                      ],
                      if (circles.isNotEmpty) ...[
                        header(l10n.translate('hub_section_groups')),
                        for (final g in circles) tile(g),
                      ],
                      if (trips.isNotEmpty) ...[
                        header(l10n.translate('hub_section_trips')),
                        for (final g in trips) tile(g),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : AppColors.midGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _startDirectChat(TourMember member) {
    final me = _repository.currentEmail;
    final myUid =
        _repository.currentUid.isNotEmpty ? _repository.currentUid : me;
    final remoteId = (member.uid != null && member.uid!.isNotEmpty)
        ? member.uid!
        : member.email;
    if (remoteId.isEmpty) return;

    final uids = [myUid, remoteId]..sort();
    final chatId = uids.join('_');
    context.push(
      '/chat/$chatId',
      extra: {
        'otherUid': remoteId,
        'sharedTourId': member.tourId,
        'otherEmail': member.email,
      },
    );
  }

  void _startDirectCall(TourMember member, {required bool isVideo}) {
    final l10n = context.l10n;
    final me = _repository.currentEmail;
    final myUid =
        _repository.currentUid.isNotEmpty ? _repository.currentUid : me;
    final remoteId = (member.uid != null && member.uid!.isNotEmpty)
        ? member.uid!
        : member.email;
    if (remoteId.isEmpty) {
      _snack(l10n.translate('chan_call_offline'), error: true);
      return;
    }
    final myName = _repository.currentDisplayName;
    final myAvatar = _repository.currentPhotoUrl;
    final callId = const Uuid().v4();
    context.push(
      '/call/$callId',
      extra: {
        'localUid': myUid,
        'remoteUid': remoteId,
        'remoteEmail': member.email,
        'sharedTourId': member.tourId,
        'remoteUserName': member.displayName.isNotEmpty
            ? member.displayName
            : member.email.split('@').first,
        'remoteAvatarUrl': member.photoUrl,
        'isCaller': true,
        'isVideoCall': isVideo,
        'localUserName': myName,
        'localAvatarUrl': myAvatar,
      },
    );
  }

  Widget _buildMemberQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.forest.readable(color), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: context.forest.readable(color),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: context.forest.accentText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n
                    .translate('hub_invite_code_copied', args: {'code': code}),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: context.forest.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyInviteLink(TourGroup group) {
    final encodedName = Uri.encodeComponent(group.name);
    final link =
        'https://app.bhromon.fun/#/join/${group.inviteCode}?name=$encodedName';
    Clipboard.setData(ClipboardData(text: link));
    if (group.ownerEmail == _repository.currentEmail &&
        group.inviteCode.isNotEmpty) {
      unawaited(_repository.syncInviteMetadata(group));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.link_rounded,
                color: context.forest.accentText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.translate('hub_invite_link_copied'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: context.forest.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddMemberDialog(BuildContext context, String tourId) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var isAdding = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.forest.dialog,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person_add_alt_1,
                  color: context.forest.accentText, size: 22),
              const SizedBox(width: 8),
              Text(
                context.l10n.translate('hub_add_member_title'),
                style: TextStyle(color: context.forest.text, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.translate('hub_add_member_help'),
                  style: TextStyle(
                      color: context.forest.text70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: context.forest.text),
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('hub_member_email_label'),
                    hintText: 'example@gmail.com',
                    labelStyle: TextStyle(color: context.forest.text70),
                    hintStyle: TextStyle(color: context.forest.text38),
                    prefixIcon: Icon(Icons.email_outlined,
                        color: context.forest.accentText),
                    filled: true,
                    fillColor: context.forest.inset26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.forest.text24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.mintGreen),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: context.forest.text),
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('hub_member_name_label'),
                    labelStyle: TextStyle(color: context.forest.text70),
                    prefixIcon: Icon(Icons.badge_outlined,
                        color: context.forest.text60),
                    filled: true,
                    fillColor: context.forest.inset26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.forest.text24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.mintGreen),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isAdding ? null : () => Navigator.pop(ctx),
              child: Text(context.l10n.translate('tour_cancel'),
                  style: TextStyle(color: context.forest.text70)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              onPressed: isAdding
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim().toLowerCase();
                      final l10n = context.l10n;
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(context.l10n
                                  .translate('hub_enter_valid_email'))),
                        );
                        return;
                      }
                      setDialogState(() => isAdding = true);
                      try {
                        await _repository.addMemberByEmail(
                          tourId: tourId,
                          email: email,
                          displayName: nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : null,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack(l10n.translate('hub_member_added',
                            args: {'email': email}));
                      } catch (e) {
                        setDialogState(() => isAdding = false);
                        _snack(
                            l10n.translate('hub_member_add_failed',
                                args: {'error': e}),
                            error: true);
                      }
                    },
              child: isAdding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.darkGreen),
                      ),
                    )
                  : Text(
                      context.l10n.translate('hub_add'),
                      style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _reportFailure(Object e) {
    _snack(
        e is FormatException || e is TourAccessException
            ? e.toString()
            : context.l10n.translate('hub_action_failed'),
        error: true);
  }

  Widget _moduleSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label,
          style: TextStyle(color: context.forest.text, fontSize: 13)),
      value: value,
      activeThumbColor: AppColors.mintGreen,
      onChanged: onChanged,
    );
  }

  Future<int?> _pickFamilyCount(BuildContext context, int current) {
    int value = current;
    return showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          backgroundColor: context.forest.card,
          title: Text(context.l10n.translate('hub_family_count_label'),
              style: TextStyle(color: context.forest.text)),
          content: DropdownButtonFormField<int>(
            initialValue: value,
            dropdownColor: context.forest.dialog,
            decoration: InputDecoration(
                labelText: context.l10n.translate('hub_family_count_hint')),
            items: [
              for (var n = 1; n <= 20; n++)
                DropdownMenuItem(
                    value: n,
                    child: Text(context.l10n
                        .translate('hub_people_count', args: {'count': n}))),
            ],
            onChanged: (v) {
              if (v != null) setDialogState(() => value = v);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(context.l10n.translate('tour_cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(c, value),
                child: Text(context.l10n.translate('tour_save'))),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: context.forest.card,
        title: Text(title, style: TextStyle(color: context.forest.text)),
        content: Text(body, style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(context.l10n.translate('hub_no'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(context.l10n.translate('hub_yes'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _onGroupMenu(
      BuildContext context, TourGroup group, String action) async {
    final l10n = context.l10n;
    switch (action) {
      case 'copy_link':
        _copyInviteLink(group);
      case 'copy_code':
        _copyInviteCode(group.inviteCode);
      case 'export_pdf':
        // The whole tour holds every member's photos, so its owner or an admin exports it.
        final role = await _repository.myRole(group.id);
        if (role == null || !role.isAdminOrOwner) {
          _snack(l10n.translate('pdf_export_admin_only'), error: true);
          return;
        }
        if (!context.mounted) return;
        await exportTourPdf(context, group: group, repository: _repository);
      case 'photo':
        await showGroupPhotoSheet(context,
            group: group, repository: _repository);
      case 'add_member':
        _showAddMemberDialog(context, group.id);
      case 'edit_name':
        final role = await _repository.myRole(group.id);
        if (role == null || !role.isAdminOrOwner) {
          _snack(l10n.translate('members_admin_only'), error: true);
          return;
        }
        if (!context.mounted) return;
        if (group.isFamily) {
          _showRenameGroupDialog(context, group);
        } else {
          _showEditGroupDialog(context, group);
        }
      case 'moments':
        final role = await _repository.myRole(group.id);
        if (role == null || !role.isAdminOrOwner) {
          _snack(l10n.translate('moments_admins_only'), error: true);
          return;
        }
        final turningOff = group.momentsEnabled;
        if (turningOff) {
          final ok = await _confirm(l10n.translate('hub_moments_off_title'),
              l10n.translate('hub_moments_off_body'));
          if (!ok) return;
        }
        try {
          await _repository.setMomentsEnabled(group.id, !turningOff);
          _snack(l10n.translate(
              turningOff ? 'moments_turned_off' : 'moments_turned_on'));
        } catch (e) {
          _reportFailure(e);
        }
      case 'code':
        final ok = await _confirm(l10n.translate('hub_rotate_code_title'),
            l10n.translate('hub_rotate_code_body'));
        if (!ok) return;
        try {
          final code =
              await _repository.rotateInviteCode(group.id, group.inviteCode);
          _snack(l10n.translate('hub_new_code', args: {'code': code}));
        } catch (e) {
          _reportFailure(e);
        }
      case 'leave':
        final nav = Navigator.of(context);
        final ok = await _confirm(
            l10n.translate(group.isFriends
                ? 'hub_leave_friends_title'
                : group.isOffice
                    ? 'hub_leave_office_title'
                    : group.isCampus
                        ? 'hub_leave_campus_title'
                        : group.isMess
                            ? 'hub_leave_mess_title'
                            : group.isSociety
                                ? 'hub_leave_society_title'
                                : group.isSamity
                                    ? 'hub_leave_samity_title'
                                    : group.isSchool
                                        ? 'hub_leave_school_title'
                                        : group.isSports
                                            ? 'hub_leave_sports_title'
                                            : group.isStudy
                                                ? 'hub_leave_study_title'
                                                : group.isCommittee
                                                    ? 'hub_leave_committee_title'
                                                    : group.isFamily
                                                        ? 'hub_leave_family_title'
                                                        : 'hub_leave_title'),
            l10n.translate('hub_leave_body', args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.leaveTour(group.id);
          unawaited(_active.clearIf(group.id));
          if (mounted) {
            setState(() {
              _selectedGroup = null;
            });
            if (nav.canPop()) {
              nav.pop();
            }
          }
        } catch (e) {
          _reportFailure(e);
        }
      case 'delete':
        final nav = Navigator.of(context);
        final ok = await _confirm(
            l10n.translate(group.isFriends
                ? 'hub_delete_friends_title'
                : group.isOffice
                    ? 'hub_delete_office_title'
                    : group.isCampus
                        ? 'hub_delete_campus_title'
                        : group.isMess
                            ? 'hub_delete_mess_title'
                            : group.isSociety
                                ? 'hub_delete_society_title'
                                : group.isSamity
                                    ? 'hub_delete_samity_title'
                                    : group.isSchool
                                        ? 'hub_delete_school_title'
                                        : group.isSports
                                            ? 'hub_delete_sports_title'
                                            : group.isStudy
                                                ? 'hub_delete_study_title'
                                                : group.isCommittee
                                                    ? 'hub_delete_committee_title'
                                                    : group.isFamily
                                                        ? 'hub_delete_family_title'
                                                        : 'hub_delete_title'),
            l10n.translate(
                group.isFriends
                    ? 'hub_delete_friends_body'
                    : group.isOffice
                        ? 'hub_delete_office_body'
                        : group.isCampus
                            ? 'hub_delete_campus_body'
                            : group.isMess
                                ? 'hub_delete_mess_body'
                                : group.isSociety
                                    ? 'hub_delete_society_body'
                                    : group.isSamity
                                        ? 'hub_delete_samity_body'
                                        : group.isSchool
                                            ? 'hub_delete_school_body'
                                            : group.isSports
                                                ? 'hub_delete_sports_body'
                                                : group.isStudy
                                                    ? 'hub_delete_study_body'
                                                    : group.isCommittee
                                                        ? 'hub_delete_committee_body'
                                                        : group.isFamily
                                                            ? 'hub_delete_family_body'
                                                            : 'hub_delete_body',
                args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.deleteTour(group.id, inviteCode: group.inviteCode);
          unawaited(_active.clearIf(group.id));
          if (mounted) {
            setState(() {
              _selectedGroup = null;
            });
            if (nav.canPop()) {
              nav.pop();
            }
          }
        } catch (e) {
          _reportFailure(e);
        }
    }
  }

  /// The group menu: copy the code, export, Moments, add a member, renew the code, and
  /// delete or leave. Shown in the banner and on the group page.
  Widget _groupMenuButton(BuildContext context, TourGroup group) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: context.forest.text70, size: 20),
      color: context.forest.dialog,
      onSelected: (v) => _onGroupMenu(context, group, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'copy_link',
          child: _menuRow(context, Icons.link_rounded,
              context.l10n.translate('hub_copy_invite_link')),
        ),
        PopupMenuItem(
          value: 'copy_code',
          child: _menuRow(context, Icons.copy_rounded,
              context.l10n.translate('hub_copy_invite_code')),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: _menuRow(context, Icons.picture_as_pdf_rounded,
              context.l10n.translate('pdf_export_menu')),
        ),
        PopupMenuItem(
          value: 'photo',
          child: _menuRow(context, Icons.photo_camera_rounded,
              context.l10n.translate('group_photo_title')),
        ),
        PopupMenuItem(
          value: 'edit_name',
          child: _menuRow(context, Icons.edit_rounded,
              context.l10n.translate('hub_edit_group_name')),
        ),
        if (group.isManaged)
          PopupMenuItem(
            value: 'moments',
            child: _menuRow(
                context,
                group.momentsEnabled
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                context.l10n.translate(group.momentsEnabled
                    ? 'hub_moments_turn_off'
                    : 'hub_moments_turn_on')),
          ),
        if (group.ownerEmail == _repository.currentEmail) ...[
          PopupMenuItem(
            value: 'add_member',
            child: _menuRow(context, Icons.person_add_alt_1,
                context.l10n.translate('hub_add_member_by_email')),
          ),
          PopupMenuItem(
            value: 'code',
            child: _menuRow(context, Icons.key_rounded,
                context.l10n.translate('hub_renew_code'),
                iconColor: context.forest.text70),
          ),
          PopupMenuItem(
            value: 'delete',
            child: _menuRow(
                context,
                Icons.delete_outline_rounded,
                context.l10n.translate(group.isHousehold
                    ? 'hub_delete_family'
                    : 'hub_delete_tour'),
                color: Colors.redAccent,
                iconColor: Colors.redAccent),
          ),
        ] else
          PopupMenuItem(
            value: 'leave',
            child: _menuRow(
                context,
                Icons.logout_rounded,
                context.l10n.translate(
                    group.isHousehold ? 'hub_leave_family' : 'hub_leave_tour'),
                iconColor: context.forest.text70),
          ),
      ],
    );
  }

  /// Opens [group] on the group page and makes it the active group.
  /// How soon a second tap on the same tool tile is ignored, so a double tap opens one
  /// route, not two (plan section 9.3).
  static const Duration _toolTapGap = Duration(milliseconds: 600);
  final Map<String, DateTime> _lastToolTap = {};

  /// The groups whose page shows every tool, not only the first ones.
  final Set<String> _toolsOpen = {};

  /// The tap for the tool tile [tile]. A tap that comes within [_toolTapGap] of the last
  /// tap on that tile is ignored.
  VoidCallback _toolTap(String tile, VoidCallback onTap) {
    return () {
      final now = DateTime.now();
      final last = _lastToolTap[tile];
      if (last != null && now.difference(last) < _toolTapGap) return;
      _lastToolTap[tile] = now;
      HapticFeedback.selectionClick();
      onTap();
    };
  }

  void _openGroup(TourGroup group) {
    unawaited(_active.select(group.id));
    setState(() {
      if (_expandedGroupId == group.id) {
        // Tapping currently expanded group toggles collapse
        _expandedGroupId = null;
      } else {
        // Tapping collapsed group expands it inline
        _expandedGroupId = group.id;
        _selectedGroup = group;
      }
    });
  }

  /// Behind kGroupsV2: the groups list with inline expandable group details.
  Widget _buildGroupsV2(
    BuildContext context,
    AsyncSnapshot<List<TourGroup>> snapshot,
    List<TourGroup> groups,
  ) {
    final routeId = widget.initialTourId;
    if (routeId == null || routeId.isEmpty) {
      return _buildGroupsList(context, snapshot, groups);
    }
    TourGroup? group;
    for (final candidate in groups) {
      if (candidate.id == routeId) group = candidate;
    }
    if (group != null) {
      _expandedGroupId ??= routeId;
      return _buildGroupsList(context, snapshot, groups);
    }
    final loading = snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData;
    return _buildGroupShell(
      context,
      loading
          ? const GroupSkeleton(cards: 2)
          : _buildGroupNotAvailable(context),
    );
  }

  /// The groups list when the groups cannot load: what happened, and a retry (section 5.2).
  /// It never reads as "no groups", which would be wrong while the groups are unknown.
  Widget _buildGroupsError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: context.forest.text54),
          const SizedBox(height: 12),
          Text(
            context.l10n.translate('hub_groups_load_failed'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
            onPressed: _retryGroups,
            child: Text(context.l10n.translate('hub_try_again')),
          ),
        ],
      ),
    );
  }

  /// The clean groups list: expandable group cards showing members and tools inline,
  /// with real-time bilingual group search filtering.
  Widget _buildGroupsList(
    BuildContext context,
    AsyncSnapshot<List<TourGroup>> snapshot,
    List<TourGroup> groups,
  ) {
    final l10n = context.l10n;
    final loading = snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData;
    final selectedId = _active.current;
    final effectiveExpandedId = _expandedGroupId;
    final filteredGroups = GroupSearchEngine.filter(
      groups: groups,
      rawQuery: _searchQuery,
    );
    final hasSearchQuery = _searchQuery.trim().isNotEmpty;
    final canCloseExpandedGroup = effectiveExpandedId != null;

    final scaffold = Scaffold(
      backgroundColor: context.forest.background,
      appBar: _hubAppBar(context),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            // Keeps the scroll position across toggling group cards.
            key: const PageStorageKey<String>('groups-list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                l10n.translate('hub_nav_tours'),
                style: TextStyle(
                  color: context.forest.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.translate('group_open_hint'),
                  style: TextStyle(color: context.forest.text70, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              if (groups.isNotEmpty || hasSearchQuery) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: context.forest.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.forest.divider10),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 14,
                    ),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.translate('hub_search_groups_hint'),
                      hintStyle: TextStyle(
                        color: context.forest.text54,
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: hasSearchQuery
                            ? AppColors.midGreen
                            : context.forest.text54,
                        size: 20,
                      ),
                      suffixIcon: hasSearchQuery
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: context.forest.text54,
                                size: 18,
                              ),
                              tooltip: l10n.translate('hub_clear_search'),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                ),
              ],
              if (loading)
                const GroupSkeleton()
              else if (snapshot.hasError && groups.isEmpty)
                _buildGroupsError(context)
              else if (groups.isEmpty)
                _buildEmptyState(context)
              else if (filteredGroups.isEmpty)
                _buildNoSearchResults(context)
              else ...[
                for (final group in filteredGroups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GroupCard(
                      group: group,
                      selected: group.id == selectedId,
                      isExpanded: group.id == effectiveExpandedId,
                      onTap: () => _openGroup(group),
                      expandedContent: group.id == effectiveExpandedId
                          ? _buildExpandedGroupDetail(context, group)
                          : null,
                    ),
                  ),
                // After the groups, show official feed when not actively searching non-official
                if (!hasSearchQuery ||
                    'official feed অফিসিয়াল ফিড bhromon ভ্রমণ'
                        .contains(_searchQuery.trim().toLowerCase()))
                  const OfficialFeedEntryCard(),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BhromonBottomNav(selectedIndex: 0),
    );

    return PopScope(
      canPop: !canCloseExpandedGroup,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (canCloseExpandedGroup) {
          setState(() {
            _expandedGroupId = null;
          });
          if (widget.initialTourId != null &&
              widget.initialTourId!.isNotEmpty) {
            context.go('/group-hub');
          }
        }
      },
      child: scaffold,
    );
  }

  /// Empty state rendered when a search query matches none of the user's groups.
  Widget _buildNoSearchResults(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.forest.card,
                shape: BoxShape.circle,
                border: Border.all(color: context.forest.divider10),
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 28,
                color: context.forest.text54,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.translate(
                'hub_no_groups_found_query',
                args: {'query': _searchQuery.trim()},
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.forest.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.translate('hub_no_groups_found_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.forest.text54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.midGreen,
              ),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: Text(l10n.translate('hub_clear_search')),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The inline expanded details for [group]: quick action bar, members strip, next step,
  /// SOS siren row, and the modules grid without Game zone and News.
  Widget _buildExpandedGroupDetail(BuildContext context, TourGroup group) {
    final l10n = context.l10n;
    return TourMembershipGuard(
      tourId: group.id,
      repository: _repository,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Group info & actions bar: Invite Code + Share + Group Menu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: context.forest.inset26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                // Invite code pill
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _copyInviteCode(group.inviteCode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.midGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded,
                              size: 13, color: AppColors.mintGreen),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              l10n.translate('hub_invite_line',
                                  args: {'code': group.inviteCode}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.share_rounded,
                      size: 20, color: context.forest.text70),
                  tooltip: l10n.translate('hub_share_invite'),
                  onPressed: () => _shareInvite(group),
                  visualDensity: VisualDensity.compact,
                ),
                _groupMenuButton(context, group),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Members strip
          _memberStripFor(context, group),
          const SizedBox(height: 14),

          // 3. Next step (for trips)
          NextStepCard(group: group, now: DateTime.now()),

          // 4. Safety SOS row (if not managed)
          if (!group.isManaged) ...[
            SosRow(
              title: l10n.translate('hub_module_safety'),
              subtitle: l10n.translate('group_sos_sub'),
              onTap: () => context.push('/group/${group.id}/safety'),
            ),
            const SizedBox(height: 14),
          ],

          // 5. Tools heading
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              l10n.translate('hub_modules_heading'),
              style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ),

          // 6. Tools grid
          _buildModulesGrid(context, group,
              excludeGamesAndNews: true, isGroupPage: true),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// The members strip for [group], from the one shared members stream of that group.
  Widget _memberStripFor(BuildContext context, TourGroup group) {
    return StreamBuilder<List<TourMember>>(
      stream: _membersOf(group.id),
      builder: (context, snapshot) {
        final members = snapshot.data;
        // Never "0 members" while the members load (section 5.2).
        if (members == null) return const GroupSkeleton(cards: 1);
        final isAdmin = _viewerIsAdmin(members);
        final isOwner = _viewerIsOwner(group, members);
        return MembersStrip(
          members: members,
          onSeeAll: () => _openMembers(context, group, members),
          onMemberTap: (member) => _showManageMemberSheet(
            context,
            group.id,
            member,
            viewerIsOwner: isOwner,
            viewerIsAdmin: isAdmin,
          ),
        );
      },
    );
  }

  /// Opens the members sheet. Admins may open a member's manage sheet and add members.
  void _openMembers(
      BuildContext context, TourGroup group, List<TourMember> current) {
    final isAdmin = _viewerIsAdmin(current);
    final isOwner = _viewerIsOwner(group, current);
    unawaited(showMembersSheet(
      context,
      members: _membersOf(group.id),
      viewerIsAdmin: isAdmin,
      onMemberTap: (member) => _showManageMemberSheet(
        context,
        group.id,
        member,
        viewerIsOwner: isOwner,
        viewerIsAdmin: isAdmin,
      ),
      onAddMember:
          isAdmin ? () => _showAddMemberDialog(context, group.id) : null,
    ));
  }

  /// A page shell for a group that is loading or not available.
  Widget _buildGroupShell(BuildContext context, Widget body) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        backgroundColor: context.forest.background,
        appBar: AppBar(
          backgroundColor: context.forest.background,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.translate('group_back_to_list'),
            icon: Icon(Icons.arrow_back_rounded, color: context.forest.text),
            onPressed: () => context.go('/group-hub'),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: body,
            ),
          ),
        ),
        bottomNavigationBar: const BhromonBottomNav(selectedIndex: 0),
      ),
    );
  }

  Widget _buildGroupNotAvailable(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.translate('group_not_available'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text70),
          ),
          TextButton(
            onPressed: () => context.go('/group-hub'),
            child: Text(l10n.translate('group_back_to_list')),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant TourGroupHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new group in the route (a card, a chip or a link) becomes the active group.
    final routeId = widget.initialTourId;
    if (routeId != null &&
        routeId.isNotEmpty &&
        routeId != oldWidget.initialTourId) {
      unawaited(_active.select(routeId));
      setState(() {
        _expandedGroupId = routeId;
      });
    }
  }

  /// The hub's app bar: the logo and title, and the menu to add or join a group.
  PreferredSizeWidget _hubAppBar(BuildContext context) {
    final effectiveExpandedId = _expandedGroupId;
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 930),
          child: AppBar(
            backgroundColor: context.forest.background,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: effectiveExpandedId != null
                ? IconButton(
                    tooltip: context.l10n.translate('group_back_to_list'),
                    icon: Icon(Icons.arrow_back_rounded,
                        color: context.forest.text),
                    onPressed: () {
                      setState(() {
                        _expandedGroupId = null;
                      });
                      if (widget.initialTourId != null &&
                          widget.initialTourId!.isNotEmpty) {
                        context.go('/group-hub');
                      }
                    },
                  )
                : null,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Image.asset(
                    'assets/bhromon_emblem.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.explore,
                      color: context.forest.accentText,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bhromon',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.forest.accentText,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        context.l10n.translate('login_tagline'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.forest.text54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (kIsWeb) const GooglePlayActionButton(),
              ListenableBuilder(
                listenable: LocaleController.instance,
                builder: (context, _) {
                  final isBn =
                      LocaleController.instance.locale.languageCode == 'bn';
                  return IconButton(
                    tooltip: isBn ? 'Switch to English' : 'বাংলায় দেখুন',
                    icon: const Icon(Icons.language_rounded,
                        color: AppColors.midGreen),
                    onPressed: () {
                      final next = isBn ? 'en' : 'bn';
                      LocaleController.instance.setLanguage(next);
                    },
                  );
                },
              ),
              PopupMenuButton<String>(
                tooltip: context.l10n.translate('hub_add_menu'),
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.midGreen),
                color: context.forest.dialog,
                onSelected: (choice) {
                  switch (choice) {
                    case 'family':
                      _showCreateFamilyDialog(context);
                    case 'friends':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.friendsPreset);
                    case 'office':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.officePreset);
                    case 'campus':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.campusPreset);
                    case 'mess':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.messPreset);
                    case 'society':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.societyPreset);
                    case 'samity':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.samityPreset);
                    case 'school':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.schoolPreset);
                    case 'sports':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.sportsPreset);
                    case 'study':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.studyPreset);
                    case 'committee':
                      _showCreateFamilyDialog(context,
                          preset: TourGroup.committeePreset);
                    case 'trip':
                      _showCreateGroupDialog(context);
                    case 'join':
                      _showJoinGroupDialog(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'family',
                    child: _menuRow(context, Icons.family_restroom_rounded,
                        context.l10n.translate('hub_create_family')),
                  ),
                  PopupMenuItem(
                    value: 'friends',
                    child: _menuRow(context, Icons.people_alt_rounded,
                        context.l10n.translate('hub_create_friends')),
                  ),
                  PopupMenuItem(
                    value: 'office',
                    child: _menuRow(context, Icons.work_rounded,
                        context.l10n.translate('hub_create_office')),
                  ),
                  PopupMenuItem(
                    value: 'campus',
                    child: _menuRow(context, Icons.school_rounded,
                        context.l10n.translate('hub_create_campus')),
                  ),
                  PopupMenuItem(
                    value: 'mess',
                    child: _menuRow(context, Icons.kitchen_rounded,
                        context.l10n.translate('hub_create_mess')),
                  ),
                  PopupMenuItem(
                    value: 'society',
                    child: _menuRow(context, Icons.apartment_rounded,
                        context.l10n.translate('hub_create_society')),
                  ),
                  PopupMenuItem(
                    value: 'samity',
                    child: _menuRow(
                        context,
                        Icons.account_balance_wallet_rounded,
                        context.l10n.translate('hub_create_samity')),
                  ),
                  PopupMenuItem(
                    value: 'school',
                    child: _menuRow(context, Icons.menu_book_rounded,
                        context.l10n.translate('hub_create_school')),
                  ),
                  PopupMenuItem(
                    value: 'sports',
                    child: _menuRow(context, Icons.sports_soccer_rounded,
                        context.l10n.translate('hub_create_sports')),
                  ),
                  PopupMenuItem(
                    value: 'study',
                    child: _menuRow(context, Icons.local_library_rounded,
                        context.l10n.translate('hub_create_study')),
                  ),
                  PopupMenuItem(
                    value: 'committee',
                    child: _menuRow(context, Icons.how_to_vote_rounded,
                        context.l10n.translate('hub_create_committee')),
                  ),
                  PopupMenuItem(
                    value: 'trip',
                    child: _menuRow(context, Icons.card_travel_rounded,
                        context.l10n.translate('hub_create_new_tour')),
                  ),
                  PopupMenuItem(
                    value: 'join',
                    child: _menuRow(context, Icons.group_add_outlined,
                        context.l10n.translate('hub_join_with_code')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TourGroup>>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        // Only tours the membership list still names are shown, so a tour the
        // user left or was removed from drops out at once.
        final groups = snapshot.data ?? [];
        if (_useGroupsV2) return _buildGroupsV2(context, snapshot, groups);
        final current = pickTour(groups, [
          _selectedGroup?.id,
          widget.initialTourId,
          _rememberedTourId,
        ]);

        final scaffold = Scaffold(
          backgroundColor: context.forest.background,
          appBar: _hubAppBar(context),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Builder(
                builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.midGreen),
                    );
                  }

                  if (snapshot.hasError &&
                      (snapshot.data == null || snapshot.data!.isEmpty)) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off_rounded,
                                color: Colors.redAccent, size: 54),
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.translate('hub_groups_load_failed'),
                              style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: context.forest.text70, fontSize: 13),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.midGreen),
                              onPressed: _retryGroups,
                              child:
                                  Text(context.l10n.translate('hub_try_again')),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (current == null) {
                    return _buildEmptyState(context);
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // 1. Active Tour Card
                      _buildActiveTourBanner(context, current, groups),
                      const SizedBox(height: 18),
                      if (current.isFamily) ...[
                        PresetHomeCard(group: current, repository: _repository),
                        const SizedBox(height: 18),
                      ],

                      // 2. Feature Launchpad Grid
                      Text(
                        context.l10n.translate('hub_modules_heading'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildModulesGrid(context, current),

                      const SizedBox(height: 20),

                      // 3. Tour Members List
                      _buildMembersSection(current),
                    ],
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar: BhromonBottomNav(
            selectedIndex: 0,
            tourId: current?.id,
          ),
        );

        final canCloseExpanded = _expandedGroupId != null;
        return PopScope(
          canPop: !canCloseExpanded,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (canCloseExpanded) {
              setState(() => _expandedGroupId = null);
              if (widget.initialTourId != null &&
                  widget.initialTourId!.isNotEmpty) {
                context.go('/group-hub');
              }
            }
          },
          child: scaffold,
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    // The empty state lists every way to start a circle, so it scrolls on a short
    // screen or with long labels instead of overflowing.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.midGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.travel_explore_rounded,
                  size: 72, color: context.forest.accentText),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.translate('hub_empty_title'),
              style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.translate('hub_empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            const OfficialFeedEntryCard(),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateGroupDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.translate('hub_create_tour')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.midGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _showJoinGroupDialog(context),
                  icon: const Icon(Icons.key),
                  label: Text(context.l10n.translate('hub_enter_code')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mintGreen,
                    side: const BorderSide(color: AppColors.mintGreen),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context),
              icon: Icon(Icons.family_restroom_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_family'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.friendsPreset),
              icon: Icon(Icons.people_alt_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_friends'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.officePreset),
              icon: Icon(Icons.work_rounded, color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_office'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.campusPreset),
              icon:
                  Icon(Icons.school_rounded, color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_campus'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.messPreset),
              icon:
                  Icon(Icons.kitchen_rounded, color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_mess'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.societyPreset),
              icon: Icon(Icons.apartment_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_society'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.samityPreset),
              icon: Icon(Icons.account_balance_wallet_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_samity'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.schoolPreset),
              icon: Icon(Icons.menu_book_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_school'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.sportsPreset),
              icon: Icon(Icons.sports_soccer_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_sports'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.studyPreset),
              icon: Icon(Icons.local_library_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_study'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            TextButton.icon(
              onPressed: () => _showCreateFamilyDialog(context,
                  preset: TourGroup.committeePreset),
              icon: Icon(Icons.how_to_vote_rounded,
                  color: context.forest.accentText),
              label: Text(context.l10n.translate('hub_create_committee'),
                  style: TextStyle(color: context.forest.accentText)),
            ),
            const SizedBox(height: 12),
            if (!_repository.isSignedIn)
              TextButton.icon(
                onPressed: () => context.push('/login'),
                icon: Icon(Icons.login,
                    color: context.forest.accentText, size: 18),
                label: Text(
                  context.l10n.translate('hub_login_or_signup'),
                  style: TextStyle(
                    color: context.forest.accentText,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            else
              Text(
                context.l10n.translate('hub_current_account',
                    args: {'email': _repository.currentEmail}),
                style: TextStyle(color: context.forest.text38, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTourBanner(
      BuildContext context, TourGroup group, List<TourGroup> allGroups) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.forest.bannerStart,
            context.forest.bannerEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        group.isFriends
                            ? context.l10n.translate('hub_friends_badge')
                            : group.isOffice
                                ? context.l10n.translate('hub_office_badge')
                                : group.isCampus
                                    ? context.l10n.translate('hub_campus_badge')
                                    : group.isMess
                                        ? context.l10n
                                            .translate('hub_mess_badge')
                                        : group.isSociety
                                            ? context.l10n
                                                .translate('hub_society_badge')
                                            : group.isSamity
                                                ? context.l10n.translate(
                                                    'hub_samity_badge')
                                                : group.isSchool
                                                    ? context.l10n.translate(
                                                        'hub_school_badge')
                                                    : group.isSports
                                                        ? context.l10n.translate(
                                                            'hub_sports_badge')
                                                        : group.isStudy
                                                            ? context.l10n
                                                                .translate(
                                                                    'hub_study_badge')
                                                            : group.isCommittee
                                                                ? context.l10n
                                                                    .translate(
                                                                        'hub_committee_badge')
                                                                : group.isFamily
                                                                    ? context
                                                                        .l10n
                                                                        .translate(
                                                                            'hub_family_badge')
                                                                    : '${group.tourType.labelBn.split(' ').first} ${group.destination}',
                        style: TextStyle(
                          color: context.forest.accentText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!group.isFamily)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.forest.text.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⏱️ ${group.durationText}',
                          style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _groupMenuButton(context, group),
                  if (!group.isFamily)
                    IconButton(
                      icon: Icon(Icons.edit_calendar_rounded,
                          size: 20, color: context.forest.accentText),
                      tooltip: context.l10n.translate('hub_settings_dates'),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showEditGroupDialog(context, group),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.edit_rounded,
                          size: 20, color: context.forest.accentText),
                      tooltip: context.l10n.translate('hub_edit_group_name'),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showRenameGroupDialog(context, group),
                    ),
                  if (allGroups.length > 1) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: context.l10n.translate('hub_switch_circle'),
                      icon: Icon(Icons.swap_horiz_rounded,
                          color: context.forest.accentText),
                      onPressed: () =>
                          _showCircleSwitcher(context, allGroups, group),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Tooltip(
                message: context.l10n.translate('group_photo_title'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => showGroupPhotoSheet(context,
                      group: group, repository: _repository),
                  child: GroupAvatar(
                      typeIcon: groupTypeIcon(group),
                      photoUrl: group.photoUrl,
                      size: 52),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.name,
                  style: TextStyle(
                    color: context.forest.text,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!group.isFamily)
            Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 12, color: context.forest.text60),
                const SizedBox(width: 5),
                Text(
                  '${localizedDateFormat('d MMM yyyy').format(group.startDate)} – ${localizedDateFormat('d MMM yyyy').format(group.endDate)}',
                  style: TextStyle(color: context.forest.text70, fontSize: 12),
                ),
                const SizedBox(width: 12),
                Icon(Icons.near_me_rounded,
                    size: 12, color: context.forest.text60),
                const SizedBox(width: 4),
                Text(
                  context.l10n.translate('hub_origin_line',
                      args: {'origin': group.originCity}),
                  style: TextStyle(color: context.forest.text70, fontSize: 12),
                ),
              ],
            ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              group.description,
              style: TextStyle(color: context.forest.text70, fontSize: 13),
            ),
          ],
          () {
            if (group.isFamily) return const SizedBox.shrink();
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final startDay = DateTime(group.startDate.year,
                group.startDate.month, group.startDate.day);
            final endDay = DateTime(
                group.endDate.year, group.endDate.month, group.endDate.day);
            final isOngoing =
                !today.isBefore(startDay) && !today.isAfter(endDay);
            final isUpcoming = today.isBefore(startDay);
            final isPast = today.isAfter(endDay);

            if (isOngoing) {
              final currentDay = today.difference(startDay).inDays + 1;
              final totalDays = endDay.difference(startDay).inDays + 1;
              final currentStop = group.stopOn(today);
              final currentStopName = currentStop?.name ?? group.destination;
              final progress = (currentDay / (totalDays > 0 ? totalDays : 1))
                  .clamp(0.05, 1.0);

              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.forest.inset26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n
                                .translate('hub_live_tour_ongoing', args: {
                              'day': context.l10n.number(currentDay),
                              'total': context.l10n.number(totalDays),
                            }),
                            style: TextStyle(
                              color: context.forest.accentText,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          context.l10n.translate('hub_live_current_stop',
                              args: {'stop': currentStopName}),
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: context.forest.divider12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.mintGreen),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.forest.text,
                              side: BorderSide(color: context.forest.text24),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                context.push('/group/${group.id}/journey'),
                            icon: Icon(Icons.alt_route_rounded,
                                size: 14, color: context.forest.accentText),
                            label: Text(
                              context.l10n.translate('hub_live_route_btn'),
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.forest.text,
                              side: BorderSide(color: context.forest.text24),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                context.push('/group/${group.id}/notices'),
                            icon: const Icon(
                                Icons.notifications_active_outlined,
                                size: 14,
                                color: AppColors.gold),
                            label: Text(
                              context.l10n.translate('hub_live_notices_btn'),
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.forest.text,
                              side: BorderSide(color: context.forest.text24),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                context.push('/group/${group.id}/ledger'),
                            icon: Icon(Icons.account_balance_wallet_outlined,
                                size: 14,
                                color: context.forest
                                    .readable(AppColors.freshGreen)),
                            label: Text(
                              context.l10n.translate('hub_live_ledger_btn'),
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            } else if (isUpcoming) {
              final daysLeft = startDay.difference(today).inDays;
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.forest.text.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.forest.divider10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        size: 14, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        daysLeft == 0
                            ? context.l10n.translate('hub_upcoming_today')
                            : context.l10n.translate('hub_upcoming_badge',
                                args: {'days': context.l10n.number(daysLeft)}),
                        style: TextStyle(
                          color: context.forest.text70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          context.push('/group/${group.id}/checklist'),
                      icon: Icon(Icons.checklist_rounded,
                          size: 14, color: context.forest.accentText),
                      label: Text(
                        context.l10n.translate('hub_upcoming_checklist'),
                        style: TextStyle(
                            color: context.forest.accentText, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            } else if (isPast) {
              final totalDays = endDay.difference(startDay).inDays + 1;
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.forest.text.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.forest.divider10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 14, color: context.forest.accentText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.translate('hub_completed_badge',
                            args: {'days': context.l10n.number(totalDays)}),
                        style: TextStyle(
                          color: context.forest.text70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          context.push('/group/${group.id}/scrapbook'),
                      icon: Icon(Icons.auto_stories_rounded,
                          size: 14, color: context.forest.accentText),
                      label: Text(
                        context.l10n.translate('hub_completed_scrapbook'),
                        style: TextStyle(
                            color: context.forest.accentText, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: context.l10n.translate('hub_tap_to_copy_code'),
                  child: InkWell(
                    onTap: () => _copyInviteCode(group.inviteCode),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.forest.divider12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.vpn_key_rounded,
                              size: 14, color: AppColors.gold),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              context.l10n.translate('hub_invite_line',
                                  args: {'code': group.inviteCode}),
                              style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded,
                              size: 14, color: context.forest.accentText),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => context.push('/group/${group.id}/feed'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: Text(
                  context.l10n.translate('hub_open_tour'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.translate('hub_share_invite'),
                icon:
                    Icon(Icons.share_rounded, color: context.forest.accentText),
                onPressed: () => _shareInvite(group),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context, TourGroup group,
      {bool excludeGamesAndNews = false, bool isGroupPage = false}) {
    final l10n = context.l10n;
    // Which tools apply, and in what order, comes from hubModulesFor. This only builds
    // the tile for each id.
    final ids = [
      for (final id in hubModulesFor(group))
        if (!(excludeGamesAndNews && (id == 'games' || id == 'news')))
          if (!(isGroupPage && id == 'safety')) id,
    ];
    final builders = <String, _ModuleItem Function()>{
      'feed': () => _ModuleItem(
            title: l10n.translate('hub_module_feed'),
            subtitle: l10n.translate('hub_module_feed_sub'),
            icon: Icons.camera_alt_rounded,
            color: const Color(0xFFF43F5E),
            onTap: () => context.push('/group/${group.id}/feed'),
          ),
      'ledger': () => _ModuleItem(
            title: l10n.translate('hub_module_ledger'),
            subtitle: l10n.translate('hub_module_ledger_sub'),
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.freshGreen,
            onTap: () => context.push('/group/${group.id}/ledger'),
          ),
      'seats': () => _ModuleItem(
            title: l10n.translate('hub_module_seats'),
            subtitle: l10n.translate('hub_module_seats_sub'),
            icon: Icons.airline_seat_recline_extra_rounded,
            color: const Color(0xFF6366F1),
            onTap: () => context.push('/group/${group.id}/logistics'),
          ),
      'calendar': () {
        final title = groupDateScreenTitle(group, l10n);
        final subtitle = groupDateScreenSubtitle(group, l10n);
        return _ModuleItem(
          title: title,
          subtitle: subtitle,
          icon: group.isHousehold
              ? Icons.event_repeat_rounded
              : Icons.event_available_rounded,
          color: const Color(0xFF84CC16),
          onTap: () => context.push(
            '/group/${group.id}/family-dates',
            extra: group,
          ),
        );
      },
      'study_subjects': () => _ModuleItem(
            title: l10n.translate('hub_module_study_subjects'),
            subtitle: l10n.translate('hub_module_study_subjects_sub'),
            icon: Icons.school_rounded,
            color: const Color(0xFF14B8A6),
            onTap: () => context.push('/group/${group.id}/study-subjects'),
          ),
      'study_reading': () => _ModuleItem(
            title: l10n.translate('hub_module_study_reading'),
            subtitle: l10n.translate('hub_module_study_reading_sub'),
            icon: Icons.event_note_rounded,
            color: const Color(0xFF0EA5E9),
            onTap: () => context.push('/group/${group.id}/study-reading'),
          ),
      'study_books': () => _ModuleItem(
            title: l10n.translate('hub_module_study_books'),
            subtitle: l10n.translate('hub_module_study_books_sub'),
            icon: Icons.menu_book_rounded,
            color: const Color(0xFFA855F7),
            onTap: () => context.push('/group/${group.id}/study-books'),
          ),
      'family_tasks': () => _ModuleItem(
            title: l10n.translate('hub_module_family_tasks'),
            subtitle: l10n.translate('hub_module_family_tasks_sub'),
            icon: Icons.checklist_rounded,
            color: const Color(0xFF22D3EE),
            onTap: () => context.push('/group/${group.id}/family-tasks'),
          ),
      'meals': () => _ModuleItem(
            title: l10n.translate('mess_module_meals'),
            subtitle: l10n.translate('mess_module_meals_sub'),
            icon: Icons.restaurant_rounded,
            color: const Color(0xFFF59E0B),
            onTap: () => context.push('/group/${group.id}/meals'),
          ),
      'requests': () => _ModuleItem(
            title: l10n.translate('society_module_requests'),
            subtitle: l10n.translate('society_module_requests_sub'),
            icon: Icons.build_circle_rounded,
            color: const Color(0xFFEA580C),
            onTap: () => context.push('/group/${group.id}/requests'),
          ),
      'samity': () => _ModuleItem(
            title: l10n.translate('samity_module_samity'),
            subtitle: l10n.translate('samity_module_samity_sub'),
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF65A30D),
            onTap: () => context.push('/group/${group.id}/samity'),
          ),
      'dependents': () => _ModuleItem(
            title: l10n.translate('hub_module_dependents'),
            subtitle: l10n.translate('hub_module_dependents_sub'),
            icon: Icons.family_restroom_rounded,
            color: const Color(0xFFF472B6),
            onTap: () => context.push('/group/${group.id}/dependents'),
          ),
      'album': () => _ModuleItem(
            title: l10n.translate('hub_module_album'),
            subtitle: l10n.translate('hub_module_album_sub'),
            icon: Icons.photo_album_rounded,
            color: const Color(0xFFFBBF24),
            onTap: () => context.push('/group/${group.id}/album'),
          ),
      'tide': () => _ModuleItem(
            title: group.tourType == TourType.beach
                ? l10n.translate('hub_module_tide')
                : l10n.translate('hub_module_weather'),
            subtitle: group.tourType == TourType.beach
                ? l10n.translate('hub_module_tide_sub')
                : l10n.translate('hub_module_weather_sub'),
            icon: group.tourType == TourType.beach
                ? Icons.waves_rounded
                : Icons.wb_sunny_rounded,
            color: const Color(0xFF38BDF8),
            onTap: () => context.push('/group/${group.id}/tide'),
          ),
      'notices': () => _ModuleItem(
            title: l10n.translate('hub_module_notices'),
            subtitle: l10n.translate('hub_module_notices_sub'),
            icon: Icons.campaign_rounded,
            color: const Color(0xFFEAB308),
            onTap: () => context.push('/group/${group.id}/notices'),
          ),
      'journey': () => _ModuleItem(
            title: l10n.translate('hub_module_journey'),
            subtitle: l10n.translate('hub_journey_sub', args: {
              'origin': group.originCity,
              'destination': group.destination,
            }),
            icon: Icons.alt_route_rounded,
            color: const Color(0xFF10B981),
            onTap: () => context.push('/group/${group.id}/journey'),
          ),
      'safety': () => _ModuleItem(
            title: l10n.translate('hub_module_safety'),
            subtitle: l10n.translate('hub_module_safety_sub'),
            icon: Icons.shield_rounded,
            color: const Color(0xFFEF4444),
            onTap: () => context.push('/group/${group.id}/safety'),
          ),
      'games': () => _ModuleItem(
            title: l10n.translate('hub_module_games'),
            subtitle: l10n.translate('hub_module_games_sub'),
            icon: Icons.sports_esports_rounded,
            color: const Color(0xFFF59E0B),
            onTap: () => context.push('/game-zone?tourId='),
          ),
      'quiz': () => _ModuleItem(
            title: l10n.translate('hub_module_quiz'),
            subtitle: l10n.translate('hub_quiz_sub',
                args: {'destination': group.destination}),
            icon: Icons.quiz_rounded,
            color: const Color(0xFF8B5CF6),
            onTap: () => context.push('/group/${group.id}/quiz'),
          ),
      'scrapbook': () => _ModuleItem(
            title: l10n.translate('hub_module_scrapbook'),
            subtitle: l10n.translate('hub_module_scrapbook_sub'),
            icon: Icons.auto_stories_rounded,
            color: const Color(0xFFD97706),
            onTap: () => context.push('/group/${group.id}/scrapbook'),
          ),
      'checklist': () => _ModuleItem(
            title: l10n.translate('hub_module_checklist'),
            subtitle: l10n.translate('hub_module_checklist_sub'),
            icon: Icons.checklist_rtl_rounded,
            color: const Color(0xFF14B8A6),
            onTap: () => context.push('/group/${group.id}/checklist'),
          ),
      'channels': () => _ModuleItem(
            title: l10n.translate('hub_module_channels'),
            subtitle: l10n.translate('hub_module_channels_sub'),
            icon: Icons.forum_rounded,
            color: const Color(0xFFEC4899),
            onTap: () => context.push('/group/${group.id}/channels'),
          ),
      'news': () => _ModuleItem(
            title: l10n.translate('hub_module_news'),
            subtitle: l10n.translate('hub_module_news_sub'),
            icon: Icons.article_rounded,
            color: const Color(0xFF0EA5E9),
            onTap: () => context.push('/newspaper-hub?tourId='),
          ),
    };
    // The group page shows the first tools and keeps the rest behind "More tools".
    final fold = isGroupPage
        ? foldHubModules(ids)
        : (shown: ids, more: const <String>[]);
    final toolsOpen = _toolsOpen.contains(group.id);
    final modules = [
      for (final id in fold.shown) builders[id]!(),
      if (toolsOpen)
        for (final id in fold.more) builders[id]!(),
    ];

    // Each tile is a fixed width and a height set by its aspect ratio. At a larger text
    // scale the tile grows with its text, so the ratio shrinks by the same factor.
    final tileTextScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount;
        final double childAspectRatio;
        if (constraints.maxWidth >= 760) {
          crossAxisCount = 4;
          childAspectRatio = 2.15;
        } else if (constraints.maxWidth >= 500) {
          crossAxisCount = 3;
          childAspectRatio = 2.1;
        } else {
          crossAxisCount = 2;
          childAspectRatio = 2.0;
        }

        final grid = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio / tileTextScale,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final m = modules[index];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toolTap(m.title, m.onTap),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.forest.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: m.color.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: m.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(m.icon,
                            color: context.forest.readable(m.color), size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.forest.text54,
                                fontSize: 11,
                              ),
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
        if (fold.more.isEmpty) return grid;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            grid,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (!_toolsOpen.remove(group.id)) {
                      _toolsOpen.add(group.id);
                    }
                  });
                },
                icon: Icon(
                  toolsOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                ),
                label: Text(
                  toolsOpen
                      ? l10n.translate('hub_tools_less')
                      : l10n.translate('hub_tools_more', args: {
                          'count': l10n.number(fold.more.length),
                        }),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: context.forest.accentText,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMembersSection(TourGroup group) {
    final tourId = group.id;
    return StreamBuilder<List<TourMember>>(
      stream: _membersOf(tourId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final canAddMember = _viewerIsAdmin(members);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.translate('hub_members_heading'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (canAddMember)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(Icons.person_add_alt_1,
                        size: 16, color: context.forest.accentText),
                    label: Text(
                      context.l10n.translate('hub_add_member_title'),
                      style: TextStyle(
                        color: context.forest.accentText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _showAddMemberDialog(context, tourId),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (members.isEmpty)
              snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(color: AppColors.midGreen)
                  : Text(context.l10n.translate('hub_no_members'),
                      style: TextStyle(color: context.forest.text54))
            else
              Material(
                color: context.forest.card,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.forest.divider10),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: context.forest.divider10, height: 1),
                    itemBuilder: (context, i) {
                      final m = members[i];
                      return ListTile(
                        onTap: () => _showManageMemberSheet(
                          context,
                          tourId,
                          m,
                          viewerIsOwner: _viewerIsOwner(group, members),
                          viewerIsAdmin: _viewerIsAdmin(members),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.midGreen,
                          backgroundImage: m.photoUrl != null
                              ? NetworkImage(signedMediaUrl(m.photoUrl!))
                              : null,
                          child: m.photoUrl == null
                              ? Text(m.displayName.isNotEmpty
                                  ? m.displayName[0].toUpperCase()
                                  : 'E')
                              : null,
                        ),
                        title: Text(m.displayName,
                            style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            _viewerIsAdmin(members)
                                ? m.email
                                : (m.role.isAdminOrOwner
                                    ? context.l10n.translate('hub_role_admin')
                                    : context.l10n
                                        .translate('hub_role_member')),
                            style: TextStyle(
                                color: context.forest.text54, fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: m.role.isAdminOrOwner
                                ? AppColors.gold.withValues(alpha: 0.2)
                                : context.forest.divider10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            m.role.toValue().toUpperCase(),
                            style: TextStyle(
                              color: m.role.isAdminOrOwner
                                  ? AppColors.gold
                                  : context.forest.text70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// A family circle, an office, a campus or a mess: a name and a description. It has no
  /// trip, so no dates, destination or travel modules are asked for.
  void _showCreateFamilyDialog(BuildContext context, {String? preset}) {
    final l10n = context.l10n;
    String pick(
            String family,
            String office,
            String campus,
            String mess,
            String society,
            String samity,
            String school,
            String sports,
            String study,
            String committee,
            [String? friends]) =>
        preset == TourGroup.friendsPreset
            ? (friends ?? family)
            : preset == TourGroup.officePreset
                ? office
                : preset == TourGroup.campusPreset
                    ? campus
                    : preset == TourGroup.messPreset
                        ? mess
                        : preset == TourGroup.societyPreset
                            ? society
                            : preset == TourGroup.samityPreset
                                ? samity
                                : preset == TourGroup.schoolPreset
                                    ? school
                                    : preset == TourGroup.sportsPreset
                                        ? sports
                                        : preset == TourGroup.studyPreset
                                            ? study
                                            : preset ==
                                                    TourGroup.committeePreset
                                                ? committee
                                                : family;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isCreating = false;
    int familyCount = 1;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                  l10n.translate(pick(
                      'hub_family_title',
                      'hub_office_title',
                      'hub_campus_title',
                      'hub_mess_title',
                      'hub_society_title',
                      'hub_samity_title',
                      'hub_school_title',
                      'hub_sports_title',
                      'hub_study_title',
                      'hub_committee_title',
                      'hub_friends_title')),
                  style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          l10n.translate(pick(
                              'hub_family_intro',
                              'hub_office_intro',
                              'hub_campus_intro',
                              'hub_mess_intro',
                              'hub_society_intro',
                              'hub_samity_intro',
                              'hub_school_intro',
                              'hub_sports_intro',
                              'hub_study_intro',
                              'hub_committee_intro',
                              'hub_friends_intro')),
                          style: TextStyle(
                              color: context.forest.text70, fontSize: 12)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate(pick(
                              'hub_family_name_hint',
                              'hub_office_name_hint',
                              'hub_campus_name_hint',
                              'hub_mess_name_hint',
                              'hub_society_name_hint',
                              'hub_samity_name_hint',
                              'hub_school_name_hint',
                              'hub_sports_name_hint',
                              'hub_study_name_hint',
                              'hub_committee_name_hint',
                              'hub_friends_name_hint')),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description_optional'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      if (preset == null) const SizedBox(height: 12),
                      if (preset == null)
                        DropdownButtonFormField<int>(
                          initialValue: familyCount,
                          dropdownColor: context.forest.dialog,
                          style: TextStyle(color: context.forest.text),
                          decoration: InputDecoration(
                            labelText: l10n.translate('hub_family_count_label'),
                            helperText: l10n.translate('hub_family_count_hint'),
                            helperStyle: TextStyle(
                                color: context.forest.text54, fontSize: 12),
                            labelStyle: TextStyle(
                                color: context.forest.text70, fontSize: 13),
                            filled: true,
                            fillColor: context.forest.inset26,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            for (var n = 1; n <= 20; n++)
                              DropdownMenuItem(
                                value: n,
                                child: Text(l10n.translate('hub_people_count',
                                    args: {'count': n})),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => familyCount = v);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating ? null : () => Navigator.pop(ctx),
                  child: Text(l10n.translate('tour_cancel'),
                      style: TextStyle(color: context.forest.text54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: isCreating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack(l10n.translate('hub_name_hint'),
                                error: true);
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isCreating = true);
                          try {
                            final today = DateTime.now();
                            final newGroup = await _repository.createGroup(
                              name: name,
                              description: descCtrl.text.trim(),
                              destination: '',
                              tourType: TourType.custom,
                              startDate: today,
                              endDate: today,
                              modules: const TourModules(
                                seatsRooms: false,
                                tideSafety: false,
                                games: true,
                                chat: true,
                              ),
                              kind: GroupKind.family,
                              ownerFamilyCount:
                                  preset == null ? familyCount : 1,
                              preset: preset,
                            );
                            if (mounted) {
                              _selectTour(newGroup);
                              setState(() {});
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate(
                                      pick(
                                          'hub_family_created',
                                          'hub_office_created',
                                          'hub_campus_created',
                                          'hub_mess_created',
                                          'hub_society_created',
                                          'hub_samity_created',
                                          'hub_school_created',
                                          'hub_sports_created',
                                          'hub_study_created',
                                          'hub_committee_created',
                                          'hub_friends_created'),
                                      args: {'name': newGroup.name})),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isCreating = false);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate(
                                      'hub_create_failed',
                                      args: {'error': e})),
                                  backgroundColor: AppColors.amber,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isCreating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_family_create'),
                          style: TextStyle(color: context.forest.text)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    final originCtrl = TextEditingController(text: 'ঢাকা');
    TourType selectedTourType = TourType.beach;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now()
        .add(const Duration(days: 3)); // 4 days 3 nights by default
    bool seatsRooms = true;
    bool tideSafety = true;
    bool games = true;
    bool chat = true;
    bool isCreating = false;

    final presets = [
      (
        label: l10n.translate('hub_preset_coxs'),
        dest: "Cox's Bazar",
        type: TourType.beach,
        tide: true
      ),
      (
        label: l10n.translate('hub_preset_sajek'),
        dest: 'Sajek Valley',
        type: TourType.hill,
        tide: false
      ),
      (
        label: l10n.translate('hub_preset_sylhet'),
        dest: 'Sylhet',
        type: TourType.nature,
        tide: false
      ),
      (
        label: l10n.translate('hub_preset_bandarban'),
        dest: 'Bandarban',
        type: TourType.hill,
        tide: false
      ),
      (
        label: l10n.translate('hub_preset_kuakata'),
        dest: 'Kuakata',
        type: TourType.beach,
        tide: true
      ),
      (
        label: l10n.translate('hub_preset_sundarbans'),
        dest: 'Sundarbans',
        type: TourType.nature,
        tide: false
      ),
    ];

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final days = endDate.difference(startDate).inDays + 1;
            final nights = days > 1 ? days - 1 : 0;
            final durationText = nights == 0
                ? l10n.translate('hub_duration_day_trip', args: {'days': days})
                : l10n.translate('hub_duration_nights',
                    args: {'days': days, 'nights': nights});

            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(context.l10n.translate('hub_create_trip_title'),
                  style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Tour Name
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.translate('hub_trip_name_hint'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          hintText: 'e.g. Sajek Tour 2026',
                          hintStyle: TextStyle(
                              color: context.forest.text54, fontSize: 12),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2. Destination Presets
                      Text(
                        context.l10n.translate('hub_popular_destinations'),
                        style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: presets.map((p) {
                          final isSelected = destCtrl.text == p.dest;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                destCtrl.text = p.dest;
                                selectedTourType = p.type;
                                tideSafety = p.tide;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.mintGreen
                                    : context.forest.divider10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : context.forest.text,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),

                      // 3. Custom Destination Field
                      TextField(
                        controller: destCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_destination_label'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          hintText: l10n.translate('hub_destination_example'),
                          hintStyle: TextStyle(
                              color: context.forest.text54, fontSize: 12),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Origin & Tour Type Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: originCtrl,
                              style: TextStyle(color: context.forest.text),
                              decoration: InputDecoration(
                                labelText: l10n.translate('hub_origin_label'),
                                labelStyle: TextStyle(
                                    color: context.forest.text70, fontSize: 12),
                                hintText: l10n.translate('hub_origin_hint'),
                                hintStyle: TextStyle(
                                    color: context.forest.text54, fontSize: 12),
                                filled: true,
                                fillColor: context.forest.inset26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<TourType>(
                              key: ValueKey(selectedTourType),
                              initialValue: selectedTourType,
                              dropdownColor: context.forest.card,
                              style: TextStyle(
                                  color: context.forest.text, fontSize: 12),
                              decoration: InputDecoration(
                                labelText:
                                    l10n.translate('hub_tour_type_label'),
                                labelStyle: TextStyle(
                                    color: context.forest.text70, fontSize: 12),
                                filled: true,
                                fillColor: context.forest.inset26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              items: TourType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                      '${t.labelBn.split(' ').first} ${t.name.toUpperCase()}',
                                      style: const TextStyle(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (t) {
                                if (t != null) {
                                  setDialogState(() {
                                    selectedTourType = t;
                                    tideSafety = (t == TourType.beach);
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 5. Date Range Selector Button
                      Text(
                        l10n.translate('hub_dates_heading'),
                        style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: dialogCtx,
                            initialDateRange:
                                DateTimeRange(start: startDate, end: endDate),
                            firstDate: DateTime(2022),
                            lastDate: DateTime(2035),
                            builder: (context, child) {
                              return Theme(
                                data: context.forest.isDark
                                    ? ThemeData.dark().copyWith(
                                        colorScheme: ColorScheme.dark(
                                          primary: AppColors.midGreen,
                                          onPrimary: Colors.white,
                                          surface: context.forest.card,
                                          onSurface: Colors.white,
                                        ),
                                      )
                                    : ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: AppColors.midGreen,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: AppColors.darkText,
                                        ),
                                      ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() {
                              startDate = picked.start;
                              endDate = picked.end;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.forest.inset38,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.date_range_rounded,
                                  color: context.forest.accentText, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${localizedDateFormat('d MMM yyyy').format(startDate)} – ${localizedDateFormat('d MMM yyyy').format(endDate)}',
                                      style: TextStyle(
                                          color: context.forest.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                    Text(
                                      l10n.translate('hub_duration_hint',
                                          args: {'duration': durationText}),
                                      style: TextStyle(
                                          color: context.forest.accentText,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.edit_calendar_rounded,
                                  color: context.forest.text54, size: 16),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(l10n.translate('hub_modules_optional'),
                          style: TextStyle(
                              color: context.forest.text70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      _moduleSwitch(
                          l10n.translate('hub_mod_seats_short'),
                          seatsRooms,
                          (v) => setDialogState(() => seatsRooms = v)),
                      _moduleSwitch(
                          l10n.translate('hub_mod_tide_short'),
                          tideSafety,
                          (v) => setDialogState(() => tideSafety = v)),
                      _moduleSwitch(l10n.translate('hub_mod_games_short'),
                          games, (v) => setDialogState(() => games = v)),
                      _moduleSwitch(l10n.translate('hub_mod_channels_short'),
                          chat, (v) => setDialogState(() => chat = v)),
                      const SizedBox(height: 8),
                      // 6. Description
                      TextField(
                        controller: descCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description_optional'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating ? null : () => Navigator.pop(ctx),
                  child: Text(l10n.translate('tour_cancel'),
                      style: TextStyle(color: context.forest.text54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: isCreating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final dest = destCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack(l10n.translate('hub_name_hint'),
                                error: true);
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isCreating = true);
                          try {
                            final newGroup = await _repository.createGroup(
                              name: name,
                              description: descCtrl.text.trim(),
                              destination:
                                  dest.isNotEmpty ? dest : "Custom Destination",
                              originCity: originCtrl.text.trim().isNotEmpty
                                  ? originCtrl.text.trim()
                                  : 'ঢাকা',
                              tourType: selectedTourType,
                              startDate: startDate,
                              endDate: endDate,
                              modules: TourModules(
                                seatsRooms: seatsRooms,
                                tideSafety: tideSafety,
                                games: games,
                                chat: chat,
                              ),
                            );
                            if (mounted) {
                              _selectTour(newGroup);
                              setState(() {});
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate('hub_created',
                                      args: {
                                        'name': newGroup.name,
                                        'duration': newGroup.durationText
                                      })),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isCreating = false);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate(
                                      'hub_create_failed',
                                      args: {'error': e})),
                                  backgroundColor: AppColors.amber,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isCreating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_create_tour'),
                          style: TextStyle(color: context.forest.text)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
      destCtrl.dispose();
      originCtrl.dispose();
    });
  }

  void _showRenameGroupDialog(BuildContext context, TourGroup group) {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController(text: group.name);
    final descCtrl = TextEditingController(text: group.description);
    bool isUpdating = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(l10n.translate('hub_edit_circle_title'),
                  style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_name_label'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_desc_label'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(ctx),
                  child: Text(l10n.translate('tour_cancel'),
                      style: TextStyle(color: context.forest.text54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: isUpdating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack(l10n.translate('hub_name_hint'),
                                error: true);
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isUpdating = true);
                          try {
                            await _repository.updateGroupSettings(
                              tourId: group.id,
                              name: name,
                              description: descCtrl.text.trim(),
                            );
                            if (mounted) {
                              setState(() {
                                _selectedGroup = group.copyWith(
                                  name: name,
                                  description: descCtrl.text.trim(),
                                );
                              });
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      l10n.translate('hub_group_name_updated')),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isUpdating = false);
                            _reportFailure(e);
                          }
                        },
                  child: isUpdating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_save_changes'),
                          style: TextStyle(color: context.forest.text)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  void _showEditGroupDialog(BuildContext context, TourGroup group) {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController(text: group.name);
    final descCtrl = TextEditingController(text: group.description);
    final destCtrl = TextEditingController(text: group.destination);
    final originCtrl = TextEditingController(text: group.originCity);
    TourType selectedTourType = group.tourType;
    DateTime startDate = group.startDate;
    DateTime endDate = group.endDate;
    bool isUpdating = false;
    bool seatsRooms = group.modules.seatsRooms;
    bool tideSafety = group.modules.tideSafety;
    bool games = group.modules.games;
    bool chat = group.modules.chat;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final days = endDate.difference(startDate).inDays + 1;
            final nights = days > 1 ? days - 1 : 0;
            final durationText = nights == 0
                ? l10n.translate('hub_duration_day_trip', args: {'days': days})
                : l10n.translate('hub_duration_nights',
                    args: {'days': days, 'nights': nights});

            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(l10n.translate('hub_edit_settings_title'),
                  style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_name_label'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: destCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_destination_label'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: originCtrl,
                              style: TextStyle(color: context.forest.text),
                              decoration: InputDecoration(
                                labelText: l10n.translate('hub_origin_label'),
                                labelStyle: TextStyle(
                                    color: context.forest.text70, fontSize: 12),
                                filled: true,
                                fillColor: context.forest.inset26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<TourType>(
                              key: ValueKey(selectedTourType),
                              initialValue: selectedTourType,
                              dropdownColor: context.forest.card,
                              style: TextStyle(
                                  color: context.forest.text, fontSize: 12),
                              decoration: InputDecoration(
                                labelText:
                                    l10n.translate('hub_tour_type_label'),
                                labelStyle: TextStyle(
                                    color: context.forest.text70, fontSize: 12),
                                filled: true,
                                fillColor: context.forest.inset26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              items: TourType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                      '${t.labelBn.split(' ').first} ${t.name.toUpperCase()}',
                                      style: const TextStyle(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (t) {
                                if (t != null) {
                                  setDialogState(() => selectedTourType = t);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l10n.translate('hub_edit_dates_heading'),
                        style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: dialogCtx,
                            initialDateRange:
                                DateTimeRange(start: startDate, end: endDate),
                            firstDate: DateTime(2022),
                            lastDate: DateTime(2035),
                            builder: (context, child) {
                              return Theme(
                                data: context.forest.isDark
                                    ? ThemeData.dark().copyWith(
                                        colorScheme: ColorScheme.dark(
                                          primary: AppColors.midGreen,
                                          onPrimary: Colors.white,
                                          surface: context.forest.card,
                                          onSurface: Colors.white,
                                        ),
                                      )
                                    : ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: AppColors.midGreen,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: AppColors.darkText,
                                        ),
                                      ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() {
                              startDate = picked.start;
                              endDate = picked.end;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.forest.inset38,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.date_range_rounded,
                                  color: context.forest.accentText, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${localizedDateFormat('d MMM yyyy').format(startDate)} – ${localizedDateFormat('d MMM yyyy').format(endDate)}',
                                      style: TextStyle(
                                          color: context.forest.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                    Text(
                                      l10n.translate('hub_new_duration',
                                          args: {'duration': durationText}),
                                      style: TextStyle(
                                          color: context.forest.accentText,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.edit_calendar_rounded,
                                  color: context.forest.text54, size: 16),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.translate('hub_modules_label'),
                          style: TextStyle(
                              color: context.forest.text70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      _moduleSwitch(
                          l10n.translate('hub_mod_seats_short'),
                          seatsRooms,
                          (v) => setDialogState(() => seatsRooms = v)),
                      _moduleSwitch(
                          l10n.translate('hub_mod_tide_short'),
                          tideSafety,
                          (v) => setDialogState(() => tideSafety = v)),
                      _moduleSwitch(l10n.translate('hub_mod_games_short'),
                          games, (v) => setDialogState(() => games = v)),
                      _moduleSwitch(l10n.translate('hub_mod_channels_short'),
                          chat, (v) => setDialogState(() => chat = v)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descCtrl,
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description'),
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(ctx),
                  child: Text(l10n.translate('tour_cancel'),
                      style: TextStyle(color: context.forest.text54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: isUpdating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final dest = destCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack(l10n.translate('hub_name_hint'),
                                error: true);
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isUpdating = true);
                          try {
                            await _repository.updateGroupSettings(
                              tourId: group.id,
                              modules: TourModules(
                                seatsRooms: seatsRooms,
                                tideSafety: tideSafety,
                                games: games,
                                chat: chat,
                              ),
                              name: name,
                              description: descCtrl.text.trim(),
                              destination:
                                  dest.isNotEmpty ? dest : group.destination,
                              originCity: originCtrl.text.trim(),
                              tourType: selectedTourType,
                              startDate: startDate,
                              endDate: endDate,
                            );
                            if (mounted) {
                              setState(() {
                                _selectedGroup = group.copyWith(
                                  name: name,
                                  description: descCtrl.text.trim(),
                                  destination: dest.isNotEmpty
                                      ? dest
                                      : group.destination,
                                  originCity: originCtrl.text.trim(),
                                  tourType: selectedTourType,
                                  startDate: startDate,
                                  endDate: endDate,
                                );
                              });
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      l10n.translate('hub_settings_saved')),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isUpdating = false);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate(
                                      'hub_update_failed',
                                      args: {'error': e})),
                                  backgroundColor: AppColors.amber,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isUpdating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_save_changes'),
                          style: TextStyle(color: context.forest.text)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      descCtrl.dispose();
      destCtrl.dispose();
      originCtrl.dispose();
    });
  }

  void _showJoinGroupDialog(BuildContext context) {
    final l10n = context.l10n;
    final codeCtrl = TextEditingController();
    bool isJoining = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(l10n.translate('hub_join_title'),
                  style: TextStyle(
                      color: context.forest.text, fontWeight: FontWeight.bold)),
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
                  child: Text(l10n.translate('tour_cancel'),
                      style: TextStyle(color: context.forest.text54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
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
                                await _repository.joinGroupWithCode(code);
                            if (mounted) {
                              _selectTour(joinedGroup);
                              setState(() {});
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate('hub_joined',
                                      args: {'name': joinedGroup.name})),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isJoining = false);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(e is FormatException
                                      ? e.message
                                      : e.toString()),
                                  backgroundColor: AppColors.amber,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isJoining
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_join'),
                          style: TextStyle(color: context.forest.text)),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(codeCtrl.dispose);
  }

  void _showManageMemberSheet(
      BuildContext context, String tourId, TourMember member,
      {required bool viewerIsOwner, required bool viewerIsAdmin}) {
    final currentEmail = _repository.currentEmail;
    final isMe = currentEmail.toLowerCase() == member.email.toLowerCase();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: context.forest.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: bottomPad + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.forest.text24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _showAvatarViewer(
                        context, member.displayName, member.photoUrl),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        MemberAvatar(
                          name: member.displayName,
                          photoUrl: member.photoUrl,
                          size: 48,
                        ),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: context.forest.card,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.zoom_in_rounded,
                            size: 12,
                            color: context.forest.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: TextStyle(
                            color: context.forest.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          viewerIsAdmin || isMe
                              ? member.email
                              : member.role.toValue().toUpperCase(),
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: member.role.isAdminOrOwner
                          ? AppColors.gold.withValues(alpha: 0.2)
                          : context.forest.divider10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      member.role.toValue().toUpperCase(),
                      style: TextStyle(
                        color: member.role.isAdminOrOwner
                            ? AppColors.gold
                            : context.forest.text70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isMe) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildMemberQuickAction(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: context.l10n.translate('chan_direct_message'),
                        color: AppColors.mintGreen,
                        onTap: () {
                          Navigator.pop(ctx);
                          _startDirectChat(member);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMemberQuickAction(
                        icon: Icons.call_outlined,
                        label: context.l10n.translate('chan_call_audio'),
                        color: const Color(0xFF64B5F6),
                        onTap: () {
                          Navigator.pop(ctx);
                          _startDirectCall(member, isVideo: false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMemberQuickAction(
                        icon: Icons.videocam_outlined,
                        label: context.l10n.translate('chan_call_video'),
                        color: const Color(0xFF81C784),
                        onTap: () {
                          Navigator.pop(ctx);
                          _startDirectCall(member, isVideo: true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.account_circle_outlined,
                      color: context.forest.accentText, size: 22),
                ),
                title: Text(
                  context.l10n.translate('prof_tab_info'),
                  style: TextStyle(
                      color: context.forest.text, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  context.l10n.translate('prof_posts'),
                  style: TextStyle(color: context.forest.text54, fontSize: 12),
                ),
                trailing:
                    Icon(Icons.chevron_right, color: context.forest.text38),
                onTap: () {
                  Navigator.pop(ctx);
                  TourMemberProfileModal.show(
                    context,
                    tourId: tourId,
                    memberEmail: member.email,
                    memberName: member.displayName,
                    memberPhoto: member.photoUrl,
                    familyCount: member.familyCount,
                  );
                },
              ),
              Divider(color: context.forest.divider10),
              if (!isMe && member.role != TourRole.owner && viewerIsAdmin) ...[
                // Promote / Demote
                if (viewerIsOwner)
                  ListTile(
                    leading: Icon(
                      member.role == TourRole.admin
                          ? Icons.person_outline
                          : Icons.admin_panel_settings_rounded,
                      color: context.forest.accentText,
                    ),
                    title: Text(
                      member.role == TourRole.admin
                          ? context.l10n.translate('hub_remove_admin')
                          : context.l10n.translate('hub_promote_admin'),
                      style: TextStyle(color: context.forest.text),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final newRole = member.role == TourRole.admin
                          ? TourRole.member
                          : TourRole.admin;
                      try {
                        await _repository.updateMemberRole(
                            tourId, member.email, newRole);
                      } catch (e) {
                        _reportFailure(e);
                        return;
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(context.l10n.translate(
                                  'hub_role_changed',
                                  args: {'name': member.displayName}))),
                        );
                      }
                    },
                  ),
                // Transfer Ownership
                if (viewerIsOwner)
                  ListTile(
                    leading:
                        const Icon(Icons.stars_rounded, color: AppColors.gold),
                    title: Text(
                      context.l10n.translate('hub_transfer_title'),
                      style: TextStyle(color: context.forest.text),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: context.forest.card,
                          title: Text(
                              context.l10n.translate('hub_transfer_question'),
                              style: TextStyle(color: context.forest.text)),
                          content: Text(
                              context.l10n.translate('hub_transfer_body',
                                  args: {'name': member.displayName}),
                              style: TextStyle(color: context.forest.text70)),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(
                                    context.l10n.translate('tour_cancel'))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: Colors.black),
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(context.l10n
                                  .translate('hub_transfer_action')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await _repository.transferOwnership(
                              tourId, member.email);
                        } catch (e) {
                          _reportFailure(e);
                        }
                      }
                    },
                  ),
                // Remove Member
                if (viewerIsOwner || member.role == TourRole.member)
                  ListTile(
                    leading: const Icon(Icons.person_remove_rounded,
                        color: Colors.redAccent),
                    title: Text(
                      context.l10n.translate('hub_remove_title'),
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: context.forest.card,
                          title: Text(
                              context.l10n.translate('hub_remove_question'),
                              style: TextStyle(color: context.forest.text)),
                          content: Text(
                              context.l10n.translate('hub_remove_body',
                                  args: {'name': member.displayName}),
                              style: TextStyle(color: context.forest.text70)),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(
                                    context.l10n.translate('tour_cancel'))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.amber,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(
                                  context.l10n.translate('hub_remove_action')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await _repository.removeMember(tourId, member.email);
                        } catch (e) {
                          _reportFailure(e);
                        }
                      }
                    },
                  ),
              ] else if (isMe) ...[
                ListTile(
                  leading: Icon(Icons.family_restroom_rounded,
                      color: context.forest.accentText),
                  title: Text(
                    context.l10n.translate('hub_family_count_line',
                        args: {'count': member.familyCount}),
                    style: TextStyle(color: context.forest.text),
                  ),
                  subtitle: Text(
                    context.l10n.translate('hub_family_count_note'),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 12),
                  ),
                  onTap: () async {
                    final count =
                        await _pickFamilyCount(ctx, member.familyCount);
                    if (count == null || count == member.familyCount) return;
                    try {
                      await _repository.setMyFamilyCount(tourId, count);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      _reportFailure(e);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    context.l10n.translate('hub_own_profile_note'),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Displays the full member avatar picture in a high-res dialog for all members.
  void _showAvatarViewer(BuildContext context, String name, String? photoUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: context.l10n.translate('group_close'),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(ctx).width * 0.85,
                          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
                        ),
                        child: kIsWeb
                            ? Image.network(
                                signedMediaUrl(photoUrl),
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                        ? child
                                        : const SizedBox(
                                            width: 140,
                                            height: 140,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                  color: AppColors.mintGreen),
                                            ),
                                          ),
                                errorBuilder: (_, __, ___) => MemberAvatar(
                                  name: name,
                                  size: 160,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: signedMediaUrl(photoUrl),
                                fit: BoxFit.contain,
                                placeholder: (_, __) => const SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.mintGreen),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => MemberAvatar(
                                  name: name,
                                  size: 160,
                                ),
                              ),
                      ),
                    )
                  : MemberAvatar(
                      name: name,
                      size: 160,
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A row for a popup menu: an icon, then a label that wraps rather than overflows.
Widget _menuRow(
  BuildContext context,
  IconData icon,
  String label, {
  Color? color,
  Color? iconColor,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: iconColor ?? context.forest.accentText),
      const SizedBox(width: 10),
      Flexible(
          child: Text(label,
              style: TextStyle(color: color ?? context.forest.text))),
    ],
  );
}

class _ModuleItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModuleItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

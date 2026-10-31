import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/tour_choice.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_hub_preference.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/localization/localized_date.dart';
import '../widgets/bhromon_bottom_nav.dart';
import '../widgets/member_profile/tour_member_profile_modal.dart';
import '../tour_pdf_export.dart';

class TourGroupHubScreen extends StatefulWidget {
  final TourGroupRepository? repository;

  /// The tour to open on, from the address (`?tourId=`). Null opens the tour
  /// the hub showed last, or the first tour.
  final String? initialTourId;

  /// Where the hub keeps its own pick. Tests pass a fake; the app leaves it null.
  final TourHubPreference? preference;

  const TourGroupHubScreen({
    super.key,
    this.repository,
    this.initialTourId,
    this.preference,
  });

  @override
  State<TourGroupHubScreen> createState() => _TourGroupHubScreenState();
}

class _TourGroupHubScreenState extends State<TourGroupHubScreen> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  late final TourHubPreference _preference =
      widget.preference ?? TourHubPreference();
  // The tour picked, created or joined during this visit. It is kept even
  // before the membership list includes it.
  TourGroup? _selectedGroup;
  // The tour the hub showed last time, read once when the hub opens.
  String? _rememberedTourId;
  late Stream<List<TourGroup>> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = _repository.watchMyGroups();
    _rememberedTourId = _preference.read();
    final routeTourId = widget.initialTourId;
    if (routeTourId != null) unawaited(_preference.remember(routeTourId));
  }

  final Map<String, Stream<List<TourMember>>> _memberStreams = {};

  Stream<List<TourMember>> _membersOf(String tourId) => _memberStreams
      .putIfAbsent(tourId, () => _repository.watchMembers(tourId));

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
    await SharePlus.instance
        .share(ShareParams(text: text, subject: group.name));
  }

  void _selectTour(TourGroup group) {
    unawaited(_preference.remember(group.id));
    setState(() => _selectedGroup = group);
  }

  /// Lists the family circles and the trips the person belongs to, in two sections.
  void _showCircleSwitcher(
    BuildContext context,
    List<TourGroup> allGroups,
    TourGroup current,
  ) {
    final families = [
      for (final g in allGroups)
        if (g.isFamily) g
    ];
    final trips = [
      for (final g in allGroups)
        if (!g.isFamily) g
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14241B),
      builder: (sheetContext) {
        final l10n = context.l10n;
        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            );
        Widget tile(TourGroup g) {
          final selected = g.id == current.id;
          return ListTile(
            leading: Icon(
                g.isFamily
                    ? Icons.family_restroom_rounded
                    : Icons.card_travel_rounded,
                color: selected ? AppColors.mintGreen : Colors.white54),
            title: Text(g.name,
                style: TextStyle(
                    color: selected ? AppColors.mintGreen : Colors.white,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
            onTap: () {
              Navigator.pop(sheetContext);
              _selectTour(g);
            },
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (families.isNotEmpty) ...[
                header(l10n.translate('hub_section_family')),
                for (final g in families) tile(g),
              ],
              if (trips.isNotEmpty) ...[
                header(l10n.translate('hub_section_trips')),
                for (final g in trips) tile(g),
              ],
            ],
          ),
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
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
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
            const Icon(Icons.check_circle_rounded,
                color: AppColors.mintGreen, size: 20),
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
        backgroundColor: const Color(0xFF14241B),
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
          backgroundColor: const Color(0xFF1B4332),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.person_add_alt_1,
                  color: AppColors.mintGreen, size: 22),
              const SizedBox(width: 8),
              Text(
                context.l10n.translate('hub_add_member_title'),
                style: const TextStyle(color: Colors.white, fontSize: 18),
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
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('hub_member_email_label'),
                    hintText: 'example@gmail.com',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: AppColors.mintGreen),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.mintGreen),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.l10n.translate('hub_member_name_label'),
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon:
                        const Icon(Icons.badge_outlined, color: Colors.white60),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
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
                  style: const TextStyle(color: Colors.white70)),
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
          style: const TextStyle(color: Colors.white, fontSize: 13)),
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
          backgroundColor: const Color(0xFF14241B),
          title: Text(context.l10n.translate('hub_family_count_label'),
              style: const TextStyle(color: Colors.white)),
          content: DropdownButtonFormField<int>(
            initialValue: value,
            dropdownColor: const Color(0xFF1B4332),
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
        backgroundColor: const Color(0xFF14241B),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
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
      case 'add_member':
        _showAddMemberDialog(context, group.id);
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
            l10n.translate(
                group.isFamily ? 'hub_leave_family_title' : 'hub_leave_title'),
            l10n.translate('hub_leave_body', args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.leaveTour(group.id);
          unawaited(_preference.forget(group.id));
          if (mounted) {
            setState(() {
              _selectedGroup = null;
              _memberStreams.remove(group.id);
              _groupsStream = _repository.watchMyGroups();
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
            l10n.translate(group.isFamily
                ? 'hub_delete_family_title'
                : 'hub_delete_title'),
            l10n.translate(
                group.isFamily ? 'hub_delete_family_body' : 'hub_delete_body',
                args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.deleteTour(group.id, inviteCode: group.inviteCode);
          unawaited(_preference.forget(group.id));
          if (mounted) {
            setState(() {
              _selectedGroup = null;
              _memberStreams.remove(group.id);
              _groupsStream = _repository.watchMyGroups();
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TourGroup>>(
      stream: _groupsStream,
      builder: (context, snapshot) {
        // Only tours the membership list still names are shown, so a tour the
        // user left or was removed from drops out at once.
        final groups = snapshot.data ?? [];
        final current = pickTour(groups, [
          _selectedGroup?.id,
          widget.initialTourId,
          _rememberedTourId,
        ]);

        return Scaffold(
          backgroundColor: const Color(0xFF0D1A12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0D1A12),
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1B4332),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.explore,
                        color: AppColors.mintGreen,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bhromon',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      context.l10n.translate('hub_title'),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: context.l10n.translate('hub_add_menu'),
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.midGreen),
                color: const Color(0xFF1B4332),
                onSelected: (choice) {
                  switch (choice) {
                    case 'family':
                      _showCreateFamilyDialog(context);
                    case 'trip':
                      _showCreateGroupDialog(context);
                    case 'join':
                      _showJoinGroupDialog(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'family',
                    child: _menuRow(Icons.family_restroom_rounded,
                        context.l10n.translate('hub_create_family')),
                  ),
                  PopupMenuItem(
                    value: 'trip',
                    child: _menuRow(Icons.card_travel_rounded,
                        context.l10n.translate('hub_create_new_tour')),
                  ),
                  PopupMenuItem(
                    value: 'join',
                    child: _menuRow(Icons.group_add_outlined,
                        context.l10n.translate('hub_join_with_code')),
                  ),
                ],
              ),
            ],
          ),
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
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.midGreen),
                              onPressed: () => setState(() {
                                _groupsStream = _repository.watchMyGroups();
                              }),
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

                      // 2. Feature Launchpad Grid
                      Text(
                        context.l10n.translate('hub_modules_heading'),
                        style: const TextStyle(
                          color: Colors.white,
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
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.midGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.travel_explore_rounded,
                  size: 72, color: AppColors.mintGreen),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.translate('hub_empty_title'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.translate('hub_empty_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
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
              icon: const Icon(Icons.family_restroom_rounded,
                  color: AppColors.mintGreen),
              label: Text(context.l10n.translate('hub_create_family'),
                  style: const TextStyle(color: AppColors.mintGreen)),
            ),
            const SizedBox(height: 12),
            if (!_repository.isSignedIn)
              TextButton.icon(
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.login,
                    color: AppColors.mintGreen, size: 18),
                label: Text(
                  context.l10n.translate('hub_login_or_signup'),
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            else
              Text(
                context.l10n.translate('hub_current_account',
                    args: {'email': _repository.currentEmail}),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
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
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B4332),
            Color(0xFF081C15),
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
                        group.isFamily
                            ? context.l10n.translate('hub_family_badge')
                            : '${group.tourType.labelBn.split(' ').first} ${group.destination}',
                        style: const TextStyle(
                          color: AppColors.mintGreen,
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
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⏱️ ${group.durationText}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white70, size: 20),
                    color: const Color(0xFF1B4332),
                    onSelected: (v) => _onGroupMenu(context, group, v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'copy_code',
                        child: _menuRow(Icons.copy_rounded,
                            context.l10n.translate('hub_copy_invite_code')),
                      ),
                      PopupMenuItem(
                        value: 'export_pdf',
                        child: _menuRow(Icons.picture_as_pdf_rounded,
                            context.l10n.translate('pdf_export_menu')),
                      ),
                      if (group.ownerEmail == _repository.currentEmail) ...[
                        PopupMenuItem(
                          value: 'add_member',
                          child: _menuRow(
                              Icons.person_add_alt_1,
                              context.l10n
                                  .translate('hub_add_member_by_email')),
                        ),
                        PopupMenuItem(
                          value: 'code',
                          child: _menuRow(Icons.key_rounded,
                              context.l10n.translate('hub_renew_code'),
                              iconColor: Colors.white70),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: _menuRow(
                              Icons.delete_outline_rounded,
                              context.l10n.translate(group.isFamily
                                  ? 'hub_delete_family'
                                  : 'hub_delete_tour'),
                              color: Colors.redAccent,
                              iconColor: Colors.redAccent),
                        ),
                      ] else
                        PopupMenuItem(
                          value: 'leave',
                          child: _menuRow(
                              Icons.logout_rounded,
                              context.l10n.translate(group.isFamily
                                  ? 'hub_leave_family'
                                  : 'hub_leave_tour'),
                              iconColor: Colors.white70),
                        ),
                    ],
                  ),
                  if (!group.isFamily)
                    IconButton(
                      icon: const Icon(Icons.edit_calendar_rounded,
                          size: 20, color: AppColors.mintGreen),
                      tooltip: context.l10n.translate('hub_settings_dates'),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showEditGroupDialog(context, group),
                    ),
                  if (allGroups.length > 1) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: context.l10n.translate('hub_switch_circle'),
                      icon: const Icon(Icons.swap_horiz_rounded,
                          color: AppColors.mintGreen),
                      onPressed: () =>
                          _showCircleSwitcher(context, allGroups, group),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (!group.isFamily)
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 12, color: Colors.white60),
                const SizedBox(width: 5),
                Text(
                  '${localizedDateFormat('d MMM yyyy').format(group.startDate)} – ${localizedDateFormat('d MMM yyyy').format(group.endDate)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.near_me_rounded,
                    size: 12, color: Colors.white60),
                const SizedBox(width: 4),
                Text(
                  context.l10n.translate('hub_origin_line',
                      args: {'origin': group.originCity}),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              group.description,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                  color: Colors.black.withValues(alpha: 0.25),
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
                            style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          context.l10n.translate('hub_live_current_stop',
                              args: {'stop': currentStopName}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
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
                        backgroundColor: Colors.white12,
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
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                context.push('/group/${group.id}/journey'),
                            icon: const Icon(Icons.alt_route_rounded,
                                size: 14, color: AppColors.mintGreen),
                            label: Text(
                              context.l10n.translate('hub_live_route_btn'),
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
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
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () =>
                                context.push('/group/${group.id}/ledger'),
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 14,
                                color: Color(0xFF52B788)),
                            label: Text(
                              context.l10n.translate('hub_live_ledger_btn'),
                              style: const TextStyle(fontSize: 11),
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
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
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
                        style: const TextStyle(
                          color: Colors.white70,
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
                      icon: const Icon(Icons.checklist_rounded,
                          size: 14, color: AppColors.mintGreen),
                      label: Text(
                        context.l10n.translate('hub_upcoming_checklist'),
                        style: const TextStyle(
                            color: AppColors.mintGreen, fontSize: 11),
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
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 14, color: AppColors.mintGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.translate('hub_completed_badge',
                            args: {'days': context.l10n.number(totalDays)}),
                        style: const TextStyle(
                          color: Colors.white70,
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
                      icon: const Icon(Icons.auto_stories_rounded,
                          size: 14, color: AppColors.mintGreen),
                      label: Text(
                        context.l10n.translate('hub_completed_scrapbook'),
                        style: const TextStyle(
                            color: AppColors.mintGreen, fontSize: 11),
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
                        border: Border.all(color: Colors.white12),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy_rounded,
                              size: 14, color: AppColors.mintGreen),
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
                    const Icon(Icons.share_rounded, color: AppColors.mintGreen),
                onPressed: () => _shareInvite(group),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context, TourGroup group) {
    // Family circles have no trip, so the trip-only tiles stay hidden.
    final isTrip = !group.isFamily;
    final l10n = context.l10n;
    final entries = <String, _ModuleItem>{
      'feed': _ModuleItem(
        title: l10n.translate('hub_module_feed'),
        subtitle: l10n.translate('hub_module_feed_sub'),
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFFF43F5E),
        onTap: () => context.push('/group/${group.id}/feed'),
      ),
      'ledger': _ModuleItem(
        title: l10n.translate('hub_module_ledger'),
        subtitle: l10n.translate('hub_module_ledger_sub'),
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF52B788),
        onTap: () => context.push('/group/${group.id}/ledger'),
      ),
      if (isTrip && group.modules.seatsRooms)
        'seats': _ModuleItem(
          title: l10n.translate('hub_module_seats'),
          subtitle: l10n.translate('hub_module_seats_sub'),
          icon: Icons.airline_seat_recline_extra_rounded,
          color: const Color(0xFF6366F1),
          onTap: () => context.push('/group/${group.id}/logistics'),
        ),
      'calendar': group.isFamily
          ? _ModuleItem(
              title: l10n.translate('hub_module_family_dates'),
              subtitle: l10n.translate('hub_module_family_dates_sub'),
              icon: Icons.event_repeat_rounded,
              color: const Color(0xFF84CC16),
              onTap: () => context.push('/group/${group.id}/family-dates'),
            )
          : _ModuleItem(
              title: l10n.translate('hub_module_calendar'),
              subtitle: l10n.translate('hub_module_calendar_sub'),
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFF84CC16),
              onTap: () => context.push('/group/${group.id}/calendar'),
            ),
      if (isTrip && group.modules.tideSafety)
        'tide': _ModuleItem(
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
      'notices': _ModuleItem(
        title: l10n.translate('hub_module_notices'),
        subtitle: l10n.translate('hub_module_notices_sub'),
        icon: Icons.campaign_rounded,
        color: const Color(0xFFEAB308),
        onTap: () => context.push('/group/${group.id}/notices'),
      ),
      if (isTrip)
        'journey': _ModuleItem(
          title: l10n.translate('hub_module_journey'),
          subtitle: l10n.translate('hub_journey_sub', args: {
            'origin': group.originCity,
            'destination': group.destination
          }),
          icon: Icons.alt_route_rounded,
          color: const Color(0xFF10B981),
          onTap: () => context.push('/group/${group.id}/journey'),
        ),
      'safety': _ModuleItem(
        title: l10n.translate('hub_module_safety'),
        subtitle: l10n.translate('hub_module_safety_sub'),
        icon: Icons.shield_rounded,
        color: const Color(0xFFEF4444),
        onTap: () => context.push('/group/${group.id}/safety'),
      ),
      if (group.modules.games)
        'games': _ModuleItem(
          title: l10n.translate('hub_module_games'),
          subtitle: l10n.translate('hub_module_games_sub'),
          icon: Icons.sports_esports_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => context.push('/game-zone'),
        ),
      if (isTrip)
        'quiz': _ModuleItem(
          title: l10n.translate('hub_module_quiz'),
          subtitle: l10n.translate('hub_quiz_sub',
              args: {'destination': group.destination}),
          icon: Icons.quiz_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () => context.push('/group/${group.id}/quiz'),
        ),
      if (isTrip)
        'scrapbook': _ModuleItem(
          title: l10n.translate('hub_module_scrapbook'),
          subtitle: l10n.translate('hub_module_scrapbook_sub'),
          icon: Icons.auto_stories_rounded,
          color: const Color(0xFFD97706),
          onTap: () => context.push('/group/${group.id}/scrapbook'),
        ),
      if (isTrip)
        'checklist': _ModuleItem(
          title: l10n.translate('hub_module_checklist'),
          subtitle: l10n.translate('hub_module_checklist_sub'),
          icon: Icons.checklist_rtl_rounded,
          color: const Color(0xFF14B8A6),
          onTap: () => context.push('/group/${group.id}/checklist'),
        ),
      if (group.modules.chat)
        'channels': _ModuleItem(
          title: l10n.translate('hub_module_channels'),
          subtitle: l10n.translate('hub_module_channels_sub'),
          icon: Icons.forum_rounded,
          color: const Color(0xFFEC4899),
          onTap: () => context.push('/group/${group.id}/channels'),
        ),
      'news': _ModuleItem(
        title: l10n.translate('hub_module_news'),
        subtitle: l10n.translate('hub_module_news_sub'),
        icon: Icons.article_rounded,
        color: const Color(0xFF0EA5E9),
        onTap: () => context.push('/newspaper-hub'),
      ),
    };
    // Trips keep the trip order. A family circle leads with what the family uses
    // every day. Any tile missing from the order is still shown, at the end.
    final order = isTrip ? _tripModuleOrder : _familyModuleOrder;
    final modules = [
      for (final id in order)
        if (entries.containsKey(id)) entries[id]!,
      for (final entry in entries.entries)
        if (!order.contains(entry.key)) entry.value,
    ];

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
          childAspectRatio = 2.35;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final m = modules[index];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: m.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14241B),
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(m.icon, color: m.color, size: 20),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10.5,
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
                  style: const TextStyle(
                    color: Colors.white,
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
                    icon: const Icon(Icons.person_add_alt_1,
                        size: 16, color: AppColors.mintGreen),
                    label: Text(
                      context.l10n.translate('hub_add_member_title'),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
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
                      style: const TextStyle(color: Colors.white54))
            else
              Material(
                color: const Color(0xFF14241B),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
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
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          child: m.photoUrl == null
                              ? Text(m.displayName.isNotEmpty
                                  ? m.displayName[0].toUpperCase()
                                  : 'E')
                              : null,
                        ),
                        title: Text(m.displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            _viewerIsAdmin(members)
                                ? m.email
                                : (m.role.isAdminOrOwner
                                    ? context.l10n.translate('hub_role_admin')
                                    : context.l10n
                                        .translate('hub_role_member')),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: m.role.isAdminOrOwner
                                ? AppColors.gold.withValues(alpha: 0.2)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            m.role.toValue().toUpperCase(),
                            style: TextStyle(
                              color: m.role.isAdminOrOwner
                                  ? AppColors.gold
                                  : Colors.white70,
                              fontSize: 10,
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

  /// A family circle: a name and a description. It has no trip, so no dates,
  /// destination or travel modules are asked for.
  void _showCreateFamilyDialog(BuildContext context) {
    final l10n = context.l10n;
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
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(l10n.translate('hub_family_title'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translate('hub_family_intro'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_family_name_hint'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description_optional'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: familyCount,
                        dropdownColor: const Color(0xFF1B4332),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_family_count_label'),
                          helperText: l10n.translate('hub_family_count_hint'),
                          helperStyle: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
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
                          if (v != null) setDialogState(() => familyCount = v);
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
                      style: const TextStyle(color: Colors.white54)),
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
                              ownerFamilyCount: familyCount,
                            );
                            if (mounted) {
                              _selectTour(newGroup);
                              setState(() {
                                _groupsStream = _repository.watchMyGroups();
                              });
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.translate(
                                      'hub_family_created',
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
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_family_create'),
                          style: const TextStyle(color: Colors.white)),
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
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(context.l10n.translate('hub_create_trip_title'),
                  style: const TextStyle(
                      color: Colors.white,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.translate('hub_trip_name_hint'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          hintText: 'e.g. Sajek Tour 2026',
                          hintStyle: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2. Destination Presets
                      Text(
                        context.l10n.translate('hub_popular_destinations'),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
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
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p.label,
                                style: TextStyle(
                                  color:
                                      isSelected ? Colors.black : Colors.white,
                                  fontSize: 11,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_destination_label'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          hintText: l10n.translate('hub_destination_example'),
                          hintStyle: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                          filled: true,
                          fillColor: Colors.black26,
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
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: l10n.translate('hub_origin_label'),
                                labelStyle: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                hintText: l10n.translate('hub_origin_hint'),
                                hintStyle: const TextStyle(
                                    color: Colors.white54, fontSize: 11),
                                filled: true,
                                fillColor: Colors.black26,
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
                              dropdownColor: const Color(0xFF14241B),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText:
                                    l10n.translate('hub_tour_type_label'),
                                labelStyle: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                filled: true,
                                fillColor: Colors.black26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              items: TourType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                      '${t.labelBn.split(' ').first} ${t.name.toUpperCase()}',
                                      style: const TextStyle(fontSize: 11)),
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
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
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
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: AppColors.midGreen,
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF14241B),
                                    onSurface: Colors.white,
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
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range_rounded,
                                  color: AppColors.mintGreen, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${localizedDateFormat('d MMM yyyy').format(startDate)} – ${localizedDateFormat('d MMM yyyy').format(endDate)}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                    Text(
                                      l10n.translate('hub_duration_hint',
                                          args: {'duration': durationText}),
                                      style: const TextStyle(
                                          color: AppColors.mintGreen,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded,
                                  color: Colors.white54, size: 16),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(l10n.translate('hub_modules_optional'),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description_optional'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
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
                      style: const TextStyle(color: Colors.white54)),
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
                              setState(() {
                                _groupsStream = _repository.watchMyGroups();
                              });
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
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_create_tour'),
                          style: const TextStyle(color: Colors.white)),
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
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(l10n.translate('hub_edit_settings_title'),
                  style: const TextStyle(
                      color: Colors.white,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_name_label'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: destCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_destination_label'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
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
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: l10n.translate('hub_origin_label'),
                                labelStyle: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                filled: true,
                                fillColor: Colors.black26,
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
                              dropdownColor: const Color(0xFF14241B),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText:
                                    l10n.translate('hub_tour_type_label'),
                                labelStyle: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                filled: true,
                                fillColor: Colors.black26,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              items: TourType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                      '${t.labelBn.split(' ').first} ${t.name.toUpperCase()}',
                                      style: const TextStyle(fontSize: 11)),
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
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
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
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: AppColors.midGreen,
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF14241B),
                                    onSurface: Colors.white,
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
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range_rounded,
                                  color: AppColors.mintGreen, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${localizedDateFormat('d MMM yyyy').format(startDate)} – ${localizedDateFormat('d MMM yyyy').format(endDate)}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                    Text(
                                      l10n.translate('hub_new_duration',
                                          args: {'duration': durationText}),
                                      style: const TextStyle(
                                          color: AppColors.mintGreen,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded,
                                  color: Colors.white54, size: 16),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.translate('hub_modules_label'),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.translate('hub_description'),
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
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
                      style: const TextStyle(color: Colors.white54)),
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
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isUpdating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_save_changes'),
                          style: const TextStyle(color: Colors.white)),
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
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(l10n.translate('hub_join_title'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.translate('hub_join_hint'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 20,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: l10n.translate('hub_join_code_example'),
                      hintStyle: const TextStyle(
                          color: Colors.white54, letterSpacing: 2),
                      filled: true,
                      fillColor: Colors.black26,
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
                      style: const TextStyle(color: Colors.white54)),
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
                              setState(() {
                                _memberStreams[joinedGroup.id] =
                                    _repository.watchMembers(joinedGroup.id);
                                _groupsStream = _repository.watchMyGroups();
                              });
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
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isJoining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.translate('hub_join'),
                          style: const TextStyle(color: Colors.white)),
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
      backgroundColor: const Color(0xFF14241B),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.midGreen,
                    backgroundImage: member.photoUrl != null
                        ? NetworkImage(member.photoUrl!)
                        : null,
                    child: member.photoUrl == null
                        ? Text(
                            member.displayName.isNotEmpty
                                ? member.displayName[0].toUpperCase()
                                : 'M',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member.email,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
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
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      member.role.toValue().toUpperCase(),
                      style: TextStyle(
                        color: member.role.isAdminOrOwner
                            ? AppColors.gold
                            : Colors.white70,
                        fontSize: 10,
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_circle_outlined,
                      color: AppColors.mintGreen, size: 22),
                ),
                title: Text(
                  context.l10n.translate('prof_tab_info'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  context.l10n.translate('prof_posts'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: Colors.white38),
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
              const Divider(color: Colors.white10),
              if (!isMe && member.role != TourRole.owner && viewerIsAdmin) ...[
                // Promote / Demote
                if (viewerIsOwner)
                  ListTile(
                    leading: Icon(
                      member.role == TourRole.admin
                          ? Icons.person_outline
                          : Icons.admin_panel_settings_rounded,
                      color: AppColors.mintGreen,
                    ),
                    title: Text(
                      member.role == TourRole.admin
                          ? context.l10n.translate('hub_remove_admin')
                          : context.l10n.translate('hub_promote_admin'),
                      style: const TextStyle(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: const Color(0xFF14241B),
                          title: Text(
                              context.l10n.translate('hub_transfer_question'),
                              style: const TextStyle(color: Colors.white)),
                          content: Text(
                              context.l10n.translate('hub_transfer_body',
                                  args: {'name': member.displayName}),
                              style: const TextStyle(color: Colors.white70)),
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
                          backgroundColor: const Color(0xFF14241B),
                          title: Text(
                              context.l10n.translate('hub_remove_question'),
                              style: const TextStyle(color: Colors.white)),
                          content: Text(
                              context.l10n.translate('hub_remove_body',
                                  args: {'name': member.displayName}),
                              style: const TextStyle(color: Colors.white70)),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(
                                    context.l10n.translate('tour_cancel'))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
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
                  leading: const Icon(Icons.family_restroom_rounded,
                      color: AppColors.mintGreen),
                  title: Text(
                    context.l10n.translate('hub_family_count_line',
                        args: {'count': member.familyCount}),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    context.l10n.translate('hub_family_count_note'),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
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
}

/// A row for a popup menu: an icon, then a label that wraps rather than overflows.
Widget _menuRow(
  IconData icon,
  String label, {
  Color color = Colors.white,
  Color iconColor = AppColors.mintGreen,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: iconColor),
      const SizedBox(width: 10),
      Flexible(child: Text(label, style: TextStyle(color: color))),
    ],
  );
}

/// The order of the hub's tiles for a trip.
const List<String> _tripModuleOrder = [
  'feed',
  'ledger',
  'seats',
  'calendar',
  'tide',
  'notices',
  'journey',
  'safety',
  'games',
  'quiz',
  'scrapbook',
  'checklist',
  'channels',
  'news',
];

/// The order of the hub's tiles for a family circle: the day-to-day tools first,
/// and the shared news last.
const List<String> _familyModuleOrder = [
  'channels',
  'notices',
  'calendar',
  'safety',
  'feed',
  'ledger',
  'games',
  'news',
];

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

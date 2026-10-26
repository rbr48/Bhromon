import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/tour_group.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class TourGroupHubScreen extends StatefulWidget {
  const TourGroupHubScreen({super.key});

  @override
  State<TourGroupHubScreen> createState() => _TourGroupHubScreenState();
}

class _TourGroupHubScreenState extends State<TourGroupHubScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _activeGroup;
  // The group shown on screen, so the backup button works without a selection.
  TourGroup? _displayedGroup;
  late final Stream<List<TourGroup>> _groupsStream =
      _repository.watchMyGroups();
  final Map<String, Stream<List<TourMember>>> _memberStreams = {};

  Stream<List<TourMember>> _membersOf(String tourId) => _memberStreams
      .putIfAbsent(tourId, () => _repository.watchMembers(tourId));

  bool _viewerIsOwner(List<TourMember> members) =>
      _displayedGroup?.ownerEmail == _repository.currentEmail ||
      members.any((m) =>
          m.email == _repository.currentEmail && m.role == TourRole.owner);

  bool _viewerIsAdmin(List<TourMember> members) => members
      .any((m) => m.email == _repository.currentEmail && m.role.isAdminOrOwner);

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : AppColors.midGreen,
      behavior: SnackBarBehavior.floating,
    ));
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
                'ইনভাইট কোড কপি হয়েছে: $code',
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
          title: const Row(
            children: [
              Icon(Icons.person_add_alt_1,
                  color: AppColors.mintGreen, size: 22),
              SizedBox(width: 8),
              Text(
                'সদস্য যোগ করুন',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'সদস্যের ইমেইল ঠিকানা দিয়ে সরাসরি এই ট্যুর গ্রুপে যুক্ত করুন। ব্যবহারকারী অ্যাপে লগইন করলেই সরাসরি গ্রুপটি দেখতে পাবেন।',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'ইমেইল ঠিকানা *',
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
                    labelText: 'নাম (ঐচ্ছিক)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.badge_outlined,
                        color: Colors.white60),
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
              child:
                  const Text('বাতিল', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              onPressed: isAdding
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim().toLowerCase();
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('সঠিক ইমেইল ঠিকানা দিন')),
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
                        _snack('$email সফলভাবে গ্রুপে যুক্ত হয়েছে');
                      } catch (e) {
                        setDialogState(() => isAdding = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('যোগ করা যায়নি: $e')),
                          );
                        }
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
                  : const Text(
                      'যোগ করুন',
                      style: TextStyle(
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
              for (var n = 1; n <= 10; n++)
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
        final ok = await _confirm(l10n.translate('hub_leave_title'),
            l10n.translate('hub_leave_body', args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.leaveTour(group.id);
          if (mounted) setState(() => _activeGroup = null);
        } catch (e) {
          _reportFailure(e);
        }
      case 'delete':
        final ok = await _confirm(l10n.translate('hub_delete_title'),
            l10n.translate('hub_delete_body', args: {'name': group.name}));
        if (!ok) return;
        try {
          await _repository.deleteTour(group.id, inviteCode: group.inviteCode);
          if (mounted) setState(() => _activeGroup = null);
        } catch (e) {
          _reportFailure(e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          context.l10n.translate('hub_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup_rounded, color: AppColors.gold),
            tooltip: context.l10n.translate('hub_backup_download'),
            onPressed: () {
              final active = _displayedGroup;
              if (active != null) {
                _exportTourJsonBackup(context, active);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined,
                color: AppColors.mintGreen),
            tooltip: context.l10n.translate('hub_join_with_code'),
            onPressed: () => _showJoinGroupDialog(context),
          ),
          IconButton(
            icon:
                const Icon(Icons.add_circle_outline, color: AppColors.midGreen),
            tooltip: context.l10n.translate('hub_create_new_tour'),
            onPressed: () => _showCreateGroupDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<TourGroup>>(
        stream: _groupsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen),
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
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.midGreen),
                      onPressed: () => setState(() {}),
                      child: Text(context.l10n.translate('hub_try_again')),
                    ),
                  ],
                ),
              ),
            );
          }

          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return _buildEmptyState(context);
          }

          final current = _activeGroup != null &&
                  groups.any((g) => g.id == _activeGroup!.id)
              ? groups.firstWhere((g) => g.id == _activeGroup!.id)
              : groups.first;

          _displayedGroup = current;

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
              _buildMembersSection(current.id),
            ],
          );
        },
      ),
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
            )
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
                        '${group.tourType.labelBn.split(' ').first} ${group.destination}',
                        style: const TextStyle(
                          color: AppColors.mintGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
                          child: const Row(
                            children: [
                              Icon(Icons.copy_rounded,
                                  size: 16, color: AppColors.mintGreen),
                              SizedBox(width: 8),
                              Text('ইনভাইট কোড কপি করুন',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          )),
                      if (group.ownerEmail == _repository.currentEmail) ...[
                        PopupMenuItem(
                            value: 'add_member',
                            child: const Row(
                              children: [
                                Icon(Icons.person_add_alt_1,
                                    size: 16, color: AppColors.mintGreen),
                                SizedBox(width: 8),
                                Text('সদস্য যোগ করুন (ইমেইল)',
                                    style: TextStyle(color: Colors.white)),
                              ],
                            )),
                        PopupMenuItem(
                            value: 'code',
                            child: Text(
                                context.l10n.translate('hub_renew_code'),
                                style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text(
                                context.l10n.translate('hub_delete_tour'),
                                style:
                                    const TextStyle(color: Colors.redAccent))),
                      ] else
                        PopupMenuItem(
                            value: 'leave',
                            child: Text(
                                context.l10n.translate('hub_leave_tour'),
                                style: const TextStyle(color: Colors.white))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_calendar_rounded,
                        size: 20, color: AppColors.mintGreen),
                    tooltip: context.l10n.translate('hub_settings_dates'),
                    padding: EdgeInsets.zero,
                    onPressed: () => _showEditGroupDialog(context, group),
                  ),
                  if (allGroups.length > 1) ...[
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: group.id,
                      dropdownColor: const Color(0xFF1B4332),
                      icon: const Icon(Icons.arrow_drop_down,
                          color: Colors.white70),
                      underline: const SizedBox(),
                      items: allGroups.map((g) {
                        return DropdownMenuItem(
                          value: g.id,
                          child: Text(g.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id != null) {
                          setState(() {
                            _activeGroup =
                                allGroups.firstWhere((g) => g.id == id);
                          });
                        }
                      },
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
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 12, color: Colors.white60),
              const SizedBox(width: 5),
              Text(
                '${DateFormat('d MMM yyyy').format(group.startDate)} – ${DateFormat('d MMM yyyy').format(group.endDate)}',
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
          const SizedBox(height: 16),
          Row(
            children: [
              Tooltip(
                message: 'ট্যাপ করে ইনভাইট কোড কপি করুন',
                child: InkWell(
                  onTap: () => _copyInviteCode(group.inviteCode),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        Text(
                          context.l10n.translate('hub_invite_line',
                              args: {'code': group.inviteCode}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.copy_rounded,
                            size: 14, color: AppColors.mintGreen),
                      ],
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

  Widget _buildModulesGrid(BuildContext context, TourGroup group) {
    final modules = [
      _ModuleItem(
        title: context.l10n.translate('hub_module_feed'),
        subtitle: context.l10n.translate('hub_module_feed_sub'),
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFFF43F5E),
        onTap: () => context.push('/group/${group.id}/feed'),
      ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_ledger'),
        subtitle: context.l10n.translate('hub_module_ledger_sub'),
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF52B788),
        onTap: () => context.push('/group/${group.id}/ledger'),
      ),
      if (group.modules.seatsRooms)
        _ModuleItem(
          title: context.l10n.translate('hub_module_seats'),
          subtitle: context.l10n.translate('hub_module_seats_sub'),
          icon: Icons.airline_seat_recline_extra_rounded,
          color: const Color(0xFF6366F1),
          onTap: () => context.push('/group/${group.id}/logistics'),
        ),
      if (group.modules.tideSafety)
        _ModuleItem(
          title: group.tourType == TourType.beach
              ? context.l10n.translate('hub_module_tide')
              : context.l10n.translate('hub_module_weather'),
          subtitle: group.tourType == TourType.beach
              ? context.l10n.translate('hub_module_tide_sub')
              : context.l10n.translate('hub_module_weather_sub'),
          icon: group.tourType == TourType.beach
              ? Icons.waves_rounded
              : Icons.wb_sunny_rounded,
          color: const Color(0xFF38BDF8),
          onTap: () => context.push('/group/${group.id}/tide'),
        ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_notices'),
        subtitle: context.l10n.translate('hub_module_notices_sub'),
        icon: Icons.campaign_rounded,
        color: const Color(0xFFEAB308),
        onTap: () => context.push('/group/${group.id}/notices'),
      ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_journey'),
        subtitle: context.l10n.translate('hub_journey_sub', args: {
          'origin': group.originCity,
          'destination': group.destination
        }),
        icon: Icons.alt_route_rounded,
        color: const Color(0xFF10B981),
        onTap: () => context.push('/group/${group.id}/journey'),
      ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_safety'),
        subtitle: context.l10n.translate('hub_module_safety_sub'),
        icon: Icons.shield_rounded,
        color: const Color(0xFFEF4444),
        onTap: () => context.push('/group/${group.id}/safety'),
      ),
      if (group.modules.games)
        _ModuleItem(
          title: context.l10n.translate('hub_module_games'),
          subtitle: context.l10n.translate('hub_module_games_sub'),
          icon: Icons.sports_esports_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => context.push('/game-zone'),
        ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_quiz'),
        subtitle: context.l10n.translate('hub_quiz_sub',
            args: {'destination': group.destination}),
        icon: Icons.quiz_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => context.push('/group/${group.id}/quiz'),
      ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_scrapbook'),
        subtitle: context.l10n.translate('hub_module_scrapbook_sub'),
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFFD97706),
        onTap: () => context.push('/group/${group.id}/scrapbook'),
      ),
      _ModuleItem(
        title: context.l10n.translate('hub_module_checklist'),
        subtitle: context.l10n.translate('hub_module_checklist_sub'),
        icon: Icons.checklist_rtl_rounded,
        color: const Color(0xFF14B8A6),
        onTap: () => context.push('/group/${group.id}/checklist'),
      ),
      if (group.modules.chat)
        _ModuleItem(
          title: context.l10n.translate('hub_module_channels'),
          subtitle: context.l10n.translate('hub_module_channels_sub'),
          icon: Icons.forum_rounded,
          color: const Color(0xFFEC4899),
          onTap: () => context.push('/group/${group.id}/channels'),
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.35,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
  }

  Widget _buildMembersSection(String tourId) {
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
                    label: const Text(
                      'সদস্য যোগ করুন',
                      style: TextStyle(
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
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
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
                      viewerIsOwner: _viewerIsOwner(members),
                      viewerIsAdmin: _viewerIsAdmin(members),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.midGreen,
                      backgroundImage:
                          m.photoUrl != null ? NetworkImage(m.photoUrl!) : null,
                      child: m.photoUrl == null
                          ? Text(m.displayName.isNotEmpty
                              ? m.displayName[0].toUpperCase()
                              : 'E')
                          : null,
                    ),
                    title: Text(m.displayName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        _viewerIsAdmin(members)
                            ? m.email
                            : (m.role.isAdminOrOwner
                                ? context.l10n.translate('hub_role_admin')
                                : context.l10n.translate('hub_role_member')),
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
          ],
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
              title: const Text('নতুন ট্যুর গ্রুপ তৈরি করুন (Universal)',
                  style: TextStyle(
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
                          labelText: 'ট্যুরের নাম (যেমন: সাজেক ক্লাউড ট্যুর)',
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
                      const Text(
                        'জনপ্রিয় গন্তব্যসমূহ (Quick Select):',
                        style: TextStyle(
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
                                      '${DateFormat('d MMM yyyy').format(startDate)} – ${DateFormat('d MMM yyyy').format(endDate)}',
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
                              setState(() {
                                _activeGroup = newGroup;
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
                                      '${DateFormat('d MMM yyyy').format(startDate)} – ${DateFormat('d MMM yyyy').format(endDate)}',
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
                                _activeGroup = group.copyWith(
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
                              setState(() {
                                _activeGroup = joinedGroup;
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

  Future<void> _exportTourJsonBackup(
      BuildContext context, TourGroup group) async {
    try {
      final snapshot = await _repository.fetchFullTourSnapshot(group.id);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(snapshot);
      final fileName =
          '${group.name.replaceAll(' ', '_')}_Backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.json';
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(jsonStr)),
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        subject: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('hub_backup_failed', args: {'error': e}))),
        );
      }
    }
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
              const SizedBox(height: 20),
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

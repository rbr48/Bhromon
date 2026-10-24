import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/tour_group.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Family & Tour Groups',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup_rounded, color: AppColors.gold),
            tooltip: 'JSON ব্যাকআপ ডাউনলোড',
            onPressed: () {
              final active = _activeGroup;
              if (active != null) {
                _exportTourJsonBackup(context, active);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined, color: AppColors.mintGreen),
            tooltip: 'Join with code',
            onPressed: () => _showJoinGroupDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.midGreen),
            tooltip: 'Create new tour',
            onPressed: () => _showCreateGroupDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<TourGroup>>(
        stream: _repository.watchMyGroups(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen),
            );
          }

          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return _buildEmptyState(context);
          }

          final current = _activeGroup ?? groups.first;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Active Tour Card
              _buildActiveTourBanner(context, current, groups),
              const SizedBox(height: 24),

              // 2. Feature Launchpad Grid
              const Text(
                'Tour Modules & Operations',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              _buildModulesGrid(context, current),

              const SizedBox(height: 28),

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
            const Text(
              'No Active Tour Groups',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Create a group for your family or friends, or join one with an invite code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateGroupDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Tour'),
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
                  label: const Text('Enter Code'),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Destination: ${group.destination}',
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (allGroups.length > 1)
                DropdownButton<String>(
                  value: group.id,
                  dropdownColor: const Color(0xFF1B4332),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                  underline: const SizedBox(),
                  items: allGroups.map((g) {
                    return DropdownMenuItem(
                      value: g.id,
                      child: Text(g.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      setState(() {
                        _activeGroup = allGroups.firstWhere((g) => g.id == id);
                      });
                    }
                  },
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded,
                        size: 14, color: AppColors.gold),
                    const SizedBox(width: 6),
                    Text(
                      'Invite: ${group.inviteCode}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
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
        title: 'Tour InstaFeed 📸',
        subtitle: 'ফটো, রিলস ও স্টোরিজ',
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFFF43F5E),
        onTap: () => context.push('/group/${group.id}/feed'),
      ),
      _ModuleItem(
        title: 'Shared Fund & Ledger',
        subtitle: 'Paisa-precise Splitwise',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF52B788),
        onTap: () => context.push('/group/${group.id}/ledger'),
      ),
      _ModuleItem(
        title: 'Bus Seats & Rooms',
        subtitle: 'Seat & room allocators',
        icon: Icons.airline_seat_recline_extra_rounded,
        color: const Color(0xFF6366F1),
        onTap: () => context.push('/group/${group.id}/logistics'),
      ),
      _ModuleItem(
        title: 'Tide & Beach Guide',
        subtitle: 'High/low tide & danger flags',
        icon: Icons.waves_rounded,
        color: const Color(0xFF38BDF8),
        onTap: () => context.push('/group/${group.id}/tide'),
      ),
      _ModuleItem(
        title: 'Notice Board 📌',
        subtitle: 'মিটিং পয়েন্ট ও জরুরি নোটিশ',
        icon: Icons.campaign_rounded,
        color: const Color(0xFFEAB308),
        onTap: () => context.push('/group/${group.id}/notices'),
      ),
      _ModuleItem(
        title: 'Highway Roadmap 🛣️',
        subtitle: '৮২০ কিমি জার্নি ট্র্যাকার',
        icon: Icons.alt_route_rounded,
        color: const Color(0xFF10B981),
        onTap: () => context.push('/group/${group.id}/journey'),
      ),
      _ModuleItem(
        title: 'Safety Hub & SOS 🚨',
        subtitle: 'বিচ কম্পাস ও হেল্পলাইন',
        icon: Icons.shield_rounded,
        color: const Color(0xFFEF4444),
        onTap: () => context.push('/group/${group.id}/safety'),
      ),
      _ModuleItem(
        title: 'Family GameZone 🎮',
        subtitle: '29, Chess, Ludo & Teen Patti',
        icon: Icons.sports_esports_rounded,
        color: const Color(0xFFF59E0B),
        onTap: () => context.push('/game-zone'),
      ),
      _ModuleItem(
        title: 'Tour Quiz 🎯',
        subtitle: 'কক্সবাজার ট্রাভেল কুইজ',
        icon: Icons.quiz_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => context.push('/group/${group.id}/quiz'),
      ),
      _ModuleItem(
        title: 'Digital Scrapbook 📖',
        subtitle: 'স্মৃতি অ্যালবাম ও ম্যাগাজিন',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFFD97706),
        onTap: () => context.push('/group/${group.id}/scrapbook'),
      ),
      _ModuleItem(
        title: 'Discussion Channels 💬',
        subtitle: '#general, #food, #emergency',
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
        childAspectRatio: 1.15,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final m = modules[index];
        return GestureDetector(
          onTap: m.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF14241B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: m.color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: m.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(m.icon, color: m.color, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMembersSection(String tourId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Tour Members',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<TourMember>>(
          stream: _repository.watchMembers(tourId),
          builder: (context, snapshot) {
            final members = snapshot.data ?? [];
            if (members.isEmpty) {
              return const Text('Loading members...',
                  style: TextStyle(color: Colors.white54));
            }

            return Container(
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
                    onTap: () => _showManageMemberSheet(context, tourId, m),
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
                    subtitle: Text(m.email,
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
            );
          },
        ),
      ],
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final destCtrl = TextEditingController(text: "Cox's Bazar");

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Create Tour Group',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Tour Name (e.g. Cox Tour 2026)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: destCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                await _repository.createGroup(
                  name: name,
                  description: descCtrl.text.trim(),
                  destination: destCtrl.text.trim(),
                  startDate: DateTime.now(),
                  endDate: DateTime.now().add(const Duration(days: 4)),
                );
              },
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showJoinGroupDialog(BuildContext context) {
    final codeCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Join Tour Group',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the 6-character tour invite code shared by your tour admin.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
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
                  hintText: 'e.g. 7X9A2F',
                  hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 2),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.mintGreen),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                if (code.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await _repository.joinGroupWithCode(code);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Successfully joined tour group!'),
                        backgroundColor: AppColors.midGreen,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              child: const Text('Join', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportTourJsonBackup(BuildContext context, TourGroup group) async {
    try {
      final snapshot = await _repository.fetchFullTourSnapshot(group.id);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(snapshot);
      final fileName = '${group.name.replaceAll(' ', '_')}_Backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.json';
      // ignore: deprecated_member_use
      await Share.share(
        jsonStr,
        subject: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ব্যাকআপ তৈরিতে ত্রুটি: $e')),
        );
      }
    }
  }

  void _showManageMemberSheet(
      BuildContext context, String tourId, TourMember member) {
    final currentEmail = _repository.currentEmail;
    final isMe = currentEmail != null && currentEmail.toLowerCase() == member.email.toLowerCase();

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
              if (!isMe && member.role != TourRole.owner) ...[
                // Promote / Demote
                ListTile(
                  leading: Icon(
                    member.role == TourRole.admin
                        ? Icons.person_outline
                        : Icons.admin_panel_settings_rounded,
                    color: AppColors.mintGreen,
                  ),
                  title: Text(
                    member.role == TourRole.admin
                        ? 'Remove Admin Role'
                        : 'Promote to Tour Admin',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final newRole = member.role == TourRole.admin
                        ? TourRole.member
                        : TourRole.admin;
                    await _repository.updateMemberRole(tourId, member.email, newRole);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${member.displayName} এর রোল পরিবর্তন করা হয়েছে')),
                      );
                    }
                  },
                ),
                // Transfer Ownership
                ListTile(
                  leading: const Icon(Icons.stars_rounded, color: AppColors.gold),
                  title: const Text(
                    'Transfer Tour Ownership',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF14241B),
                        title: const Text('মালিকানা হস্তান্তর করবেন?', style: TextStyle(color: Colors.white)),
                        content: Text('আপনি কি নিশ্চিত যে ${member.displayName} কে এই ট্যুরের প্রধান মালিক করবেন?', style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('হস্তান্তর করুন'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _repository.transferOwnership(tourId, member.email);
                    }
                  },
                ),
                // Remove Member
                ListTile(
                  leading: const Icon(Icons.person_remove_rounded, color: Colors.redAccent),
                  title: const Text(
                    'Remove from Tour',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF14241B),
                        title: const Text('সদস্য অপসারণ', style: TextStyle(color: Colors.white)),
                        content: Text('${member.displayName} কে ট্যুর গ্রুপ থেকে বাদ দিতে চান?', style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('বাতিল')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('অপসারণ করুন'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _repository.removeMember(tourId, member.email);
                    }
                  },
                ),
              ] else if (isMe) ...[
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'এটি আপনার প্রোফাইল। আপনি ট্যুরের সক্রিয় সদস্য।',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
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

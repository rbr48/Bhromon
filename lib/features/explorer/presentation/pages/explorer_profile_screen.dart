import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/services/media_upload_service.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../../tour_group/domain/models/tour_group.dart';
import '../../../tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import '../../domain/usecases/get_explorer_profile_usecase.dart';
import '../../../game_zone/presentation/widgets/game_analytics_view.dart';

/// The modern, Tour Group-Centric Profile Screen for Bhromon Travelers.
/// Replaces the legacy public social/YouTube architecture with live
/// tour groups, digital scrapbooks, offline vault, and personal settings.
class ExplorerProfileScreen extends StatefulWidget {
  final String uid;

  const ExplorerProfileScreen({super.key, required this.uid});

  @override
  State<ExplorerProfileScreen> createState() => _ExplorerProfileScreenState();
}

class _ExplorerProfileScreenState extends State<ExplorerProfileScreen> {
  late final GetExplorerProfileUseCase _getExplorerProfile;
  final TourGroupRepository _tourRepo = TourGroupRepository();

  ExplorerProfile? _profile;
  bool _isLoading = false;
  String? _error;
  DocumentSnapshot? _rawProfileDoc;
  String? _bloodGroup;
  String? _statusNote;
  String _activeCategory = 'all';

  // Active tab: 'tours' | 'vault' | 'settings'
  String _activeTab = 'tours';
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _getExplorerProfile = getIt<GetExplorerProfileUseCase>();
    _loadProfile();
  }

  bool get _isBn => LocaleController.instance.locale.languageCode == 'bn';

  Future<void> _loadProfile() async {
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final targetUid = (widget.uid == 'guest' ||
            widget.uid.isEmpty ||
            widget.uid == 'explorer_user')
        ? (currentUid.isNotEmpty ? currentUid : 'explorer_user')
        : widget.uid;

    if (targetUid == 'explorer_user') {
      setState(() {
        _isGuest = true;
        _isLoading = false;
        _error = null;
      });
      return;
    }
    _isGuest = false;

    if (_profile == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final either = await _getExplorerProfile(targetUid);
      final profile = either.fold(
        (failure) {
          if (authState is Authenticated &&
              authState.profile.uid == targetUid) {
            return authState.profile;
          }
          throw Exception(failure.message);
        },
        (p) => p,
      );

      final rawDoc = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(profile.uid)
          .get();

      if (mounted) {
        final data = rawDoc.data();
        setState(() {
          _profile = profile;
          _rawProfileDoc = rawDoc;
          _bloodGroup = data?['bloodGroup'] as String?;
          _statusNote =
              data?['statusNote'] as String? ?? data?['note'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _getDisplayBio(ExplorerProfile profile) {
    final rawData = _rawProfileDoc?.data() as Map<String, dynamic>?;
    if (_isBn) {
      final bn = rawData?['bioBangla'] as String?;
      if (bn != null && bn.trim().isNotEmpty) return bn.trim();
    } else {
      final en = rawData?['bioEnglish'] as String?;
      if (en != null && en.trim().isNotEmpty) return en.trim();
    }
    return profile.bio?.trim() ?? '';
  }

  Future<void> _editStatusNote(BuildContext context, bool isOwnProfile) async {
    if (!isOwnProfile) return;
    final ctrl = TextEditingController(text: _statusNote ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B3326),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.mintGreen),
            const SizedBox(width: 8),
            Text(
              _isBn ? 'স্ট্যাটাস নোট' : 'Status Note',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 80,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: _isBn
                ? 'আজকের অনুভূতি বা নোট লিখুন...'
                : 'Write your travel note or mood...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.mintGreen)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _isBn ? 'বাতিল' : 'Cancel',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(
              _isBn ? 'সংরক্ষণ' : 'Save',
              style: const TextStyle(
                  color: AppColors.darkGreen, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() => _statusNote = result.isEmpty ? null : result);
      final uid = _profile?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(uid)
              .set({'statusNote': result}, SetOptions(merge: true));
        } catch (_) {}
      }
    }
  }

  Future<void> _editBloodGroup(BuildContext context, bool isOwnProfile) async {
    if (!isOwnProfile) return;
    const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
    String chosen = _bloodGroup ?? 'O+';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1B3326),
          title: Row(
            children: [
              const Icon(Icons.bloodtype_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                _isBn ? 'রক্তের গ্রুপ' : 'Blood Group',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          content: DropdownButtonFormField<String>(
            initialValue: groups.contains(chosen) ? chosen : 'O+',
            dropdownColor: const Color(0xFF14241B),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.mintGreen)),
            ),
            items: [
              for (final g in groups)
                DropdownMenuItem(value: g, child: Text(g)),
            ],
            onChanged: (v) {
              if (v != null) setDialog(() => chosen = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                _isBn ? 'বাতিল' : 'Cancel',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              onPressed: () => Navigator.pop(ctx, chosen),
              child: Text(
                _isBn ? 'সংরক্ষণ' : 'Save',
                style: const TextStyle(
                    color: AppColors.darkGreen, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _bloodGroup = result);
      final uid = _profile?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(uid)
              .set({'bloodGroup': result}, SetOptions(merge: true));
        } catch (_) {}
      }
    }
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final isOwnProfile =
        currentUid.isNotEmpty && (_profile?.uid ?? widget.uid) == currentUid;

    final email = _tourRepo.currentEmail;
    final rawHandle = email.isNotEmpty
        ? email.split('@').first
        : (_profile?.displayName.toLowerCase().replaceAll(' ', '_') ??
            'explorer');
    final handle = rawHandle.replaceAll(RegExp(r'[^a-zA-Z0-9_.]'), '');

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1A12),
        appBar: AppBar(
          title: Text(
            '@$handle',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0D1A12),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            tooltip: _isBn ? 'ফিরে যান' : 'Back',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  color: Colors.white70, size: 20),
              tooltip: _isBn ? 'শেয়ার করুন' : 'Share Profile',
              onPressed: () {
                final name = _profile?.displayName ?? 'Traveler';
                SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Check out $name (@$handle) on Bhromon — Bangladesh Smart Tour Operating System!\nhttps://app.bhromon.fun',
                  ),
                );
              },
            ),
            if (isOwnProfile) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.mintGreen, size: 20),
                tooltip: _isBn ? 'প্রোফাইল পরিবর্তন' : 'Edit Profile',
                onPressed: () {
                  if (_profile != null) {
                    _showEditProfileBottomSheet(_profile!);
                  }
                },
              ),
              IconButton(
                icon:
                    const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                tooltip: _isBn ? 'লগআউট' : 'Log out',
                onPressed: () => _confirmLogout(context),
              ),
            ],
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: RefreshIndicator(
              onRefresh: _loadProfile,
              color: AppColors.mintGreen,
              child: _buildBody(isOwnProfile),
            ),
          ),
        ),
        bottomNavigationBar: BhromonBottomNav(
          selectedIndex: 4,
          tourId: TourGroupRepository.lastActiveTourId,
        ),
      ),
    );
  }

  Widget _buildBody(bool isOwnProfile) {
    if (_isGuest) {
      return _buildGuestPrompt();
    }

    if (_isLoading && _profile == null) {
      return _buildProfileSkeleton();
    }

    if (_error != null && _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _isBn
                    ? 'প্রোফাইল লোড করা সম্ভব হয়নি: $_error'
                    : 'Failed to load profile: $_error',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: Colors.black),
                child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_profile == null) {
      return const SizedBox.shrink();
    }

    final profile = _profile!;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return StreamBuilder<List<TourGroup>>(
      stream: _tourRepo.watchMyGroups(),
      builder: (context, groupsSnap) {
        final groups = groupsSnap.data ?? [];
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomInset + 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Cover & Avatar Header
              _buildCoverAndAvatar(profile, isOwnProfile),
              const SizedBox(height: 54),

              // 2. User Info & Bio
              _buildUserInfo(profile, isOwnProfile),
              const SizedBox(height: 16),

              // 3. Tour Group Metrics Summary Bar
              _buildTourMetricsBar(groups),
              const SizedBox(height: 18),

              // 4. Tour Action Buttons (Create Tour, Join Tour, Share, Settings)
              if (isOwnProfile) ...[
                _buildTourActionButtons(profile),
                const SizedBox(height: 20),
              ],

              // 5. Story Category Circles (হাইজলাইটস / ক্যাটাগরি)
              _buildCategoryCircles(),
              const SizedBox(height: 20),

              // 6. Achievements Showcase (অর্জনের শোকেস)
              _buildAchievementsShowcase(groups),
              const SizedBox(height: 20),

              // 7. Segmented Navigation Tabs
              _buildSegmentedTabs(),
              const SizedBox(height: 16),

              // 6. Active Tab Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildActiveTabContent(profile, groups, isOwnProfile),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Header Widgets
  // ---------------------------------------------------------------------------

  Widget _buildCoverAndAvatar(ExplorerProfile profile, bool isOwnProfile) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Cover Image
        GestureDetector(
          onTap: () {
            if (isOwnProfile) _showEditProfileBottomSheet(profile);
          },
          child: Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(
              image: profile.coverUrl != null
                  ? DecorationImage(
                      image: sizedImage(
                        CachedNetworkImageProvider(
                          profile.coverUrl!,
                          errorListener: (dynamic error) {},
                        ),
                        context.decodeWidth(),
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
              gradient: profile.coverUrl == null
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF081C15),
                        Color(0xFF1B4332),
                        Color(0xFF2D6A4F),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.65),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (isOwnProfile)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _isBn ? 'কভার পরিবর্তন' : 'Edit Cover',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Overlapping Avatar
        Positioned(
          bottom: -46,
          child: GestureDetector(
            onTap: () {
              if (isOwnProfile) _showEditProfileBottomSheet(profile);
            },
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D1A12),
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF58529),
                          Color(0xFFFEDA77),
                          Color(0xFFDD2A7B),
                          Color(0xFF8134AF),
                          Color(0xFF515BD4),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFDD2A7B).withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFF1B4332),
                      backgroundImage: profile.avatarUrl != null
                          ? sizedImage(
                              CachedNetworkImageProvider(
                                profile.avatarUrl!,
                                errorListener: (dynamic error) {},
                              ),
                              context.decodeWidth(92),
                            )
                          : null,
                      child: profile.avatarUrl == null
                          ? Text(
                              profile.displayName.isNotEmpty
                                  ? profile.displayName[0].toUpperCase()
                                  : 'T',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                if (isOwnProfile)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF0D1A12), width: 2),
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.black, size: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfo(ExplorerProfile profile, bool isOwnProfile) {
    final bio = _getDisplayBio(profile);
    final email = _tourRepo.currentEmail;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Status Note bubble above name
          GestureDetector(
            onTap: () => _editStatusNote(context, isOwnProfile),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOwnProfile &&
                      (_statusNote == null || _statusNote!.isEmpty))
                    const Icon(Icons.add, size: 12, color: AppColors.mintGreen),
                  Text(
                    (_statusNote != null && _statusNote!.isNotEmpty)
                        ? _statusNote!
                        : (isOwnProfile
                            ? (_isBn ? '+ নোট যুক্ত করুন' : '+ Add Note')
                            : (_isBn ? 'ভ্রমণকারী নোট' : 'Traveler Note')),
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Display Name
          Text(
            profile.displayName.isNotEmpty ? profile.displayName : 'Traveler',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // User Tag / Email Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_rounded,
                    size: 13, color: AppColors.mintGreen),
                const SizedBox(width: 5),
                Text(
                  email.isNotEmpty
                      ? email
                      : (_isBn ? 'ভ্রমণকারী সদস্য' : 'Tour Traveler'),
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Logistics & Blood Group detail chips
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildDetailChip(
                icon: Icons.hotel_rounded,
                text: _isBn ? 'রিসোর্ট অতিথি' : 'Resort Guest',
                color: Colors.amberAccent,
              ),
              _buildDetailChip(
                icon: Icons.directions_bus_rounded,
                text: _isBn ? 'এক্সপ্রেস সিট' : 'Express Seat',
                color: Colors.cyanAccent,
              ),
              GestureDetector(
                onTap: isOwnProfile
                    ? () => _editBloodGroup(context, isOwnProfile)
                    : null,
                child: _buildDetailChip(
                  icon: Icons.bloodtype_rounded,
                  text: _bloodGroup != null && _bloodGroup!.isNotEmpty
                      ? '🩸 $_bloodGroup'
                      : (isOwnProfile
                          ? (_isBn ? '🩸 + রক্তের গ্রুপ' : '🩸 + Blood Group')
                          : '🩸 O+'),
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bio
          if (bio.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                bio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          if (isOwnProfile)
            GestureDetector(
              onTap: () => _showEditProfileBottomSheet(profile),
              child: Text(
                bio.isEmpty
                    ? (_isBn ? '+ বায়ো যুক্ত করুন' : '+ Add Bio')
                    : (_isBn ? 'বায়ো পরিবর্তন করুন' : 'Edit Bio'),
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tour Metrics Summary Bar (4-metric Stats)
  // ---------------------------------------------------------------------------

  Widget _buildTourMetricsBar(List<TourGroup> groups) {
    final email = _tourRepo.currentEmail;
    final ownedCount = groups.where((g) => g.ownerEmail == email).length;
    final totalDays = groups.fold<int>(0, (acc, g) {
      final days = g.endDate.difference(g.startDate).inDays + 1;
      return acc + (days > 0 ? days : 1);
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem(
            '${groups.length}',
            _isBn ? 'ট্যুর গ্রুপ' : 'Tour Groups',
            Icons.groups_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            '$ownedCount',
            _isBn ? 'পরিচালিত' : 'Organized',
            Icons.stars_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            '$totalDays',
            _isBn ? 'ভ্রমণ দিন' : 'Tour Days',
            Icons.calendar_month_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            _isBn ? 'সক্রিয়' : 'Active',
            _isBn ? 'লেজার' : 'Ledger',
            Icons.account_balance_wallet_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String value, String label, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.mintGreen),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Action Buttons
  // ---------------------------------------------------------------------------

  Widget _buildTourActionButtons(ExplorerProfile profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Create Tour Button (Primary Mint)
          Expanded(
            flex: 4,
            child: ElevatedButton.icon(
              onPressed: () => _showCreateGroupDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_circle, size: 18),
              label: Text(
                _isBn ? 'নতুন ট্যুর' : 'Create Tour',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Join Tour with Code Button
          Expanded(
            flex: 4,
            child: OutlinedButton.icon(
              onPressed: () => _showJoinGroupDialog(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.mintGreen,
                side: const BorderSide(color: AppColors.mintGreen, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: Text(
                _isBn ? 'কোডে যোগ' : 'Join Tour',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Share Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              onPressed: () {
                final text =
                    '${profile.displayName} — Bhromon Traveler\nhttps://app.bhromon.fun';
                SharePlus.instance.share(ShareParams(text: text));
              },
              tooltip: _isBn ? 'শেয়ার' : 'Share',
              icon: const Icon(Icons.share_outlined,
                  color: Colors.white70, size: 20),
            ),
          ),
          const SizedBox(width: 8),

          // Settings Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              onPressed: () => context.push('/settings'),
              tooltip: _isBn ? 'সেটিংস' : 'Settings',
              icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Story Category Circles (হাইজলাইটস / ক্যাটাগরি)
  // ---------------------------------------------------------------------------

  Widget _buildCategoryCircles() {
    final categories = [
      (
        id: 'all',
        label: _isBn ? 'সব ট্যুর' : 'All Tours',
        icon: Icons.wb_sunny_rounded,
        color: AppColors.gold,
      ),
      (
        id: 'beach',
        label: _isBn ? 'সি-বিচ' : 'Sea Beach',
        icon: Icons.beach_access_rounded,
        color: Colors.lightBlueAccent,
      ),
      (
        id: 'hills',
        label: _isBn ? 'পাহাড় ও ঝর্ণা' : 'Hills & Treks',
        icon: Icons.terrain_rounded,
        color: AppColors.mintGreen,
      ),
      (
        id: 'food',
        label: _isBn ? 'সি-ফুড' : 'Sea Food',
        icon: Icons.restaurant_rounded,
        color: Colors.orangeAccent,
      ),
      (
        id: 'journey',
        label: _isBn ? 'বাস জার্নি' : 'Bus Journey',
        icon: Icons.directions_bus_rounded,
        color: Colors.cyanAccent,
      ),
      (
        id: 'sunset',
        label: _isBn ? 'সানসেট' : 'Sunset',
        icon: Icons.wb_twilight_rounded,
        color: Colors.deepOrangeAccent,
      ),
      (
        id: 'hotel',
        label: _isBn ? 'হোটেল' : 'Hotel',
        icon: Icons.hotel_rounded,
        color: Colors.pinkAccent,
      ),
      (
        id: 'hangout',
        label: _isBn ? 'আড্ডা' : 'Hangout',
        icon: Icons.celebration_rounded,
        color: Colors.purpleAccent,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, i) {
            final cat = categories[i];
            final isSelected = _activeCategory == cat.id;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _activeCategory = cat.id);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? cat.color : Colors.white24,
                        width: isSelected ? 2.2 : 1.0,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: isSelected
                          ? cat.color.withValues(alpha: 0.25)
                          : const Color(0xFF182630),
                      child: Icon(cat.icon,
                          size: 20,
                          color: isSelected ? cat.color : Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    cat.label,
                    style: TextStyle(
                      color: isSelected ? cat.color : Colors.white60,
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Achievements Showcase (অর্জনের শোকেস)
  // ---------------------------------------------------------------------------

  Widget _buildAchievementsShowcase(List<TourGroup> groups) {
    final achievements = <({String title, IconData icon, Color color})>[
      (
        title: _isBn ? 'ফটোগ্রাফার' : 'Photographer',
        icon: Icons.camera_alt_rounded,
        color: Colors.blueAccent,
      ),
      (
        title: _isBn ? 'রিলস ডিরেক্টর' : 'Reels Director',
        icon: Icons.movie_creation_rounded,
        color: Colors.purpleAccent,
      ),
      (
        title: _isBn ? 'স্টার ট্রাভেলার' : 'Star Traveler',
        icon: Icons.star_rounded,
        color: AppColors.gold,
      ),
      if (_bloodGroup != null && _bloodGroup!.isNotEmpty)
        (
          title: _isBn ? 'লাইফ সেভার' : 'Life Saver',
          icon: Icons.favorite_rounded,
          color: Colors.redAccent,
        ),
      (
        title: _isBn ? 'স্পট এক্সপ্লোরার' : 'Spot Explorer',
        icon: Icons.hotel_rounded,
        color: AppColors.mintGreen,
      ),
      if (groups.isNotEmpty)
        (
          title: _isBn ? 'টপ কন্ট্রিবিউটর' : 'Top Contributor',
          icon: Icons.account_balance_wallet_rounded,
          color: Colors.amber,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              Text(
                '${_isBn ? 'অর্জনের শোকেস' : 'Achievements'} (${achievements.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: achievements.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final a = achievements[i];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14241B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: a.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.icon, size: 14, color: a.color),
                      const SizedBox(width: 6),
                      Text(
                        a.title,
                        style: TextStyle(
                          color: a.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segmented Tabs
  // ---------------------------------------------------------------------------

  Widget _buildSegmentedTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabItem(
            'tours',
            Icons.explore_rounded,
            _isBn ? 'ট্যুরসমূহ' : 'My Tours',
          ),
          _buildTabItem(
            'games',
            Icons.emoji_events_rounded,
            _isBn ? 'গেমিং' : 'Games',
          ),
          _buildTabItem(
            'vault',
            Icons.folder_shared_rounded,
            _isBn ? 'স্মৃতি' : 'Vault',
          ),
          _buildTabItem(
            'settings',
            Icons.tune_rounded,
            _isBn ? 'সেটিংস' : 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(String key, IconData icon, String label) {
    final isActive = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.mintGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.black : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab Content
  // ---------------------------------------------------------------------------

  Widget _buildActiveTabContent(
    ExplorerProfile profile,
    List<TourGroup> groups,
    bool isOwnProfile,
  ) {
    switch (_activeTab) {
      case 'vault':
        return _buildKeepsakesTab(groups);
      case 'games':
        return const GameAnalyticsView();
      case 'settings':
        return _buildPreferencesTab(profile);
      case 'tours':
      default:
        return _buildMyToursTab(groups, isOwnProfile);
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 1: My Tours
  // ---------------------------------------------------------------------------

  Widget _buildMyToursTab(List<TourGroup> groups, bool isOwnProfile) {
    if (groups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF14241B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            const Icon(Icons.travel_explore_rounded,
                size: 56, color: AppColors.mintGreen),
            const SizedBox(height: 14),
            Text(
              _isBn ? 'কোনো ট্যুর গ্রুপ পাওয়া যায়নি' : 'No Tour Groups Found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isBn
                  ? 'নতুন ট্যুর তৈরি করুন অথবা কোড দিয়ে বন্ধুর ট্যুরে যোগ দিন।'
                  : 'Create a new tour or join with an invite code.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateGroupDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(_isBn ? 'ট্যুর তৈরি' : 'Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.midGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _showJoinGroupDialog(context),
                  icon: const Icon(Icons.key, size: 16),
                  label: Text(_isBn ? 'যোগ দিন' : 'Join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mintGreen,
                    side: const BorderSide(color: AppColors.mintGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final email = _tourRepo.currentEmail;
    final filteredGroups = switch (_activeCategory) {
      'beach' => groups
          .where((g) =>
              g.name.toLowerCase().contains('cox') ||
              g.name.toLowerCase().contains('beach') ||
              g.name.toLowerCase().contains('kuakata') ||
              g.name.toLowerCase().contains('martin') ||
              g.destination.toLowerCase().contains('cox') ||
              g.destination.toLowerCase().contains('beach') ||
              g.destination.toLowerCase().contains('kuakata'))
          .toList(),
      'hills' => groups
          .where((g) =>
              g.name.toLowerCase().contains('sajek') ||
              g.name.toLowerCase().contains('bandarban') ||
              g.name.toLowerCase().contains('hill') ||
              g.name.toLowerCase().contains('sylhet') ||
              g.destination.toLowerCase().contains('sajek') ||
              g.destination.toLowerCase().contains('bandarban') ||
              g.destination.toLowerCase().contains('hill'))
          .toList(),
      _ => groups,
    };
    final displayGroups = filteredGroups.isEmpty ? groups : filteredGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isBn
                  ? 'সক্রিয় ও পূর্বের ট্যুর (${displayGroups.length})'
                  : 'Active & Past Tours (${displayGroups.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showJoinGroupDialog(context),
              icon: const Icon(Icons.add, size: 15, color: AppColors.mintGreen),
              label: Text(
                _isBn ? 'কোড দিয়ে যোগ' : 'Join by Code',
                style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayGroups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final group = displayGroups[index];
            final isOwner = group.ownerEmail == email;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B4332), Color(0xFF112217)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Role Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📍 ${group.destination}  ·  ${group.tourType.labelBn.split(' ').first}',
                              style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOwner
                              ? AppColors.gold.withValues(alpha: 0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isOwner
                                ? AppColors.gold.withValues(alpha: 0.5)
                                : Colors.white24,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isOwner
                              ? (_isBn ? '👑 ওনার' : 'Owner')
                              : (_isBn ? '🎒 সদস্য' : 'Member'),
                          style: TextStyle(
                            color: isOwner ? AppColors.gold : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Dates and Duration
                  Row(
                    children: [
                      const Icon(Icons.date_range_rounded,
                          size: 14, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text(
                        '${DateFormat('d MMM yyyy').format(group.startDate)} – ${DateFormat('d MMM yyyy').format(group.endDate)}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '⏱️ ${group.durationText}',
                        style: const TextStyle(
                          color: AppColors.mintGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Bottom action buttons on card
                  Row(
                    children: [
                      // Copy Invite Code Pill
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: group.inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isBn
                                    ? 'ইনভাইট কোড কপি হয়েছে: ${group.inviteCode}'
                                    : 'Invite code copied: ${group.inviteCode}',
                              ),
                              backgroundColor: AppColors.midGreen,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy_rounded,
                                  size: 12, color: AppColors.mintGreen),
                              const SizedBox(width: 4),
                              Text(
                                group.inviteCode,
                                style: const TextStyle(
                                  color: AppColors.mintGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Go to Hub / Open Tour
                      ElevatedButton.icon(
                        onPressed: () {
                          TourGroupRepository.lastActiveTourId = group.id;
                          context.go('/group-hub');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.midGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: Text(
                          _isBn ? 'ট্যুর হাব খুলুন' : 'Open Hub',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Keepsakes & Vault
  // ---------------------------------------------------------------------------

  Widget _buildKeepsakesTab(List<TourGroup> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isBn
              ? 'ট্যুর স্মৃতি ও অফলাইন ভল্ট'
              : 'Trip Keepsakes & Offline Vault',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // 1. Digital Scrapbooks Card
        _buildKeepsakeCard(
          title: _isBn
              ? 'ট্যুর ম্যাগাজিন ও স্ক্র্যাপবুক'
              : 'Trip Scrapbook Magazines',
          subtitle: _isBn
              ? 'আপনার প্রতিটি ট্যুরের স্বয়ংক্রিয় ফটো অ্যালবাম, খরচ পরিসংখ্যান ও মেমোরি বই।'
              : 'Auto-curated photo stories, awards, and numbers from your travels.',
          icon: Icons.auto_stories_rounded,
          color: AppColors.mintGreen,
          onTap: () {
            if (groups.isNotEmpty) {
              final activeId =
                  TourGroupRepository.lastActiveTourId ?? groups.first.id;
              context.push('/group/$activeId/scrapbook');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isBn
                      ? 'স্ক্র্যাপবুক দেখতে আগে একটি ট্যুরে যোগ দিন।'
                      : 'Join a tour to view trip scrapbooks.'),
                  backgroundColor: AppColors.midGreen,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
        const SizedBox(height: 12),

        // 2. Offline Travel Vault Card
        _buildKeepsakeCard(
          title: _isBn ? 'অফলাইন ট্রাভেল ভল্ট' : 'Offline Travel Vault',
          subtitle: _isBn
              ? 'বাসের টিকিট, হোটেল বুকিং নোট ও প্যাকিং লিস্টের অফলাইন সংরক্ষণাগার।'
              : 'Offline storage for bus tickets, hotel reservations, and emergency notes.',
          icon: Icons.lock_clock_rounded,
          color: AppColors.gold,
          onTap: () => context.push('/vault'),
        ),
        const SizedBox(height: 12),

        // 3. Family Safety & Emergency Card
        _buildKeepsakeCard(
          title:
              _isBn ? 'ফ্যামিলি সেফটি হাব ও এসওএস' : 'Family Safety Hub & SOS',
          subtitle: _isBn
              ? 'জরুরি সাইরেন, কোস্টাল জোয়ার-ভাটার সতর্কতা ও ট্যুর সদস্যদের লোকেশন নোটিশ।'
              : 'Emergency siren alerts, coastal tide advisories, and member safety.',
          icon: Icons.shield_rounded,
          color: Colors.redAccent,
          onTap: () {
            if (groups.isNotEmpty) {
              final activeId =
                  TourGroupRepository.lastActiveTourId ?? groups.first.id;
              context.push('/group/$activeId/safety');
            } else {
              context.go('/group-hub');
            }
          },
        ),
        const SizedBox(height: 12),

        // 4. Game Zone Card
        _buildKeepsakeCard(
          title: _isBn ? 'ফ্যামিলি গেম জোন' : 'Family Game Zone',
          subtitle: _isBn
              ? 'লুডো, ক্যারাম, কার্ড ২৯, ট্রাভেল চেস এবং তিন পাত্তি মাল্টিপ্লেয়ার।'
              : 'Play Card 29, Carrom, Chess AI, Ludo, and Teen Patti on the bus or train.',
          icon: Icons.sports_esports_rounded,
          color: Colors.lightBlueAccent,
          onTap: () => context.push('/game-zone'),
        ),
      ],
    );
  }

  Widget _buildKeepsakeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF14241B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 22),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Preferences & Settings
  // ---------------------------------------------------------------------------

  Widget _buildPreferencesTab(ExplorerProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isBn ? 'অ্যাপ পছন্দ ও সেটিংস' : 'App Preferences & Settings',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Language Selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.language_rounded,
                      color: AppColors.mintGreen, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isBn ? 'অ্যাপের ভাষা' : 'App Language',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceChip(
                      selected: _isBn,
                      label: 'বাংলা (Bengali)',
                      onTap: () => LocaleController.instance.setLanguage('bn'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildChoiceChip(
                      selected: !_isBn,
                      label: 'English',
                      onTap: () => LocaleController.instance.setLanguage('en'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Account Information & Logout
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_circle_outlined,
                      color: AppColors.mintGreen, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isBn ? 'অ্যাকাউন্ট তথ্য' : 'Account Details',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildAccountRow(_isBn ? 'নাম' : 'Name', profile.displayName),
              _buildAccountRow(
                  _isBn ? 'ইমেইল' : 'Email', _tourRepo.currentEmail),
              _buildAccountRow(_isBn ? 'বিভাগ' : 'Division', profile.division),
              _buildAccountRow(
                _isBn ? 'যোগদান' : 'Joined',
                DateFormat('d MMMM yyyy').format(profile.createdAt),
              ),
              const Divider(color: Colors.white10, height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.logout, size: 16),
                  label: Text(_isBn ? 'অ্যাকাউন্ট থেকে লগআউট' : 'Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mintGreen.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.mintGreen : Colors.white24,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.mintGreen : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(
            value.isNotEmpty ? value : '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs: Create Tour & Join Tour
  // ---------------------------------------------------------------------------

  void _showCreateGroupDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    final originCtrl = TextEditingController(text: 'ঢাকা');
    TourType selectedTourType = TourType.beach;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 3));
    bool isCreating = false;

    final presets = [
      (label: "কক্সবাজার", dest: "Cox's Bazar", type: TourType.beach),
      (label: "সাজেক ভ্যালি", dest: 'Sajek Valley', type: TourType.hill),
      (label: "শ্রীমঙ্গল / সিলেট", dest: 'Sylhet', type: TourType.nature),
      (label: "বান্দরবান", dest: 'Bandarban', type: TourType.hill),
      (label: "কুয়াকাটা", dest: 'Kuakata', type: TourType.beach),
      (label: "সুন্দরবন", dest: 'Sundarbans', type: TourType.nature),
    ];

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final days = endDate.difference(startDate).inDays + 1;
            final nights = days > 1 ? days - 1 : 0;
            final durationText =
                nights == 0 ? '$days দিন' : '$days দিন $nights রাত';

            return AlertDialog(
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                _isBn ? 'নতুন ট্যুর গ্রুপ তৈরি করুন' : 'Create New Tour Group',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
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
                          labelText: _isBn
                              ? 'ট্যুরের নাম (যেমন: সাজেক ট্যুর ২০২৬)'
                              : 'Tour Name',
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Presets
                      Text(
                        _isBn
                            ? 'জনপ্রিয় গন্তব্যসমূহ (Quick Select):'
                            : 'Popular Destinations:',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
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

                      // Destination field
                      TextField(
                        controller: destCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _isBn ? 'গন্তব্য' : 'Destination',
                          labelStyle: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Dates
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: dialogCtx,
                            initialDateRange:
                                DateTimeRange(start: startDate, end: endDate),
                            firstDate: DateTime(2022),
                            lastDate: DateTime(2035),
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
                                child: Text(
                                  '${DateFormat('d MMM yyyy').format(startDate)} – ${DateFormat('d MMM yyyy').format(endDate)} ($durationText)',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating ? null : () => Navigator.pop(ctx),
                  child: Text(
                    _isBn ? 'বাতিল' : 'Cancel',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: isCreating
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final dest = destCtrl.text.trim();
                          if (name.isEmpty) return;

                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          setDialogState(() => isCreating = true);
                          try {
                            final newGroup = await _tourRepo.createGroup(
                              name: name,
                              description: '',
                              destination:
                                  dest.isNotEmpty ? dest : 'Custom Destination',
                              originCity: originCtrl.text.trim().isNotEmpty
                                  ? originCtrl.text.trim()
                                  : 'ঢাকা',
                              tourType: selectedTourType,
                              startDate: startDate,
                              endDate: endDate,
                            );
                            if (mounted) {
                              TourGroupRepository.lastActiveTourId =
                                  newGroup.id;
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isBn
                                        ? 'ট্যুর গ্রুপ তৈরি হয়েছে: ${newGroup.name}'
                                        : 'Created tour: ${newGroup.name}',
                                  ),
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
                                  content: Text('Error: $e'),
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
                      : Text(
                          _isBn ? 'ট্যুর তৈরি করুন' : 'Create Tour',
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showJoinGroupDialog(BuildContext context) {
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
              title: Text(
                _isBn ? 'ট্যুর গ্রুপে যোগ দিন' : 'Join Tour Group',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isBn
                        ? 'ট্যুরের ৮ অক্ষরের আমন্ত্রণ কোড লিখুন:'
                        : 'Enter the 8-character tour invite code:',
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
                      hintText: '7KQ2M9XB',
                      hintStyle: const TextStyle(
                          color: Colors.white38, letterSpacing: 2),
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
                  child: Text(
                    _isBn ? 'বাতিল' : 'Cancel',
                    style: const TextStyle(color: Colors.white54),
                  ),
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
                          final nav = Navigator.of(ctx);
                          setDialogState(() => isJoining = true);
                          try {
                            final joinedGroup =
                                await _tourRepo.joinGroupWithCode(code);
                            if (mounted) {
                              TourGroupRepository.lastActiveTourId =
                                  joinedGroup.id;
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isBn
                                        ? '${joinedGroup.name} ট্যুরে যুক্ত হয়েছেন!'
                                        : 'Joined ${joinedGroup.name}!',
                                  ),
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
                      : Text(
                          _isBn ? 'যোগ দিন' : 'Join',
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Dialog: Edit Profile Bottom Sheet
  // ---------------------------------------------------------------------------

  void _showEditProfileBottomSheet(ExplorerProfile profile) {
    final nameController = TextEditingController(text: profile.displayName);
    final rawData = _rawProfileDoc?.data() as Map<String, dynamic>?;
    final rawBn = rawData?['bioBangla'] as String? ?? '';
    final rawEn = rawData?['bioEnglish'] as String? ?? '';
    final bioBanglaController = TextEditingController(text: rawBn);
    final bioEnglishController = TextEditingController(
        text: rawEn.isNotEmpty ? rawEn : (profile.bio ?? ''));

    String selectedDivision = profile.division;
    const divisions = [
      'Dhaka',
      'Sylhet',
      'Chittagong',
      'Khulna',
      'Barishal',
      'Rajshahi',
      'Rangpur',
      'Mymensingh'
    ];

    final statusNoteController = TextEditingController(
        text: _statusNote ?? rawData?['statusNote'] as String? ?? '');
    String selectedBloodGroup =
        _bloodGroup ?? rawData?['bloodGroup'] as String? ?? 'O+';
    const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

    XFile? dialogAvatarFile;
    XFile? dialogCoverFile;
    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          const double coverHeight = 130.0;
          const double avatarRadius = 38.0;

          return Container(
            margin:
                EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24),
            decoration: BoxDecoration(
              color: context.surfacePanel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: const Border(
                top: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isBn
                              ? 'প্রোফাইল তথ্য পরিবর্তন'
                              : 'EDIT TRAVELER PROFILE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 20),
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          // Cover & Avatar Stack
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              GestureDetector(
                                onTap: isSaving
                                    ? null
                                    : () async {
                                        final file = await ImagePicker()
                                            .pickImage(
                                                source: ImageSource.gallery,
                                                imageQuality: 80);
                                        if (file != null) {
                                          setDialogState(() {
                                            dialogCoverFile = file;
                                          });
                                        }
                                      },
                                child: Container(
                                  height: coverHeight,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF0F2027),
                                                Color(0xFF203A43),
                                                Color(0xFF2C5364)
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                        ),
                                        if (dialogCoverFile != null)
                                          (kIsWeb
                                              ? Image.network(
                                                  dialogCoverFile!.path,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const ColoredBox(
                                                          color:
                                                              Colors.black26),
                                                )
                                              : Image.file(
                                                  File(dialogCoverFile!.path),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const ColoredBox(
                                                          color:
                                                              Colors.black26),
                                                ))
                                        else if (profile.coverUrl != null)
                                          CachedNetworkImage(
                                            imageUrl: profile.coverUrl!,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                const ColoredBox(
                                                    color: Colors.black26),
                                          ),
                                        Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.35),
                                          alignment: Alignment.center,
                                          child: Text(
                                            _isBn
                                                ? 'কভার পরিবর্তন করতে ট্যাপ করুন'
                                                : 'TAP TO CHANGE COVER PHOTO',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: -36,
                                child: GestureDetector(
                                  onTap: isSaving
                                      ? null
                                      : () async {
                                          final file = await ImagePicker()
                                              .pickImage(
                                                  source: ImageSource.gallery,
                                                  imageQuality: 80);
                                          if (file != null) {
                                            setDialogState(() {
                                              dialogAvatarFile = file;
                                            });
                                          }
                                        },
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppColors.mintGreen,
                                              width: 3),
                                        ),
                                        child: ClipOval(
                                          child: SizedBox(
                                            width: avatarRadius * 2,
                                            height: avatarRadius * 2,
                                            child: dialogAvatarFile != null
                                                ? (kIsWeb
                                                    ? Image.network(
                                                        dialogAvatarFile!.path,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(
                                                                Icons.person),
                                                      )
                                                    : Image.file(
                                                        File(dialogAvatarFile!
                                                            .path),
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(
                                                                Icons.person),
                                                      ))
                                                : (profile.avatarUrl != null
                                                    ? CachedNetworkImage(
                                                        imageUrl:
                                                            profile.avatarUrl!,
                                                        fit: BoxFit.cover,
                                                        errorWidget: (_, __,
                                                                ___) =>
                                                            const Icon(
                                                                Icons.person),
                                                      )
                                                    : Container(
                                                        color: const Color(
                                                            0xFF1B4332),
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          profile.displayName
                                                                  .isNotEmpty
                                                              ? profile
                                                                  .displayName[0]
                                                              : 'T',
                                                          style: const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 24,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold),
                                                        ),
                                                      )),
                                          ),
                                        ),
                                      ),
                                      const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: AppColors.mintGreen,
                                        child: Icon(Icons.camera_alt,
                                            size: 12, color: Colors.black),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 48),

                          // Display Name
                          Text(_isBn ? 'প্রদর্শন নাম' : 'DISPLAY NAME',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameController,
                            enabled: !isSaving,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              hintText: 'Enter your name',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Bio Bangla
                          Text(_isBn ? 'বায়ো (বাংলা)' : 'BIO (BANGLA)',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: bioBanglaController,
                            enabled: !isSaving,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              hintText: 'আপনার ভ্রমণ নিয়ে কিছু বলুন...',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Bio English
                          Text(_isBn ? 'বায়ো (ইংরেজি)' : 'BIO (ENGLISH)',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: bioEnglishController,
                            enabled: !isSaving,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              hintText: 'Describe your journeys in English...',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Division
                          Text(_isBn ? 'বিভাগ' : 'DIVISION',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: selectedDivision,
                            dropdownColor: context.surfacePanel,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: divisions
                                .map((div) => DropdownMenuItem(
                                      value: div,
                                      child: Text(div),
                                    ))
                                .toList(),
                            onChanged: isSaving
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setDialogState(() {
                                        selectedDivision = val;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 16),

                          // Blood Group
                          Text(_isBn ? 'রক্তের গ্রুপ' : 'BLOOD GROUP',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue:
                                bloodGroups.contains(selectedBloodGroup)
                                    ? selectedBloodGroup
                                    : 'O+',
                            dropdownColor: context.surfacePanel,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: bloodGroups
                                .map((bg) => DropdownMenuItem(
                                      value: bg,
                                      child: Text(bg),
                                    ))
                                .toList(),
                            onChanged: isSaving
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setDialogState(() {
                                        selectedBloodGroup = val;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 16),

                          // Status Note
                          Text(_isBn ? 'স্ট্যাটাস নোট' : 'STATUS NOTE',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: statusNoteController,
                            enabled: !isSaving,
                            maxLength: 80,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              filled: true,
                              hintText: _isBn
                                  ? 'আজকের ভ্রমণ নোট বা অনুভূতি...'
                                  : 'Today\'s travel note...',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side:
                                        const BorderSide(color: Colors.white10),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed: isSaving
                                      ? null
                                      : () => Navigator.pop(bottomSheetContext),
                                  child: Text(_isBn ? 'বাতিল' : 'Cancel'),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.mintGreen,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          setDialogState(() => isSaving = true);
                                          try {
                                            String? finalAvatarUrl =
                                                profile.avatarUrl;
                                            String? finalCoverUrl =
                                                profile.coverUrl;

                                            if (dialogAvatarFile != null) {
                                              final timestamp = DateTime.now()
                                                  .millisecondsSinceEpoch;
                                              if (kIsWeb) {
                                                final bytes =
                                                    await dialogAvatarFile!
                                                        .readAsBytes();
                                                finalAvatarUrl =
                                                    await MediaUploadService
                                                        .uploadBytes(
                                                  bytes: bytes,
                                                  path:
                                                      'explorer_avatars/${profile.uid}_$timestamp.jpg',
                                                  contentType: 'image/jpeg',
                                                );
                                              } else {
                                                finalAvatarUrl =
                                                    await MediaUploadService
                                                        .uploadFile(
                                                  file: File(
                                                      dialogAvatarFile!.path),
                                                  path:
                                                      'explorer_avatars/${profile.uid}_$timestamp.jpg',
                                                );
                                              }
                                            }

                                            if (dialogCoverFile != null) {
                                              final timestamp = DateTime.now()
                                                  .millisecondsSinceEpoch;
                                              if (kIsWeb) {
                                                final bytes =
                                                    await dialogCoverFile!
                                                        .readAsBytes();
                                                finalCoverUrl =
                                                    await MediaUploadService
                                                        .uploadBytes(
                                                  bytes: bytes,
                                                  path:
                                                      'explorer_covers/${profile.uid}_$timestamp.jpg',
                                                  contentType: 'image/jpeg',
                                                );
                                              } else {
                                                finalCoverUrl =
                                                    await MediaUploadService
                                                        .uploadFile(
                                                  file: File(
                                                      dialogCoverFile!.path),
                                                  path:
                                                      'explorer_covers/${profile.uid}_$timestamp.jpg',
                                                );
                                              }
                                            }

                                            final updated = profile.copyWith(
                                              displayName:
                                                  nameController.text.trim(),
                                              bio: bioEnglishController.text
                                                      .trim()
                                                      .isNotEmpty
                                                  ? bioEnglishController.text
                                                      .trim()
                                                  : profile.bio,
                                              division: selectedDivision,
                                              avatarUrl: finalAvatarUrl,
                                              coverUrl: finalCoverUrl,
                                            );

                                            if (!context.mounted) return;
                                            await context
                                                .read<AuthCubit>()
                                                .updateProfile(updated);

                                            await FirebaseFirestore.instance
                                                .collection('explorer_profiles')
                                                .doc(profile.uid)
                                                .set({
                                              'bioBangla': bioBanglaController
                                                  .text
                                                  .trim(),
                                              'bioEnglish': bioEnglishController
                                                  .text
                                                  .trim(),
                                              'bloodGroup': selectedBloodGroup,
                                              'statusNote': statusNoteController
                                                  .text
                                                  .trim(),
                                            }, SetOptions(merge: true));

                                            if (mounted) {
                                              setState(() {
                                                _bloodGroup =
                                                    selectedBloodGroup;
                                                _statusNote =
                                                    statusNoteController.text
                                                        .trim();
                                              });
                                              _loadProfile();
                                            }
                                            if (bottomSheetContext.mounted) {
                                              Navigator.pop(bottomSheetContext);
                                            }
                                          } catch (e) {
                                            setDialogState(
                                                () => isSaving = false);
                                            if (bottomSheetContext.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed: $e'),
                                                  backgroundColor:
                                                      Colors.redAccent,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                  child: isSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black),
                                        )
                                      : Text(
                                          _isBn
                                              ? 'সংরক্ষণ করুন'
                                              : 'Save Changes',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Guest & Skeleton States
  // ---------------------------------------------------------------------------

  Widget _buildGuestPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle_outlined,
                size: 72, color: AppColors.mintGreen),
            const SizedBox(height: 20),
            Text(
              _isBn ? 'আপনার ভ্রমণ প্রোফাইল' : 'Your Traveler Profile',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isBn
                  ? 'ট্যুর গ্রুপ পরিচালনা, ফটো শেয়ার ও খরচ ভাগাভাগি করতে সাইন-ইন করুন।'
                  : 'Sign in to manage tour groups, split expenses, and share moments.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login),
              label: Text(_isBn ? 'লগইন বা সাইন-আপ' : 'Sign In / Register'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSkeleton() {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Shimmer(
        child: Column(
          children: [
            SkeletonBox(
              height: 190,
              radius: 0,
            ),
            SizedBox(height: 60),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SkeletonBox(width: 140, height: 20),
                  SizedBox(height: 8),
                  SkeletonBox(width: 100, height: 14),
                  SizedBox(height: 24),
                  SkeletonBox(height: 60, radius: 16),
                  SizedBox(height: 20),
                  SkeletonBox(height: 140, radius: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.surfacePanel,
        title: Text(
          _isBn ? 'লগআউট করতে চান?' : 'Log out?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          _isBn
              ? 'আপনার অফলাইন ম্যাপ ও ট্যুর ড্রাফট এই ডিভাইসেই থাকবে। আপনি যেকোনো সময় আবার সাইন-ইন করতে পারবেন।'
              : 'Your offline data stays safely on this device. You can sign back in anytime.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              _isBn ? 'বাতিল' : 'Cancel',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_isBn ? 'লগআউট' : 'Log Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthCubit>().signOut();
      if (context.mounted) {
        context.go('/login');
      }
    }
  }
}

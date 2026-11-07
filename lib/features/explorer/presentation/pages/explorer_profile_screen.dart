import 'dart:io';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/services/media_upload_service.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/widgets/swipe_step.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../../tour_group/domain/models/tour_group.dart';
import '../../../tour_group/domain/services/tour_choice.dart';
import '../../../tour_group/presentation/tour_routes.dart';
import '../../../tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import '../../../tour_group/presentation/widgets/trip_shell.dart';
import '../../domain/profile_view.dart';
import '../../domain/usecases/get_explorer_profile_usecase.dart';
import '../../../game_zone/presentation/widgets/game_analytics_view.dart';
import '../widgets/server_patron_card.dart';
import '../widgets/bangla_qr_profile_sheet.dart';
import '../../../tour_group/domain/services/payment_profile_service.dart';
import 'package:bhromon/core/config/feature_flags.dart';
import 'package:bhromon/core/database/app_database.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/explorer/presentation/widgets/games_link_card.dart';
import 'package:bhromon/features/explorer/domain/profile_tabs.dart';

/// The modern, Tour Group-Centric Profile Screen for Bhromon Travelers.
/// Replaces the legacy public social/YouTube architecture with live
/// tour groups, gaming, and personal settings.
class ExplorerProfileScreen extends StatefulWidget {
  final String uid;

  /// The tour the visitor came from, so the tour tabs and cards open it. Null
  /// when the profile is opened outside a tour.
  final String? tourId;

  /// The person's email when the caller knows it, such as the chat with them.
  /// It only helps find their groups; it is never shown unless a shared
  /// group's membership confirms it.
  final String? emailHint;

  /// The group repository. The app leaves this null; tests pass a fake.
  final TourGroupRepository? repository;

  /// Reads the raw profile fields (blood group, status note, bios). The app leaves this
  /// null and reads Firestore; tests pass a fake.
  final Future<Map<String, dynamic>?> Function(String uid)? readProfileData;

  /// Which tabs the own profile shows. Null follows kGroupsV2; tests pass it to try both
  /// layouts.
  final bool? groupsV2;

  const ExplorerProfileScreen({
    super.key,
    required this.uid,
    this.tourId,
    this.emailHint,
    this.repository,
    this.readProfileData,
    this.groupsV2,
  });

  @override
  State<ExplorerProfileScreen> createState() => _ExplorerProfileScreenState();
}

class _ExplorerProfileScreenState extends State<ExplorerProfileScreen> {
  late final GetExplorerProfileUseCase _getExplorerProfile;
  late final TourGroupRepository _tourRepo;

  /// The signed-in person's groups, created once in [initState] (BUG-1).
  late final Stream<List<TourGroup>> _myGroupsStream;

  ExplorerProfile? _profile;
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _rawProfileData;
  String? _bloodGroup;
  String? _statusNote;
  String _activeCategory = 'all';

  // Active tab: 'tours' | 'settings' | 'games'. Set in initState, once the
  // layout is known.
  late String _activeTab;

  /// Whether the groups-V2 tabs show (see [ExplorerProfileScreen.groupsV2]).
  bool get _useGroupsV2 => widget.groupsV2 ?? kGroupsV2;

  // On someone else's profile: the groups you share with them, null until
  // known, and their email as their membership row in a shared group gives it.
  Set<String>? _sharedTourIds;
  String? _subjectEmail;
  String _sharedKey = '';
  bool _isGuest = false;

  // The tour the tabs and cards open. Creating or joining a tour changes it.
  String? _tourId;

  @override
  void initState() {
    super.initState();
    _tourRepo = widget.repository ?? TourGroupRepository();
    _myGroupsStream = _tourRepo.watchMyGroups();
    LocaleController.instance.addListener(_onLocaleChanged);
    _getExplorerProfile = getIt<GetExplorerProfileUseCase>();
    _tourId = widget.tourId;
    _activeTab = defaultProfileTab(groupsV2: _useGroupsV2);
    _loadProfile();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LocaleController.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  bool get _isBn => LocaleController.instance.locale.languageCode == 'bn';

  /// The email of the person this profile belongs to: yours on your own
  /// profile, and on someone else's the one their shared membership confirms.
  String _emailFor(bool isOwnProfile) =>
      isOwnProfile ? _tourRepo.currentEmail : (_subjectEmail ?? '');

  /// Works out which of [myGroups] the profile's person is also in, once per
  /// set of groups.
  void _ensureSharedGroups(List<TourGroup> myGroups) {
    final uid = _profile?.uid ?? widget.uid;
    final ids = [for (final g in myGroups) g.id]..sort();
    final key = '$uid|${ids.join(',')}';
    if (key == _sharedKey) return;
    _sharedKey = key;
    _tourRepo
        .sharedGroupsWith(uid: uid, email: widget.emailHint, tourIds: ids)
        .then((result) {
      if (!mounted || key != _sharedKey) return;
      setState(() {
        _sharedTourIds = result.tourIds;
        _subjectEmail = result.tourIds.isEmpty ? null : result.email;
      });
    });
  }

  /// The raw profile document's fields, read from Firestore. Null when there is none.
  Future<Map<String, dynamic>?> _readProfileData(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(uid)
        .get();
    return doc.data();
  }

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

      final data =
          await (widget.readProfileData ?? _readProfileData)(profile.uid);

      final isOwn = currentUid.isNotEmpty && profile.uid == currentUid;
      String? fallbackAvatar;
      if (isOwn) {
        try {
          fallbackAvatar = FirebaseAuth.instance.currentUser?.photoURL;
        } catch (e, st) {
          // Firebase is not initialized in widget test environment.
          logSkipped(e, st);
        }
      }
      final effectiveAvatar = profile.avatarUrl?.isNotEmpty == true
          ? profile.avatarUrl
          : ((data?['avatarUrl'] as String?)?.isNotEmpty == true
              ? (data?['avatarUrl'] as String)
              : ((data?['photoUrl'] as String?)?.isNotEmpty == true
                  ? (data?['photoUrl'] as String)
                  : ((data?['photoURL'] as String?)?.isNotEmpty == true
                      ? (data?['photoURL'] as String)
                      : fallbackAvatar)));

      final effectiveCover = profile.coverUrl?.isNotEmpty == true
          ? profile.coverUrl
          : ((data?['coverUrl'] as String?)?.isNotEmpty == true
              ? (data?['coverUrl'] as String)
              : ((data?['coverPhotoUrl'] as String?)?.isNotEmpty == true
                  ? (data?['coverPhotoUrl'] as String)
                  : (data?['cover_url'] as String?)));

      final mergedProfile = profile.copyWith(
        avatarUrl: effectiveAvatar,
        coverUrl: effectiveCover,
      );

      if (mounted) {
        setState(() {
          _profile = mergedProfile;
          _rawProfileData = data;
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
    final rawData = _rawProfileData;
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
        backgroundColor: context.forest.dialog,
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: context.forest.accentText),
            const SizedBox(width: 8),
            Text(
              _isBn ? 'স্ট্যাটাস নোট' : 'Status Note',
              style: TextStyle(color: context.forest.text, fontSize: 16),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 80,
          autofocus: true,
          style: TextStyle(color: context.forest.text),
          decoration: InputDecoration(
            hintText: _isBn
                ? 'আজকের অনুভূতি বা নোট লিখুন...'
                : 'Write your travel note or mood...',
            hintStyle: TextStyle(color: context.forest.text38, fontSize: 13),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.forest.text24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.mintGreen)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _isBn ? 'বাতিল' : 'Cancel',
              style: TextStyle(color: context.forest.text54),
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
        } catch (error, stackTrace) {
          logSkipped(error, stackTrace);
        }
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
          backgroundColor: context.forest.dialog,
          title: Row(
            children: [
              const Icon(Icons.bloodtype_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                _isBn ? 'রক্তের গ্রুপ' : 'Blood Group',
                style: TextStyle(color: context.forest.text, fontSize: 16),
              ),
            ],
          ),
          content: DropdownButtonFormField<String>(
            initialValue: groups.contains(chosen) ? chosen : 'O+',
            dropdownColor: context.forest.card,
            style: TextStyle(color: context.forest.text),
            decoration: InputDecoration(
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.forest.text24)),
              focusedBorder: const UnderlineInputBorder(
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
                style: TextStyle(color: context.forest.text54),
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
        } catch (error, stackTrace) {
          logSkipped(error, stackTrace);
        }
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
          Icon(icon, size: 13, color: context.forest.readable(color)),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: context.forest.readable(color),
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

    final handle = profileHandle(
      email: _emailFor(isOwnProfile),
      displayName: _profile?.displayName ?? '',
    );

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(tourHubPath(_tourId));
      },
      child: Scaffold(
        backgroundColor: context.forest.background,
        appBar: AppBar(
          title: Text(
            '@$handle',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: context.forest.text,
            ),
          ),
          centerTitle: true,
          backgroundColor: context.forest.background,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.forest.text70),
            tooltip: _isBn ? 'ফিরে যান' : 'Back',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(tourHubPath(_tourId));
              }
            },
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.share_outlined,
                  color: context.forest.text70, size: 20),
              tooltip: _isBn ? 'শেয়ার করুন' : 'Share Profile',
              onPressed: () {
                final name = _profile?.displayName ?? 'Member';
                SharePlus.instance.share(
                  ShareParams(
                    text:
                        '$name (@$handle) is on Bhromon, the app for every group you belong to.\nhttps://app.bhromon.fun',
                  ),
                );
              },
            ),
            if (isOwnProfile) ...[
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    color: context.forest.accentText, size: 20),
                tooltip: _isBn ? 'প্রোফাইল পরিবর্তন' : 'Edit Profile',
                onPressed: () {
                  if (_profile != null) {
                    _showEditProfileBottomSheet(_profile!);
                  }
                },
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
        bottomNavigationBar:
            MediaQuery.sizeOf(context).width < TripShell.railBreakpoint
                ? BhromonBottomNav(
                    selectedIndex: 4,
                    tourId: _tourId,
                  )
                : null,
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
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
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
                      ? 'প্রোফাইল লোড করা সম্ভব হয়নি: $_error'
                      : 'Failed to load profile: $_error',
                  style: TextStyle(color: context.forest.text70, fontSize: 13),
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
        ),
      );
    }

    if (_profile == null) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: SizedBox.shrink(),
      );
    }

    final profile = _profile!;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return StreamBuilder<List<TourGroup>>(
      stream: _myGroupsStream,
      builder: (context, groupsSnap) {
        final myGroups = groupsSnap.data ?? [];
        if (!isOwnProfile && groupsSnap.hasData) _ensureSharedGroups(myGroups);
        // Someone else's profile lists only the groups you share with them.
        final groups = profileGroups(
          isOwnProfile: isOwnProfile,
          myGroups: myGroups,
          sharedIds: _sharedTourIds,
          idOf: (g) => g.id,
        );
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
              _buildTourMetricsBar(groups, isOwnProfile),
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
              _buildAchievementsShowcase(groups, isOwnProfile),
              const SizedBox(height: 20),

              // 7. Segmented Navigation Tabs: games and settings are
              // your own, so someone else's profile shows only shared groups.
              if (isOwnProfile) ...[
                _buildSegmentedTabs(),
                const SizedBox(height: 16),
              ],

              // 6. Active Tab Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: isOwnProfile
                    ? SwipeStep(
                        onStep: _stepTab,
                        nextLabel: _isBn ? 'পরের ট্যাব' : 'Next tab',
                        previousLabel: _isBn ? 'আগের ট্যাব' : 'Previous tab',
                        child: _buildActiveTabContent(
                            profile, groups, isOwnProfile),
                      )
                    : _buildActiveTabContent(profile, groups, isOwnProfile),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF081C15),
                  Color(0xFF1B4332),
                  Color(0xFF2D6A4F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (profile.coverUrl != null && profile.coverUrl!.isNotEmpty)
                  kIsWeb
                      ? Image.network(
                          signedMediaUrl(profile.coverUrl!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 190,
                          errorBuilder: (_, __, ___) => Image.network(
                            profile.coverUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 190,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: signedMediaUrl(profile.coverUrl!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 190,
                          memCacheWidth: context.decodeWidth(),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
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
                  decoration: BoxDecoration(
                    color: context.forest.background,
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
                    child: ClipOval(
                      child: SizedBox(
                        width: 92,
                        height: 92,
                        child: profile.avatarUrl != null &&
                                profile.avatarUrl!.isNotEmpty
                            ? (kIsWeb
                                ? Image.network(
                                    signedMediaUrl(profile.avatarUrl!),
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Image.network(
                                      profile.avatarUrl!,
                                      width: 92,
                                      height: 92,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _buildAvatarFallback(profile),
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl:
                                        signedMediaUrl(profile.avatarUrl!),
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                    memCacheWidth: context.decodeWidth(92),
                                    placeholder: (_, __) =>
                                        _buildAvatarFallback(profile),
                                    errorWidget: (_, __, ___) =>
                                        _buildAvatarFallback(profile),
                                  ))
                            : _buildAvatarFallback(profile),
                      ),
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
                            color: context.forest.background, width: 2),
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

  Widget _buildAvatarFallback(ExplorerProfile profile) {
    return Container(
      color: const Color(0xFF1B4332),
      alignment: Alignment.center,
      child: Text(
        profile.displayName.isNotEmpty
            ? profile.displayName[0].toUpperCase()
            : 'T',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUserInfo(ExplorerProfile profile, bool isOwnProfile) {
    final bio = _getDisplayBio(profile);
    final email = _emailFor(isOwnProfile);
    final hasNote = _statusNote != null && _statusNote!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Status Note bubble above name: on someone else's profile only
          // when they wrote one.
          if (isOwnProfile || hasNote)
            GestureDetector(
              onTap: () => _editStatusNote(context, isOwnProfile),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: context.forest.text.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOwnProfile &&
                        (_statusNote == null || _statusNote!.isEmpty)) ...[
                      Icon(Icons.add,
                          size: 12, color: context.forest.accentText),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      (_statusNote != null && _statusNote!.isNotEmpty)
                          ? _statusNote!
                          : (isOwnProfile
                              ? (_isBn ? 'নোট যুক্ত করুন' : 'Add Note')
                              : (_isBn ? 'সদস্য নোট' : 'Member note')),
                      style: TextStyle(
                        color: context.forest.accentText,
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
            profile.displayName.isNotEmpty ? profile.displayName : 'Member',
            style: TextStyle(
              color: context.forest.text,
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
                Icon(Icons.verified_user_rounded,
                    size: 13, color: context.forest.accentText),
                const SizedBox(width: 5),
                Text(
                  email.isNotEmpty
                      ? email
                      : (_isBn ? 'গ্রুপের সদস্য' : 'Group member'),
                  style: TextStyle(
                    color: context.forest.accentText,
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
              if (isOwnProfile ||
                  (_bloodGroup != null && _bloodGroup!.isNotEmpty))
                GestureDetector(
                  onTap: isOwnProfile
                      ? () => _editBloodGroup(context, isOwnProfile)
                      : null,
                  child: _buildDetailChip(
                    icon: Icons.bloodtype_rounded,
                    text: _bloodGroup != null && _bloodGroup!.isNotEmpty
                        ? _bloodGroup!
                        : (_isBn ? 'রক্তের গ্রুপ যোগ করুন' : 'Add Blood Group'),
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
                style: TextStyle(
                  color: context.forest.text70,
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
                    ? (_isBn ? '+ বায়ো যুক্ত করুন' : '+ Add Bio')
                    : (_isBn ? 'বায়ো পরিবর্তন করুন' : 'Edit Bio'),
                style: TextStyle(
                  color: context.forest.accentText,
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

  Widget _buildTourMetricsBar(List<TourGroup> groups, bool isOwnProfile) {
    final email = _emailFor(isOwnProfile);
    final ownedCount = groups.where((g) => g.ownerEmail == email).length;
    final totalDays = groups.fold<int>(0, (acc, g) {
      final days = g.endDate.difference(g.startDate).inDays + 1;
      return acc + (days > 0 ? days : 1);
    });
    final activeLedgers = groups.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.forest.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.forest.text.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem(
            _isBn ? context.l10n.number(groups.length) : '${groups.length}',
            _isBn ? 'গ্রুপ' : 'Groups',
            Icons.groups_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: context.forest.text.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            _isBn ? context.l10n.number(ownedCount) : '$ownedCount',
            _isBn ? 'পরিচালিত' : 'Organized',
            Icons.stars_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: context.forest.text.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            _isBn ? context.l10n.number(totalDays) : '$totalDays',
            _isBn ? 'ভ্রমণ দিন' : 'Tour Days',
            Icons.calendar_month_rounded,
          ),
          Container(
            height: 32,
            width: 1,
            color: context.forest.text.withValues(alpha: 0.1),
          ),
          _buildMetricItem(
            _isBn ? context.l10n.number(activeLedgers) : '$activeLedgers',
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
            Icon(icon, size: 15, color: context.forest.accentText),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: context.forest.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: context.forest.text70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
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
                _isBn ? 'নতুন গ্রুপ' : 'Create Group',
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
                _isBn ? 'কোডে যোগ' : 'Join Group',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Share Button
          Container(
            decoration: BoxDecoration(
              color: context.forest.text.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: context.forest.text.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              onPressed: () {
                final text =
                    '${profile.displayName} — on Bhromon\nhttps://app.bhromon.fun';
                SharePlus.instance.share(ShareParams(text: text));
              },
              tooltip: _isBn ? 'শেয়ার' : 'Share',
              icon: Icon(Icons.share_outlined,
                  color: context.forest.text70, size: 20),
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
        label: _isBn ? 'সব গ্রুপ' : 'All Groups',
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
        label: _isBn ? 'পাহাড় ও ঝর্ণা' : 'Hills & Treks',
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
                        color: isSelected ? cat.color : context.forest.text24,
                        width: isSelected ? 2.2 : 1.0,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: isSelected
                          ? cat.color.withValues(alpha: 0.25)
                          : context.forest.chip,
                      child: Icon(cat.icon,
                          size: 20,
                          color: isSelected
                              ? context.forest.readable(cat.color)
                              : context.forest.text70),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    cat.label,
                    style: TextStyle(
                      color: isSelected
                          ? context.forest.readable(cat.color)
                          : context.forest.text60,
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

  Widget _buildAchievementsShowcase(List<TourGroup> groups, bool isOwnProfile) {
    // Only what the data shows: a blood group on file, and owning a group.
    final email = _emailFor(isOwnProfile);
    final ownsGroup =
        email.isNotEmpty && groups.any((g) => g.ownerEmail == email);
    final achievements = <({String title, IconData icon, Color color})>[
      if (_bloodGroup != null && _bloodGroup!.isNotEmpty)
        (
          title: _isBn ? 'লাইফ সেভার' : 'Life Saver',
          icon: Icons.favorite_rounded,
          color: Colors.redAccent,
        ),
      if (ownsGroup)
        (
          title: _isBn ? 'আয়োজক' : 'Organiser',
          icon: Icons.workspace_premium_rounded,
          color: AppColors.gold,
        ),
    ];
    if (achievements.isEmpty) return const SizedBox.shrink();
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
                style: TextStyle(
                  color: context.forest.text,
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
                    color: context.forest.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: a.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.icon,
                          size: 14, color: context.forest.readable(a.color)),
                      const SizedBox(width: 6),
                      Text(
                        a.title,
                        style: TextStyle(
                          color: context.forest.readable(a.color),
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

  /// The own profile's tabs (see profileTabKeys).
  List<String> get _ownTabKeys => profileTabKeys(groupsV2: _useGroupsV2);

  /// Moves to the next or previous tab. The first and last tabs stop the swipe.
  /// Only the active tab's content is built, so a tab loads its data only while
  /// it is shown.
  void _stepTab(int by) {
    final next = stepProfileTab(_ownTabKeys, _activeTab, by);
    if (next == _activeTab) return;
    setState(() => _activeTab = next);
  }

  Widget _buildSegmentedTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.forest.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.forest.text.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          if (!_useGroupsV2)
            _buildTabItem(
              'tours',
              Icons.explore_rounded,
              _isBn ? 'গ্রুপসমূহ' : 'My Groups',
            ),
          _buildTabItem(
            'games',
            Icons.emoji_events_rounded,
            _isBn ? 'গেমিং' : 'Games',
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
                color: isActive ? Colors.black : context.forest.text60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : context.forest.text70,
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

  /// The game analytics embedded into the profile scroll view with shrinkWrap enabled.
  Widget _gameAnalyticsSection() {
    return const GameAnalyticsView(shrinkWrap: true);
  }

  Widget _buildActiveTabContent(
    ExplorerProfile profile,
    List<TourGroup> groups,
    bool isOwnProfile,
  ) {
    if (!isOwnProfile) return _buildMyToursTab(groups, false);
    switch (_activeTab) {
      case 'games':
        return _useGroupsV2 ? _buildGamesTabV2() : _gameAnalyticsSection();
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

  /// The Games tab with the Game zone, News, and Holiday Calendar cards (D-8). All are global, so they
  /// belong to the person, not to a group.
  Widget _buildGamesTabV2() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GamesLinkCard(
          icon: Icons.sports_esports_rounded,
          color: const Color(0xFFF59E0B),
          title: l10n.translate('hub_module_games'),
          subtitle: l10n.translate('hub_module_games_sub'),
          onTap: () => context.push('/game-zone'),
        ),
        const SizedBox(height: 10),
        GamesLinkCard(
          icon: Icons.article_rounded,
          color: const Color(0xFF0EA5E9),
          title: l10n.translate('hub_module_news'),
          subtitle: l10n.translate('hub_module_news_sub'),
          onTap: () => context.push('/newspaper-hub'),
        ),
        const SizedBox(height: 10),
        GamesLinkCard(
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF10B981),
          title: l10n.translate('hub_module_calendar'),
          subtitle: l10n.translate('hub_module_calendar_sub'),
          onTap: () => context.push('/holiday-calendar'),
        ),
        const SizedBox(height: 16),
        _gameAnalyticsSection(),
      ],
    );
  }

  Widget _buildMyToursTab(List<TourGroup> groups, bool isOwnProfile) {
    if (groups.isEmpty && !isOwnProfile) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _sharedTourIds == null
              ? (_isBn
                  ? 'শেয়ার করা গ্রুপ খোঁজা হচ্ছে…'
                  : 'Finding shared groups…')
              : (_isBn
                  ? 'আপনাদের কোনো শেয়ার করা গ্রুপ নেই।'
                  : 'You have no groups in common.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.forest.text54, fontSize: 13),
        ),
      );
    }
    if (groups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.forest.card,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: context.forest.text.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Icon(Icons.travel_explore_rounded,
                size: 56, color: context.forest.accentText),
            const SizedBox(height: 14),
            Text(
              _isBn ? 'কোনো গ্রুপ পাওয়া যায়নি' : 'No Groups Found',
              style: TextStyle(
                color: context.forest.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isBn
                  ? 'নতুন গ্রুপ তৈরি করুন অথবা কোড দিয়ে বন্ধুর গ্রুপে যোগ দিন।'
                  : 'Create a new group or join with an invite code.',
              style: TextStyle(color: context.forest.text54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showCreateGroupDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(_isBn ? 'গ্রুপ তৈরি' : 'Create'),
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
                    foregroundColor: context.forest.accentText,
                    side: BorderSide(color: context.forest.accentText),
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

    final email = _emailFor(isOwnProfile);
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
              isOwnProfile
                  ? (_isBn
                      ? 'সক্রিয় ও পূর্বের গ্রুপ (${displayGroups.length})'
                      : 'Active & Past Groups (${displayGroups.length})')
                  : (_isBn
                      ? 'শেয়ার করা গ্রুপ (${displayGroups.length})'
                      : 'Groups in common (${displayGroups.length})'),
              style: TextStyle(
                color: context.forest.text,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isOwnProfile)
              TextButton.icon(
                onPressed: () => _showJoinGroupDialog(context),
                icon:
                    Icon(Icons.add, size: 15, color: context.forest.accentText),
                label: Text(
                  _isBn ? 'কোড দিয়ে যোগ' : 'Join by Code',
                  style: TextStyle(
                      color: context.forest.accentText,
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
                gradient: LinearGradient(
                  colors: [
                    context.forest.bannerStart,
                    context.forest.bannerEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.forest.isDark
                      ? AppColors.mintGreen.withValues(alpha: 0.25)
                      : context.forest.text.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: context.forest.isDark ? 0.3 : 0.06),
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
                              style: TextStyle(
                                color: context.forest.text,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📍 ${group.destination}  ·  ${group.tourType.labelBn.split(' ').first}',
                              style: TextStyle(
                                color: context.forest.accentText,
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
                              ? AppColors.gold.withValues(
                                  alpha: context.forest.isDark ? 0.2 : 0.15)
                              : (context.forest.isDark
                                  ? context.forest.divider10
                                  : context.forest.text
                                      .withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isOwner
                                ? AppColors.gold.withValues(alpha: 0.5)
                                : context.forest.text24,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isOwner
                              ? (_isBn ? '👑 ওনার' : 'Owner')
                              : (_isBn ? '🎒 সদস্য' : 'Member'),
                          style: TextStyle(
                            color: isOwner
                                ? (context.forest.isDark
                                    ? AppColors.gold
                                    : const Color(0xFFB78103))
                                : context.forest.text70,
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
                      Icon(Icons.date_range_rounded,
                          size: 14, color: context.forest.text54),
                      const SizedBox(width: 5),
                      Text(
                        '${localizedDateFormat('d MMM yyyy').format(group.startDate)} – ${localizedDateFormat('d MMM yyyy').format(group.endDate)}',
                        style: TextStyle(
                            color: context.forest.text70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '⏱️ ${group.durationText}',
                        style: TextStyle(
                          color: context.forest.accentText,
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
                                    ? 'ইনভাইট কোড কপি হয়েছে: ${group.inviteCode}'
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
                            color: context.forest.isDark
                                ? context.forest.inset26
                                : Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: context.forest.isDark
                                    ? AppColors.mintGreen.withValues(alpha: 0.3)
                                    : AppColors.midGreen
                                        .withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded,
                                  size: 12, color: context.forest.accentText),
                              const SizedBox(width: 4),
                              Text(
                                group.inviteCode,
                                style: TextStyle(
                                  color: context.forest.accentText,
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
                          context.go(tourHubPath(group.id));
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
                          _isBn ? 'গ্রুপ হাব খুলুন' : 'Open Group Hub',
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
  // Tab 2: Preferences & Settings
  // ---------------------------------------------------------------------------

  Widget _buildPreferencesTab(ExplorerProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isBn ? 'অ্যাপ পছন্দ ও সেটিংস' : 'App Preferences & Settings',
          style: TextStyle(
            color: context.forest.text,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Language Selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.forest.card,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: context.forest.text.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.language_rounded,
                      color: context.forest.accentText, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isBn ? 'অ্যাপের ভাষা' : 'App Language',
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: LocaleController.instance,
                builder: (context, _) => Row(
                  children: [
                    Expanded(
                      child: _buildChoiceChip(
                        selected: _isBn,
                        label: 'বাংলা',
                        onTap: () {
                          LocaleController.instance.setLanguage('bn');
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildChoiceChip(
                        selected: !_isBn,
                        label: 'English',
                        onTap: () {
                          LocaleController.instance.setLanguage('en');
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Theme Selector (Dark / Light / System)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.forest.card,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: context.forest.text.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined,
                      color: context.forest.accentText, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isBn ? 'অ্যাপের থিম' : 'App Theme',
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: ThemeController.instance,
                builder: (context, _) {
                  final currentMode = ThemeController.instance.mode;
                  return Row(
                    children: [
                      Expanded(
                        child: _buildChoiceChip(
                          selected: currentMode == ThemeMode.dark,
                          label: _isBn ? 'ডার্ক' : 'Dark',
                          onTap: () {
                            ThemeController.instance.setMode(ThemeMode.dark);
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildChoiceChip(
                          selected: currentMode == ThemeMode.light,
                          label: _isBn ? 'লাইট' : 'Light',
                          onTap: () {
                            ThemeController.instance.setMode(ThemeMode.light);
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildChoiceChip(
                          selected: currentMode == ThemeMode.system,
                          label: _isBn ? 'সিস্টেম' : 'System',
                          onTap: () {
                            ThemeController.instance.setMode(ThemeMode.system);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Bangla QR & Payment Profile
        _buildPaymentQrCard(profile),
        const SizedBox(height: 12),

        // Community Support / Keep Bhromon Alive Card
        const ServerPatronCard(),
        const SizedBox(height: 12),

        // Account Information & Logout
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.forest.card,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: context.forest.text.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_circle_outlined,
                      color: context.forest.accentText, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isBn ? 'অ্যাকাউন্ট তথ্য' : 'Account Details',
                    style: TextStyle(
                      color: context.forest.text,
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
              _buildAccountRow(
                _isBn ? 'বিভাগ' : 'Division',
                _isBn
                    ? (() {
                        final val = context.l10n
                            .translate('div_${profile.division.toLowerCase()}');
                        return val.startsWith('div_') ? profile.division : val;
                      })()
                    : profile.division,
              ),
              _buildAccountRow(
                _isBn ? 'যোগদান' : 'Joined',
                localizedDateFormat('d MMMM yyyy').format(profile.createdAt),
              ),
              Divider(color: context.forest.divider10, height: 24),
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
            color: selected ? AppColors.mintGreen : context.forest.text24,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? context.forest.accentText : context.forest.text70,
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
              style: TextStyle(color: context.forest.text54, fontSize: 12)),
          Text(
            value.isNotEmpty ? value : '—',
            style: TextStyle(
              color: context.forest.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentQrCard(ExplorerProfile profile) {
    final raw = _rawProfileData;
    final qrUrl =
        raw?['banglaQrUrl'] as String? ?? raw?['paymentQrUrl'] as String?;
    final accountNumber = raw?['paymentAccountNumber'] as String? ??
        raw?['mfsNumber'] as String? ??
        raw?['phone'] as String?;
    final provider = raw?['paymentProvider'] as String? ??
        raw?['mfsProvider'] as String? ??
        'bKash';
    final accountType = raw?['paymentAccountType'] as String? ?? 'personal';
    final hasQr = qrUrl != null && qrUrl.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.forest.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.forest.text.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded,
                  color: context.forest.accentText, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isBn
                      ? 'বাংলা কিউআর ও পেমেন্ট প্রোফাইল'
                      : 'Bangla QR & Payment Profile',
                  style: TextStyle(
                    fontFamily: 'NotoSansBengali',
                    color: context.forest.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (hasQr)
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text(_isBn ? 'পরিবর্তন' : 'Edit'),
                  onPressed: () => _openPaymentQrSheet(profile),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isBn
                ? 'আপনার বিকাশ, নগদ বা ব্যাংক কিউআর একবার সেভ করে রাখুন। গ্রুপের খরচের হিসাব মেলানোর সময় মেম্বাররা সরাসরি আপনার কিউআর দেখে টাকা পরিশোধ করতে পারবেন।'
                : 'Save your bKash, Nagad, or Bank QR code once. Group members can scan your QR directly to settle up expenses without repeatedly asking.',
            style: TextStyle(
              fontFamily: 'NotoSansBengali',
              color: context.forest.text70,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (hasQr) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.forest.surfaceFor(const Color(0xFF142428)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.forest.divider12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 64,
                      height: 64,
                      color: Colors.white,
                      child: Image.network(
                        qrUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.qr_code,
                          size: 32,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                provider.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.mintGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              accountType == 'personal'
                                  ? (_isBn
                                      ? 'ব্যক্তিগত (Send Money)'
                                      : 'Personal')
                                  : (_isBn
                                      ? 'মার্চেন্ট (Bangla QR)'
                                      : 'Merchant'),
                              style: TextStyle(
                                fontFamily: 'NotoSansBengali',
                                color: context.forest.text60,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (accountNumber != null &&
                            accountNumber.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            accountNumber,
                            style: TextStyle(
                              fontFamily: 'NotoSansBengali',
                              color: context.forest.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: AppColors.darkGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              ),
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: Text(
                _isBn ? 'বাংলা কিউআর যোগ করুন' : 'Add Bangla QR',
                style: const TextStyle(
                  fontFamily: 'NotoSansBengali',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              onPressed: () => _openPaymentQrSheet(profile),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPaymentQrSheet(ExplorerProfile profile) async {
    final raw = _rawProfileData;
    final initial = PaymentProfileInfo.fromMap(raw);
    final updated = await showBanglaQrProfileSheet(
      context,
      uid: profile.uid,
      initialProfile: initial,
    );
    if (updated != null && mounted) {
      setState(() {
        final current = Map<String, dynamic>.from(_rawProfileData ?? {});
        if (updated.banglaQrUrl != null) {
          current['banglaQrUrl'] = updated.banglaQrUrl;
        } else {
          current.remove('banglaQrUrl');
        }
        if (updated.accountNumber != null) {
          current['paymentAccountNumber'] = updated.accountNumber;
        }
        if (updated.provider != null) {
          current['paymentProvider'] = updated.provider;
        }
        if (updated.accountType != null) {
          current['paymentAccountType'] = updated.accountType;
        }
        _rawProfileData = current;
      });
    }
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
      (label: "কুয়াকাটা", dest: 'Kuakata', type: TourType.beach),
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
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                _isBn ? 'নতুন গ্রুপ তৈরি করুন' : 'Create New Group',
                style: TextStyle(
                  color: context.forest.text,
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
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: _isBn
                              ? 'গ্রুপের নাম (যেমন: সাজেক ট্যুর ২০২৬)'
                              : 'Group Name',
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Presets
                      Text(
                        _isBn
                            ? 'জনপ্রিয় গন্তব্যসমূহ (Quick Select):'
                            : 'Popular Destinations:',
                        style: TextStyle(
                          color: context.forest.text70,
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
                                    : context.forest.divider10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : context.forest.text,
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
                        style: TextStyle(color: context.forest.text),
                        decoration: InputDecoration(
                          labelText: _isBn ? 'গন্তব্য' : 'Destination',
                          labelStyle: TextStyle(
                              color: context.forest.text70, fontSize: 13),
                          filled: true,
                          fillColor: context.forest.inset26,
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
                                child: Text(
                                  '${localizedDateFormat('d MMM yyyy').format(startDate)} – ${localizedDateFormat('d MMM yyyy').format(endDate)} ($durationText)',
                                  style: TextStyle(
                                      color: context.forest.text, fontSize: 12),
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
                    style: TextStyle(color: context.forest.text54),
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
                              setState(() => _tourId = newGroup.id);
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isBn
                                        ? 'গ্রুপ তৈরি হয়েছে: ${newGroup.name}'
                                        : 'Created group: ${newGroup.name}',
                                  ),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              if (context.mounted) {
                                context.go(tourHubPath(newGroup.id));
                              }
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
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(
                          _isBn ? 'গ্রুপ তৈরি করুন' : 'Create Group',
                          style: TextStyle(color: context.forest.text),
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
              backgroundColor: context.forest.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                _isBn ? 'গ্রুপে যোগ দিন' : 'Join a Group',
                style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isBn
                        ? 'গ্রুপের ৮ অক্ষরের আমন্ত্রণ কোড লিখুন:'
                        : 'Enter the 8-character group invite code:',
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
                      hintText: '7KQ2M9XB',
                      hintStyle: TextStyle(
                          color: context.forest.text38, letterSpacing: 2),
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
                    _isBn ? 'বাতিল' : 'Cancel',
                    style: TextStyle(color: context.forest.text54),
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
                              setState(() => _tourId = joinedGroup.id);
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isBn
                                        ? '${joinedGroup.name} গ্রুপে যুক্ত হয়েছেন!'
                                        : 'Joined ${joinedGroup.name}!',
                                  ),
                                  backgroundColor: AppColors.midGreen,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              if (context.mounted) {
                                context.go(tourHubPath(joinedGroup.id));
                              }
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
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: context.forest.text, strokeWidth: 2),
                        )
                      : Text(
                          _isBn ? 'যোগ দিন' : 'Join',
                          style: TextStyle(color: context.forest.text),
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
    final rawData = _rawProfileData;
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
              border: Border(
                top: BorderSide(color: context.forest.divider12, width: 1),
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
                        color: context.forest.text24,
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
                          _isBn ? 'প্রোফাইল তথ্য পরিবর্তন' : 'EDIT PROFILE',
                          style: TextStyle(
                            color: context.forest.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: context.forest.text54, size: 20),
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: context.forest.divider10),
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
                                        color: context.forest.text
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
                                        else if (profile.coverUrl != null &&
                                            profile.coverUrl!.isNotEmpty)
                                          kIsWeb
                                              ? Image.network(
                                                  signedMediaUrl(
                                                      profile.coverUrl!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const ColoredBox(
                                                          color:
                                                              Colors.black26),
                                                )
                                              : CachedNetworkImage(
                                                  imageUrl: signedMediaUrl(
                                                      profile.coverUrl!),
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) =>
                                                      const ColoredBox(
                                                          color:
                                                              Colors.black26),
                                                )
                                        else
                                          const SizedBox.shrink(),
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
                                                : (profile.avatarUrl != null &&
                                                        profile.avatarUrl!
                                                            .isNotEmpty
                                                    ? (kIsWeb
                                                        ? Image.network(
                                                            signedMediaUrl(
                                                                profile
                                                                    .avatarUrl!),
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_,
                                                                    __, ___) =>
                                                                const Icon(Icons
                                                                    .person),
                                                          )
                                                        : CachedNetworkImage(
                                                            imageUrl:
                                                                signedMediaUrl(
                                                                    profile
                                                                        .avatarUrl!),
                                                            fit: BoxFit.cover,
                                                            errorWidget: (_, __,
                                                                    ___) =>
                                                                const Icon(Icons
                                                                    .person),
                                                          ))
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
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameController,
                            enabled: !isSaving,
                            style: TextStyle(color: context.forest.text),
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
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
                          Text(_isBn ? 'বায়ো (বাংলা)' : 'BIO (BANGLA)',
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: bioBanglaController,
                            enabled: !isSaving,
                            style: TextStyle(color: context.forest.text),
                            maxLines: 2,
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
                              filled: true,
                              hintText: 'আপনার ভ্রমণ নিয়ে কিছু বলুন...',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Bio English
                          Text(_isBn ? 'বায়ো (ইংরেজি)' : 'BIO (ENGLISH)',
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: bioEnglishController,
                            enabled: !isSaving,
                            style: TextStyle(color: context.forest.text),
                            maxLines: 2,
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
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
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: selectedDivision,
                            dropdownColor: context.surfacePanel,
                            style: TextStyle(color: context.forest.text),
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
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
                              style: TextStyle(
                                  color: context.forest.text54,
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
                            style: TextStyle(color: context.forest.text),
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
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
                              style: TextStyle(
                                  color: context.forest.text54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: statusNoteController,
                            enabled: !isSaving,
                            maxLength: 80,
                            style: TextStyle(color: context.forest.text),
                            decoration: InputDecoration(
                              fillColor:
                                  context.forest.text.withValues(alpha: 0.04),
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
                                    foregroundColor: context.forest.text70,
                                    side: BorderSide(
                                        color: context.forest.divider10),
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
                                              'avatarUrl': finalAvatarUrl,
                                              'photoUrl': finalAvatarUrl,
                                              'coverUrl': finalCoverUrl,
                                              'coverPhotoUrl': finalCoverUrl,
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
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_circle_outlined,
                  size: 72, color: context.forest.accentText),
              const SizedBox(height: 20),
              Text(
                _isBn ? 'আপনার প্রোফাইল' : 'Your profile',
                style: TextStyle(
                  color: context.forest.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isBn
                    ? 'গ্রুপ পরিচালনা, ফটো শেয়ার ও খরচ ভাগাভাগি করতে সাইন-ইন করুন।'
                    : 'Sign in to manage your groups, split expenses, and share moments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text70, fontSize: 13),
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
      ),
    );
  }

  Widget _buildProfileSkeleton() {
    return const SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
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
    int unsyncedCount = 0;
    try {
      if (getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        unsyncedCount = await db.getTotalUnsyncedChangesCount();
      }
    } catch (e) {
      debugPrint('Failed to query unsynced changes count: $e');
    }

    if (!context.mounted) return;

    final hasUnsynced = unsyncedCount > 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            if (hasUnsynced) ...[
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.amber, size: 24),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                hasUnsynced
                    ? context.l10n.translate('unsynced_warning_title')
                    : (_isBn ? 'লগআউট করতে চান?' : 'Log out?'),
                style: TextStyle(
                  color: hasUnsynced ? Colors.amber : context.forest.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          hasUnsynced
              ? context.l10n.translate(
                  'unsynced_warning_body',
                  args: {'count': unsyncedCount.toString()},
                )
              : context.l10n.translate('unsynced_safe_logout_body'),
          style: TextStyle(
            color: context.forest.text70,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              hasUnsynced
                  ? context.l10n.translate('unsynced_action_wait_sync')
                  : (_isBn ? 'বাতিল' : 'Cancel'),
              style: TextStyle(
                color:
                    hasUnsynced ? AppColors.mintGreen : context.forest.text54,
                fontWeight: hasUnsynced ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  hasUnsynced ? Colors.red.shade700 : Colors.redAccent,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              hasUnsynced
                  ? context.l10n.translate('unsynced_action_force_logout')
                  : (_isBn ? 'লগআউট' : 'Log Out'),
            ),
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

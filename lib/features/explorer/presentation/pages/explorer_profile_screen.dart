import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/localization/translation_keys.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/value_objects/explorer_score.dart';
import '../../domain/usecases/get_explorer_profile_usecase.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../widgets/badge_shelf.dart';
import '../widgets/travel_heatmap_widget.dart';
import '../widgets/voice_bio_widget.dart';
import '../widgets/weather_destinations_widget.dart';
import '../widgets/social_graph_widget.dart';
import '../../../trust/presentation/pages/achievements_screen.dart';
import '../../../../core/entities/trip_log.dart';
import 'package:bhromon/features/feed/presentation/widgets/trip_log_detail_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/utils/doc_future_cache.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/media_upload_service.dart';
import '../../../../core/widgets/journey_timeline.dart';
import '../../../../core/widgets/district_fill_map.dart';
import '../../../../core/services/diary_badges_service.dart';
import '../widgets/saved_diaries_widget.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/utils/image_sizing.dart';

class ExplorerProfileScreen extends StatefulWidget {
  final String uid;

  const ExplorerProfileScreen({super.key, required this.uid});

  @override
  State<ExplorerProfileScreen> createState() => _ExplorerProfileScreenState();
}

class _ExplorerProfileScreenState extends State<ExplorerProfileScreen> {
  late final GetExplorerProfileUseCase _getExplorerProfile;
  ExplorerProfile? _profile;
  bool _isLoading = false;
  String? _error;
  DocumentSnapshot? _rawProfileDoc;
  String _bioLanguage = 'en';
  String _activeTab = 'identity'; // 'identity' | 'analytics' | 'diary'
  String _activeSubTab = 'logs'; // 'logs' | 'timeline' | 'map' | 'saved'
  bool _showAllMedia = false;
  bool _blockedOther = false;
  bool _blockedByOther = false;

  // Cached streams to completely eliminate unsubscription flashing / shaking
  Stream<QuerySnapshot>? _tripLogsStream;

  static const int _kTripLogPageStep = 10;
  int _visibleTripLogCount = _kTripLogPageStep;

  /// Profiles whose bucket list was already synced this session.
  static final Set<String> _bucketListSyncedFor = {};
  Stream<QuerySnapshot>? _followersStream;
  Stream<QuerySnapshot>? _followingStream;
  Stream<QuerySnapshot>? _bucketListStream;
  Stream<DocumentSnapshot>? _followStatusStream;

  // Cached rank and leaderboard stats to prevent lag
  int? _globalRank;
  int? _totalExplorers;
  List<QueryDocumentSnapshot>? _topExplorers;

  @override
  void initState() {
    super.initState();
    _getExplorerProfile = getIt<GetExplorerProfileUseCase>();
    _initStreams();
    _loadProfile();
  }

  void _initStreams() {
    final targetUid = (widget.uid == 'guest' ||
            widget.uid.isEmpty ||
            widget.uid == 'explorer_user')
        ? 'explorer_user'
        : widget.uid;

    if (targetUid == 'explorer_user') return;

    _tripLogsStream = FirebaseFirestore.instance
        .collection('trip_logs')
        .where('authorId', isEqualTo: targetUid)
        .snapshots();

    _followersStream = FirebaseFirestore.instance
        .collection('follows')
        .where('followedId', isEqualTo: targetUid)
        .snapshots();

    _followingStream = FirebaseFirestore.instance
        .collection('follows')
        .where('followerId', isEqualTo: targetUid)
        .snapshots();

    _bucketListStream = FirebaseFirestore.instance
        .collection('explorer_profiles')
        .doc(targetUid)
        .collection('bucket_list')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  Future<void> _loadLeaderboardAndRank(String uid, int userScore) async {
    try {
      // count() aggregations cost one read per 1,000 index entries instead
      // of downloading every profile just to read the result size.
      final profiles =
          FirebaseFirestore.instance.collection('explorer_profiles');
      final counts = await Future.wait([
        profiles
            .where('explorerScore.value', isGreaterThan: userScore)
            .count()
            .get(),
        profiles.count().get(),
      ]);
      final rank = (counts[0].count ?? 0) + 1;
      final total = counts[1].count ?? 0;

      final topSnap = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .orderBy('explorerScore.value', descending: true)
          .limit(5)
          .get();

      if (mounted) {
        setState(() {
          _globalRank = rank;
          _totalExplorers = total;
          _topExplorers = topSnap.docs;
        });
      }
    } catch (e) {
      debugPrint('Error loading leaderboard/rank: $e');
    }
  }

  Future<void> _syncBucketList(String uid) async {
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('trip_logs')
          .where('authorId', isEqualTo: uid)
          .get();

      final Set<String> visitedDistricts = {};
      for (final doc in logsSnap.docs) {
        final data = doc.data();
        final dist = data['district'] as String?;
        if (dist != null && dist.isNotEmpty) {
          visitedDistricts.add(dist.toLowerCase().trim());
        }
      }

      final bucketSnap = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(uid)
          .collection('bucket_list')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final doc in bucketSnap.docs) {
        final data = doc.data();
        final district =
            (data['district'] ?? '').toString().toLowerCase().trim();
        final bool completed = data['completed'] as bool? ?? false;

        if (visitedDistricts.contains(district) && !completed) {
          batch.update(doc.reference, {'completed': true});
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error syncing bucket list: $e');
    }
  }

  String _t(String key) {
    final values = TranslationKeys.localizedValues[_bioLanguage];
    if (values != null && values.containsKey(key)) {
      return values[key]!;
    }
    return key;
  }

  String _translateDivision(String div) {
    final key = 'div_${div.toLowerCase().trim()}';
    final values = TranslationKeys.localizedValues[_bioLanguage];
    if (values != null && values.containsKey(key)) {
      return values[key]!;
    }
    return div;
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
        _profile = ExplorerProfile(
          uid: 'explorer_user',
          displayName: 'Guest Explorer',
          explorerScore:
              const ExplorerScore(value: 0, tier: TrustTier.unverified),
          tier: TrustTier.unverified,
          badges: const [],
          division: 'Dhaka',
          createdAt: DateTime.now(),
          bio: 'Sign in to sync your exploration log and unlock achievements!',
        );
        _isLoading = false;
        _error = null;
      });
      return;
    }

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

      // Load leaderboard and rank
      _loadLeaderboardAndRank(profile.uid, profile.explorerScore.value);
      // Only the owner can tick off their own bucket list; once per session
      // is enough since it's driven by their published trip logs.
      if (currentUid.isNotEmpty &&
          currentUid == profile.uid &&
          _bucketListSyncedFor.add(profile.uid)) {
        _syncBucketList(profile.uid);
      }

      final rawDocFuture = FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(profile.uid)
          .get();

      bool blockedOther = false;
      bool blockedByOther = false;
      if (currentUid.isNotEmpty && currentUid != profile.uid) {
        final docId = '${currentUid}_${profile.uid}';
        _followStatusStream = FirebaseFirestore.instance
            .collection('follows')
            .doc(docId)
            .snapshots();

        // Independent reads: run them together instead of back to back.
        final blockDocs = await Future.wait([
          FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(currentUid)
              .collection('blocked_users')
              .doc(profile.uid)
              .get(),
          FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(profile.uid)
              .collection('blocked_users')
              .doc(currentUid)
              .get(),
        ]);
        blockedOther = blockDocs[0].exists;
        blockedByOther = blockDocs[1].exists;
      }

      // Fetch the raw document to get bioBangla/bioEnglish
      final doc = await rawDocFuture;

      // Check and award badges dynamically
      List<String> dynamicBadges = [];
      if (currentUid.isNotEmpty && currentUid == profile.uid) {
        final newBadges = DiaryBadgesService.checkAndAwardBadges(profile);
        if (newBadges.isNotEmpty) {
          dynamicBadges = newBadges;
          final updatedBadges = [...profile.badges, ...newBadges];
          await FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(profile.uid)
              .update({'badges': updatedBadges});

          if (mounted) {
            for (final badgeId in newBadges) {
              final badgeDef = DiaryBadgesService.getBadge(badgeId);
              if (badgeDef != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.darkGreen,
                    content: Row(
                      children: [
                        Text(badgeDef.emoji,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            doc.data()?['bioBangla'] != null
                                ? 'অভিনন্দন! আপনি নতুন ব্যাজ "${badgeDef.titleBn}" অর্জন করেছেন!'
                                : 'Congratulations! You earned a new badge: "${badgeDef.titleEn}"!',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
          }
        }
      }

      final finalProfile = dynamicBadges.isNotEmpty
          ? profile.copyWith(badges: [...profile.badges, ...dynamicBadges])
          : profile;

      if (mounted) {
        setState(() {
          _profile = finalProfile;
          _rawProfileDoc = doc;
          _isLoading = false;
          _error = null;
          _blockedOther = blockedOther;
          _blockedByOther = blockedByOther;
          if (doc.exists) {
            final data = doc.data();
            if (data != null) {
              final bn = data['bioBangla'] as String?;
              final en = data['bioEnglish'] as String?;
              if (bn != null && bn.isNotEmpty && (en == null || en.isEmpty)) {
                _bioLanguage = 'bn';
              } else {
                _bioLanguage = 'en';
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_profile == null) {
            _error = e.toString();
          }
        });
      }
    }
  }

  Future<void> _toggleBlockStatus(String currentUid, String targetUid) async {
    setState(() => _isLoading = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(currentUid)
          .collection('blocked_users')
          .doc(targetUid);

      if (_blockedOther) {
        await docRef.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('🔓 Explorer unblocked successfully.')),
          );
        }
      } else {
        await docRef.set({
          'blockedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🚫 Explorer blocked successfully.')),
          );
        }
      }
      _loadProfile();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling block: $e')),
        );
      }
    }
  }

  void _showEditProfileBottomSheet(ExplorerProfile profile) {
    final nameController = TextEditingController(text: profile.displayName);
    final bioController = TextEditingController(text: profile.bio ?? '');

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

    XFile? dialogAvatarFile;
    XFile? dialogCoverFile;
    bool isSaving = false;
    String savingStatus = 'Saving...';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          const double coverHeight = 140.0;
          const double avatarRadius = 42.0;
          final tierColor = AppColors.forTier(profile.tier);

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
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom +
                        MediaQuery.of(context).padding.bottom +
                        24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
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
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'EDIT EXPLORER PROFILE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 1.5,
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
                                                    imageQuality: 80,
                                                    maxWidth:
                                                        kMaxCaptureDimension,
                                                    maxHeight:
                                                        kMaxCaptureDimension);
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
                                            // Fallback gradient always rendered in the background
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
                                            // Image Layer
                                            if (dialogCoverFile != null)
                                              (kIsWeb
                                                  ? Image.network(
                                                      dialogCoverFile!.path,
                                                      cacheWidth:
                                                          context.decodeWidth(),
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return const SizedBox
                                                            .shrink();
                                                      },
                                                    )
                                                  : Image.file(
                                                      File(dialogCoverFile!
                                                          .path),
                                                      cacheWidth:
                                                          context.decodeWidth(),
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return const SizedBox
                                                            .shrink();
                                                      },
                                                    ))
                                            else if (profile.coverUrl != null)
                                              CachedNetworkImage(
                                                memCacheWidth:
                                                    context.decodeWidth(),
                                                imageUrl: profile.coverUrl!,
                                                fit: BoxFit.cover,
                                                errorWidget:
                                                    (context, url, error) {
                                                  return const SizedBox
                                                      .shrink();
                                                },
                                              ),
                                            // Semi-transparent overlay with text/icon
                                            Container(
                                              color: Colors.black
                                                  .withValues(alpha: 0.3),
                                              alignment: Alignment.center,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 18,
                                                    backgroundColor: Colors
                                                        .black
                                                        .withValues(alpha: 0.6),
                                                    child: const Icon(
                                                        Icons
                                                            .camera_alt_outlined,
                                                        size: 18,
                                                        color: Colors.white),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  const Text(
                                                    'TAP TO CHANGE COVER PHOTO',
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: 1.0),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -40,
                                    child: GestureDetector(
                                      onTap: isSaving
                                          ? null
                                          : () async {
                                              final file = await ImagePicker()
                                                  .pickImage(
                                                      source:
                                                          ImageSource.gallery,
                                                      imageQuality: 80,
                                                      maxWidth: 1024,
                                                      maxHeight: 1024);
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
                                                  color: tierColor, width: 3),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: tierColor.withValues(
                                                      alpha: 0.3),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: ClipOval(
                                              child: SizedBox(
                                                width: avatarRadius * 2,
                                                height: avatarRadius * 2,
                                                child: dialogAvatarFile != null
                                                    ? (kIsWeb
                                                        ? Image.network(
                                                            dialogAvatarFile!
                                                                .path,
                                                            cacheWidth: context
                                                                .decodeWidth(
                                                                    avatarRadius *
                                                                        2),
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (context, error,
                                                                    stackTrace) {
                                                              return Container(
                                                                color: AppColors
                                                                    .darkGreen,
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: Text(
                                                                  profile.displayName
                                                                          .isNotEmpty
                                                                      ? profile
                                                                          .displayName[0]
                                                                      : 'E',
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          28,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold),
                                                                ),
                                                              );
                                                            },
                                                          )
                                                        : Image.file(
                                                            File(
                                                                dialogAvatarFile!
                                                                    .path),
                                                            cacheWidth: context
                                                                .decodeWidth(
                                                                    avatarRadius *
                                                                        2),
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (context, error,
                                                                    stackTrace) {
                                                              return Container(
                                                                color: AppColors
                                                                    .darkGreen,
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: Text(
                                                                  profile.displayName
                                                                          .isNotEmpty
                                                                      ? profile
                                                                          .displayName[0]
                                                                      : 'E',
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          28,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold),
                                                                ),
                                                              );
                                                            },
                                                          ))
                                                    : (profile.avatarUrl != null
                                                        ? CachedNetworkImage(
                                                            memCacheWidth: context
                                                                .decodeWidth(
                                                                    avatarRadius *
                                                                        2),
                                                            imageUrl: profile
                                                                .avatarUrl!,
                                                            fit: BoxFit.cover,
                                                            placeholder:
                                                                (context,
                                                                        url) =>
                                                                    Container(
                                                              color: AppColors
                                                                  .darkGreen,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              child:
                                                                  const CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                            Color>(
                                                                        Colors
                                                                            .white),
                                                              ),
                                                            ),
                                                            errorWidget:
                                                                (context, url,
                                                                    error) {
                                                              return Container(
                                                                color: AppColors
                                                                    .darkGreen,
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: Text(
                                                                  profile.displayName
                                                                          .isNotEmpty
                                                                      ? profile
                                                                          .displayName[0]
                                                                      : 'E',
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          28,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold),
                                                                ),
                                                              );
                                                            },
                                                          )
                                                        : Container(
                                                            color: AppColors
                                                                .darkGreen,
                                                            alignment: Alignment
                                                                .center,
                                                            child: Text(
                                                              profile.displayName
                                                                      .isNotEmpty
                                                                  ? profile
                                                                      .displayName[0]
                                                                  : 'E',
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 28,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                            ),
                                                          )),
                                              ),
                                            ),
                                          ),
                                          const CircleAvatar(
                                            radius: 13,
                                            backgroundColor:
                                                AppColors.mintGreen,
                                            child: Icon(Icons.camera_alt,
                                                size: 13, color: Colors.black),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 56),
                              // Display Name
                              const Text('DISPLAY NAME',
                                  style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: nameController,
                                enabled: !isSaving,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.04),
                                  filled: true,
                                  hintText: 'Enter your name',
                                  hintStyle:
                                      const TextStyle(color: Colors.white30),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        const BorderSide(color: Colors.white10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.mintGreen),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Bio English
                              const Text('BIO (ENGLISH)',
                                  style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: bioEnglishController,
                                enabled: !isSaving,
                                style: const TextStyle(color: Colors.white),
                                maxLines: 3,
                                decoration: InputDecoration(
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.04),
                                  filled: true,
                                  hintText: 'Describe your journeys...',
                                  hintStyle:
                                      const TextStyle(color: Colors.white30),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        const BorderSide(color: Colors.white10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.mintGreen),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Bio Bangla
                              const Text('BIO (BANGLA / বাংলা)',
                                  style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: bioBanglaController,
                                enabled: !isSaving,
                                style: const TextStyle(color: Colors.white),
                                maxLines: 3,
                                decoration: InputDecoration(
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.04),
                                  filled: true,
                                  hintText: 'আপনার ভ্রমণ নিয়ে কিছু বলুন...',
                                  hintStyle:
                                      const TextStyle(color: Colors.white30),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        const BorderSide(color: Colors.white10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.mintGreen),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Division
                              const Text('DIVISION',
                                  style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: selectedDivision,
                                dropdownColor: context.surfacePanel,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.04),
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        const BorderSide(color: Colors.white10),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.mintGreen),
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
                              const SizedBox(height: 32),
                              // Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: const BorderSide(
                                            color: Colors.white10),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      onPressed: isSaving
                                          ? null
                                          : () =>
                                              Navigator.pop(bottomSheetContext),
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
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
                                              setDialogState(() {
                                                isSaving = true;
                                              });

                                              try {
                                                String? finalAvatarUrl =
                                                    profile.avatarUrl;
                                                String? finalCoverUrl =
                                                    profile.coverUrl;

                                                if (dialogAvatarFile != null) {
                                                  setDialogState(() {
                                                    savingStatus =
                                                        'Uploading avatar...';
                                                  });
                                                  final timestamp = DateTime
                                                          .now()
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
                                                          dialogAvatarFile!
                                                              .path),
                                                      path:
                                                          'explorer_avatars/${profile.uid}_$timestamp.jpg',
                                                    );
                                                  }
                                                }

                                                if (dialogCoverFile != null) {
                                                  setDialogState(() {
                                                    savingStatus =
                                                        'Uploading cover...';
                                                  });
                                                  final timestamp = DateTime
                                                          .now()
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
                                                          dialogCoverFile!
                                                              .path),
                                                      path:
                                                          'explorer_covers/${profile.uid}_$timestamp.jpg',
                                                    );
                                                  }
                                                }

                                                setDialogState(() {
                                                  savingStatus =
                                                      'Saving profile...';
                                                });

                                                final updated =
                                                    profile.copyWith(
                                                  displayName: nameController
                                                      .text
                                                      .trim(),
                                                  bio: bioEnglishController.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? bioEnglishController
                                                          .text
                                                          .trim()
                                                      : bioController.text
                                                          .trim(),
                                                  division: selectedDivision,
                                                  avatarUrl: finalAvatarUrl,
                                                  coverUrl: finalCoverUrl,
                                                );

                                                if (!context.mounted) return;
                                                final authCubit =
                                                    context.read<AuthCubit>();
                                                await authCubit
                                                    .updateProfile(updated);

                                                await FirebaseFirestore.instance
                                                    .collection(
                                                        'explorer_profiles')
                                                    .doc(profile.uid)
                                                    .set({
                                                  'bioBangla':
                                                      bioBanglaController.text
                                                          .trim(),
                                                  'bioEnglish':
                                                      bioEnglishController.text
                                                          .trim(),
                                                }, SetOptions(merge: true));

                                                if (mounted) {
                                                  _loadProfile();
                                                }
                                                if (bottomSheetContext
                                                    .mounted) {
                                                  Navigator.pop(
                                                      bottomSheetContext);
                                                }
                                              } catch (e) {
                                                debugPrint(
                                                    'Error saving profile: $e');
                                                setDialogState(() {
                                                  isSaving = false;
                                                });
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Failed to save profile: $e'),
                                                        backgroundColor:
                                                            Colors.redAccent),
                                                  );
                                                }
                                              }
                                            },
                                      child: const Text('Save Changes',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSaving)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: AppColors.mintGreen),
                            const SizedBox(height: 16),
                            Text(
                              savingStatus,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      nameController.dispose();
      bioController.dispose();
      bioBanglaController.dispose();
      bioEnglishController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final isOwnProfile = (widget.uid == currentUid && currentUid.isNotEmpty) ||
        ((widget.uid == 'guest' ||
                widget.uid == 'explorer_user' ||
                widget.uid.isEmpty) &&
            currentUid.isEmpty);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/feed');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            'EXPLORER PROFILE',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: isOwnProfile
              ? [
                  IconButton(
                    icon:
                        const Icon(Icons.settings, color: AppColors.mintGreen),
                    onPressed: () => context.push('/settings'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: AppColors.mintGreen),
                    onPressed: () {
                      if (_profile != null) {
                        _showEditProfileBottomSheet(_profile!);
                      }
                    },
                  ),
                ]
              : [
                  if (currentUid.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF1E1E2E),
                      onSelected: (value) {
                        if (value == 'block') {
                          _toggleBlockStatus(currentUid, widget.uid);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'block',
                          child: Text(
                            _blockedOther
                                ? 'Unblock Explorer'
                                : 'Block Explorer',
                            style: TextStyle(
                                color: _blockedOther
                                    ? Colors.green
                                    : Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadProfile,
          color: AppColors.mintGreen,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildProfileSkeleton() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomInset + 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover & Avatar stack
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              const ShimmerLoadingWidget(
                width: double.infinity,
                height: 180,
                borderRadius: 0,
              ),
              Positioned(
                bottom: -46,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF09090E),
                    shape: BoxShape.circle,
                  ),
                  child: const ShimmerLoadingWidget(
                    width: 92,
                    height: 92,
                    borderRadius: 46,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 60),
          // Bio Card placeholder
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF13131E).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: const Column(
              children: [
                ShimmerLoadingWidget(width: 140, height: 18),
                SizedBox(height: 8),
                ShimmerLoadingWidget(width: 100, height: 12),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShimmerLoadingWidget(
                        width: 40, height: 22, borderRadius: 6),
                    SizedBox(width: 8),
                    ShimmerLoadingWidget(
                        width: 60, height: 22, borderRadius: 6),
                  ],
                ),
                SizedBox(height: 16),
                ShimmerLoadingWidget(
                    width: double.infinity, height: 44, borderRadius: 10),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Tab bar placeholder
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                    child: ShimmerLoadingWidget(
                        width: double.infinity, height: 40, borderRadius: 10)),
                SizedBox(width: 8),
                Expanded(
                    child: ShimmerLoadingWidget(
                        width: double.infinity, height: 40, borderRadius: 10)),
                SizedBox(width: 8),
                Expanded(
                    child: ShimmerLoadingWidget(
                        width: double.infinity, height: 40, borderRadius: 10)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Content block placeholders
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ShimmerLoadingWidget(
                    width: double.infinity, height: 72, borderRadius: 16),
                SizedBox(height: 16),
                ShimmerLoadingWidget(
                    width: double.infinity, height: 120, borderRadius: 16),
                SizedBox(height: 16),
                ShimmerLoadingWidget(
                    width: double.infinity, height: 160, borderRadius: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _profile == null) {
      return _buildProfileSkeleton();
    }

    if (_error != null && _profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load profile: $_error',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return const SizedBox.shrink();
    }

    final profile = _profile!;

    if (_blockedByOther) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            const Text(
              'This profile is unavailable.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_blockedOther) {
      final authState = context.read<AuthCubit>().state;
      final currentUid =
          authState is Authenticated ? authState.profile.uid : '';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block,
                size: 64, color: Colors.redAccent.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'You have blocked this explorer.',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unblock to view their profile and travel logs.',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _toggleBlockStatus(currentUid, widget.uid),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Unblock Explorer'),
            ),
          ],
        ),
      );
    }
    final logsStream = _tripLogsStream;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    if (logsStream == null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomInset + 80),
        child: _buildProfileContent(profile, const []),
      );
    }

    final authState = context.read<AuthCubit>().state;
    final currentProfile =
        authState is Authenticated ? authState.profile : null;
    final currentUid = currentProfile?.uid ?? '';
    final targetUid = (widget.uid == 'guest' ||
            widget.uid == 'explorer_user' ||
            widget.uid.isEmpty)
        ? 'explorer_user'
        : widget.uid;
    final isOwnProfile = targetUid == currentUid || currentUid.isEmpty;

    if (isOwnProfile) {
      return StreamBuilder<QuerySnapshot>(
        stream: logsStream,
        builder: (context, tripLogsSnap) {
          final docs = tripLogsSnap.data?.docs ?? [];
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomInset + 80),
            child: _buildProfileContent(profile, docs),
          );
        },
      );
    }

    final docId = '${currentUid}_$targetUid';
    final followStatusSt = _followStatusStream ??
        FirebaseFirestore.instance.collection('follows').doc(docId).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: followStatusSt,
      builder: (context, followSnap) {
        final isFollowing = followSnap.data?.exists ?? false;

        return StreamBuilder<QuerySnapshot>(
          stream: logsStream,
          builder: (context, tripLogsSnap) {
            final rawDocs = tripLogsSnap.data?.docs ?? [];
            final filteredDocs = rawDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final visibility = data['visibility']?.toString() ?? 'community';
              if (visibility == 'private') return false;
              if (visibility == 'friends') return isFollowing;
              return true;
            }).toList();

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottomInset + 80),
              child: _buildProfileContent(profile, filteredDocs),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileContent(
      ExplorerProfile profile, List<QueryDocumentSnapshot> docs) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';
    final isOwnProfile = (widget.uid == currentUid && currentUid.isNotEmpty) ||
        ((widget.uid == 'guest' ||
                widget.uid == 'explorer_user' ||
                widget.uid.isEmpty) &&
            currentUid.isEmpty);

    final tierColor = AppColors.forTier(profile.tier);
    final isBn = _bioLanguage == 'bn';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Facebook-style Header (Cover & Avatar)
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Cover Image
            GestureDetector(
              onTap: () {
                if (isOwnProfile) {
                  _showEditProfileBottomSheet(profile);
                }
              },
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: profile.coverUrl != null
                      ? DecorationImage(
                          image: sizedImage(
                              CachedNetworkImageProvider(
                                profile.coverUrl!,
                                errorListener: (dynamic error) {},
                              ),
                              context.decodeWidth()),
                          fit: BoxFit.cover,
                        )
                      : null,
                  gradient: profile.coverUrl == null
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF0D1B2A),
                            Color(0xFF1B263B),
                            Color(0xFF415A77)
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
                            Colors.black.withValues(alpha: 0.6)
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
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                isBn ? 'কভার পরিবর্তন' : 'Edit Cover',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
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
              bottom: -50,
              child: GestureDetector(
                onTap: () {
                  if (isOwnProfile) {
                    _showEditProfileBottomSheet(profile);
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF09090E),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: tierColor.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: 'profile_avatar_${profile.uid}',
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: AppColors.darkGreen,
                            backgroundImage: profile.avatarUrl != null
                                ? sizedImage(
                                    CachedNetworkImageProvider(
                                      profile.avatarUrl!,
                                      errorListener: (dynamic error) {},
                                    ),
                                    context.decodeWidth(100))
                                : null,
                            child: profile.avatarUrl == null
                                ? Text(
                                    profile.displayName.isNotEmpty
                                        ? profile.displayName[0]
                                        : 'E',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (isOwnProfile)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.grey.shade300, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.black, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 60),

        // Padding wrapper for the remaining details below header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Name & Subtitle
              Center(
                child: Text(
                  profile.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              if (_getDisplayBio(profile).isNotEmpty) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _getDisplayBio(profile),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.4,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (isOwnProfile)
                  Center(
                    child: GestureDetector(
                      onTap: () => _showEditProfileBottomSheet(profile),
                      child: Text(
                        isBn ? 'বায়ো পরিবর্তন করুন' : 'Edit Bio',
                        style: const TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ] else if (isOwnProfile) ...[
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditProfileBottomSheet(profile),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.mintGreen,
                      side: const BorderSide(
                          color: AppColors.mintGreen, width: 0.8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(
                      isBn ? 'বায়ো যুক্ত করুন' : 'Add Bio',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Overlapping Followers Row
              _buildOverlappingFollowers(profile.uid),
              const SizedBox(height: 12),

              // Language Toggle Centered
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLanguageToggle('en', 'EN'),
                  const SizedBox(width: 8),
                  _buildLanguageToggle('bn', 'বাংলা'),
                ],
              ),
              const SizedBox(height: 20),

              // Facebook-style Action Buttons
              _buildFacebookActionButtons(profile, isOwnProfile, currentUid),
              const SizedBox(height: 24),

              // Divider
              Container(
                  height: 0.8, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 20),

              // Facebook-style Intro Section
              Text(
                isBn ? 'পরিচিতি' : 'Intro',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _buildIntroItem(
                  Icons.workspace_premium_outlined,
                  isBn
                      ? 'পদবী: ${profile.tier.displayNameBn}'
                      : 'Tier: ${profile.tier.displayName}'),
              _buildIntroItem(
                  Icons.home_outlined,
                  isBn
                      ? 'বিভাগ: ${_translateDivision(profile.division)}'
                      : 'Lives in ${_translateDivision(profile.division)} Division'),
              _buildIntroItem(
                  Icons.explore_outlined,
                  isBn
                      ? 'অভিযান সম্পন্ন: ${profile.districtsCount} টি জেলা'
                      : 'Explored ${profile.districtsCount} districts in Bangladesh'),
              _buildIntroItem(
                  Icons.calendar_today_outlined,
                  isBn
                      ? 'যোগদান করেছেন: ${_formatJoinDate(profile.createdAt)}'
                      : 'Joined Bhromon in ${_formatJoinDate(profile.createdAt)}'),

              // Follow stats inside Intro
              _buildFacebookFollowStatsRow(profile.uid),

              // Featured Badges collection shelf (Facebook style)
              _buildFacebookFeaturedSection(profile),
              const SizedBox(height: 20),

              _buildExpeditionStatusBanner(docs),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // 4. Custom Segmented Dashboard Tab Switcher
        _buildDashboardTabBar(),
        const SizedBox(height: 20),

        // 5. Dynamic Tab View Content
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: Container(
              key: ValueKey<String>(_activeTab),
              child: _buildDashboardActiveTab(profile, docs, isOwnProfile),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildOverlappingFollowers(String uid) {
    final followersSt = FirebaseFirestore.instance
        .collection('follows')
        .where('followedId', isEqualTo: uid)
        .limit(5)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: followersSt,
      builder: (context, followersSnap) {
        final docs = followersSnap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final followerIds = docs
            .map((d) =>
                (d.data() as Map<String, dynamic>)['followerId'] as String? ??
                '')
            .where((id) => id.isNotEmpty)
            .toList();

        if (followerIds.isEmpty) return const SizedBox.shrink();
        final isBn = _bioLanguage == 'bn';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 24,
                width: 16.0 * followerIds.length + 8.0,
                child: Stack(
                  children: List.generate(followerIds.length, (index) {
                    final fId = followerIds[index];
                    return Positioned(
                      left: index * 14.0,
                      child: Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: const BoxDecoration(
                          color: Color(0xFF09090E),
                          shape: BoxShape.circle,
                        ),
                        child: _MiniAvatarFetcher(uid: fId),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showSocialSheet(context, uid, true),
                child: Text(
                  isBn
                      ? 'আপনাকে অনেকে অনুসরণ করছেন'
                      : '${followerIds.length} mutual connections / followers',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFacebookFeaturedSection(ExplorerProfile profile) {
    if (profile.badges.isEmpty) return const SizedBox.shrink();
    final isBn = _bioLanguage == 'bn';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          isBn ? 'ফিচারড ব্যাজ' : 'Featured Badges',
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: profile.badges.length,
            itemBuilder: (context, index) {
              final badgeId = profile.badges[index];
              final key = badgeId.toLowerCase().trim();
              final badgeDef = DiaryBadgesService.getBadge(key);

              final String emoji = badgeDef?.emoji ?? '🏅';
              final String title = badgeDef != null
                  ? (isBn ? badgeDef.titleBn : badgeDef.titleEn)
                  : badgeId.toUpperCase();
              final String desc = badgeDef != null
                  ? (isBn ? badgeDef.descBn : badgeDef.titleEn)
                  : 'A unique exploration achievement milestone for Bhromon.';
              final String next = isBn
                  ? 'ভ্রমণ অব্যাহত রাখুন এবং এক্সপি অর্জন করুন!'
                  : 'Keep exploring and sharing logs to level up!';

              return GestureDetector(
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: context.surfacePanel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(
                            color: AppColors.mintGreen, width: 0.8),
                      ),
                      title: Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            desc,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isBn ? 'পরবর্তী মাইলস্টোন' : 'NEXT MILESTONE',
                            style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            next,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          child: Text(isBn ? 'অসাধারণ' : 'Awesome',
                              style:
                                  const TextStyle(color: AppColors.mintGreen)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131E),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageToggle(String langCode, String label) {
    final isActive = _bioLanguage == langCode;
    return GestureDetector(
      onTap: () => setState(() => _bioLanguage = langCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.mintGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: isActive
                  ? AppColors.mintGreen.withValues(alpha: 0.4)
                  : Colors.white24,
              width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.mintGreen : Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFacebookActionButtons(
      ExplorerProfile profile, bool isOwnProfile, String currentUid) {
    final isBn = _bioLanguage == 'bn';

    if (isOwnProfile) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push('/editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                isBn ? 'ডায়েরি যুক্ত করুন' : 'Add Log',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showEditProfileBottomSheet(profile),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              icon: const Icon(Icons.edit, size: 16),
              label: Text(
                isBn ? 'প্রোফাইল পরিবর্তন' : 'Edit Profile',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings, color: Colors.white, size: 20),
            ),
          ),
        ],
      );
    }

    final docId = '${currentUid}_${profile.uid}';
    final followStatusSt = _followStatusStream ??
        FirebaseFirestore.instance.collection('follows').doc(docId).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: followStatusSt,
      builder: (context, snapshot) {
        final isFollowing = snapshot.data?.exists ?? false;

        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _toggleFollow(currentUid, profile.uid, isFollowing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFollowing
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.mintGreen,
                  foregroundColor: isFollowing ? Colors.white : Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: isFollowing
                      ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
                      : null,
                ),
                icon: Icon(isFollowing ? Icons.check : Icons.person_add,
                    size: 16),
                label: Text(
                  isFollowing
                      ? (isBn ? 'ফলো করছেন' : 'Following')
                      : (isBn ? 'ফলো করুন' : 'Follow'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  final uids = [currentUid, profile.uid]..sort();
                  final chatId = uids.join('_');
                  context
                      .push('/chat/$chatId', extra: {'otherUid': profile.uid});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text(
                  isBn ? 'মেসেজ' : 'Message',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: PopupMenuButton<String>(
                icon:
                    const Icon(Icons.more_horiz, color: Colors.white, size: 20),
                color: const Color(0xFF1E1E2E),
                onSelected: (value) {
                  if (value == 'block') {
                    _toggleBlockStatus(currentUid, profile.uid);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'block',
                    child: Text(
                      _blockedOther
                          ? (isBn ? 'আনব্লক করুন' : 'Unblock')
                          : (isBn ? 'ব্লক করুন' : 'Block'),
                      style: TextStyle(
                          color:
                              _blockedOther ? Colors.green : Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleFollow(
      String currentUid, String followedId, bool isFollowing) async {
    final docId = '${currentUid}_$followedId';
    final ref = FirebaseFirestore.instance.collection('follows').doc(docId);

    if (isFollowing) {
      await ref.delete();
    } else {
      await ref.set({
        'followerId': currentUid,
        'followedId': followedId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      final authState = context.read<AuthCubit>().state;
      final currentProfile =
          authState is Authenticated ? authState.profile : null;
      final currentName = currentProfile?.displayName ?? 'An explorer';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(followedId)
          .collection('notifications')
          .add({
        'title': 'New Follower!',
        'body': '$currentName started following your travels.',
        'action': 'tier_upgrade',
        'uid': currentUid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Widget _buildIntroItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatJoinDate(DateTime date) {
    const monthsEn = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    const monthsBn = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর'
    ];
    final month = date.month;
    final year = date.year;

    if (_bioLanguage == 'bn') {
      return '${monthsBn[month - 1]} $year';
    }
    return '${monthsEn[month - 1]} $year';
  }

  Widget _buildFacebookFollowStatsRow(String uid) {
    final followersSt = _followersStream ??
        FirebaseFirestore.instance
            .collection('follows')
            .where('followedId', isEqualTo: uid)
            .snapshots();

    final followingSt = _followingStream ??
        FirebaseFirestore.instance
            .collection('follows')
            .where('followerId', isEqualTo: uid)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: followersSt,
      builder: (context, followersSnap) {
        final followersCount = followersSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot>(
          stream: followingSt,
          builder: (context, followingSnap) {
            final followingCount = followingSnap.data?.docs.length ?? 0;
            final isBn = _bioLanguage == 'bn';

            return Column(
              children: [
                GestureDetector(
                  onTap: () => _showSocialSheet(context, uid, true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline,
                            color: Colors.white54, size: 20),
                        const SizedBox(width: 12),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            children: [
                              TextSpan(
                                  text: isBn ? 'ফলোয়ার: ' : 'Followed by '),
                              TextSpan(
                                text: '$followersCount',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              TextSpan(text: isBn ? ' জন' : ' people'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showSocialSheet(context, uid, false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.person_add_alt_1_outlined,
                            color: Colors.white54, size: 20),
                        const SizedBox(width: 12),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            children: [
                              TextSpan(
                                  text: isBn ? 'ফলো করছেন: ' : 'Following '),
                              TextSpan(
                                text: '$followingCount',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              TextSpan(text: isBn ? ' জনকে' : ' people'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildDashboardTabButton('identity', '🏆', 'Identity'),
          _buildDashboardTabButton('analytics', '🗺️', 'Insights'),
          _buildDashboardTabButton('diary', '📖', 'Diary'),
        ],
      ),
    );
  }

  Widget _buildDashboardTabButton(
      String tabKey, String emoji, String fallbackLabel) {
    final isActive = _activeTab == tabKey;
    final isBn = _bioLanguage == 'bn';
    String label = fallbackLabel;
    if (tabKey == 'identity') label = isBn ? 'আইডেন্টিটি' : 'Identity';
    if (tabKey == 'analytics') label = isBn ? 'বিশ্লেষণ' : 'Insights';
    if (tabKey == 'diary') label = isBn ? 'ডায়েরি' : 'Diary';

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppColors.mintGreen : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? AppColors.mintGreen : Colors.white60,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardActiveTab(ExplorerProfile profile,
      List<QueryDocumentSnapshot> docs, bool isOwnProfile) {
    switch (_activeTab) {
      case 'analytics':
        return Column(
          children: [
            _buildExplorerDNACard(docs),
            const SizedBox(height: 20),
            TravelHeatmapWidget(docs: docs),
            const SizedBox(height: 20),
            _buildBangladeshHeatmap(docs),
            const SizedBox(height: 20),
            WeatherDestinationsWidget(docs: docs),
            const SizedBox(height: 20),
            SocialGraphWidget(uid: profile.uid),
            const SizedBox(height: 20),
            _buildMemoryCollage(docs),
          ],
        );
      case 'diary':
        return Column(
          children: [
            _buildProfileTabBar(),
            const SizedBox(height: 16),
            _buildActiveTabContent(profile, docs, isOwnProfile),
          ],
        );
      case 'identity':
      default:
        return Column(
          children: [
            _buildStatsSection(profile),
            const SizedBox(height: 20),
            _buildStatRow(_t('Division'), _translateDivision(profile.division)),
            _buildTierProgressCard(profile),
            const SizedBox(height: 20),
            _buildRankLeaderboard(profile),
            const SizedBox(height: 20),
            if (isOwnProfile) ...[
              _buildQuickNavigationActions(context),
              const SizedBox(height: 20),
            ],
            VoiceBioWidget(uid: profile.uid, isOwnProfile: isOwnProfile),
            const SizedBox(height: 20),
            _buildBucketList(profile.uid, isOwnProfile, docs),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _t('BADGES'),
                style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: BadgeShelf(
                badges: profile.badges,
                isBangla: _bioLanguage == 'bn',
              ),
            ),
            const SizedBox(height: 20),
            _buildTrophyShelf(docs),
            const SizedBox(height: 20),
            if (isOwnProfile) ...[
              _buildSecurityCard(context),
              const SizedBox(height: 20),
              _buildCreatorDashboard(profile, docs),
            ],
          ],
        );
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTierProgressCard(ExplorerProfile profile) {
    final score = profile.explorerScore.value;
    final currentTier = profile.tier;

    String nextTierName = '';
    int currentMin = 0;
    int nextThreshold = 0;

    switch (currentTier) {
      case TrustTier.unverified:
        nextTierName = 'Community Explorer';
        currentMin = 0;
        nextThreshold = 100;
        break;
      case TrustTier.community:
        nextTierName = 'Verified Explorer';
        currentMin = 100;
        nextThreshold = 500;
        break;
      case TrustTier.verified:
        nextTierName = 'Region Expert';
        currentMin = 500;
        nextThreshold = 1500;
        break;
      case TrustTier.regionExpert:
        nextTierName = 'Pioneer';
        currentMin = 1500;
        nextThreshold = 4000;
        break;
      case TrustTier.pioneer:
        nextTierName = 'Max Level';
        currentMin = 4000;
        nextThreshold = 4000;
        break;
    }

    final pointsInCurrentRange = score - currentMin;
    final rangeSize = nextThreshold - currentMin;
    final progress = rangeSize > 0
        ? (pointsInCurrentRange / rangeSize).clamp(0.0, 1.0)
        : 1.0;

    final tierColor = AppColors.forTier(currentTier);
    final pointsNeeded = nextThreshold - score;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tierColor.withValues(alpha: 0.2)),
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech, color: tierColor, size: 24),
              const SizedBox(width: 8),
              Text(
                _t('EXPLORER SCORE & LEVEL'),
                style: TextStyle(
                  color: tierColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '$score ${_t('pts')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t(currentTier.displayName),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Text(
                currentTier == TrustTier.pioneer
                    ? (_bioLanguage == 'bn'
                        ? 'সর্বোচ্চ স্তর অর্জিত'
                        : 'PIONEER MAXED')
                    : (_bioLanguage == 'bn'
                        ? 'পরবর্তী: ${_t(nextTierName)} ($pointsNeeded ${_t('pts')} বাকি)'
                        : 'Next: $nextTierName ($pointsNeeded pts left)'),
                style: TextStyle(
                  color: currentTier == TrustTier.pioneer
                      ? tierColor
                      : Colors.white30,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Text(
            _t('HOW TO EARN SCORE POINTS:'),
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          _buildScoreTipRow(_t('Publish a travel log'), '+50 ${_t('pts')}'),
          _buildScoreTipRow(
              _t('Receive helpful vote on log'), '+10 ${_t('pts')}'),
          _buildScoreTipRow(
              _t('Visit a new district in Bangladesh'), '+100 ${_t('pts')}'),
        ],
      ),
    );
  }

  Widget _buildScoreTipRow(String task, String points) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '• $task',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          Text(
            points,
            style: const TextStyle(
                color: AppColors.mintGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetDashboard(List<QueryDocumentSnapshot> docs) {
    int totalTransport = 0;
    int totalLodging = 0;
    int totalFood = 0;
    int totalShopping = 0;
    int totalActivities = 0;
    int totalOthers = 0;
    int grandTotal = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final costItemsList = data['costItems'] as List<dynamic>? ?? [];
      for (final item in costItemsList) {
        if (item is Map<String, dynamic>) {
          final category =
              (item['category'] ?? '').toString().toLowerCase().trim();
          final amount = (item['amountBDT'] ?? 0) as int;
          grandTotal += amount;
          if (category.contains('transport')) {
            totalTransport += amount;
          } else if (category.contains('lodg') ||
              category.contains('hotel') ||
              category.contains('stay')) {
            totalLodging += amount;
          } else if (category.contains('food') ||
              category.contains('eat') ||
              category.contains('restaurant')) {
            totalFood += amount;
          } else if (category.contains('shop')) {
            totalShopping += amount;
          } else if (category.contains('activit') ||
              category.contains('ticket') ||
              category.contains('entert')) {
            totalActivities += amount;
          } else {
            totalOthers += amount;
          }
        }
      }
    }

    if (grandTotal == 0) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfacePanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Row(
          children: [
            Icon(Icons.pie_chart_outline, color: Colors.white38, size: 24),
            SizedBox(width: 12),
            Text(
              'No expense logs found in travel logs.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    Widget buildCategoryProgress(
        String name, int amount, Color color, IconData icon) {
      final percentage = grandTotal > 0 ? (amount / grandTotal) : 0.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'BDT $amount (${(percentage * 100).toStringAsFixed(1)}%)',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BUDGET EXPENSE ANALYTICS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                'TOTAL: BDT $grandTotal',
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (totalTransport > 0)
            buildCategoryProgress('Transport', totalTransport,
                const Color(0xFF4EA8DE), Icons.directions_bus),
          if (totalLodging > 0)
            buildCategoryProgress(
                'Lodging', totalLodging, const Color(0xFF70E000), Icons.hotel),
          if (totalFood > 0)
            buildCategoryProgress('Food & Dining', totalFood,
                const Color(0xFFFFB703), Icons.fastfood),
          if (totalShopping > 0)
            buildCategoryProgress('Shopping', totalShopping,
                const Color(0xFF9D4EDD), Icons.shopping_bag),
          if (totalActivities > 0)
            buildCategoryProgress('Activities & Tickets', totalActivities,
                const Color(0xFFF15BB5), Icons.local_activity),
          if (totalOthers > 0)
            buildCategoryProgress(
                'Others', totalOthers, Colors.white60, Icons.more_horiz),
        ],
      ),
    );
  }

  Widget _buildMyTripLogsSection(BuildContext context, String uid,
      bool isOwnProfile, List<QueryDocumentSnapshot> docs) {
    final authState = context.read<AuthCubit>().state;
    final profile = authState is Authenticated ? authState.profile : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOwnProfile && profile != null) ...[
          _buildFacebookComposerBox(profile),
        ],
        if (docs.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                'No travel logs shared yet.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
        ] else ...[
          _buildExplorationProgress(docs),
          const SizedBox(height: 12),
          _buildBudgetDashboard(docs),
          const SizedBox(height: 12),
          const Text(
            'TRAVEL LOGS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        // This list sits inside the profile's scroll view, so every card it
        // creates is laid out. Show them in steps rather than all at once.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: min(docs.length, _visibleTripLogCount),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final viewsCount = data['views'] as int? ?? 0;

            TripLog log;
            try {
              log = TripLog.fromJson(data);
            } catch (e) {
              debugPrint('Error parsing TripLog: $e');
              return const SizedBox.shrink();
            }

            final dateStr = log.publishedAt != null
                ? '${log.publishedAt!.day}/${log.publishedAt!.month}/${log.publishedAt!.year}'
                : '${log.lastConfirmed.day}/${log.lastConfirmed.month}/${log.lastConfirmed.year}';

            return GestureDetector(
              onTap: () => TripLogDetailSheet.show(context, log),
              child: Card(
                color: context.surfacePanel,
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              log.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            dateStr,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${log.division} · ${log.district} · ${log.blocks.length} blocks · ${log.helpfulVotes} helpful votes · $viewsCount views',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      if (isOwnProfile) ...[
                        const Divider(color: Colors.white10, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.mintGreen),
                              onPressed: () {
                                context.push('/editor', extra: {
                                  'tripLog': log,
                                  'pinId': log.locationPinId,
                                });
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent),
                              onPressed: () => _showDeleteConfirmation(log),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Delete',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (docs.length > _visibleTripLogCount)
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _visibleTripLogCount += _kTripLogPageStep),
              child: Text(
                'Show more (${docs.length - _visibleTripLogCount})',
                style: const TextStyle(
                    color: Color(0xFF74C69D), fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFacebookComposerBox(ExplorerProfile profile) {
    final isBn = _bioLanguage == 'bn';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.darkGreen,
                backgroundImage: profile.avatarUrl != null
                    ? sizedImage(
                        CachedNetworkImageProvider(
                          profile.avatarUrl!,
                          errorListener: (dynamic error) {},
                        ),
                        context.decodeWidth(36))
                    : null,
                child: profile.avatarUrl == null
                    ? Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName[0]
                            : 'E',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/editor'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      isBn
                          ? 'ভ্রমণের নতুন গল্প লিখুন...'
                          : "What's on your mind?",
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 0.8, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildComposerAction(Icons.photo_library, Colors.greenAccent,
                  isBn ? 'ছবি/ভিডিও' : 'Photo', () => context.push('/editor')),
              _buildComposerAction(Icons.location_on, Colors.redAccent,
                  isBn ? 'চেক-ইন' : 'Check In', () => context.push('/editor')),
              _buildComposerAction(Icons.local_offer, Colors.blueAccent,
                  isBn ? 'ট্যাগ' : 'Tag', () => context.push('/editor')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerAction(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(TripLog log) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surfacePanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text('DELETE TRAVEL LOG',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        content: Text(
            'Are you sure you want to delete "${log.title}"? This action cannot be undone.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await FirebaseFirestore.instance
                    .collection('trip_logs')
                    .doc(log.tripId)
                    .delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Travel log deleted successfully.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to delete log: $e'),
                        backgroundColor: AppColors.amber),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(ExplorerProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn(
              'districts_logged',
              '${profile.districtsDiaryLogged.length} districts',
              Icons.map_outlined),
          _buildStatColumn('total_trip_days', '${profile.totalTripDays} days',
              Icons.calendar_today_outlined),
          _buildStatColumn(
              'total_spent',
              '৳${profile.totalSpentBDT.toStringAsFixed(0)}',
              Icons.payments_outlined),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String labelKey, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.mintGreen, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          _t(labelKey),
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildProfileTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _buildTabButton('logs', '📝', 'Logs'),
          _buildTabButton('timeline', '🗓️', 'Timeline'),
          _buildTabButton('map', '🗺️', 'Map'),
          _buildTabButton('saved', '🔖', 'Saved'),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabKey, String emoji, String fallbackLabel) {
    final isActive = _activeSubTab == tabKey;
    final isBn = _bioLanguage == 'bn';
    String label = fallbackLabel;
    if (tabKey == 'logs') label = isBn ? 'ব্লগ' : 'Logs';
    if (tabKey == 'timeline') label = isBn ? 'টাইমলাইন' : 'Timeline';
    if (tabKey == 'map') label = isBn ? 'মানচিত্র' : 'Map';
    if (tabKey == 'saved') label = isBn ? 'সংরক্ষিত' : 'Saved';

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeSubTab = tabKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.mintGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(ExplorerProfile profile,
      List<QueryDocumentSnapshot> docs, bool isOwnProfile) {
    switch (_activeSubTab) {
      case 'timeline':
        final journeyEntries = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          TripLog log;
          try {
            log = TripLog.fromJson(data);
          } catch (e) {
            log = TripLog(
              tripId: doc.id,
              authorId: data['authorId']?.toString() ?? '',
              title: data['title']?.toString() ?? 'Trip Log',
              locationPinId: data['locationPinId']?.toString() ?? '',
              division: data['division']?.toString() ?? '',
              district: data['district']?.toString() ?? '',
              lastConfirmed: DateTime.now(),
              blocks: const [],
              costItems: const [],
              routePoints: const [],
              trustScore: 50,
              helpfulVotes: 0,
            );
          }
          return JourneyEntry(
            tripId: log.tripId,
            destination: log.title,
            district: log.district,
            date: log.publishedAt ?? log.lastConfirmed,
            tripDays: log.tripDays,
            totalSpent: log.totalSpentBDT,
          );
        }).toList();
        return JourneyTimelineWidget(entries: journeyEntries);

      case 'map':
        final visitedDistrictsNormalized = docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              return (data?['district'] ?? '').toString().trim();
            })
            .where((d) => d.isNotEmpty)
            .toList();
        return DistrictFillMapWidget(
          visitedDistricts: visitedDistrictsNormalized,
          size: MediaQuery.of(context).size.width - 32,
        );

      case 'saved':
        return SavedDiariesWidget(
          uid: profile.uid,
          savedTripLogIds: profile.savedTripLogIds,
        );

      case 'logs':
      default:
        return _buildMyTripLogsSection(
            context, profile.uid, isOwnProfile, docs);
    }
  }

  Widget _buildSecurityCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACCOUNT ACTIONS',
            style: TextStyle(
                color: Colors.white30,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.inbox_outlined, color: AppColors.mintGreen),
            title: const Text('Inbox / Messages',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
                'Access your traveler chats and message history',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: () => context.push('/chats'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline, color: AppColors.mintGreen),
            title: const Text('Change / Set Password',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
                'Add or update password for email sign-in backup',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: () => _showChangePasswordDialog(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.workspace_premium, color: AppColors.gold),
            title: const Text('Milestones & Leaderboards',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('View your unlocked badges and explorer ranks',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (context) => const AchievementsScreen()),
              );
            },
          ),
          const Divider(color: Colors.white10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Sign out of your active explorer session',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: () async {
              context.read<AuthCubit>().signOut();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Delete Profile & Account',
                style: TextStyle(color: Colors.redAccent, fontSize: 14)),
            subtitle: const Text(
                'Permanently delete your profile and travel logs',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.redAccent),
            onTap: () => _showDeleteProfileConfirmation(context),
          ),
        ],
      ),
    );
  }

  void _showDeleteProfileConfirmation(BuildContext context) {
    final confirmationController = TextEditingController();
    bool canDelete = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: context.surfacePanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 0.8),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DELETE ACCOUNT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'This action is irreversible. All your travel logs, profile information, and account details will be permanently deleted.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Type "DELETE" to confirm:',
                style: TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle:
                      const TextStyle(color: Colors.white24, fontSize: 13),
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                onChanged: (val) {
                  setStateDialog(() {
                    canDelete = val.trim() == 'DELETE';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canDelete ? Colors.redAccent : Colors.white10,
                foregroundColor: canDelete ? Colors.white : Colors.white24,
              ),
              onPressed: !canDelete
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      _deleteProfileAndAccount();
                    },
              child: const Text('Delete Permanently',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).then((_) => confirmationController.dispose());
  }

  Future<void> _deleteProfileAndAccount() async {
    final authState = context.read<AuthCubit>().state;
    final uid = authState is Authenticated ? authState.profile.uid : '';
    if (uid.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // 1. Delete all travel logs
      final logsQuery = await FirebaseFirestore.instance
          .collection('trip_logs')
          .where('authorId', isEqualTo: uid)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in logsQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // 2. Delete explorer profile document
      await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(uid)
          .delete();

      // 3. Delete Firebase Auth user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully.')),
        );
        context.read<AuthCubit>().signOut();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Sensitive operation. Please log out and sign back in to delete account.'),
              backgroundColor: Colors.amber,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${e.message}'),
                backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surfacePanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.mintGreen.withValues(alpha: 0.2)),
        ),
        title: const Text(
          'SET NEW PASSWORD',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter a password to set on your account.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Minimum 6 characters',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                fillColor: Colors.white.withValues(alpha: 0.05),
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () async {
              final pwd = passwordController.text.trim();
              if (pwd.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Password must be at least 6 characters.')),
                );
                return;
              }

              Navigator.pop(dialogContext);
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await user.updatePassword(pwd);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Password updated successfully!')),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('No authenticated user session found.')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Update', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    ).then((_) => passwordController.dispose());
  }

  static const Map<String, List<String>> _bangladeshDistricts = {
    'Dhaka': [
      'Dhaka',
      'Faridpur',
      'Gazipur',
      'Gopalganj',
      'Kishoreganj',
      'Madaripur',
      'Manikganj',
      'Munshiganj',
      'Narayanganj',
      'Narsingdi',
      'Rajbari',
      'Shariatpur',
      'Tangail'
    ],
    'Sylhet': ['Habiganj', 'Moulvibazar', 'Sunamganj', 'Sylhet'],
    'Chittagong': [
      'Bandarban',
      'Brahmanbaria',
      'Chandpur',
      'Chittagong',
      'Comilla',
      'Cox\'s Bazar',
      'Feni',
      'Khagrachhari',
      'Lakshmipur',
      'Noakhali',
      'Rangamati'
    ],
    'Barishal': [
      'Barguna',
      'Barishal',
      'Bhola',
      'Jhalokati',
      'Patuakhali',
      'Pirojpur'
    ],
    'Khulna': [
      'Bagerhat',
      'Chuadanga',
      'Jessore',
      'Jhenaidah',
      'Khulna',
      'Kushtia',
      'Magura',
      'Meherpur',
      'Narail',
      'Satkhira'
    ],
    'Rajshahi': [
      'Bogra',
      'Joypurhat',
      'Naogaon',
      'Natore',
      'Chapainawabganj',
      'Pabna',
      'Rajshahi',
      'Sirajganj'
    ],
    'Rangpur': [
      'Dinajpur',
      'Gaibandha',
      'Kurigram',
      'Lalmonirhat',
      'Nilphamari',
      'Panchagarh',
      'Rangpur',
      'Thakurgaon'
    ],
    'Mymensingh': ['Jamalpur', 'Mymensingh', 'Netrokona', 'Sherpur'],
  };

  Widget _buildExplorationProgress(List<QueryDocumentSnapshot> docs) {
    final visitedDistrictsNormalized = docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return (data?['district'] ?? '').toString().trim().toLowerCase();
        })
        .where((d) => d.isNotEmpty)
        .toSet();

    int totalVisited = 0;
    _bangladeshDistricts.forEach((division, districts) {
      for (final dist in districts) {
        if (visitedDistrictsNormalized.contains(dist.toLowerCase())) {
          totalVisited++;
        }
      }
    });

    final overallPercentage = totalVisited / 64.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BANGLADESH EXPLORATION PROGRESS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '$totalVisited / 64 DISTRICTS',
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: overallPercentage,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _bangladeshDistricts.keys.length,
              itemBuilder: (context, index) {
                final division = _bangladeshDistricts.keys.elementAt(index);
                final districts = _bangladeshDistricts[division]!;
                final visitedInDiv = districts
                    .where((d) =>
                        visitedDistrictsNormalized.contains(d.toLowerCase()))
                    .toList();

                final percent = visitedInDiv.length / districts.length;

                return ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  iconColor: AppColors.mintGreen,
                  collapsedIconColor: Colors.white30,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$division Division'.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                      ),
                      Text(
                        '${visitedInDiv.length} / ${districts.length}',
                        style: TextStyle(
                          color: visitedInDiv.isNotEmpty
                              ? AppColors.mintGreen
                              : Colors.white30,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: percent,
                        backgroundColor: Colors.white.withValues(alpha: 0.03),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            visitedInDiv.length == districts.length
                                ? AppColors.mintGreen
                                : const Color(0xFF52B788)
                                    .withValues(alpha: 0.6)),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: districts.map((district) {
                          final isVisited = visitedDistrictsNormalized
                              .contains(district.toLowerCase());
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isVisited
                                  ? AppColors.mintGreen.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isVisited
                                    ? AppColors.mintGreen.withValues(alpha: 0.4)
                                    : Colors.white.withValues(alpha: 0.05),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isVisited) ...[
                                  const Icon(Icons.check,
                                      color: AppColors.mintGreen, size: 12),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  district,
                                  style: TextStyle(
                                    color: isVisited
                                        ? Colors.white
                                        : Colors.white38,
                                    fontSize: 11,
                                    fontWeight: isVisited
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSocialSheet(BuildContext context, String uid, bool isFollowers) {
    // Built once for the sheet, not on every sheet rebuild.
    final socialStream = FirebaseFirestore.instance
        .collection('follows')
        .where(isFollowers ? 'followedId' : 'followerId', isEqualTo: uid)
        .snapshots();
    final authState = context.read<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  isFollowers ? 'FOLLOWERS' : 'FOLLOWING',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10),
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: socialStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: FeedListSkeleton(count: 2));
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Text(
                            'No connections found here.',
                            style:
                                TextStyle(color: Colors.white30, fontSize: 13),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final targetUserId = isFollowers
                            ? (data['followerId'] ?? '') as String
                            : (data['followedId'] ?? '') as String;
                        if (targetUserId.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _UserSocialTile(
                          userId: targetUserId,
                          currentUid: currentUid,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpeditionStatusBanner(List<QueryDocumentSnapshot> docs) {
    String? customLive;
    if (_rawProfileDoc != null) {
      final data = _rawProfileDoc!.data();
      if (data is Map<String, dynamic>) {
        customLive = data['liveExpedition'] as String?;
      }
    }
    final isOwnProfile = widget.uid == FirebaseAuth.instance.currentUser?.uid ||
        (widget.uid.isEmpty && FirebaseAuth.instance.currentUser?.uid == null);
    final isBn = _bioLanguage == 'bn';

    if (customLive == null && docs.isEmpty) {
      final placeholder = Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            const Icon(Icons.explore_outlined, color: Colors.white30, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isBn
                    ? 'স্ট্যাটাস: অভিযানের জন্য প্রস্তুত'
                    : 'Status: Ready for adventure',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            if (isOwnProfile)
              const Icon(Icons.edit_location_alt_outlined,
                  color: AppColors.mintGreen, size: 18),
          ],
        ),
      );

      return isOwnProfile
          ? GestureDetector(
              onTap: _showLiveExpeditionSelector,
              child: placeholder,
            )
          : placeholder;
    }

    String district;
    bool isLive;
    if (customLive != null) {
      district = customLive;
      isLive = true;
    } else {
      final sortedDocs = List<QueryDocumentSnapshot>.from(docs)
        ..sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>?)?['lastConfirmed'];
          final bTime = (b.data() as Map<String, dynamic>?)?['lastConfirmed'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });

      final latestDoc = sortedDocs.first;
      final latestData = latestDoc.data() as Map<String, dynamic>;
      district = (latestData['district'] as String?) ?? 'Bangladesh';
      final rawConfirmed = latestData['lastConfirmed'];
      DateTime confirmedDate = DateTime.now();
      if (rawConfirmed is Timestamp) {
        confirmedDate = rawConfirmed.toDate();
      }

      final diffDays = DateTime.now().difference(confirmedDate).inDays;
      isLive = diffDays <= 3;
    }

    final banner = Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive
              ? AppColors.mintGreen.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLive ? AppColors.mintGreen : Colors.amber,
                ),
              ),
              if (isLive) _expeditionPulseEffect(),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLive
                      ? (isBn ? 'লাইভ অভিযান' : 'LIVE EXPEDITION')
                      : (isBn ? 'বেস ক্যাম্প স্ট্যাটাস' : 'BASE CAMP STATUS'),
                  style: TextStyle(
                    color: isLive ? AppColors.mintGreen : Colors.amber,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLive
                      ? (isBn
                          ? 'অনুসন্ধান করছেন: $district'
                          : 'Exploring: $district')
                      : (isBn
                          ? 'ফিরে এসেছেন: $district থেকে'
                          : 'Back from: $district'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (isOwnProfile) ...[
            const SizedBox(width: 8),
            const Icon(Icons.edit_location_alt,
                color: AppColors.mintGreen, size: 18),
          ],
        ],
      ),
    );

    return isOwnProfile
        ? GestureDetector(
            onTap: _showLiveExpeditionSelector,
            child: banner,
          )
        : banner;
  }

  void _showLiveExpeditionSelector() {
    final List<String> allDistricts = [];
    _bangladeshDistricts.forEach((division, districts) {
      allDistricts.addAll(districts);
    });
    allDistricts.sort();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surfacePanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.mintGreen.withValues(alpha: 0.2)),
        ),
        title: Row(
          children: [
            const Icon(Icons.explore, color: AppColors.mintGreen, size: 20),
            const SizedBox(width: 8),
            Text(
              _bioLanguage == 'bn'
                  ? 'লাইভ অভিযান নির্বাচন'
                  : 'SELECT LIVE EXPEDITION',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _bioLanguage == 'bn'
                    ? 'আপনার বর্তমান অভিযানের স্থানটি নির্বাচন করুন:'
                    : 'Select your current live travel destination:',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allDistricts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        title: Text(
                          _bioLanguage == 'bn'
                              ? '❌ ক্লিয়ার করুন (অভিযান নেই)'
                              : '❌ Clear Current Expedition',
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          try {
                            await FirebaseFirestore.instance
                                .collection('explorer_profiles')
                                .doc(widget.uid)
                                .update(
                                    {'liveExpedition': FieldValue.delete()});
                            _loadProfile(); // Refresh screen state
                          } catch (_) {}
                        },
                      );
                    }
                    final dist = allDistricts[index - 1];
                    return ListTile(
                      title: Text(
                        dist,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white24, size: 16),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        try {
                          await FirebaseFirestore.instance
                              .collection('explorer_profiles')
                              .doc(widget.uid)
                              .update({
                            'liveExpedition': dist,
                            'liveExpeditionTime': FieldValue.serverTimestamp(),
                          });
                          _loadProfile(); // Refresh screen state
                        } catch (_) {}
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expeditionPulseEffect() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: AppColors.mintGreen.withValues(alpha: 0.4), width: 2),
      ),
    );
  }

  Widget _buildExplorerDNACard(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return const SizedBox.shrink();
    }

    double natureCount = 0;
    double adventureCount = 0;
    double heritageCount = 0;
    double culinaryCount = 0;
    double offbeatCount = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final title = (data['title'] ?? '').toString().toLowerCase();

      final blocks = data['blocks'] as List<dynamic>? ?? [];
      String textContent = '';
      for (final block in blocks) {
        if (block is Map<String, dynamic>) {
          if (block['runtimeType'] == 'text' || block['type'] == 'text') {
            textContent +=
                ' ${(block['content'] ?? '').toString().toLowerCase()}';
          }
        }
      }
      final combined = '$title $textContent';

      bool classified = false;
      if (combined.contains('trek') ||
          combined.contains('hill') ||
          combined.contains('climb') ||
          combined.contains('camp') ||
          combined.contains('hike') ||
          combined.contains('adventure')) {
        adventureCount++;
        classified = true;
      }
      if (combined.contains('beach') ||
          combined.contains('lake') ||
          combined.contains('forest') ||
          combined.contains('waterfall') ||
          combined.contains('river') ||
          combined.contains('sea') ||
          combined.contains('nature') ||
          combined.contains('sundarban') ||
          combined.contains('island')) {
        natureCount++;
        classified = true;
      }
      if (combined.contains('history') ||
          combined.contains('mosque') ||
          combined.contains('temple') ||
          combined.contains('fort') ||
          combined.contains('palace') ||
          combined.contains('museum') ||
          combined.contains('heritage') ||
          combined.contains('ruin') ||
          combined.contains('historical')) {
        heritageCount++;
        classified = true;
      }
      if (combined.contains('food') ||
          combined.contains('eat') ||
          combined.contains('cafe') ||
          combined.contains('restaurant') ||
          combined.contains('dining') ||
          combined.contains('biryani') ||
          combined.contains('tea')) {
        culinaryCount++;
        classified = true;
      }
      if (!classified) {
        offbeatCount++;
      }
    }

    final total = natureCount +
        adventureCount +
        heritageCount +
        culinaryCount +
        offbeatCount;
    if (total == 0) return const SizedBox.shrink();

    final categories = [
      'Nature',
      'Adventure',
      'Heritage',
      'Culinary',
      'Offbeat'
    ];
    final Map<String, double> scores = {
      'Nature': natureCount / total,
      'Adventure': adventureCount / total,
      'Heritage': heritageCount / total,
      'Culinary': culinaryCount / total,
      'Offbeat': offbeatCount / total,
    };

    String primaryTrait = 'Offbeat Wanderer';
    double maxScore = -1;
    scores.forEach((key, val) {
      if (val > maxScore) {
        maxScore = val;
        primaryTrait = switch (key) {
          'Nature' => 'Nature Seeker',
          'Adventure' => 'Thrill Explorer',
          'Heritage' => 'Heritage Historian',
          'Culinary' => 'Culinary Nomad',
          _ => 'Offbeat Wanderer',
        };
      }
    });

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRAVEL PROFILE DNA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  primaryTrait.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: RadarChartPainter(
                  scores: scores,
                  categories: categories,
                  accentColor: AppColors.mintGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBangladeshHeatmap(List<QueryDocumentSnapshot> docs) {
    final visitedDistrictsNormalized = docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return (data?['district'] ?? '').toString().trim().toLowerCase();
        })
        .where((d) => d.isNotEmpty)
        .toSet();

    final Map<String, double> divisionProgress = {};
    _bangladeshDistricts.forEach((division, districts) {
      int visitedCount = 0;
      for (final dist in districts) {
        if (visitedDistrictsNormalized.contains(dist.toLowerCase())) {
          visitedCount++;
        }
      }
      divisionProgress[division] = visitedCount / districts.length;
    });

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'REGIONAL EXPLORATION DENSITY',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: BangladeshHeatmapPainter(
                divisionProgress: divisionProgress,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrophyShelf(List<QueryDocumentSnapshot> docs) {
    final visitedDistrictsNormalized = docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          return (data?['district'] ?? '').toString().trim().toLowerCase();
        })
        .where((d) => d.isNotEmpty)
        .toSet();

    final dhakaDistricts = _bangladeshDistricts['Dhaka'] ?? [];
    final hasDhaka = dhakaDistricts
        .any((d) => visitedDistrictsNormalized.contains(d.toLowerCase()));

    final sylhetDistricts = _bangladeshDistricts['Sylhet'] ?? [];
    final hasSylhetAll = sylhetDistricts
        .every((d) => visitedDistrictsNormalized.contains(d.toLowerCase()));

    final hasWanderlust = visitedDistrictsNormalized.length >= 5;

    bool hasBudgetGuru = false;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      int totalLogCost = 0;
      final costItemsList = data['costItems'] as List<dynamic>? ?? [];
      for (final item in costItemsList) {
        if (item is Map<String, dynamic>) {
          totalLogCost += (item['amountBDT'] ?? 0) as int;
        }
      }
      if (totalLogCost > 0 && totalLogCost < 3000) {
        hasBudgetGuru = true;
        break;
      }
    }

    final hasGenerous = docs.length >= 3;

    final trophies = [
      _TrophyItem(
        title: 'Dhaka Pioneer',
        desc: 'Visit a district in Dhaka division',
        icon: Icons.location_city,
        unlocked: hasDhaka,
      ),
      _TrophyItem(
        title: 'Sylhet Conqueror',
        desc: 'Visit all 4 Sylhet districts',
        icon: Icons.landscape,
        unlocked: hasSylhetAll,
      ),
      _TrophyItem(
        title: 'Wanderlust',
        desc: 'Explore 5+ different districts',
        icon: Icons.travel_explore,
        unlocked: hasWanderlust,
      ),
      _TrophyItem(
        title: 'Budget Guru',
        desc: 'Log a trip under BDT 3,000',
        icon: Icons.savings,
        unlocked: hasBudgetGuru,
      ),
      _TrophyItem(
        title: 'Generous Guide',
        desc: 'Share 3+ travel itineraries',
        icon: Icons.rate_review,
        unlocked: hasGenerous,
      ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MILESTONE TROPHY SHELF',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: trophies.length,
              itemBuilder: (context, index) {
                final trophy = trophies[index];
                return GestureDetector(
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: context.surfacePanel,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color: trophy.unlocked
                                  ? AppColors.mintGreen.withValues(alpha: 0.2)
                                  : Colors.white10),
                        ),
                        title: Row(
                          children: [
                            Icon(
                              trophy.icon,
                              color: trophy.unlocked
                                  ? AppColors.mintGreen
                                  : Colors.white24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              trophy.title.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        content: Text(
                          '${trophy.desc}\n\nStatus: ${trophy.unlocked ? 'Unlocked 🎉' : 'Locked 🔒'}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK',
                                style: TextStyle(color: AppColors.mintGreen)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    width: 72,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: trophy.unlocked
                            ? AppColors.mintGreen.withValues(alpha: 0.2)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          trophy.icon,
                          color: trophy.unlocked
                              ? AppColors.mintGreen
                              : Colors.white24,
                          size: 32,
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            trophy.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: trophy.unlocked
                                  ? Colors.white70
                                  : Colors.white24,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorDashboard(
      ExplorerProfile profile, List<QueryDocumentSnapshot> docs) {
    final isVerified = profile.tier.isVerifiedOrAbove;
    if (!isVerified) return const SizedBox.shrink();

    int totalVotes = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      totalVotes += (data?['helpfulVotes'] ?? 0) as int;
    }

    final estimatedEarnings = totalVotes * 50;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  color: AppColors.gold, size: 24),
              const SizedBox(width: 8),
              const Text(
                'CREATOR HUB & ANALYTICS',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricColumn('Travel Logs', '${docs.length}'),
              _buildMetricColumn('Helpful Votes', '$totalVotes'),
              _buildMetricColumn('Est. Earnings', 'BDT $estimatedEarnings'),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white30, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Earnings are calculated from community helpful votes (BDT 50/vote) as part of the Creator Fund.',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
      ],
    );
  }

  String _getDisplayBio(ExplorerProfile profile) {
    if (_rawProfileDoc != null && _rawProfileDoc!.exists) {
      final data = _rawProfileDoc!.data() as Map<String, dynamic>?;
      if (data != null) {
        if (_bioLanguage == 'bn') {
          final bn = data['bioBangla'] as String?;
          if (bn != null && bn.isNotEmpty) return bn;
        } else {
          final en = data['bioEnglish'] as String?;
          if (en != null && en.isNotEmpty) return en;
        }
      }
    }
    return profile.bio ?? 'No bio written yet.';
  }

  Widget _buildQuickNavigationActions(BuildContext context) {
    final bool isBn = _bioLanguage == 'bn';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation_outlined,
                  color: AppColors.mintGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                isBn ? 'কুইক নেভিগেশন' : 'QUICK NAVIGATION',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickNavButton(
                context,
                icon: Icons.dashboard_outlined,
                label: isBn ? 'ড্যাশবোর্ড' : 'Dashboard',
                route: '/dashboard',
                color: const Color(0xFF6366F1),
              ),
              _buildQuickNavButton(
                context,
                icon: Icons.emoji_events_outlined,
                label: isBn ? 'চ্যালেঞ্জ' : 'Challenges',
                route: '/challenges',
                color: const Color(0xFFFFD166),
              ),
              _buildQuickNavButton(
                context,
                icon: Icons.style_outlined,
                label: isBn ? 'ডিসকভার' : 'Discover',
                route: '/discover',
                color: const Color(0xFFEC4899),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickNavButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankLeaderboard(ExplorerProfile profile) {
    final rank = _globalRank;
    final total = _totalExplorers;
    final topDocs = _topExplorers;

    if (rank == null || total == null || topDocs == null) {
      return const PanelSkeleton(height: 120);
    }

    final percentile = total > 0 ? (rank / total) * 100 : 100.0;
    final isTopTen = percentile <= 10.0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfacePanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: AppColors.mintGreen,
              collapsedIconColor: Colors.white54,
              title: Row(
                children: [
                  const Icon(Icons.leaderboard,
                      color: AppColors.mintGreen, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _t('GLOBAL RANK & LEADERBOARD'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _bioLanguage == 'bn'
                          ? 'র‍্যাংক: #$rank, মোট: $total'
                          : 'Rank: #$rank of $total',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isTopTen
                            ? AppColors.gold.withValues(alpha: 0.15)
                            : AppColors.mintGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isTopTen
                            ? (_bioLanguage == 'bn'
                                ? 'সেরা ${percentile.toStringAsFixed(1)}%'
                                : 'TOP ${percentile.toStringAsFixed(1)}%')
                            : (_bioLanguage == 'bn'
                                ? 'সেরা ${percentile.toStringAsFixed(0)}%'
                                : 'TOP ${percentile.toStringAsFixed(0)}%'),
                        style: TextStyle(
                          color:
                              isTopTen ? AppColors.gold : AppColors.mintGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              children: [
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _bioLanguage == 'bn'
                        ? 'সেরা ৫ অভিযাত্রী'
                        : 'TOP 5 LEADERBOARD',
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: topDocs.length,
                  itemBuilder: (context, index) {
                    final doc = topDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String name =
                        (data['displayName'] as String?) ?? 'Explorer';
                    final avatar = data['avatarUrl'] as String?;
                    final scoreVal = data['explorerScore']?['value'] ?? 0;
                    final tierStr = data['tier'] ?? 'unverified';
                    final isCurrentUser = doc.id == profile.uid;

                    final tier = TrustTier.values.firstWhere(
                      (t) => t.name == tierStr,
                      orElse: () => TrustTier.unverified,
                    );
                    final displayName = tier.displayName;

                    return GestureDetector(
                      onTap: () {
                        context.push('/profile/${doc.id}');
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCurrentUser
                              ? AppColors.mintGreen.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrentUser
                                ? AppColors.mintGreen.withValues(alpha: 0.2)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: index == 0
                                    ? AppColors.gold.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: index == 0
                                        ? AppColors.gold
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.darkGreen,
                              backgroundImage: avatar != null
                                  ? sizedImage(
                                      CachedNetworkImageProvider(
                                        avatar,
                                        errorListener: (dynamic error) {},
                                      ),
                                      context.decodeWidth(28))
                                  : null,
                              child: avatar == null
                                  ? Text(
                                      name.isNotEmpty ? name[0] : 'E',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: isCurrentUser
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _t(displayName).toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white30,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$scoreVal ${_t('pts')}',
                              style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/leaderboard'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _t('View Full Leaderboard'),
                        style: const TextStyle(
                          color: AppColors.mintGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward,
                          color: AppColors.mintGreen, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBucketList(
      String uid, bool isOwnProfile, List<QueryDocumentSnapshot> docs) {
    final Set<String> visitedDistricts = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final dist = data['district'] as String?;
      if (dist != null && dist.isNotEmpty) {
        visitedDistricts.add(dist.toLowerCase().trim());
      }
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _bucketListStream ??
          FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(uid)
              .collection('bucket_list')
              .orderBy('addedAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final items = snapshot.data!.docs;
        int completedCount = 0;

        for (final item in items) {
          final data = item.data() as Map<String, dynamic>;
          final district =
              (data['district'] ?? '').toString().toLowerCase().trim();
          final bool completed = data['completed'] as bool? ?? false;
          final isDone = completed || visitedDistricts.contains(district);

          if (isDone) {
            completedCount++;
          }
        }

        final double progress =
            items.isEmpty ? 0.0 : completedCount / items.length;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfacePanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bookmark_outline,
                          color: AppColors.mintGreen, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'EXPLORATION BUCKET LIST',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  if (isOwnProfile)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.mintGreen, size: 20),
                      onPressed: () => _showAddToBucketListDialog(uid),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'No destinations added to your bucket list yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$completedCount of ${items.length} completed',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: AppColors.mintGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.mintGreen),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final doc = items[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String district =
                        (data['district'] as String?) ?? 'Unknown';
                    final String division =
                        (data['division'] as String?) ?? 'Unknown';
                    final bool completed = data['completed'] as bool? ?? false;
                    final isDone = completed ||
                        visitedDistricts
                            .contains(district.toString().toLowerCase().trim());

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDone ? Icons.check_circle : Icons.circle_outlined,
                            color:
                                isDone ? AppColors.mintGreen : Colors.white24,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  district,
                                  style: TextStyle(
                                    color: Colors.white,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  division,
                                  style: const TextStyle(
                                      color: Colors.white30, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          if (isOwnProfile)
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.white30, size: 18),
                              onPressed: () => FirebaseFirestore.instance
                                  .collection('explorer_profiles')
                                  .doc(uid)
                                  .collection('bucket_list')
                                  .doc(doc.id)
                                  .delete(),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showAddToBucketListDialog(String uid) {
    String selectedDivision = 'Dhaka';
    String selectedDistrict = 'Dhaka';

    final Map<String, List<String>> divDistricts = {
      'Dhaka': [
        'Dhaka',
        'Gazipur',
        'Narayanganj',
        'Munshiganj',
        'Manikganj',
        'Faridpur',
        'Madaripur',
        'Gopalganj'
      ],
      'Chittagong': [
        'Cox\'s Bazar',
        'Bandarban',
        'Rangamati',
        'Khagrachhari',
        'Chittagong',
        'Feni',
        'Cumilla',
        'Noakhali'
      ],
      'Sylhet': ['Sylhet', 'Moulvibazar', 'Sunamganj', 'Habiganj'],
      'Khulna': ['Khulna', 'Jessore', 'Bagerhat', 'Satkhira', 'Kushtia'],
      'Rajshahi': ['Rajshahi', 'Bogura', 'Natore', 'Pabna', 'Naogaon'],
      'Rangpur': ['Rangpur', 'Dinajpur', 'Panchagarh', 'Kurigram'],
      'Barishal': ['Barishal', 'Patuakhali', 'Bhola', 'Pirojpur'],
      'Mymensingh': ['Mymensingh', 'Netrokona', 'Sherpur', 'Jamalpur']
    };

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.surfacePanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.mintGreen.withValues(alpha: 0.2)),
          ),
          title: const Text('ADD TO BUCKET LIST',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Division',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: selectedDivision,
                dropdownColor: context.surfacePanel,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: divDistricts.keys
                    .map((div) => DropdownMenuItem(
                          value: div,
                          child: Text(div),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedDivision = val;
                      selectedDistrict = divDistricts[val]!.first;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('District',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: selectedDistrict,
                dropdownColor: context.surfacePanel,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: divDistricts[selectedDivision]!
                    .map((dist) => DropdownMenuItem(
                          value: dist,
                          child: Text(dist),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedDistrict = val;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await FirebaseFirestore.instance
                    .collection('explorer_profiles')
                    .doc(uid)
                    .collection('bucket_list')
                    .add({
                  'district': selectedDistrict,
                  'division': selectedDivision,
                  'addedAt': FieldValue.serverTimestamp(),
                  'completed': false,
                });
              },
              child: const Text('Add',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCollage(List<QueryDocumentSnapshot> docs) {
    final List<String> imageUrls = [];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final blocks = data['blocks'] as List<dynamic>? ?? [];
      for (final block in blocks) {
        if (block is Map<String, dynamic>) {
          final type = block['runtimeType'] ?? block['type'];
          if (type == 'image' &&
              block['storageUrl'] != null &&
              block['storageUrl'].toString().isNotEmpty) {
            imageUrls.add(block['storageUrl'].toString());
          }
        }
      }
    }

    if (imageUrls.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfacePanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.photo_library_outlined,
                color: Colors.white38, size: 24),
            const SizedBox(width: 12),
            Text(
              _t('No memories found. Add images to trip logs!'),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final displayedImages =
        _showAllMedia ? imageUrls : imageUrls.take(9).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library_outlined,
                  color: AppColors.mintGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                _t('TRAVEL MEMORY COLLAGE'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                _bioLanguage == 'bn'
                    ? '${imageUrls.length}${_t('photos')}'
                    : '${imageUrls.length} photos',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayedImages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final url = displayedImages[index];
              return GestureDetector(
                onTap: () => _showFullScreenImage(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    memCacheWidth: context.decodeWidth(),
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.mintGreen),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.broken_image_outlined,
                          color: Colors.white24),
                    ),
                  ),
                ),
              );
            },
          ),
          if (imageUrls.length > 9) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAllMedia = !_showAllMedia;
                  });
                },
                icon: Icon(
                  _showAllMedia
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.mintGreen,
                  size: 18,
                ),
                label: Text(
                  _t(_showAllMedia ? 'Show Less' : 'Show More'),
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showFullScreenImage(String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                memCacheWidth: context.decodeWidth(),
                imageUrl: url,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSocialTile extends StatelessWidget {
  final String userId;
  final String currentUid;

  const _UserSocialTile({required this.userId, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: DocFutureCache.instance.get(FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(userId)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            title: SizedBox(
              width: 100,
              height: 12,
              child: LinearProgressIndicator(
                  color: AppColors.mintGreen, backgroundColor: Colors.white10),
            ),
          );
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        final String displayName =
            (data['displayName'] as String?) ?? 'Explorer';
        final avatarUrl = data['avatarUrl'] as String?;
        final tierName = data['tier'] ?? 'unverified';
        final tier = TrustTier.values.firstWhere(
          (t) => t.name == tierName,
          orElse: () => TrustTier.unverified,
        );
        final color = AppColors.forTier(tier);

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: AppColors.darkGreen,
            backgroundImage: avatarUrl != null
                ? sizedImage(
                    CachedNetworkImageProvider(
                      avatarUrl,
                      errorListener: (dynamic error) {},
                    ),
                    context.decodeWidth())
                : null,
            child: avatarUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'E',
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          title: Row(
            children: [
              Text(displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: color.withValues(alpha: 0.5), width: 0.5),
                ),
                child: Text(
                  tier.displayName.toUpperCase(),
                  style: TextStyle(
                      color: color, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          trailing: userId == currentUid
              ? null
              : IconButton(
                  icon: const Icon(Icons.chat_bubble_outline,
                      color: AppColors.mintGreen),
                  onPressed: () {
                    Navigator.pop(context); // close sheet
                    final uids = [currentUid, userId]..sort();
                    final chatId = uids.join('_');
                    context.push('/chat/$chatId', extra: {'otherUid': userId});
                  },
                ),
          onTap: () {
            Navigator.pop(context); // close sheet
            context.push('/profile/$userId');
          },
        );
      },
    );
  }
}

class RadarChartPainter extends CustomPainter {
  final Map<String, double> scores;
  final List<String> categories;
  final Color accentColor;

  RadarChartPainter({
    required this.scores,
    required this.categories,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2 * 0.8;

    final paintLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..color = accentColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final paintStroke = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 1; i <= 3; i++) {
      final r = radius * (i / 3);
      final path = Path();
      for (int j = 0; j < categories.length; j++) {
        final angle = (j * 2 * 3.14159265 / categories.length) - 3.14159265 / 2;
        final x = centerX + r * cos(angle);
        final y = centerY + r * sin(angle);
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paintLine);
    }

    for (int j = 0; j < categories.length; j++) {
      final angle = (j * 2 * 3.14159265 / categories.length) - 3.14159265 / 2;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);
      canvas.drawLine(Offset(centerX, centerY), Offset(x, y), paintLine);

      final label = categories[j];
      final labelAngle = angle;
      final labelRadius = radius + 15;
      final lx = centerX + labelRadius * cos(labelAngle);
      final ly = centerY + labelRadius * sin(labelAngle) - 6;

      textPainter.text = TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(
            color: Colors.white60,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(lx - textPainter.width / 2, ly));
    }

    final polyPath = Path();
    for (int j = 0; j < categories.length; j++) {
      final angle = (j * 2 * 3.14159265 / categories.length) - 3.14159265 / 2;
      final scoreVal = scores[categories[j]] ?? 0.0;
      final r = radius * scoreVal.clamp(0.0, 1.0);
      final x = centerX + r * cos(angle);
      final y = centerY + r * sin(angle);
      if (j == 0) {
        polyPath.moveTo(x, y);
      } else {
        polyPath.lineTo(x, y);
      }
    }
    polyPath.close();

    canvas.drawPath(polyPath, paintFill);
    canvas.drawPath(polyPath, paintStroke);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (int j = 0; j < categories.length; j++) {
      final angle = (j * 2 * 3.14159265 / categories.length) - 3.14159265 / 2;
      final scoreVal = scores[categories[j]] ?? 0.0;
      final r = radius * scoreVal.clamp(0.0, 1.0);
      final x = centerX + r * cos(angle);
      final y = centerY + r * sin(angle);
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class BangladeshHeatmapPainter extends CustomPainter {
  final Map<String, double> divisionProgress;

  BangladeshHeatmapPainter({required this.divisionProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final Map<String, Offset> positions = {
      'Rangpur': Offset(w * 0.25, h * 0.15),
      'Rajshahi': Offset(w * 0.20, h * 0.40),
      'Mymensingh': Offset(w * 0.50, h * 0.25),
      'Sylhet': Offset(w * 0.78, h * 0.25),
      'Dhaka': Offset(w * 0.50, h * 0.50),
      'Khulna': Offset(w * 0.22, h * 0.72),
      'Barishal': Offset(w * 0.48, h * 0.82),
      'Chittagong': Offset(w * 0.78, h * 0.72),
    };

    final Map<String, List<String>> connections = {
      'Rangpur': ['Rajshahi', 'Mymensingh'],
      'Rajshahi': ['Dhaka', 'Khulna'],
      'Mymensingh': ['Dhaka', 'Sylhet'],
      'Sylhet': ['Dhaka', 'Chittagong'],
      'Dhaka': ['Barishal', 'Khulna', 'Chittagong'],
      'Barishal': ['Khulna', 'Chittagong'],
    };

    final linkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    connections.forEach((start, ends) {
      final pStart = positions[start];
      if (pStart == null) return;
      for (final end in ends) {
        final pEnd = positions[end];
        if (pEnd != null) {
          canvas.drawLine(pStart, pEnd, linkPaint);
        }
      }
    });

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    positions.forEach((name, pos) {
      final progress = divisionProgress[name] ?? 0.0;
      final nodeColor = Color.lerp(
        Colors.white.withValues(alpha: 0.05),
        AppColors.mintGreen,
        progress,
      )!;

      final fillPaint = Paint()
        ..color = nodeColor.withValues(alpha: progress > 0.0 ? 0.25 : 0.05)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = progress > 0.0
            ? nodeColor.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(pos, 28, fillPaint);
      canvas.drawCircle(pos, 28, borderPaint);

      textPainter.text = TextSpan(
        text: name.toUpperCase().substring(0, 3),
        style: TextStyle(
          color: progress > 0.0 ? Colors.white : Colors.white30,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(pos.dx - textPainter.width / 2, pos.dy - 10));

      textPainter.text = TextSpan(
        text: '${(progress * 100).toInt()}%',
        style: TextStyle(
          color: progress > 0.0 ? AppColors.mintGreen : Colors.white24,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(pos.dx - textPainter.width / 2, pos.dy + 3));
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TrophyItem {
  final String title;
  final String desc;
  final IconData icon;
  final bool unlocked;

  _TrophyItem({
    required this.title,
    required this.desc,
    required this.icon,
    required this.unlocked,
  });
}

class ShimmerLoadingWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoadingWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoadingWidget> createState() => _ShimmerLoadingWidgetState();
}

class _ShimmerLoadingWidgetState extends State<ShimmerLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFF161622),
                Color(0xFF28293D),
                Color(0xFF161622),
              ],
              stops: const [0.3, 0.5, 0.7],
              begin: Alignment(-2.0 + _controller.value * 4.0, -1.0),
              end: Alignment(-1.0 + _controller.value * 4.0, 1.0),
            ),
          ),
        );
      },
    );
  }
}

class _MiniAvatarFetcher extends StatelessWidget {
  final String uid;
  const _MiniAvatarFetcher({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: DocFutureCache.instance
          .get(FirebaseFirestore.instance.collection('users').doc(uid)),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final avatarUrl = data?['avatarUrl'] as String?;
        final displayName = data?['displayName'] as String? ?? 'E';
        return CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.darkGreen,
          backgroundImage: avatarUrl != null
              ? sizedImage(
                  CachedNetworkImageProvider(
                    avatarUrl,
                    errorListener: (dynamic error) {},
                  ),
                  context.decodeWidth(24))
              : null,
          child: avatarUrl == null
              ? Text(
                  displayName.isNotEmpty ? displayName[0] : 'E',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                )
              : null,
        );
      },
    );
  }
}

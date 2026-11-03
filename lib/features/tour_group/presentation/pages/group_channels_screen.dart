import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/swipe_pager.dart';
import '../../data/channel_read_store.dart';
import '../../data/channel_message_cache.dart';
import '../../data/channel_swipe_controller.dart';
import '../../data/tour_channel_repository.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_uploader.dart';
import '../../data/voice_room_service.dart';
import '../../domain/models/channel_models.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/channel_draft_rules.dart';
import '../../domain/services/chat_commands.dart';
import '../../domain/services/chat_mentions.dart';
import '../../domain/services/fund_analytics.dart';
import '../../domain/services/media_rules.dart';
import '../tour_routes.dart';
import '../../domain/services/presence_rules.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../widgets/channel_composer.dart';
import '../widgets/channel_media_viewer.dart';
import '../widgets/channel_message_bubble.dart';
import '../widgets/cached_channel_messages.dart';
import '../widgets/channel_message_listener.dart';
import '../widgets/channel_sheets.dart';

enum _ChannelMenu { newChannel, editChannel, deleteChannel, toggleMute }

class GroupChannelsScreen extends StatefulWidget {
  final String tourId;

  const GroupChannelsScreen({super.key, required this.tourId});

  @override
  State<GroupChannelsScreen> createState() => _GroupChannelsScreenState();
}

class _GroupChannelsScreenState extends State<GroupChannelsScreen> {
  final TourGroupRepository _groups = TourGroupRepository();
  late final TourChannelRepository _repo =
      TourChannelRepository(groups: _groups);
  final ChannelReadStore _store = ChannelReadStore();
  final VoiceRoomService _voiceService = VoiceRoomService();

  // The channel swipe. The pager and the chip strip follow one selection.
  final PageController _channelPager = PageController();
  final ScrollController _stripController = ScrollController();
  final Map<String, GlobalKey> _chipKeys = {};
  // Per channel: the newest messages waiting to be written to this device's cache,
  // and the timer that writes them once the list has been still for a moment.
  final Map<String, List<ChannelMessage>> _cacheScheduled = {};
  final Map<String, Timer> _cacheTimers = {};
  // Rough width of one chip with its gap, used to reach a chip that the strip
  // has not built yet.
  static const double _chipSlotWidth = 120;

  final List<StreamSubscription<dynamic>> _subs = [];
  // Whether the circle is a family circle, which has its own built-in channels.
  bool _isFamily = false;
  bool _isOffice = false;
  bool _isCampus = false;
  bool _isMess = false;
  bool _isSociety = false;
  bool _isSamity = false;
  bool _isSchool = false;
  bool _isSports = false;
  bool _isStudy = false;
  bool _isCommittee = false;

  /// Last-seen time of each member, keyed by email. Drives the online count.
  Map<String, DateTime?> _presence = const {};
  Timer? _presenceBeat;
  Timer? _presenceRefresh;
  List<TourChannel> _channelDocs = const [];
  List<TourMember> _members = const [];
  List<BusSeat> _seats = const [];
  List<HotelRoom> _rooms = const [];
  List<RouteCheckpoint> _checkpoints = const [];
  String? _liveStopId;
  bool _itineraryOpen = false;

  String _selectedId = kBuiltInChannelIds.first;
  final Map<String, DateTime?> _lastRead = {};
  final Map<String, DateTime?> _divider = {};
  final Set<String> _prefsLoaded = {};
  final Set<String> _muted = {};

  final Map<String, Stream<List<ChannelMessage>>> _messageStreams = {};
  final Map<String, Stream<List<ChannelMessage>>> _latestStreams = {};
  final Map<String, Stream<List<ChannelMessage>>> _mentionStreams = {};
  final Map<String, Stream<List<TypingMember>>> _typingStreams = {};
  final Map<String, TextEditingController> _drafts = {};
  final FocusNode _focus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchText = '';
  bool _searching = false;

  ChannelReply? _replyTo;
  ChannelMessage? _editing;
  final List<PendingAttachment> _pending = [];
  bool _sending = false;
  bool _recordingVoice = false;
  double _uploadProgress = 0;
  int _uploadDone = 0;
  int _uploadTotal = 0;
  TourMediaUpload? _currentUpload;

  MentionQuery? _mentionQuery;
  int _mentionCursor = 0;
  List<String> _mentionLabels = const [];

  DateTime? _lastTypingSignal;
  String? _typingIn;
  Timer? _typingStop;

  String get _me => _groups.currentEmail;

  bool get _isAdmin {
    final me = normalizeEmail(_me);
    for (final m in _members) {
      if (normalizeEmail(m.email) == me) return m.role != TourRole.member;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    ChannelSwipeController.instance.addListener(_onSwipeSettingChanged);
    _subs.addAll([
      _repo.watchChannels(widget.tourId).listen((channels) {
        _update(() => _channelDocs = channels);
        for (final c in _channels) {
          unawaited(_ensurePrefs(c.id));
        }
      }, onError: (_) {}),
      _groups
          .watchMembers(widget.tourId)
          .listen((m) => _update(() => _members = m), onError: (_) {}),
      _groups
          .watchBusSeats(widget.tourId)
          .listen((s) => _update(() => _seats = s), onError: (_) {}),
      _groups
          .watchHotelRooms(widget.tourId)
          .listen((r) => _update(() => _rooms = r), onError: (_) {}),
      _groups
          .watchCheckpoints(widget.tourId)
          .listen((c) => _update(() => _checkpoints = c), onError: (_) {}),
      _repo
          .watchLiveStop(widget.tourId)
          .listen((id) => _update(() => _liveStopId = id), onError: (_) {}),
      _voiceService.changes.listen((_) => _update(() {})),
      _repo
          .watchPresence(widget.tourId)
          .listen((p) => _update(() => _presence = p), onError: (_) {}),
    ]);
    for (final id in kAllBuiltInChannelIds) {
      unawaited(_ensurePrefs(id));
    }
    _subs.add(_groups.watchGroup(widget.tourId).listen(
        (TourGroup? group) => _update(() {
              _isFamily = group?.isFamily ?? false;
              _isOffice = group?.isOffice ?? false;
              _isCampus = group?.isCampus ?? false;
              _isMess = group?.isMess ?? false;
              _isSociety = group?.isSociety ?? false;
              _isSamity = group?.isSamity ?? false;
              _isSchool = group?.isSchool ?? false;
              _isSports = group?.isSports ?? false;
              _isStudy = group?.isStudy ?? false;
              _isCommittee = group?.isCommittee ?? false;
            }),
        onError: (_) {}));
    unawaited(_markHere());
    _presenceBeat = Timer.periodic(kPresenceHeartbeat, (_) => _markHere());
    // Recounts the online members, so someone who has gone quiet drops out
    // even though nothing was written.
    _presenceRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _markHere() async {
    try {
      await _repo.markPresent(widget.tourId);
    } catch (e) {
      logWarning('[GroupChannels] presence not recorded: $e');
    }
  }

  int _onlineCount() {
    final now = DateTime.now();
    return _presence.values.where((seen) => isOnlineAt(seen, now)).length;
  }

  @override
  void dispose() {
    ChannelSwipeController.instance.removeListener(_onSwipeSettingChanged);
    _stopTyping();
    _presenceBeat?.cancel();
    _presenceRefresh?.cancel();
    unawaited(_repo.markAway(widget.tourId));
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _focus.dispose();
    for (final timer in _cacheTimers.values) {
      timer.cancel();
    }
    _channelPager.dispose();
    _stripController.dispose();
    _searchCtrl.dispose();
    for (final c in _drafts.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether swiping the message area changes channel (a Settings toggle).
  bool get _swipeChannels => ChannelSwipeController.instance.enabled;

  void _onSwipeSettingChanged() => _update(() {});

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  // ---------------------------------------------------------------------------
  // Channels and per-device state
  // ---------------------------------------------------------------------------

  /// The built-in channels, then the ones admins added, by name.
  List<TourChannel> get _channels {
    final byId = {for (final c in _channelDocs) c.id: c};
    final builtIns = [
      for (final id in builtInChannelIdsFor(
        family: _isFamily,
        office: _isOffice,
        campus: _isCampus,
        mess: _isMess,
        society: _isSociety,
        samity: _isSamity,
        school: _isSchool,
        sports: _isSports,
        study: _isStudy,
        committee: _isCommittee,
      ))
        byId[id] ?? TourChannel(id: id),
    ];
    final custom = _channelDocs.where((c) => !c.isBuiltIn).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...builtIns, ...custom];
  }

  TourChannel _selectedOf(List<TourChannel> channels) {
    return channels.firstWhere(
      (c) => c.id == _selectedId,
      orElse: () => channels.first,
    );
  }

  Future<void> _ensurePrefs(String channelId) async {
    if (_prefsLoaded.contains(channelId)) return;
    _prefsLoaded.add(channelId);
    final read = await _store.lastRead(widget.tourId, channelId);
    final muted = await _store.isMuted(widget.tourId, channelId);
    _update(() {
      _lastRead[channelId] = read;
      _divider[channelId] = read;
      if (muted) _muted.add(channelId);
    });
  }

  void _selectChannel(String channelId) {
    if (shouldClearEditDraftOnSwitch(
      isEditing: _editing != null,
      fromChannelId: _selectedId,
      toChannelId: channelId,
    )) {
      _draftFor(_selectedId).clear();
    }
    _update(() {
      _selectedId = channelId;
      _divider[channelId] = _lastRead[channelId];
      _replyTo = null;
      _editing = null;
      _mentionQuery = null;
      _mentionLabels = const [];
    });
  }

  /// Saves the newest time the reader has seen, once the channel's read state
  /// has loaded. The divider keeps the time the channel was opened.
  void _markReadSoon(String channelId, DateTime newest) {
    if (!_prefsLoaded.contains(channelId)) return;
    final current = _lastRead[channelId];
    if (current != null && !newest.isAfter(current)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = _lastRead[channelId];
      if (now != null && !newest.isAfter(now)) return;
      _update(() => _lastRead[channelId] = newest);
      unawaited(_store.markRead(widget.tourId, channelId, newest));
    });
  }

  String _titleOf(TourChannel channel) {
    final l10n = context.l10n;
    if (channel.id == kBuiltInVoiceChannelId) {
      return l10n.translate('chan_voice_lounge');
    }
    if (channel.kind == ChannelKind.voice) {
      return channel.name.isEmpty ? '🔊 Voice' : '🔊 ${channel.name}';
    }
    switch (channel.id) {
      case 'general':
        return l10n.translate('tour_channel_general');
      case 'food':
        return l10n.translate(_isOffice
            ? 'office_channel_food'
            : _isCampus
                ? 'campus_channel_food'
                : _isMess
                    ? 'mess_channel_food'
                    : _isSociety
                        ? 'society_channel_food'
                        : _isSamity
                            ? 'samity_channel_food'
                            : _isSchool
                                ? 'school_channel_food'
                                : _isSports
                                    ? 'sports_channel_food'
                                    : _isStudy
                                        ? 'study_channel_food'
                                        : _isCommittee
                                            ? 'committee_channel_food'
                                            : _isFamily
                                                ? 'family_channel_food'
                                                : 'tour_channel_food');
      case 'sightseeing':
        return l10n.translate(_isOffice
            ? 'office_channel_events'
            : _isCampus
                ? 'campus_channel_events'
                : _isMess
                    ? 'mess_channel_bills'
                    : _isSociety
                        ? 'society_channel_events'
                        : _isSamity
                            ? 'samity_channel_events'
                            : _isSchool
                                ? 'school_channel_events'
                                : _isSports
                                    ? 'sports_channel_events'
                                    : _isStudy
                                        ? 'study_channel_events'
                                        : _isCommittee
                                            ? 'committee_channel_events'
                                            : _isFamily
                                                ? 'family_channel_sightseeing'
                                                : 'tour_channel_places');
      case 'home':
        return l10n.translate('family_channel_home');
      case 'kids':
        return l10n.translate('family_channel_kids');
      case 'shopping':
        return l10n.translate('family_channel_shopping');
      case 'emergency':
        return l10n.translate('tour_channel_safety');
      default:
        return channel.name.isEmpty ? '#${channel.id}' : '# ${channel.name}';
    }
  }

  String _badgeFor(String email) {
    final l10n = context.l10n;
    final me = normalizeEmail(email);
    final parts = <String>[];
    for (final s in _seats) {
      if (s.assignedMemberEmail != null &&
          normalizeEmail(s.assignedMemberEmail!) == me) {
        parts.add(
            l10n.translate('chan_badge_seat', args: {'seat': s.seatNumber}));
        break;
      }
    }
    for (final r in _rooms) {
      if (r.assignedMemberEmails.map(normalizeEmail).contains(me)) {
        parts.add(
            l10n.translate('chan_badge_room', args: {'room': r.roomNumber}));
        break;
      }
    }
    return parts.join(' · ');
  }

  Stream<List<ChannelMessage>> _messagesOf(String id) => _messageStreams
      .putIfAbsent(id, () => _repo.watchMessages(widget.tourId, id));

  Stream<List<ChannelMessage>> _latestOf(String id) => _latestStreams
      .putIfAbsent(id, () => _repo.watchLatestMessage(widget.tourId, id));

  Stream<List<ChannelMessage>> _mentionsOf(String id) => _mentionStreams
      .putIfAbsent(id, () => _repo.watchMentionsOf(widget.tourId, id, _me));

  Stream<List<TypingMember>> _typingOf(String id) => _typingStreams.putIfAbsent(
      id, () => _repo.watchTyping(widget.tourId, id));

  TextEditingController _draftFor(String channelId) =>
      _drafts.putIfAbsent(channelId, TextEditingController.new);

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.midGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Runs a repository write and reports a failure in the channel.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      _snack(
        context.l10n.translate('chan_action_failed', args: {'error': e}),
        error: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final channels = _channels;
    final selected = _selectedOf(channels);
    final canPost = !selected.adminOnly || _isAdmin;

    return PopScope(
        canPop: !_searching,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_searching) {
            _toggleSearch();
          }
        },
        child: Scaffold(
          backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
          appBar: AppBar(
            backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: context.forest.text),
              onPressed: () {
                if (_searching) {
                  _toggleSearch();
                  return;
                }
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(tourHubPath(widget.tourId));
                }
              },
            ),
            title: _searching
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: TextStyle(color: context.forest.text, fontSize: 15),
                    cursorColor: AppColors.mintGreen,
                    decoration: InputDecoration(
                      hintText: l10n.translate('chan_search_hint'),
                      hintStyle: TextStyle(color: context.forest.text54),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => _update(() => _searchText = v),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.translate('tour_channels_title'),
                        style: TextStyle(
                            color: context.forest.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      Text(
                        l10n.translate('chan_online_count',
                            args: {'count': l10n.number(_onlineCount())}),
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 11),
                      ),
                    ],
                  ),
            actions: [
              IconButton(
                tooltip: l10n.translate('chan_search_tooltip'),
                icon: Icon(_searching ? Icons.close : Icons.search,
                    color: context.forest.text70),
                onPressed: _toggleSearch,
              ),
              IconButton(
                tooltip: l10n.translate('chan_pins_tooltip'),
                icon:
                    Icon(Icons.push_pin_outlined, color: context.forest.text70),
                onPressed: () => _showPins(selected),
              ),
              IconButton(
                tooltip: l10n.translate('chan_members_tooltip'),
                icon: Icon(Icons.group_outlined, color: context.forest.text70),
                onPressed: () => showChannelMembersSheet(
                  context,
                  members: _members,
                  myEmail: _me,
                  badgeFor: _badgeFor,
                  onStartChat: (m) => _startDirectChat(m),
                  onStartCall: (m, isVideo) =>
                      _startDirectCall(m, isVideo: isVideo),
                ),
              ),
              PopupMenuButton<_ChannelMenu>(
                icon: Icon(Icons.more_vert, color: context.forest.text70),
                color: context.forest.surfaceFor(const Color(0xFF1F2C34)),
                onSelected: (choice) => _onMenu(choice, selected),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ChannelMenu.toggleMute,
                    child: Text(
                      l10n.translate(_muted.contains(selected.id)
                          ? 'chan_unmute'
                          : 'chan_mute'),
                      style: TextStyle(color: context.forest.text),
                    ),
                  ),
                  if (_isAdmin) ...[
                    PopupMenuItem(
                      value: _ChannelMenu.newChannel,
                      child: Text(l10n.translate('chan_new_channel'),
                          style: TextStyle(color: context.forest.text)),
                    ),
                    PopupMenuItem(
                      value: _ChannelMenu.editChannel,
                      child: Text(l10n.translate('chan_edit_channel'),
                          style: TextStyle(color: context.forest.text)),
                    ),
                    if (!selected.isBuiltIn)
                      PopupMenuItem(
                        value: _ChannelMenu.deleteChannel,
                        child: Text(l10n.translate('chan_delete_channel'),
                            style: TextStyle(
                                color:
                                    context.forest.readable(Colors.redAccent))),
                      ),
                  ],
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _buildItinerary(),
              _buildChannelStrip(channels, selected),
              if (selected.topic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selected.topic,
                      style:
                          TextStyle(color: context.forest.text54, fontSize: 12),
                    ),
                  ),
                ),
              Expanded(child: _buildChannelPager(channels, selected)),
              if (!selected.isVoice) ...[
                _TypingLine(stream: _typingOf(selected.id), myEmail: _me),
                if (_voiceService.isConnected &&
                    _voiceService.currentChannelId != selected.id)
                  _buildDockedVoiceBar(channels),
                if (canPost)
                  _buildComposer(selected)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text(
                      l10n.translate('chan_read_only'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: context.forest.text54, fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        ));
  }

  // ---------------------------------------------------------------------------
  // Itinerary bar
  // ---------------------------------------------------------------------------

  Widget _buildItinerary() {
    if (_checkpoints.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final stops = [..._checkpoints]
      ..sort((a, b) => a.kmFromStart.compareTo(b.kmFromStart));

    RouteCheckpoint? current;
    for (final s in stops) {
      if (s.id == _liveStopId) current = s;
    }
    RouteCheckpoint? next;
    if (current != null) {
      for (final s in stops) {
        if (s.kmFromStart > current.kmFromStart) {
          next = s;
          break;
        }
      }
    }

    final String line;
    if (current == null) {
      line = l10n.translate('chan_stop_none');
    } else {
      final now = l10n.translate('chan_stop_now', args: {'name': current.name});
      final after = next == null
          ? l10n.translate('chan_stop_last')
          : l10n.translate('chan_stop_next', args: {'name': next.name});
      line = '$now  ➔  $after';
    }

    return Material(
      color: context.forest.surfaceFor(const Color(0xFF13261A)),
      child: Column(
        children: [
          InkWell(
            onTap: () => _update(() => _itineraryOpen = !_itineraryOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: context.forest.readable(AppColors.gold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.forest.text, fontSize: 12),
                    ),
                  ),
                  Icon(
                    _itineraryOpen ? Icons.expand_less : Icons.expand_more,
                    color: context.forest.text54,
                  ),
                ],
              ),
            ),
          ),
          if (_itineraryOpen)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in stops)
                    ListTile(
                      dense: true,
                      selected: s.id == _liveStopId,
                      selectedTileColor: context.forest.divider10,
                      leading: Icon(
                        s.id == _liveStopId
                            ? Icons.my_location
                            : Icons.circle_outlined,
                        size: 16,
                        color: context.forest.accentText,
                      ),
                      title: Text(s.name,
                          style: TextStyle(
                              color: context.forest.text, fontSize: 13)),
                      subtitle: Text('${s.kmFromStart} km',
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 11)),
                      onTap: _isAdmin ? () => _setStop(s.id) : null,
                    ),
                  if (_isAdmin && _liveStopId != null)
                    TextButton(
                      onPressed: () => _setStop(null),
                      child: Text(l10n.translate('chan_stop_clear'),
                          style: TextStyle(color: context.forest.accentText)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setStop(String? stopId) async {
    await _guard(() => _repo.setLiveStop(widget.tourId, stopId));
  }

  // ---------------------------------------------------------------------------
  // Channel strip
  // ---------------------------------------------------------------------------

  Widget _buildChannelStrip(List<TourChannel> channels, TourChannel selected) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = channels[i];
          return _ChannelChip(
            key: _chipKeys.putIfAbsent(c.id, GlobalKey.new),
            label: _titleOf(c),
            selected: c.id == selected.id,
            muted: _muted.contains(c.id),
            adminOnly: c.adminOnly,
            isVoice: c.isVoice,
            voiceParticipants: c.isVoice
                ? _voiceService.watchParticipants(widget.tourId, c.id)
                : null,
            lastRead: _lastRead[c.id],
            myEmail: _me,
            latest: _latestOf(c.id),
            mentions: _mentionsOf(c.id),
            onTap: () => _selectChannel(c.id),
          );
        },
      ),
    );
  }

  /// The message area, one page per channel. Only the settled channel is live:
  /// its messages or voice room are built. A neighbour page is a placeholder,
  /// so a swipe in progress subscribes to nothing and marks nothing read.
  Widget _buildChannelPager(List<TourChannel> channels, TourChannel selected) {
    final l10n = context.l10n;
    final index = channels.indexWhere((c) => c.id == selected.id);
    return SwipePager(
      controller: _channelPager,
      count: channels.length,
      selectedIndex: index < 0 ? 0 : index,
      enabled: _swipeChannels && !_searching,
      nextLabel: l10n.translate('chan_swipe_next'),
      previousLabel: l10n.translate('chan_swipe_previous'),
      onSettled: (i) => _onChannelSettled(channels, i),
      itemBuilder: (context, i) {
        final channel = channels[i];
        final live = channel.id == selected.id;
        return KeyedSubtree(
          key: ValueKey('channel-page-${channel.id}'),
          child: !live
              ? _ChannelPagePlaceholder(title: _titleOf(channel))
              : channel.isVoice
                  ? _buildVoiceRoom(channel)
                  : _buildMessages(channel),
        );
      },
    );
  }

  /// A swipe came to rest on [index]: that channel becomes the selection.
  void _onChannelSettled(List<TourChannel> channels, int index) {
    if (index < 0 || index >= channels.length) return;
    final channel = channels[index];
    if (channel.id == _selectedId) return;
    _selectChannel(channel.id);
    unawaited(_revealChip(channel.id, index));
  }

  /// Brings the chip of [channelId] into view on the strip. A chip the strip
  /// has not built yet is reached by scrolling to where it should be first.
  Future<void> _revealChip(String channelId, int index) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_stripController.hasClients) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    var chip = _chipKeys[channelId]?.currentContext;
    if (chip == null) {
      final position = _stripController.position;
      final target = (index * _chipSlotWidth +
              _chipSlotWidth / 2 -
              position.viewportDimension / 2)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();
      await _stripController.animateTo(
        target,
        duration: motion,
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      chip = _chipKeys[channelId]?.currentContext;
    }
    if (chip == null || !chip.mounted) return;
    await Scrollable.ensureVisible(
      chip,
      alignment: 0.5,
      duration: motion,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onMenu(_ChannelMenu choice, TourChannel selected) async {
    switch (choice) {
      case _ChannelMenu.toggleMute:
        _toggleMute(selected.id);
      case _ChannelMenu.newChannel:
        await _createChannel();
      case _ChannelMenu.editChannel:
        await _editChannel(selected);
      case _ChannelMenu.deleteChannel:
        await _deleteChannel(selected);
    }
  }

  void _toggleMute(String channelId) {
    final muted = !_muted.contains(channelId);
    _update(() {
      if (muted) {
        _muted.add(channelId);
      } else {
        _muted.remove(channelId);
      }
    });
    unawaited(_store.setMuted(widget.tourId, channelId, muted: muted));
  }

  Future<void> _createChannel() async {
    final l10n = context.l10n;
    final draft = await showChannelEditor(
      context,
      title: l10n.translate('chan_new_channel'),
      nameEditable: true,
    );
    if (draft == null || !mounted) return;
    try {
      final id = await _repo.createChannel(
        widget.tourId,
        name: draft.name,
        topic: draft.topic,
        adminOnly: draft.adminOnly,
        kind: draft.kind,
      );
      if (!mounted) return;
      _selectChannel(id);
      _snack(l10n.translate('chan_saved'));
    } catch (e) {
      _snack(l10n.translate('chan_action_failed', args: {'error': e}),
          error: true);
    }
  }

  Future<void> _editChannel(TourChannel channel) async {
    final l10n = context.l10n;
    final draft = await showChannelEditor(
      context,
      title: l10n.translate('chan_edit_channel'),
      nameEditable: !channel.isBuiltIn,
      existing: channel,
    );
    if (draft == null || !mounted) return;
    await _guard(() => _repo.updateChannel(
          widget.tourId,
          channelId: channel.id,
          name: channel.isBuiltIn ? channel.name : draft.name,
          topic: draft.topic,
          adminOnly: draft.adminOnly,
        ));
    _snack(l10n.translate('chan_saved'));
  }

  Future<void> _deleteChannel(TourChannel channel) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF1F2C34)),
        title: Text(l10n.translate('chan_delete_channel'),
            style: TextStyle(color: context.forest.text)),
        content: Text(l10n.translate('chan_delete_channel_body'),
            style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('tour_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('chan_delete_channel'),
                style: TextStyle(
                    color: context.forest.readable(Colors.redAccent))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() => _repo.deleteChannel(widget.tourId, channel.id));
    if (!mounted) return;
    _selectChannel(kBuiltInChannelIds.first);
  }

  void _toggleSearch() {
    _update(() {
      _searching = !_searching;
      if (!_searching) {
        _searchText = '';
        _searchCtrl.clear();
      }
    });
  }

  void _startDirectChat(TourMember member) {
    final me = _groups.currentEmail;
    final myUid = _groups.currentUid.isNotEmpty ? _groups.currentUid : me;
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
    final me = _groups.currentEmail;
    final myUid = _groups.currentUid.isNotEmpty ? _groups.currentUid : me;
    final remoteId = (member.uid != null && member.uid!.isNotEmpty)
        ? member.uid!
        : member.email;
    if (remoteId.isEmpty) {
      _snack(l10n.translate('chan_call_offline'), error: true);
      return;
    }
    final myName = _groups.currentDisplayName;
    final myAvatar = _groups.currentPhotoUrl;
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

  Future<void> _joinVoice(TourChannel channel) async {
    try {
      final myName = _groups.currentDisplayName;
      final myPhoto = _groups.currentPhotoUrl;
      final myUid = _groups.currentUid.isNotEmpty ? _groups.currentUid : _me;
      await _voiceService.joinVoiceRoom(
        tourId: widget.tourId,
        channelId: channel.id,
        myEmail: _me,
        myName: myName,
        photoUrl: myPhoto,
        myUid: myUid,
      );
    } on VoiceRoomFullException catch (e) {
      if (!mounted) return;
      _snack(
        context.l10n.translate('chan_voice_full',
            args: {'count': context.l10n.number(e.capacity)}),
        error: true,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        context.l10n.translate('chan_call_failed', args: {'error': e}),
        error: true,
      );
    }
  }

  Widget _buildVoiceRoom(TourChannel channel) {
    final l10n = context.l10n;
    final isConnectedToThis = _voiceService.isConnected &&
        _voiceService.currentChannelId == channel.id;

    return StreamBuilder<List<VoiceParticipant>>(
      stream: _voiceService.watchParticipants(widget.tourId, channel.id),
      builder: (context, snapshot) {
        final participants = snapshot.data ?? const <VoiceParticipant>[];

        return Column(
          children: [
            Expanded(
              child: participants.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    AppColors.midGreen.withValues(alpha: 0.2),
                              ),
                              child: Icon(Icons.headset_mic_rounded,
                                  size: 64, color: context.forest.accentText),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _titleOf(channel),
                              style: TextStyle(
                                  color: context.forest.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.translate('chan_voice_empty'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: context.forest.text60, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            if (!isConnectedToThis)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.mintGreen,
                                  foregroundColor: AppColors.darkGreen,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                ),
                                icon: const Icon(Icons.call),
                                label: Text(
                                  l10n.translate('chan_voice_join'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                onPressed: () => _joinVoice(channel),
                              ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        itemCount: participants.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.1,
                        ),
                        itemBuilder: (context, i) {
                          final p = participants[i];
                          return _buildParticipantCard(p);
                        },
                      ),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: isConnectedToThis
                    ? _buildVoiceRoomControls()
                    : (participants.isNotEmpty
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.mintGreen,
                                foregroundColor: AppColors.darkGreen,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28)),
                              ),
                              icon: const Icon(Icons.call),
                              label: Text(
                                l10n.translate('chan_voice_join'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              onPressed: () => _joinVoice(channel),
                            ),
                          )
                        : const SizedBox.shrink()),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildParticipantCard(VoiceParticipant p) {
    final isMe = p.email == _me;
    final isVideoActive = isMe
        ? (_voiceService.isVideoOn &&
            _voiceService.localRenderer.srcObject != null)
        : (_voiceService.remoteRenderers.containsKey(p.email) &&
            _voiceService.remoteRenderers[p.email]!.srcObject != null &&
            p.isVideoOn);

    return Container(
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF1F2C34)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !p.isAudioMuted
              ? AppColors.mintGreen.withValues(alpha: 0.6)
              : context.forest.divider10,
          width: !p.isAudioMuted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isVideoActive)
            Positioned.fill(
              child: RTCVideoView(
                isMe
                    ? _voiceService.localRenderer
                    : _voiceService.remoteRenderers[p.email]!,
                mirror: isMe,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else ...[
            if (!isMe &&
                _voiceService.remoteRenderers.containsKey(p.email) &&
                _voiceService.remoteRenderers[p.email]!.srcObject != null)
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0.01,
                  child: RTCVideoView(_voiceService.remoteRenderers[p.email]!),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.midGreen,
                    boxShadow: !p.isAudioMuted
                        ? [
                            BoxShadow(
                              color: AppColors.mintGreen.withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      p.displayName.isNotEmpty
                          ? p.displayName.substring(0, 1).toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    isMe ? '${p.displayName} (you)' : p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.forest.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isVideoActive)
                  Expanded(
                    child: Text(
                      isMe ? '${p.displayName} (you)' : p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.forest.text,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 4),
                          ]),
                    ),
                  )
                else
                  const Spacer(),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    p.isAudioMuted ? Icons.mic_off : Icons.mic,
                    size: 14,
                    color:
                        p.isAudioMuted ? Colors.redAccent : AppColors.mintGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRoomControls() {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF1F2C34)),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              _voiceService.isSpeakerOn
                  ? Icons.volume_up
                  : Icons.volume_down_rounded,
              color: _voiceService.isSpeakerOn
                  ? context.forest.accentText
                  : context.forest.text70,
            ),
            tooltip: l10n.translate('chan_voice_speaker'),
            onPressed: () => _voiceService.toggleSpeaker(),
          ),
          IconButton(
            icon: Icon(
              _voiceService.isAudioMuted ? Icons.mic_off : Icons.mic,
              color: _voiceService.isAudioMuted
                  ? context.forest.readable(Colors.redAccent)
                  : context.forest.accentText,
            ),
            tooltip: l10n.translate(_voiceService.isAudioMuted
                ? 'chan_voice_unmute'
                : 'chan_voice_mute'),
            onPressed: () => _voiceService.toggleAudio(),
          ),
          IconButton(
            icon: Icon(
              _voiceService.isVideoOn ? Icons.videocam : Icons.videocam_off,
              color: _voiceService.isVideoOn
                  ? context.forest.accentText
                  : context.forest.text70,
            ),
            tooltip: l10n.translate(_voiceService.isVideoOn
                ? 'chan_voice_video_off'
                : 'chan_voice_video_on'),
            onPressed: () => _voiceService.toggleVideo(),
          ),
          if (!kIsWeb && _voiceService.isVideoOn)
            IconButton(
              icon: Icon(Icons.cameraswitch, color: context.forest.text70),
              onPressed: () => _voiceService.switchCamera(),
            ),
          GestureDetector(
            onTap: () => _voiceService.leaveVoiceRoom(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockedVoiceBar(List<TourChannel> channels) {
    final activeId = _voiceService.currentChannelId;
    if (activeId == null) return const SizedBox.shrink();

    final activeChan = channels.firstWhere(
      (c) => c.id == activeId,
      orElse: () => TourChannel(id: activeId),
    );
    final l10n = context.l10n;

    return Material(
      color: context.forest.surfaceFor(const Color(0xFF13261A)),
      child: InkWell(
        onTap: () => _selectChannel(activeId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            border:
                Border(left: BorderSide(color: AppColors.mintGreen, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.volume_up, color: context.forest.accentText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.translate('chan_voice_connected'),
                      style: TextStyle(
                          color: context.forest.accentText,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _titleOf(activeChan),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.forest.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _voiceService.isAudioMuted ? Icons.mic_off : Icons.mic,
                  color: _voiceService.isAudioMuted
                      ? context.forest.readable(Colors.redAccent)
                      : context.forest.accentText,
                  size: 20,
                ),
                tooltip: l10n.translate(_voiceService.isAudioMuted
                    ? 'chan_voice_unmute'
                    : 'chan_voice_mute'),
                onPressed: () => _voiceService.toggleAudio(),
              ),
              IconButton(
                icon: Icon(Icons.call_end,
                    color: context.forest.readable(Colors.redAccent), size: 20),
                tooltip: l10n.translate('chan_voice_leave'),
                onPressed: () => _voiceService.leaveVoiceRoom(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Writes the channel's newest messages to this device's cache once the list has
  /// been still for two seconds. A list that has not changed is not written again.
  void _scheduleCacheWrite(String channelId, List<ChannelMessage> messages) {
    if (identical(_cacheScheduled[channelId], messages)) return;
    _cacheScheduled[channelId] = messages;
    _cacheTimers[channelId]?.cancel();
    _cacheTimers[channelId] = Timer(const Duration(seconds: 2), () {
      unawaited(
          ChannelMessageCache().write(widget.tourId, channelId, messages));
    });
  }

  Widget _buildMessages(TourChannel channel) {
    final l10n = context.l10n;
    return CachedChannelMessages(
      tourId: widget.tourId,
      channelId: channel.id,
      builder: (context, cached) => ChannelMessageListener(
        stream: _messagesOf(channel.id),
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData && cached == null) {
            return Center(
              child: Text(l10n.translate('tour_messages_load_failed'),
                  style: TextStyle(color: context.forest.text54)),
            );
          }
          // The live query wins. Until it answers, the messages this device cached
          // show, so the channel opens with its messages in place.
          final live = snapshot.data;
          final all = live ?? cached;
          if (all == null || (live == null && all.isEmpty)) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.midGreen));
          }
          if (live != null) {
            _scheduleCacheWrite(channel.id, live);
            // Only the settled channel's messages count as read, and only ones the
            // live query has confirmed.
            if (live.isNotEmpty && channel.id == _selectedId) {
              _markReadSoon(channel.id, live.first.timestamp);
            }
          }

          final query = _searchText.trim().toLowerCase();
          final messages = query.isEmpty
              ? all
              : all
                  .where((m) =>
                      m.text.toLowerCase().contains(query) ||
                      m.senderName.toLowerCase().contains(query))
                  .toList();
          if (messages.isEmpty) {
            return Center(
              child: Text(
                l10n.translate(query.isEmpty
                    ? 'tour_no_messages'
                    : 'chan_no_search_results'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.forest.text54),
              ),
            );
          }

          final divider = _divider[channel.id];
          return ListView.builder(
            key: PageStorageKey<String>('channel-messages-${channel.id}'),
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            itemCount: messages.length,
            itemBuilder: (context, i) {
              final m = messages[i];
              final bubble = ChannelMessageBubble(
                key: ValueKey(m.id),
                message: m,
                isMine: m.isSentBy(_me),
                mentionsMe: m.mentionsEmail(_me),
                myEmail: _me,
                badge: _badgeFor(m.senderEmail),
                onLongPress: () => _onMessageLongPress(channel, m),
                onReact: (emoji) => _react(channel, m, emoji),
                onVote: (option) => _vote(channel, m, option),
                onOpenMedia: (index) =>
                    showChannelMediaViewer(context, m.visualAttachments[index]),
                onOpenLedger: () =>
                    context.push('/group/${widget.tourId}/ledger'),
              );
              // The divider sits under the last message read before this visit,
              // when newer messages have arrived since.
              final endsRead = divider != null &&
                  i > 0 &&
                  !m.timestamp.isAfter(divider) &&
                  messages[i - 1].timestamp.isAfter(divider);
              if (!endsRead) return bubble;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  bubble,
                  _NewMessagesDivider(
                      label: l10n.translate('chan_new_messages'))
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onMessageLongPress(
      TourChannel channel, ChannelMessage m) async {
    final l10n = context.l10n;
    final choice = await showChannelMessageActions(
      context,
      message: m,
      isMine: m.isSentBy(_me),
      isAdmin: _isAdmin,
      myReaction: m.reactionBy(_me),
    );
    if (choice == null || !mounted) return;
    final emoji = choice.emoji;
    if (emoji != null) {
      await _react(channel, m, emoji);
      return;
    }
    switch (choice.action!) {
      case ChannelAction.reply:
        _update(() {
          _replyTo = ChannelReply.quoting(m);
          _editing = null;
        });
        _focus.requestFocus();
      case ChannelAction.edit:
        _startEdit(channel, m);
      case ChannelAction.copy:
        await Clipboard.setData(ClipboardData(text: m.text));
        _snack(l10n.translate('chan_copied'));
      case ChannelAction.pin:
        await _guard(
            () => _repo.setPinned(widget.tourId, channel.id, m.id, true));
      case ChannelAction.unpin:
        await _guard(
            () => _repo.setPinned(widget.tourId, channel.id, m.id, false));
      case ChannelAction.delete:
        await _confirmDelete(channel, m);
    }
  }

  Future<void> _react(TourChannel channel, ChannelMessage m, String emoji) {
    return _guard(
        () => _repo.toggleReaction(widget.tourId, channel.id, m.id, emoji));
  }

  Future<void> _vote(TourChannel channel, ChannelMessage m, int option) {
    return _guard(() => _repo.vote(widget.tourId, channel.id, m.id, option));
  }

  Future<void> _confirmDelete(TourChannel channel, ChannelMessage m) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF1F2C34)),
        title: Text(l10n.translate('chan_delete_message_title'),
            style: TextStyle(color: context.forest.text)),
        content: Text(l10n.translate('chan_delete_message_body'),
            style: TextStyle(color: context.forest.text70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('tour_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('chan_action_delete'),
                style: TextStyle(
                    color: context.forest.readable(Colors.redAccent))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() => _repo.deleteMessage(widget.tourId, channel.id, m));
  }

  void _startEdit(TourChannel channel, ChannelMessage m) {
    final draft = _draftFor(channel.id);
    draft.value = TextEditingValue(
      text: m.text,
      selection: TextSelection.collapsed(offset: m.text.length),
    );
    _update(() {
      _editing = m;
      _replyTo = null;
    });
    _focus.requestFocus();
  }

  void _cancelContext(TourChannel channel) {
    if (_editing != null) _draftFor(channel.id).clear();
    _update(() {
      _editing = null;
      _replyTo = null;
    });
  }

  Future<void> _showPins(TourChannel channel) {
    final l10n = context.l10n;
    final stream = _repo.watchPinned(widget.tourId, channel.id);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF1F2C34)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: StreamBuilder<List<ChannelMessage>>(
            stream: stream,
            builder: (context, snapshot) {
              final pins = snapshot.data ?? const <ChannelMessage>[];
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      l10n.translate('chan_pins_title'),
                      style: TextStyle(
                          color: context.forest.text,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (pins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.translate('chan_pins_empty'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.forest.text54)),
                    ),
                  for (final p in pins)
                    ListTile(
                      leading: Icon(Icons.push_pin,
                          size: 18,
                          color: context.forest.readable(AppColors.gold)),
                      title: Text(
                        p.kind == ChannelMessageKind.expense
                            ? p.expenseTitle
                            : p.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: context.forest.text, fontSize: 13),
                      ),
                      subtitle: Text(p.senderName,
                          style: TextStyle(
                              color: context.forest.readable(AppColors.gold),
                              fontSize: 11)),
                      trailing: _isAdmin
                          ? IconButton(
                              tooltip: l10n.translate('chan_action_unpin'),
                              icon: Icon(Icons.close,
                                  color: context.forest.text54, size: 18),
                              onPressed: () => unawaited(_guard(() =>
                                  _repo.setPinned(
                                      widget.tourId, channel.id, p.id, false))),
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Composer
  // ---------------------------------------------------------------------------

  Widget _buildComposer(TourChannel channel) {
    final l10n = context.l10n;
    return ChannelComposer(
      controller: _draftFor(channel.id),
      focusNode: _focus,
      hint: l10n.translate('tour_message_hint'),
      sending: _sending,
      replyTo: _replyTo,
      editing: _editing != null,
      pending: _pending,
      uploadProgress: _uploadProgress,
      uploadLabel: _uploadTotal == 0
          ? null
          : l10n.translate('chan_uploading',
              args: {'done': _uploadDone + 1, 'total': _uploadTotal}),
      mentionChoices: [
        for (final label in _mentionLabels)
          MentionChoice(label: label, display: _mentionDisplay(label)),
      ],
      onChanged: (value) => _onDraftChanged(channel, value),
      onPickMention: (choice) => _pickMention(channel, choice),
      onSend: () => unawaited(_send(channel)),
      onAttach: () => unawaited(_attach(channel)),
      onCancelContext: () => _cancelContext(channel),
      onCancelUpload: () => unawaited(_currentUpload?.cancel()),
      onRemovePending: (i) => _update(() => _pending.removeAt(i)),
      recordingVoice: _recordingVoice,
      onStartVoice: () => _update(() => _recordingVoice = true),
      onVoiceSent: (path, duration) =>
          unawaited(_sendVoice(channel, path, duration)),
      onVoiceCancel: () => _update(() => _recordingVoice = false),
    );
  }

  String _mentionDisplay(String label) {
    final l10n = context.l10n;
    if (label == kMentionEveryone) {
      return '@everyone · ${l10n.translate('chan_mention_everyone')}';
    }
    if (label == kMentionAdmins) {
      return '@admin · ${l10n.translate('chan_mention_admins')}';
    }
    return '@$label';
  }

  void _onDraftChanged(TourChannel channel, String value) {
    final draft = _draftFor(channel.id);
    final cursor = draft.selection.baseOffset < 0
        ? value.length
        : draft.selection.baseOffset;
    final query = activeMentionQuery(value, cursor);
    _update(() {
      _mentionQuery = query;
      _mentionCursor = cursor;
      _mentionLabels =
          query == null ? const [] : mentionSuggestions(query, _members);
    });

    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }
    final now = DateTime.now();
    final last = _lastTypingSignal;
    if (last == null || now.difference(last) > const Duration(seconds: 4)) {
      _lastTypingSignal = now;
      _typingIn = channel.id;
      unawaited(_repo.setTyping(widget.tourId, channel.id, typing: true));
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 5), _stopTyping);
  }

  void _stopTyping() {
    _typingStop?.cancel();
    _typingStop = null;
    final channelId = _typingIn;
    if (channelId == null) return;
    _typingIn = null;
    _lastTypingSignal = null;
    unawaited(_repo.setTyping(widget.tourId, channelId, typing: false));
  }

  void _pickMention(TourChannel channel, MentionChoice choice) {
    final query = _mentionQuery;
    if (query == null) return;
    final draft = _draftFor(channel.id);
    final text = applyMention(draft.text, query, _mentionCursor, choice.label);
    draft.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
          offset: query.start + choice.label.length + 2),
    );
    _update(() {
      _mentionQuery = null;
      _mentionLabels = const [];
    });
  }

  Future<void> _send(TourChannel channel) async {
    final draft = _draftFor(channel.id);
    final text = draft.text.trim();
    if (_sending || (text.isEmpty && _pending.isEmpty)) return;

    final editing = _editing;
    if (editing != null) {
      await _saveEdit(channel, editing, text);
      return;
    }
    if (_pending.isEmpty) {
      final command = parseChatCommand(text);
      if (command != null) {
        await _runCommand(channel, command);
        return;
      }
    }
    await _post(channel, text);
  }

  /// Sends a voice note. It is uploaded like a photo, then posted as a text
  /// message with one audio attachment.
  Future<void> _sendVoice(
      TourChannel channel, String path, Duration duration) async {
    final l10n = context.l10n;
    final uploads = <TourMediaUpload>[];
    _update(() {
      _recordingVoice = false;
      _sending = true;
      _uploadProgress = 0;
      _uploadDone = 0;
      _uploadTotal = 1;
    });
    try {
      final file = XFile(path,
          name: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          mimeType: 'audio/mp4');
      final upload = await _repo.startVoice(widget.tourId, file);
      uploads.add(upload);
      _currentUpload = upload;
      final progress =
          upload.progress.listen((v) => _update(() => _uploadProgress = v));
      final url = await upload.finish();
      await progress.cancel();
      await _repo.sendMessage(
        widget.tourId,
        channel.id,
        text: '',
        attachments: [
          ChannelAttachment(
              url: url, isAudio: true, durationSeconds: duration.inSeconds),
        ],
        replyTo: _replyTo,
      );
      _update(() => _replyTo = null);
    } on TourUploadCancelled {
      await _discard(uploads);
      _snack(l10n.translate('chan_upload_cancelled'));
    } catch (e) {
      await _discard(uploads);
      _snack(l10n.translate('tour_message_send_failed', args: {'error': e}),
          error: true);
    } finally {
      _currentUpload = null;
      _update(() {
        _sending = false;
        _uploadTotal = 0;
      });
    }
  }

  Future<void> _post(TourChannel channel, String text) async {
    final l10n = context.l10n;
    final draft = _draftFor(channel.id);
    final uploads = <TourMediaUpload>[];
    final attachments = <ChannelAttachment>[];
    _update(() {
      _sending = true;
      _uploadProgress = 0;
      _uploadDone = 0;
      _uploadTotal = _pending.length;
    });
    try {
      for (final p in _pending) {
        final upload = await _repo.startAttachment(
          widget.tourId,
          p.file,
          isVideo: p.isVideo,
          isDocument: p.isDocument,
        );
        uploads.add(upload);
        _currentUpload = upload;
        final progress =
            upload.progress.listen((v) => _update(() => _uploadProgress = v));
        final url = await upload.finish();
        await progress.cancel();
        attachments.add(ChannelAttachment(
          url: url,
          isVideo: p.isVideo,
          isFile: p.isDocument,
          fileName: p.isDocument ? p.file.name : null,
          fileSizeBytes: p.isDocument ? p.fileSizeBytes : null,
        ));
        _update(() => _uploadDone++);
      }
      final send = _repo.sendMessage(
        widget.tourId,
        channel.id,
        text: text,
        attachments: attachments,
        replyTo: _replyTo,
        mentions: resolveMentions(text, _members),
      );
      if (attachments.isEmpty) {
        // A text message is written to the local cache at once, so the composer
        // is not held while the server acknowledges it. If the server rejects
        // the write, it is rolled back and the text goes back into the draft.
        unawaited(send.catchError((Object e) {
          if (!mounted) return;
          if (draft.text.trim().isEmpty) draft.text = text;
          _snack(l10n.translate('tour_message_send_failed', args: {'error': e}),
              error: true);
        }));
      } else {
        await send;
      }
      if (draft.text.trim() == text) draft.clear();
      _update(() {
        _pending.clear();
        _replyTo = null;
      });
      _stopTyping();
    } on TourUploadCancelled {
      await _discard(uploads);
      _snack(l10n.translate('chan_upload_cancelled'));
    } catch (e) {
      await _discard(uploads);
      _snack(l10n.translate('tour_message_send_failed', args: {'error': e}),
          error: true);
    } finally {
      _currentUpload = null;
      _update(() {
        _sending = false;
        _uploadTotal = 0;
      });
    }
  }

  Future<void> _discard(List<TourMediaUpload> uploads) async {
    for (final u in uploads) {
      await u.discard();
    }
  }

  Future<void> _saveEdit(
      TourChannel channel, ChannelMessage message, String text) async {
    final l10n = context.l10n;
    final draft = _draftFor(channel.id);
    _update(() => _sending = true);
    try {
      await _repo.editMessage(
        widget.tourId,
        channel.id,
        message.id,
        text,
        mentions: resolveMentions(text, _members),
      );
      draft.clear();
      _update(() => _editing = null);
    } catch (e) {
      _snack(l10n.translate('chan_action_failed', args: {'error': e}),
          error: true);
    } finally {
      _update(() => _sending = false);
    }
  }

  Future<void> _runCommand(TourChannel channel, ChatCommand command) async {
    final l10n = context.l10n;
    final draft = _draftFor(channel.id);
    switch (command) {
      case ChatCommandError(:final messageKey):
        _snack(l10n.translate(messageKey), error: true);
      case SplitCommand(:final amountPaisa, :final title):
        _update(() => _sending = true);
        try {
          await _repo.sendExpense(
            widget.tourId,
            channel.id,
            title: title,
            amountPaisa: amountPaisa,
            category: splitCategoryFor(
                family: _isFamily,
                office: _isOffice,
                campus: _isCampus,
                mess: _isMess,
                society: _isSociety,
                samity: _isSamity,
                school: _isSchool,
                sports: _isSports,
                study: _isStudy,
                committee: _isCommittee,
                channelId: channel.id),
          );
          draft.clear();
          _snack(l10n.translate('chan_split_done', args: {
            'title': title,
            'amount': TripLedgerEngine.formatTaka(amountPaisa),
          }));
        } catch (e) {
          _snack(l10n.translate('chan_action_failed', args: {'error': e}),
              error: true);
        } finally {
          _update(() => _sending = false);
        }
      case PollCommand(:final question, :final options):
        _update(() => _sending = true);
        try {
          await _repo.sendPoll(
            widget.tourId,
            channel.id,
            question: question,
            options: options,
          );
          draft.clear();
        } catch (e) {
          _snack(l10n.translate('chan_action_failed', args: {'error': e}),
              error: true);
        } finally {
          _update(() => _sending = false);
        }
    }
  }

  Future<void> _attach(TourChannel channel) async {
    final source = await showAttachSheet(context);
    if (source == null || !mounted) return;
    final l10n = context.l10n;
    if (source == AttachSource.location) {
      final locText = await _promptLocation(context);
      if (locText != null && locText.isNotEmpty && mounted) {
        final draft = _draftFor(channel.id);
        _update(() {
          draft.text = draft.text.isEmpty ? locText : '${draft.text}\n$locText';
        });
      }
      return;
    }
    final picker = ImagePicker();
    final hasVideo = _pending.any((p) => p.isVideo);
    try {
      if (source == AttachSource.video) {
        if (_pending.isNotEmpty) {
          _snack(l10n.translate('chan_attach_limit'), error: true);
          return;
        }
        final file = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: kMaxReelSeconds),
        );
        if (file != null && mounted) {
          _update(
              () => _pending.add(PendingAttachment(file: file, isVideo: true)));
        }
        return;
      }
      if (source == AttachSource.document) {
        if (hasVideo) {
          _snack(l10n.translate('chan_attach_limit'), error: true);
          return;
        }
        final room = kChannelMaxImages - _pending.length;
        if (room <= 0) {
          _snack(l10n.translate('chan_attach_limit'), error: true);
          return;
        }
        final res = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'txt',
            'zip',
            'csv'
          ],
          allowMultiple: true,
          withData: kIsWeb,
        );
        if (res == null || res.files.isEmpty || !mounted) return;
        if (res.files.length > room) {
          _snack(l10n.translate('chan_attach_limit'), error: true);
        }
        final toAdd = <PendingAttachment>[];
        for (final f in res.files.take(room)) {
          if (f.size > kMaxDocBytes) {
            _snack('${f.name}: ${l10n.translate('chan_file_too_large')}',
                error: true);
            continue;
          }
          final xfile = f.bytes != null
              ? XFile.fromData(f.bytes!, name: f.name, length: f.size)
              : (f.path != null
                  ? XFile(f.path!, name: f.name, length: f.size)
                  : null);
          if (xfile != null) {
            toAdd.add(PendingAttachment(
              file: xfile,
              isVideo: false,
              isDocument: true,
              fileSizeBytes: f.size,
            ));
          }
        }
        if (toAdd.isNotEmpty && mounted) {
          _update(() => _pending.addAll(toAdd));
        }
        return;
      }
      if (hasVideo) {
        _snack(l10n.translate('chan_attach_limit'), error: true);
        return;
      }
      final List<XFile> picked;
      if (source == AttachSource.camera) {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          imageQuality: 85,
        );
        picked = photo == null ? const [] : [photo];
      } else {
        picked = await picker.pickMultiImage(maxWidth: 1920, imageQuality: 85);
      }
      if (!mounted) return;
      final room = kChannelMaxImages - _pending.length;
      if (picked.length > room) {
        _snack(l10n.translate('chan_attach_limit'), error: true);
      }
      _update(() {
        _pending.addAll([
          for (final f in picked.take(room))
            PendingAttachment(file: f, isVideo: false),
        ]);
      });
    } catch (e) {
      _snack(l10n.translate('chan_action_failed', args: {'error': e}),
          error: true);
    }
  }

  Future<String?> _promptLocation(BuildContext context) async {
    final l10n = context.l10n;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF1B3326)),
        title: Row(
          children: [
            Icon(Icons.location_on_rounded, color: context.forest.accentText),
            const SizedBox(width: 8),
            Text(
              l10n.translate('chan_attach_location'),
              style: TextStyle(color: context.forest.text, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TextStyle(color: context.forest.text),
              decoration: InputDecoration(
                labelText: l10n.translate('chan_location_name'),
                labelStyle: TextStyle(color: context.forest.text70),
                hintText: l10n.translate('chan_location_hint'),
                hintStyle:
                    TextStyle(color: context.forest.text38, fontSize: 12),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.forest.text38)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.mintGreen)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: context.forest.text),
              decoration: InputDecoration(
                labelText: l10n.translate('chan_location_maps_link'),
                labelStyle: TextStyle(color: context.forest.text70),
                hintText: 'https://maps.app.goo.gl/...',
                hintStyle:
                    TextStyle(color: context.forest.text38, fontSize: 12),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: context.forest.text38)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.mintGreen)),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.mintGreen,
                side: BorderSide(
                    color: AppColors.mintGreen.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                try {
                  var perm = await Geolocator.checkPermission();
                  if (perm == LocationPermission.denied) {
                    perm = await Geolocator.requestPermission();
                  }
                  if (perm == LocationPermission.denied ||
                      perm == LocationPermission.deniedForever) {
                    return;
                  }
                  final pos = await Geolocator.getCurrentPosition();
                  urlCtrl.text =
                      'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
                  if (nameCtrl.text.trim().isEmpty) {
                    nameCtrl.text = l10n.translate('chan_my_location');
                  }
                } catch (error, stackTrace) {
                  logSkipped(error, stackTrace);
                }
              },
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: Text(
                l10n.translate('chan_location_current_btn'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('tour_cancel'),
                style: TextStyle(color: context.forest.text54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty && url.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              final title = name.isNotEmpty
                  ? name
                  : l10n.translate('chan_location_title');
              final mapsUrl = url.isNotEmpty
                  ? url
                  : 'https://maps.google.com/?q=${Uri.encodeComponent(title)}';
              Navigator.pop(ctx, '📍 [$title]($mapsUrl)');
            },
            child: Text(
              l10n.translate('tour_save'),
              style: const TextStyle(
                  color: AppColors.darkGreen, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line that separates messages read before a visit from newer ones.
class _NewMessagesDivider extends StatelessWidget {
  final String label;

  const _NewMessagesDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.gold, height: 1)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: context.forest.readable(AppColors.gold),
                  fontSize: 11)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.gold, height: 1)),
        ],
      ),
    );
  }
}

/// A channel in the strip, with an unread dot and a count of unread mentions.
/// What a channel page shows before the swipe settles on it: the channel's
/// name, and no subscriptions.
class _ChannelPagePlaceholder extends StatelessWidget {
  const _ChannelPagePlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.forest.surfaceFor(const Color(0xFF0D1A12)),
      child: Center(
        child: Text(
          title,
          style: TextStyle(color: context.forest.text54, fontSize: 15),
        ),
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool muted;
  final bool adminOnly;
  final bool isVoice;
  final Stream<List<VoiceParticipant>>? voiceParticipants;
  final DateTime? lastRead;
  final String myEmail;
  final Stream<List<ChannelMessage>> latest;
  final Stream<List<ChannelMessage>> mentions;
  final VoidCallback onTap;

  const _ChannelChip({
    super.key,
    required this.label,
    required this.selected,
    required this.muted,
    required this.adminOnly,
    this.isVoice = false,
    this.voiceParticipants,
    required this.lastRead,
    required this.myEmail,
    required this.latest,
    required this.mentions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isVoice && voiceParticipants != null) {
      return StreamBuilder<List<VoiceParticipant>>(
        stream: voiceParticipants,
        builder: (context, snap) {
          final count = snap.data?.length ?? 0;
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.midGreen
                    : context.forest.text.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? context.forest.text
                          : context.forest.text70,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.mintGreen,
                        borderRadius: BorderRadius.all(Radius.circular(9)),
                      ),
                      height: 18,
                      child: Text(
                        '$count',
                        style: const TextStyle(
                            color: AppColors.darkGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    return StreamBuilder<List<ChannelMessage>>(
      stream: latest,
      builder: (context, latestSnap) {
        return StreamBuilder<List<ChannelMessage>>(
          stream: mentions,
          builder: (context, mentionSnap) {
            final hasNew = !selected &&
                !muted &&
                countUnread(latestSnap.data ?? const [], lastRead, myEmail) > 0;
            final mentionCount = selected
                ? 0
                : countUnread(mentionSnap.data ?? const [], lastRead, myEmail);
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.midGreen
                      : context.forest.text.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (adminOnly) ...[
                      Icon(Icons.campaign_outlined,
                          size: 14,
                          color: context.forest.readable(AppColors.gold)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? context.forest.text
                            : context.forest.text70,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.notifications_off_outlined,
                          size: 13, color: context.forest.text54),
                    ],
                    if (hasNew) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    if (mentionCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        height: 18,
                        child: Text(
                          '$mentionCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
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
}

/// "Someone is typing…" under the messages. Signals older than the typing
/// window are hidden; the line re-checks them every two seconds.
class _TypingLine extends StatefulWidget {
  final Stream<List<TypingMember>> stream;
  final String myEmail;

  const _TypingLine({required this.stream, required this.myEmail});

  @override
  State<_TypingLine> createState() => _TypingLineState();
}

class _TypingLineState extends State<_TypingLine> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TypingMember>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final me = normalizeEmail(widget.myEmail);
        final others = (snapshot.data ?? const <TypingMember>[])
            .where((t) => t.email != me && t.isFreshAt(now))
            .toList();
        if (others.isEmpty) return const SizedBox.shrink();
        final l10n = context.l10n;
        final first = others.first.name;
        final text = others.length == 1
            ? l10n.translate('chan_typing_one', args: {'name': first})
            : l10n.translate('chan_typing_many',
                args: {'name': first, 'count': others.length - 1});
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: TextStyle(
                  color: context.forest.text54,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ),
        );
      },
    );
  }
}

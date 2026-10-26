import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/channel_read_store.dart';
import '../../data/tour_channel_repository.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/channel_models.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/chat_commands.dart';
import '../../domain/services/chat_mentions.dart';
import '../../domain/services/media_rules.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../widgets/channel_composer.dart';
import '../widgets/channel_media_viewer.dart';
import '../widgets/channel_message_bubble.dart';
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

  final List<StreamSubscription<dynamic>> _subs = [];
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
    ]);
    for (final id in kBuiltInChannelIds) {
      unawaited(_ensurePrefs(id));
    }
  }

  @override
  void dispose() {
    _stopTyping();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _focus.dispose();
    _searchCtrl.dispose();
    for (final c in _drafts.values) {
      c.dispose();
    }
    super.dispose();
  }

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
      for (final id in kBuiltInChannelIds) byId[id] ?? TourChannel(id: id),
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
    switch (channel.id) {
      case 'general':
        return l10n.translate('tour_channel_general');
      case 'food':
        return l10n.translate('tour_channel_food');
      case 'sightseeing':
        return l10n.translate('tour_channel_places');
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

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: AppColors.mintGreen,
                decoration: InputDecoration(
                  hintText: l10n.translate('chan_search_hint'),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) => _update(() => _searchText = v),
              )
            : Text(
                l10n.translate('tour_channels_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
        actions: [
          IconButton(
            tooltip: l10n.translate('chan_search_tooltip'),
            icon: Icon(_searching ? Icons.close : Icons.search,
                color: Colors.white70),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: l10n.translate('chan_pins_tooltip'),
            icon: const Icon(Icons.push_pin_outlined, color: Colors.white70),
            onPressed: () => _showPins(selected),
          ),
          IconButton(
            tooltip: l10n.translate('chan_members_tooltip'),
            icon: const Icon(Icons.group_outlined, color: Colors.white70),
            onPressed: () => showChannelMembersSheet(
              context,
              members: _members,
              myEmail: _me,
              badgeFor: _badgeFor,
            ),
          ),
          PopupMenuButton<_ChannelMenu>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF1F2C34),
            onSelected: (choice) => _onMenu(choice, selected),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ChannelMenu.toggleMute,
                child: Text(
                  l10n.translate(_muted.contains(selected.id)
                      ? 'chan_unmute'
                      : 'chan_mute'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (_isAdmin) ...[
                PopupMenuItem(
                  value: _ChannelMenu.newChannel,
                  child: Text(l10n.translate('chan_new_channel'),
                      style: const TextStyle(color: Colors.white)),
                ),
                PopupMenuItem(
                  value: _ChannelMenu.editChannel,
                  child: Text(l10n.translate('chan_edit_channel'),
                      style: const TextStyle(color: Colors.white)),
                ),
                if (!selected.isBuiltIn)
                  PopupMenuItem(
                    value: _ChannelMenu.deleteChannel,
                    child: Text(l10n.translate('chan_delete_channel'),
                        style: const TextStyle(color: Colors.redAccent)),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          Expanded(child: _buildMessages(selected)),
          _TypingLine(stream: _typingOf(selected.id), myEmail: _me),
          if (canPost)
            _buildComposer(selected)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                l10n.translate('chan_read_only'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
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
      color: const Color(0xFF13261A),
      child: Column(
        children: [
          InkWell(
            onTap: () => _update(() => _itineraryOpen = !_itineraryOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 16, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Icon(
                    _itineraryOpen ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
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
                      selectedTileColor: Colors.white10,
                      leading: Icon(
                        s.id == _liveStopId
                            ? Icons.my_location
                            : Icons.circle_outlined,
                        size: 16,
                        color: AppColors.mintGreen,
                      ),
                      title: Text(s.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      subtitle: Text('${s.kmFromStart} km',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                      onTap: _isAdmin ? () => _setStop(s.id) : null,
                    ),
                  if (_isAdmin && _liveStopId != null)
                    TextButton(
                      onPressed: () => _setStop(null),
                      child: Text(l10n.translate('chan_stop_clear'),
                          style: const TextStyle(color: AppColors.mintGreen)),
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
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = channels[i];
          return _ChannelChip(
            label: _titleOf(c),
            selected: c.id == selected.id,
            muted: _muted.contains(c.id),
            adminOnly: c.adminOnly,
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
        backgroundColor: const Color(0xFF1F2C34),
        title: Text(l10n.translate('chan_delete_channel'),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('chan_delete_channel_body'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('tour_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('chan_delete_channel'),
                style: const TextStyle(color: Colors.redAccent)),
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

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Widget _buildMessages(TourChannel channel) {
    final l10n = context.l10n;
    return StreamBuilder<List<ChannelMessage>>(
      stream: _messagesOf(channel.id),
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(
            child: Text(l10n.translate('tour_messages_load_failed'),
                style: const TextStyle(color: Colors.white54)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen));
        }
        final all = snapshot.data!;
        if (all.isNotEmpty) _markReadSoon(channel.id, all.first.timestamp);

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
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }

        final divider = _divider[channel.id];
        return ListView.builder(
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
                  showChannelMediaViewer(context, m.attachments[index]),
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
                _NewMessagesDivider(label: l10n.translate('chan_new_messages'))
              ],
            );
          },
        );
      },
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
        backgroundColor: const Color(0xFF1F2C34),
        title: Text(l10n.translate('chan_delete_message_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('chan_delete_message_body'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('tour_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('chan_action_delete'),
                style: const TextStyle(color: Colors.redAccent)),
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
      backgroundColor: const Color(0xFF1F2C34),
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (pins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.translate('chan_pins_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54)),
                    ),
                  for (final p in pins)
                    ListTile(
                      leading: const Icon(Icons.push_pin,
                          size: 18, color: AppColors.gold),
                      title: Text(
                        p.kind == ChannelMessageKind.expense
                            ? p.expenseTitle
                            : p.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      subtitle: Text(p.senderName,
                          style: const TextStyle(
                              color: AppColors.gold, fontSize: 11)),
                      trailing: _isAdmin
                          ? IconButton(
                              tooltip: l10n.translate('chan_action_unpin'),
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
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
      onAttach: () => unawaited(_attach()),
      onCancelContext: () => _cancelContext(channel),
      onCancelUpload: () => unawaited(_currentUpload?.cancel()),
      onRemovePending: (i) => _update(() => _pending.removeAt(i)),
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
        final upload = await _repo.startAttachment(widget.tourId, p.file,
            isVideo: p.isVideo);
        uploads.add(upload);
        _currentUpload = upload;
        final progress =
            upload.progress.listen((v) => _update(() => _uploadProgress = v));
        final url = await upload.finish();
        await progress.cancel();
        attachments.add(ChannelAttachment(url: url, isVideo: p.isVideo));
        _update(() => _uploadDone++);
      }
      await _repo.sendMessage(
        widget.tourId,
        channel.id,
        text: text,
        attachments: attachments,
        replyTo: _replyTo,
        mentions: resolveMentions(text, _members),
      );
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
            category: channel.id == 'food' ? 'Food' : 'Others',
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

  Future<void> _attach() async {
    final source = await showAttachSheet(context);
    if (source == null || !mounted) return;
    final l10n = context.l10n;
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
              style: const TextStyle(color: AppColors.gold, fontSize: 11)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.gold, height: 1)),
        ],
      ),
    );
  }
}

/// A channel in the strip, with an unread dot and a count of unread mentions.
class _ChannelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool muted;
  final bool adminOnly;
  final DateTime? lastRead;
  final String myEmail;
  final Stream<List<ChannelMessage>> latest;
  final Stream<List<ChannelMessage>> mentions;
  final VoidCallback onTap;

  const _ChannelChip({
    required this.label,
    required this.selected,
    required this.muted,
    required this.adminOnly,
    required this.lastRead,
    required this.myEmail,
    required this.latest,
    required this.mentions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (adminOnly) ...[
                      const Icon(Icons.campaign_outlined,
                          size: 14, color: AppColors.gold),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (muted) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.notifications_off_outlined,
                          size: 13, color: Colors.white54),
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
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ),
        );
      },
    );
  }
}

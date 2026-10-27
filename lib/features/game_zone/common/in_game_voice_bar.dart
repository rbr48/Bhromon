import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import 'package:bhromon/features/tour_group/data/voice_room_service.dart';

/// Floating / docked in-game voice bar for real-time trash talk & strategy.
/// Connects players through WebRTC mesh audio without disrupting gameplay.
class InGameVoiceBar extends StatefulWidget {
  final String tourId;
  final String gameId;
  final String myEmail;
  final String myDisplayName;
  final String? myPhotoUrl;
  final String myUid;
  final bool initialJoin;

  const InGameVoiceBar({
    super.key,
    required this.tourId,
    required this.gameId,
    required this.myEmail,
    required this.myDisplayName,
    this.myPhotoUrl,
    required this.myUid,
    this.initialJoin = false,
  });

  @override
  State<InGameVoiceBar> createState() => _InGameVoiceBarState();
}

class _InGameVoiceBarState extends State<InGameVoiceBar> {
  final VoiceRoomService _voiceService = VoiceRoomService();
  StreamSubscription<dynamic>? _voiceSub;
  bool _isExpanded = false;

  String get _gameVoiceChannelId => 'game_${widget.gameId}';

  bool get _isConnectedToThisGame =>
      _voiceService.isConnected &&
      _voiceService.currentChannelId == _gameVoiceChannelId;

  @override
  void initState() {
    super.initState();
    _voiceSub = _voiceService.changes.listen((_) {
      if (mounted) setState(() {});
    });

    if (widget.initialJoin && !_voiceService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _joinGameVoice();
      });
    }
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    super.dispose();
  }

  Future<void> _joinGameVoice() async {
    try {
      await _voiceService.joinVoiceRoom(
        tourId: widget.tourId,
        channelId: _gameVoiceChannelId,
        myEmail: widget.myEmail,
        myName: widget.myDisplayName,
        photoUrl: widget.myPhotoUrl,
        myUid: widget.myUid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect voice: $e')),
        );
      }
    }
  }

  Future<void> _leaveGameVoice() async {
    await _voiceService.leaveVoiceRoom();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tourId.isEmpty || widget.gameId.isEmpty) {
      return const SizedBox.shrink();
    }

    final isConnected = _isConnectedToThisGame;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF132218).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? AppColors.mintGreen.withValues(alpha: 0.5)
              : Colors.white12,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnected
                ? AppColors.mintGreen.withValues(alpha: 0.15)
                : Colors.black38,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Voice Indicator Icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.mintGreen.withValues(alpha: 0.2)
                      : Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.volume_up_rounded : Icons.mic_off_outlined,
                  color: isConnected ? AppColors.mintGreen : Colors.white60,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),

              // Title / Status
              Expanded(
                child: Text(
                  isConnected
                      ? 'Game Voice Lounge'
                      : 'Voice chat with group',
                  style: TextStyle(
                    color: isConnected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (!isConnected) ...[
                TextButton.icon(
                  onPressed: _joinGameVoice,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.mintGreen.withValues(alpha: 0.18),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.headset_mic_rounded,
                      color: AppColors.mintGreen, size: 14),
                  label: const Text(
                    'Join Voice',
                    style: TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                // Mute Mic Toggle Button
                IconButton(
                  icon: Icon(
                    _voiceService.isAudioMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    color: _voiceService.isAudioMuted
                        ? Colors.redAccent
                        : AppColors.mintGreen,
                    size: 18,
                  ),
                  tooltip: _voiceService.isAudioMuted ? 'Unmute' : 'Mute',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _voiceService.toggleAudio(),
                ),

                // Video / Camera Toggle (Optional)
                IconButton(
                  icon: Icon(
                    _voiceService.isVideoOn
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    color: _voiceService.isVideoOn
                        ? AppColors.mintGreen
                        : Colors.white54,
                    size: 18,
                  ),
                  tooltip: _voiceService.isVideoOn ? 'Cam off' : 'Cam on',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _voiceService.toggleVideo(),
                ),

                // Expand/Collapse participants list
                IconButton(
                  icon: Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.people_alt_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                  tooltip: 'Participants',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),

                // Disconnect Voice Button
                IconButton(
                  icon: const Icon(Icons.call_end_rounded,
                      color: Colors.redAccent, size: 18),
                  tooltip: 'Leave Voice',
                  visualDensity: VisualDensity.compact,
                  onPressed: _leaveGameVoice,
                ),
              ],
            ],
          ),

          // Expanded Active Participants Tray
          if (isConnected && _isExpanded) ...[
            const Divider(color: Colors.white12, height: 12),
            StreamBuilder<List<VoiceParticipant>>(
              stream: _voiceService.watchParticipants(
                widget.tourId,
                _gameVoiceChannelId,
              ),
              builder: (context, snapshot) {
                final participants = snapshot.data ?? [];
                if (participants.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Waiting for other players to join voice...',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  );
                }

                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: participants.map((p) {
                    final isMe = p.email == widget.myEmail;
                    return Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      avatar: CircleAvatar(
                        backgroundColor: p.isAudioMuted
                            ? Colors.red.shade900
                            : AppColors.mintGreen.withValues(alpha: 0.3),
                        child: Icon(
                          p.isAudioMuted ? Icons.mic_off : Icons.mic,
                          color: p.isAudioMuted
                              ? Colors.white70
                              : AppColors.mintGreen,
                          size: 11,
                        ),
                      ),
                      label: Text(
                        '${p.displayName}${isMe ? ' (You)' : ''}',
                        style: TextStyle(
                          color: isMe ? AppColors.mintGreen : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      backgroundColor: const Color(0xFF1E3526),
                      side: BorderSide(
                        color: p.isAudioMuted
                            ? Colors.redAccent.withValues(alpha: 0.4)
                            : AppColors.mintGreen.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

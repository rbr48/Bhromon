import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../common/in_game_voice_bar.dart';
import '../common/playing_card_view.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';
import '../domain/models/teen_patti_table.dart';
import '../teen_patti/teen_patti_engine.dart';

/// Pauses before the table plays a bot's move, so people can follow the hand.
/// The host's phone paces the bots, so they are not played twice as fast.
const Duration _botPaceHost = Duration(milliseconds: 900);
const Duration _botPaceOther = Duration(milliseconds: 1800);

/// Extra time after a person's deadline, to allow for clock differences.
const Duration _deadlineGrace = Duration(seconds: 2);
const Duration _retryAfter = Duration(seconds: 3);

/// The online Teen Patti table. The server deals the cards and runs every
/// move. The phone shows the public table, this seat's own cards, and the
/// moves the server will accept.
class OnlineTeenPattiView extends StatefulWidget {
  const OnlineTeenPattiView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  @override
  State<OnlineTeenPattiView> createState() => _OnlineTeenPattiViewState();
}

class _OnlineTeenPattiViewState extends State<OnlineTeenPattiView> {
  Timer? _advanceTimer;
  int _scheduledStep = -1;
  bool _busy = false;

  Stream<TeenPattiPrivateHand?>? _handStream;
  int? _handStreamSeat;

  OnlineGameSession get _session => widget.session;

  int? get _mySeat => _session.playerByEmail(widget.myEmail)?.seatIndex;

  bool get _isHost => _session.hostEmail == widget.myEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleAdvance();
    });
  }

  @override
  void didUpdateWidget(covariant OnlineTeenPattiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.session.state['step'] != widget.session.state['step'] ||
            oldWidget.session.status != widget.session.status;
    if (changed) _scheduleAdvance();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  // --- Keeping the table moving -------------------------------------------

  /// Arranges the next step when one is due: a bot's move, or a person whose
  /// time has run out. Nothing is scheduled between hands.
  void _scheduleAdvance() {
    if (_session.status != GameSessionStatus.inProgress) return;
    final table = TeenPattiTable.fromState(_session.state);
    if (table.step == _scheduledStep) return;
    _scheduledStep = table.step;
    _advanceTimer?.cancel();

    final delay = _delayFor(table);
    if (delay == null) return;
    final step = table.step;
    _advanceTimer = Timer(delay, () => _advance(step));
  }

  Duration? _delayFor(TeenPattiTable table) {
    final seat = table.actingSeat;
    if (seat == null) return null;
    if (_session.playerAt(seat)?.isBot ?? false) {
      return _isHost ? _botPaceHost : _botPaceOther;
    }
    final deadline = table.turnDeadline;
    if (deadline == null) return null;
    final wait = deadline.difference(DateTime.now()) + _deadlineGrace;
    return wait.isNegative ? _deadlineGrace : wait;
  }

  Future<void> _advance(int step) async {
    if (!mounted) return;
    final table = TeenPattiTable.fromState(_session.state);
    if (table.step != step) return; // a newer step is already scheduled

    try {
      final status = await widget.repository.teenPatti.advance(
        tourId: _session.tourId,
        gameId: _session.id,
        expectedStep: step,
      );
      // The server refuses a turn that has not run out, so ask again once this
      // phone's clock says it has.
      if (status == 'noop' && _awaitingPastDeadline(table)) {
        _retry(step);
      }
    } catch (_) {
      _retry(step);
    }
  }

  bool _awaitingPastDeadline(TeenPattiTable table) {
    final deadline = table.turnDeadline;
    return deadline != null && DateTime.now().isAfter(deadline);
  }

  void _retry(int step) {
    if (!mounted) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(_retryAfter, () => _advance(step));
  }

  // --- Acting ----------------------------------------------------------------

  Future<void> _act(Map<String, dynamic> action) async {
    if (_busy) return;
    final table = TeenPattiTable.fromState(_session.state);
    setState(() => _busy = true);
    try {
      await widget.repository.teenPatti.act(
        tourId: _session.tourId,
        gameId: _session.id,
        action: action,
        expectedStep: table.step,
      );
      HapticFeedback.selectionClick();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'That move did not go through.');
    } catch (_) {
      _snack('Could not reach the table. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Stream<TeenPattiPrivateHand?>? _handFor(int seat) {
    if (_handStream == null || _handStreamSeat != seat) {
      _handStreamSeat = seat;
      _handStream = widget.repository.watchTeenPattiSeat(
        _session.tourId,
        _session.id,
        seat,
      );
    }
    return _handStream;
  }

  // --- Words for the table ---------------------------------------------------

  String _nameOf(int? seat) {
    if (seat == null) return 'Someone';
    if (seat == _mySeat) return 'You';
    return _session.playerAt(seat)?.displayName ?? 'Seat ${seat + 1}';
  }

  String _seatStatus(TeenPattiSeat s) {
    if (!s.playing) return 'Sitting out';
    if (s.isFolded) return s.lastKind == 'left' ? 'Left' : 'Packed';
    return s.isSeen ? 'Seen' : 'Blind';
  }

  String? _lastActionText(TeenPattiSeat s) {
    final amount = s.lastAmount == null ? '' : ' ${s.lastAmount}';
    switch (s.lastKind) {
      case 'blind':
        return 'Blind$amount';
      case 'chaal':
        return 'Chaal$amount';
      case 'raise':
        return 'Raise$amount';
      case 'show':
        return 'Show$amount';
      case 'sideshow':
        return 'Sideshow$amount';
      case 'sideshowLost':
        return 'Lost the sideshow';
      default:
        return null;
    }
  }

  String? _eventText(TeenPattiTable table) {
    final seat = table.lastEventSeat;
    switch (table.lastEventType) {
      case 'dealt':
        return 'New hand dealt.';
      case 'seen':
        return '${_nameOf(seat)} looked at their cards.';
      case 'bet':
        return '${_nameOf(seat)} played ${table.lastEventValue ?? ''}.';
      case 'raise':
        return '${_nameOf(seat)} raised the stake to ${table.baseBet}.';
      case 'pack':
        return '${_nameOf(seat)} packed.';
      case 'sideshowAsked':
        return '${_nameOf(seat)} asked ${_nameOf(table.lastEventValue)} for a sideshow.';
      case 'sideshowDeclined':
        return '${_nameOf(seat)} declined the sideshow.';
      case 'sideshowResult':
        return '${_nameOf(seat)} lost the sideshow.';
      case 'left':
        return '${_nameOf(seat)} left the table.';
      case 'rebuy':
        return '${_nameOf(seat)} bought more chips.';
      default:
        return null;
    }
  }

  String? _handName(String? handType) {
    if (handType == null) return null;
    final match = TeenPattiHandType.values.where((t) => t.name == handType);
    return match.isEmpty ? handType : match.first.banglaName;
  }

  // --- Layout ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final table = TeenPattiTable.fromState(_session.state);
    final mySeat = _mySeat;
    final activeName = _nameOf(table.actingSeat);

    return Column(
      children: [
        InGameVoiceBar(
          tourId: _session.tourId,
          gameId: _session.id,
          myEmail: widget.myEmail,
          myDisplayName: widget.repository.currentDisplayName,
          myPhotoUrl: widget.repository.currentPhotoUrl,
          myUid: widget.repository.currentUid,
        ),
        _header(table, activeName, mySeat),
        Expanded(child: _felt(table, mySeat)),
        if (mySeat != null) _myCards(table, mySeat),
        if (mySeat != null) _controls(table, mySeat),
      ],
    );
  }

  Widget _header(TeenPattiTable table, String activeName, int? mySeat) {
    final myTurn = mySeat != null && table.actingSeat == mySeat;
    final eventText = _eventText(table);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: myTurn ? AppColors.mintGreen : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pot: ${table.pot} chips',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Stake ${table.baseBet}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                myTurn ? 'YOUR TURN' : "$activeName's turn",
                style: TextStyle(
                  color: myTurn ? AppColors.mintGreen : Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (eventText != null) ...[
            const SizedBox(height: 4),
            Text(
              eventText,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _felt(TeenPattiTable table, int? mySeat) {
    final waiting = table.handNumber == 0;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2D6A4F), width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (waiting)
            const Text(
              'Waiting for the host to deal',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            )
          else
            Padding(
              padding: const EdgeInsets.all(10),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var seat = 0; seat < table.seats.length; seat++)
                    _seatTile(table, seat, seat == mySeat),
                ],
              ),
            ),
          if (table.result != null) _resultCard(table.result!),
        ],
      ),
    );
  }

  Widget _seatTile(TeenPattiTable table, int seat, bool isMe) {
    final s = table.seats[seat];
    final player = _session.playerAt(seat);
    final acting = table.actingSeat == seat;
    final shown = table.revealed[seat];
    final lastAction = _lastActionText(s);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF233F2E) : Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: acting ? AppColors.mintGreen : Colors.white12,
          width: acting ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _nameOf(seat) + (player?.isBot ?? false ? ' (bot)' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (table.dealer == seat)
                const Text(
                  'D',
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
            ],
          ),
          Text(
            '${s.chips} chips',
            style: const TextStyle(color: Colors.amber, fontSize: 11),
          ),
          Text(
            lastAction == null
                ? _seatStatus(s)
                : '${_seatStatus(s)} · $lastAction',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          if (shown != null)
            Row(
              children: [
                for (final card in shown)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: PlayingCardView(
                      rank: card.rank,
                      suitSymbol: card.suitSymbol,
                      isRed: card.suit == 'H' || card.suit == 'D',
                      width: 26,
                      height: 36,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultCard(TeenPattiHandResult result) {
    final names = result.winners.map(_nameOf).join(' & ');
    final hand = _handName(result.handType);
    final String detail;
    if (result.isTie) {
      detail = '$names tie and split ${result.potWon} chips.';
    } else if (result.wasShowdown) {
      detail =
          '$names win ${result.potWon} chips${hand == null ? '' : ' with $hand'}.';
    } else {
      detail = '$names take the pot of ${result.potWon} chips.';
    }
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 36),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _myCards(TeenPattiTable table, int mySeat) {
    final seen =
        table.seats[mySeat].isSeen || table.revealed.containsKey(mySeat);
    return StreamBuilder<TeenPattiPrivateHand?>(
      stream: _handFor(mySeat),
      builder: (context, snapshot) {
        final cards = snapshot.data?.cards ?? const <TeenPattiCard>[];
        if (cards.isEmpty) return const SizedBox(height: 92);
        return SizedBox(
          height: 92,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final card in cards)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: seen
                        ? PlayingCardView(
                            rank: card.rank,
                            suitSymbol: card.suitSymbol,
                            isRed: card.suit == 'H' || card.suit == 'D',
                            width: 58,
                            height: 84,
                          )
                        : Container(
                            width: 58,
                            height: 84,
                            decoration: BoxDecoration(
                              color: const Color(0xFF233F2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controls(TeenPattiTable table, int mySeat) {
    final buttons = <Widget>[];
    final myTurn = table.isTurnOf(mySeat);

    if (table.canReplySideshow(mySeat)) {
      buttons
        ..add(_button('Accept sideshow', AppColors.mintGreen,
            () => _act({'type': 'sideshowReply', 'accept': true})))
        ..add(_button('Decline', Colors.redAccent,
            () => _act({'type': 'sideshowReply', 'accept': false})));
    }
    if (myTurn) {
      buttons
          .add(_button('Pack', Colors.redAccent, () => _act({'type': 'pack'})));
      if (table.canRaise(mySeat)) {
        buttons
            .add(_button('Raise', Colors.amber, () => _act({'type': 'raise'})));
      }
      if (table.canShow(mySeat)) {
        buttons
            .add(_button('Show', Colors.amber, () => _act({'type': 'show'})));
      }
      if (table.canSideshow(mySeat)) {
        buttons.add(_button(
            'Sideshow', Colors.amber, () => _act({'type': 'sideshow'})));
      }
      final isSeen = table.seats[mySeat].isSeen;
      final label = '${isSeen ? 'Chaal' : 'Blind'} ${table.costFor(mySeat)}';
      if (table.canBet(mySeat)) {
        buttons.add(
            _button(label, AppColors.mintGreen, () => _act({'type': 'bet'})));
      }
    }
    if (table.canSee(mySeat)) {
      buttons.add(_button(
          'See cards', const Color(0xFF233F2E), () => _act({'type': 'see'})));
    }
    if (table.canRebuy(mySeat)) {
      buttons.add(
          _button('Rebuy 500', Colors.amber, () => _act({'type': 'rebuy'})));
    }
    if (table.isRoundOver && table.handNumber > 0) {
      buttons.add(_button(
          'Next hand', AppColors.mintGreen, () => _act({'type': 'nextHand'})));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: buttons.isEmpty
          ? Text(
              table.canReplySideshow(mySeat)
                  ? ''
                  : 'Waiting for ${_nameOf(table.actingSeat)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: buttons,
            ),
    );
  }

  Widget _button(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../common/in_game_voice_bar.dart';
import '../common/playing_card_view.dart';
import '../common/poker_chip_view.dart';
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
    final myChips = mySeat != null ? table.seats[mySeat].chips : null;

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
              if (myChips != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'Chips: $myChips',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Stake: ${table.baseBet}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: myTurn ? AppColors.mintGreen : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  myTurn ? 'YOUR TURN' : "$activeName's turn",
                  style: TextStyle(
                    color: myTurn ? Colors.black87 : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (eventText != null) ...[
            const SizedBox(height: 4),
            Text(
              eventText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _felt(TeenPattiTable table, int? mySeat) {
    final waiting = table.handNumber == 0;
    final opponentSeats = [
      for (var i = 0; i < table.seats.length; i++)
        if (mySeat == null || i != mySeat) i
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [
            Color(0xFF1E5638),
            Color(0xFF143F28),
            Color(0xFF0A2416),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD4AF37), width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
            ),
            if (waiting)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.style, size: 48, color: Colors.white24),
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for the host to deal',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  if (_isHost) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : () => _act({'type': 'nextHand'}),
                      icon: const Icon(Icons.play_arrow, color: Colors.black87),
                      label: const Text('Deal Hand',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black87)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.mintGreen,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                    ),
                  ],
                ],
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 240;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: _buildOpponents(table, opponentSeats, compact),
                      ),
                      Expanded(
                        child: Center(
                          child: _buildCenterPot(table, constraints),
                        ),
                      ),
                    ],
                  );
                },
              ),
            if (table.result != null) _resultCard(table.result!),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponents(TeenPattiTable table, List<int> seats, bool compact) {
    if (seats.isEmpty) return const SizedBox.shrink();
    if (seats.length <= 3) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final seat in seats)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _seatTile(table, seat, compact: compact),
              ),
            ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final seat in seats)
          SizedBox(
            width: 105,
            child: _seatTile(table, seat, compact: compact),
          ),
      ],
    );
  }

  Widget _buildCenterPot(TeenPattiTable table, BoxConstraints constraints) {
    final potSize = min(constraints.biggest.shortestSide * 0.75, 120.0);
    if (potSize < 36) return const SizedBox.shrink();

    return Container(
      width: potSize,
      height: potSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xFF1B6638), Color(0xFF134526), Color(0xFF092B15)],
        ),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PokerChipView(value: table.pot, size: 36),
                const SizedBox(height: 3),
                Text(
                  'POT: ৳${table.pot}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 2,
                          offset: Offset(0, 1)),
                    ],
                  ),
                ),
                Text(
                  'Stake: ৳${table.baseBet}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seatTile(TeenPattiTable table, int seat, {bool compact = false}) {
    final s = table.seats[seat];
    final player = _session.playerAt(seat);
    final acting = table.actingSeat == seat;
    final shown = table.revealed[seat];
    final lastAction = _lastActionText(s);
    final isDealer = table.dealer == seat;
    final isBot = player?.isBot ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: acting
            ? const Color(0xFF264E36)
            : Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: acting
              ? AppColors.mintGreen
              : (s.isFolded
                  ? Colors.red.withValues(alpha: 0.4)
                  : const Color(0xFFD4AF37).withValues(alpha: 0.4)),
          width: acting ? 2 : 1,
        ),
        boxShadow: acting
            ? [
                BoxShadow(
                  color: AppColors.mintGreen.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: acting ? AppColors.mintGreen : Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBot ? Icons.smart_toy : Icons.person,
                  size: 11,
                  color: acting ? Colors.black87 : Colors.white70,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    _nameOf(seat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: acting ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (isDealer) ...[
                  const SizedBox(width: 3),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'D',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.monetization_on, size: 11, color: Colors.amber),
              const SizedBox(width: 2),
              Text(
                '${s.chips}',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: s.isFolded
                  ? Colors.red.shade900.withValues(alpha: 0.6)
                  : (lastAction != null
                      ? Colors.amber.shade900.withValues(alpha: 0.5)
                      : Colors.black26),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              s.isFolded ? 'PACKED' : (lastAction ?? _seatStatus(s)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: s.isFolded ? Colors.redAccent : Colors.white70,
                fontSize: 10,
                fontWeight: s.isFolded || lastAction != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          if (compact)
            const SizedBox.shrink()
          else if (s.isFolded)
            const SizedBox(height: 34)
          else if (shown != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final card in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: PlayingCardView(
                      rank: card.rank,
                      suitSymbol: card.suitSymbol,
                      isRed: card.suit == 'H' || card.suit == 'D',
                      width: 22,
                      height: 32,
                    ),
                  ),
              ],
            )
          else if (s.playing)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 1.5),
                  child: PlayingCardView(
                    rank: '',
                    suitSymbol: '',
                    isRed: false,
                    isFaceUp: false,
                    width: 20,
                    height: 30,
                    backColor: Color(0xFF8B0000),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 1.5),
                  child: PlayingCardView(
                    rank: '',
                    suitSymbol: '',
                    isRed: false,
                    isFaceUp: false,
                    width: 20,
                    height: 30,
                    backColor: Color(0xFF8B0000),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 1.5),
                  child: PlayingCardView(
                    rank: '',
                    suitSymbol: '',
                    isRed: false,
                    isFaceUp: false,
                    width: 20,
                    height: 30,
                    backColor: Color(0xFF8B0000),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Out',
              style: TextStyle(color: Colors.white38, fontSize: 10),
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
        color: const Color(0xFF092614),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 38),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _myCards(TeenPattiTable table, int mySeat) {
    final seat = table.seats[mySeat];
    final seen = seat.isSeen || table.revealed.containsKey(mySeat);

    return StreamBuilder<TeenPattiPrivateHand?>(
      stream: _handFor(mySeat),
      builder: (context, snapshot) {
        final cards = snapshot.data?.cards ?? const <TeenPattiCard>[];
        if (cards.isEmpty) return const SizedBox(height: 96);

        HandEvaluation? eval;
        if (seen && cards.length == 3) {
          try {
            eval = TeenPattiEngine.evaluateHand(cards);
          } catch (_) {}
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eval != null && !seat.isFolded)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    '🔥 ${eval.handType.banglaName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: seen
                          ? PlayingCardView(
                              rank: card.rank,
                              suitSymbol: card.suitSymbol,
                              isRed: card.suit == 'H' || card.suit == 'D',
                              width: 60,
                              height: 88,
                              dimmed: seat.isFolded,
                            )
                          : GestureDetector(
                              onTap: (seat.isFolded || _busy)
                                  ? null
                                  : () => _act({'type': 'see'}),
                              child: SizedBox(
                                width: 60,
                                height: 88,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const PlayingCardView(
                                      rank: '',
                                      suitSymbol: '',
                                      isRed: false,
                                      isFaceUp: false,
                                      width: 60,
                                      height: 88,
                                      backColor: Color(0xFF8B0000),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: const Text(
                                        '👀 SEE',
                                        style: TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
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
      },
    );
  }

  Widget _controls(TeenPattiTable table, int mySeat) {
    final buttons = <Widget>[];
    final myTurn = table.isTurnOf(mySeat);

    if (table.canReplySideshow(mySeat)) {
      buttons
        ..add(_actionButton('Accept sideshow', AppColors.mintGreen,
            () => _act({'type': 'sideshowReply', 'accept': true})))
        ..add(_actionButton('Decline', Colors.redAccent,
            () => _act({'type': 'sideshowReply', 'accept': false})));
    }
    if (myTurn) {
      buttons.add(_actionButton(
          'Pack', Colors.redAccent, () => _act({'type': 'pack'}),
          isOutlined: true));
      final isSeen = table.seats[mySeat].isSeen;
      final cost = table.costFor(mySeat);
      final label = '${isSeen ? 'Chaal' : 'Blind'} ৳$cost';
      if (table.canBet(mySeat)) {
        buttons.add(_actionButton(
            label, AppColors.mintGreen, () => _act({'type': 'bet'})));
      }
      if (table.canRaise(mySeat)) {
        buttons.add(_actionButton(
            'Raise', Colors.amber, () => _act({'type': 'raise'})));
      }
      if (table.canShow(mySeat)) {
        buttons.add(_actionButton(
            'Show', Colors.amber, () => _act({'type': 'show'})));
      }
      if (table.canSideshow(mySeat)) {
        buttons.add(_actionButton('Sideshow', Colors.lightBlueAccent,
            () => _act({'type': 'sideshow'})));
      }
    }
    if (table.canSee(mySeat)) {
      buttons.add(_actionButton(
          'See cards', const Color(0xFF233F2E), () => _act({'type': 'see'}),
          textColor: Colors.white));
    }
    if (table.canRebuy(mySeat)) {
      buttons.add(_actionButton(
          'Rebuy 500', Colors.amber, () => _act({'type': 'rebuy'})));
    }
    if (table.isRoundOver && table.handNumber > 0) {
      buttons.add(_actionButton(
          'Next hand', AppColors.mintGreen, () => _act({'type': 'nextHand'})));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: buttons.isEmpty
          ? Text(
              table.canReplySideshow(mySeat)
                  ? ''
                  : 'Waiting for ${_nameOf(table.actingSeat)}...',
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

  Widget _actionButton(
    String label,
    Color color,
    VoidCallback onPressed, {
    bool isOutlined = false,
    Color textColor = Colors.black87,
  }) {
    if (isOutlined) {
      return OutlinedButton(
        onPressed: _busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          visualDensity: VisualDensity.compact,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
    }

    return ElevatedButton(
      onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        visualDensity: VisualDensity.compact,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

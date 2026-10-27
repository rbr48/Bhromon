import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../card29/card29_engine.dart';
import '../card29/card29_game.dart';
import '../common/in_game_voice_bar.dart';
import '../common/playing_card_view.dart';
import '../data/online_game_repository.dart';
import '../domain/models/card29_table.dart';
import '../domain/models/online_game_session.dart';

/// How long a bot's move waits, so people can follow the table. The host's
/// phone goes first; the others wait longer and only step in if it stalls.
const Duration _botPaceHost = Duration(milliseconds: 900);
const Duration _botPaceOther = Duration(milliseconds: 2400);

/// How long a finished trick stays on the table before it is collected.
const Duration _trickPause = Duration(milliseconds: 1300);

/// Slack after a turn deadline, so the server's clock and this phone's agree.
const Duration _deadlineGrace = Duration(milliseconds: 600);

/// How long to wait before asking again after a failed or refused step.
const Duration _retryAfter = Duration(seconds: 2);

/// A 29 table: the server deals and runs it, and each phone shows its own seat.
class OnlineCard29View extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineCard29View({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineCard29View> createState() => _OnlineCard29ViewState();
}

class _OnlineCard29ViewState extends State<OnlineCard29View> {
  Timer? _advanceTimer;
  int _scheduledStep = -1;
  bool _busy = false;

  Stream<Card29PrivateHand?>? _handStream;
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
  void didUpdateWidget(covariant OnlineCard29View oldWidget) {
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

  /// Arranges the next step of the table when one is due: a bot, a finished
  /// trick, or a player whose time has run out.
  void _scheduleAdvance() {
    if (_session.status != GameSessionStatus.inProgress) return;
    final table = Card29Table.fromState(_session.state);
    if (table.step == _scheduledStep) return;
    _scheduledStep = table.step;
    _advanceTimer?.cancel();

    final delay = _delayFor(table);
    if (delay == null) return;
    final step = table.step;
    _advanceTimer = Timer(delay, () => _advance(step));
  }

  Duration? _delayFor(Card29Table table) {
    switch (table.phase) {
      case Card29Phase.trickComplete:
        return _trickPause;
      case Card29Phase.bidding:
      case Card29Phase.trumpSelection:
      case Card29Phase.playing:
        final seat = table.actingSeat;
        if (_session.playerAt(seat)?.isBot ?? false) {
          return _isHost ? _botPaceHost : _botPaceOther;
        }
        final deadline = table.turnDeadline;
        if (deadline == null) return null;
        final wait = deadline.difference(DateTime.now()) + _deadlineGrace;
        return wait.isNegative ? _deadlineGrace : wait;
      case Card29Phase.roundOver:
      case Card29Phase.matchOver:
        return null;
    }
  }

  Future<void> _advance(int step) async {
    if (!mounted) return;
    final table = Card29Table.fromState(_session.state);
    if (table.step != step) return; // a newer step is already scheduled

    try {
      final status = await widget.repository.card29.advance(
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

  bool _awaitingPastDeadline(Card29Table table) {
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
    final table = Card29Table.fromState(_session.state);
    setState(() => _busy = true);
    try {
      await widget.repository.card29.act(
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

  Stream<Card29PrivateHand?>? _handFor(int seat) {
    if (_handStream == null || _handStreamSeat != seat) {
      _handStreamSeat = seat;
      _handStream = widget.repository.watchCard29Seat(
        _session.tourId,
        _session.id,
        seat,
      );
    }
    return _handStream;
  }

  // --- Text ------------------------------------------------------------------

  String _name(int seat, int? me) {
    if (seat == me) return 'You';
    return _session.playerAt(seat)?.displayName ?? 'Seat ${seat + 1}';
  }

  String _statusText(Card29Table table, int? me, Card29PrivateHand? hand) {
    final myTurn = me != null && table.actingSeat == me;
    switch (table.phase) {
      case Card29Phase.bidding:
        if (myTurn) return 'Your bid: ${table.minimumBid()} or more, or pass.';
        return 'Waiting for ${_name(table.currentTurn, me)} to bid.';
      case Card29Phase.trumpSelection:
        if (myTurn) {
          return 'You won the bid at ${table.highestBid}. Pick the secret trump.';
        }
        return '${_name(table.highestBidder, me)} is choosing the trump.';
      case Card29Phase.playing:
        if (myTurn) return 'Your turn: play a card.';
        return "${_name(table.currentTurn, me)}'s turn.";
      case Card29Phase.trickComplete:
        return '${_name(table.trickWinner ?? -1, me)} takes the trick.';
      case Card29Phase.roundOver:
        return _roundSummary(table, me);
      case Card29Phase.matchOver:
        final winner = table.matchPips[0] >= Card29Game.pipsToWin
            ? 'Your side'
            : 'The other side';
        return 'Match over. $winner won ${table.matchPips.join(' - ')}.';
    }
  }

  String _roundSummary(Card29Table table, int? me) {
    final score = table.lastEvent?.value ?? 0;
    final made = table.lastEvent?.type == 'bidMade';
    final bidders =
        Card29Game.teamOf(table.highestBidder) == Card29Game.teamOf(me ?? 0)
            ? 'Your side'
            : 'The other side';
    return made
        ? '$bidders made the bid ($score/${table.bidTarget}).'
        : '$bidders fell short ($score/${table.bidTarget}).';
  }

  String? _lastEventText(Card29Table table, int? me) {
    final event = table.lastEvent;
    if (event == null) return null;
    final who = _name(event.seat, me);
    switch (event.type) {
      case 'bid':
        return '$who bid ${event.value}.';
      case 'pass':
        return '$who passed.';
      case 'allPassed':
        return 'Everyone passed. The dealer plays at ${event.value}.';
      case 'trumpChosen':
        return '$who chose the trump.';
      case 'reveal':
        return '$who revealed the trump.';
      case 'ask':
        return '$who asked for trump.';
      case 'pair':
        return '$who showed the pair. Target is now ${event.value}.';
      case 'dealt':
        return 'New deal. ${_name(table.dealer, me)} dealt.';
      default:
        return null;
    }
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final table = Card29Table.fromState(_session.state);
    final me = _mySeat;

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
        if (_session.status == GameSessionStatus.waiting)
          const Expanded(
            child: Center(
              child: Text(
                'Waiting for the host to start the table.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        else if (me == null)
          const Expanded(
            child: Center(
              child: Text(
                'You are not seated at this table.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        else
          Expanded(
            child: StreamBuilder<Card29PrivateHand?>(
              stream: _handFor(me),
              builder: (context, snapshot) {
                final hand = snapshot.data;
                return _buildTable(table, me, hand);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTable(Card29Table table, int me, Card29PrivateHand? hand) {
    final cards = hand?.cards ?? const <Card29>[];
    final knownTrump = hand?.trumpSuit;
    final legal = hand == null
        ? const <Card29>[]
        : table.legalCards(seat: me, hand: cards, knownTrump: knownTrump);
    final event = _lastEventText(table, me);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        _scoreStrip(table),
        const SizedBox(height: 8),
        _statusCard(table, me, hand),
        if (event != null) ...[
          const SizedBox(height: 4),
          Text(event,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        _trickMat(table, me),
        const SizedBox(height: 10),
        _seatRow(table, me),
        const SizedBox(height: 10),
        _controls(table, me, cards, knownTrump),
        const SizedBox(height: 10),
        if (hand == null)
          const Center(
            child: Text('Dealing your cards...',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else
          _handTray(cards, legal),
      ],
    );
  }

  Widget _scoreStrip(Card29Table table) {
    return Row(
      children: [
        Expanded(
            child: _scoreChip(
                'You & North', table.matchPips[0], table.teamPoints[0])),
        const SizedBox(width: 8),
        Expanded(
            child: _scoreChip(
                'East & West', table.matchPips[1], table.teamPoints[1])),
      ],
    );
  }

  Widget _scoreChip(String label, int pips, int points) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text('$pips pips  ·  $points pts',
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statusCard(Card29Table table, int me, Card29PrivateHand? hand) {
    final myTurn = table.actingSeat == me &&
        (table.phase == Card29Phase.bidding ||
            table.phase == Card29Phase.trumpSelection ||
            table.phase == Card29Phase.playing);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: myTurn ? AppColors.mintGreen : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            _statusText(table, me, hand),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: myTurn ? AppColors.mintGreen : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            table.highestBidder < 0
                ? 'No bids yet'
                : 'Bid ${table.highestBid} by ${_name(table.highestBidder, me)}'
                    '${table.phase == Card29Phase.playing || table.phase == Card29Phase.trickComplete ? '  ·  target ${table.bidTarget}' : ''}',
            style: const TextStyle(color: Colors.amber, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _trickMat(Card29Table table, int me) {
    final showing = table.currentTrick;
    final trumpLabel = table.trumpRevealed && table.trumpSuit != null
        ? 'Trump: ${table.trumpSuit!.symbol} ${table.trumpSuit!.name}'
        : 'Trump hidden';
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF1B4332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2D6A4F), width: 4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 8,
            right: 10,
            child: Text(trumpLabel,
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          if (showing.isEmpty)
            Text(
              table.phase == Card29Phase.bidding ? 'BIDDING' : '29 FELT MAT',
              style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final play in showing)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlayingCardView(
                        rank: play.card.rank.code,
                        suitSymbol: play.card.suit.symbol,
                        isRed: play.card.suit == CardSuit.hearts ||
                            play.card.suit == CardSuit.diamonds,
                        width: 50,
                        height: 72,
                      ),
                      Text(_name(play.playerIndex, me),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _seatRow(Card29Table table, int me) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var seat = 0; seat < 4; seat++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: table.currentTurn == seat
                  ? AppColors.mintGreen.withValues(alpha: 0.2)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_name(seat, me)}'
              '${seat == table.highestBidder ? ' (bidder)' : ''}'
              '  ·  ${table.handCounts.length > seat ? table.handCounts[seat] : 0} cards',
              style: TextStyle(
                color: seat == me ? AppColors.mintGreen : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _controls(
      Card29Table table, int me, List<Card29> cards, CardSuit? knownTrump) {
    final buttons = <Widget>[];

    if (table.phase == Card29Phase.roundOver) {
      buttons.add(_button('Next deal', () => _act({'type': 'nextDeal'})));
    }
    if (table.phase == Card29Phase.matchOver) {
      buttons.add(_button('New match', () => _act({'type': 'newMatch'})));
    }

    if (table.phase == Card29Phase.bidding && table.actingSeat == me) {
      buttons.add(_button('Pass', () => _act({'type': 'pass'}), muted: true));
      final first = table.minimumBid();
      for (var bid = first;
          bid <= Card29Engine.maxBid && bid < first + 4;
          bid++) {
        buttons
            .add(_button('Bid $bid', () => _act({'type': 'bid', 'bid': bid})));
      }
    }

    if (table.phase == Card29Phase.trumpSelection &&
        table.highestBidder == me) {
      for (final suit in CardSuit.values) {
        buttons.add(_button(
          '${suit.symbol} ${suit.name}',
          () => _act({'type': 'selectTrump', 'suit': suitKey(suit)}),
        ));
      }
    }

    final hand = cards;
    if (table.canAskTrump(seat: me, hand: hand)) {
      buttons.add(_button('Ask for trump', () => _act({'type': 'ask'})));
    }
    if (table.canRevealTrump(seat: me, hand: hand)) {
      buttons.add(_button('Reveal trump', () => _act({'type': 'reveal'})));
    }
    if (table.canClaimPair(hand: hand, knownTrump: knownTrump)) {
      buttons
          .add(_button('Show the pair', () => _act({'type': 'claimRoyalty'})));
    }

    if (buttons.isEmpty) return const SizedBox(height: 4);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: buttons,
    );
  }

  Widget _button(String label, VoidCallback onPressed, {bool muted = false}) {
    return ElevatedButton(
      onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: muted ? Colors.white12 : AppColors.mintGreen,
        foregroundColor: muted ? Colors.white : Colors.black87,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _handTray(List<Card29> cards, List<Card29> legal) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: legal.contains(card) && !_busy
                    ? () => _act({'type': 'play', 'card': card.code})
                    : null,
                child: PlayingCardView(
                  rank: card.rank.code,
                  suitSymbol: card.suit.symbol,
                  isRed: card.suit == CardSuit.hearts ||
                      card.suit == CardSuit.diamonds,
                  width: 52,
                  height: 74,
                  highlighted: legal.contains(card),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on Card29Table {
  /// The lowest bid the next player may make.
  int minimumBid() => highestBid >= 16 ? highestBid + 1 : 16;
}

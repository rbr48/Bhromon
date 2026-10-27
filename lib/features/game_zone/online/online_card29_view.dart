import 'dart:async';
import 'dart:math';

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

    final northSeat = (me + 2) % 4;
    final westSeat = (me + 3) % 4;
    final eastSeat = (me + 1) % 4;

    return Column(
      children: [
        _scoreHeader(table, me, hand),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 6,
                    child: _buildSeatBadge(table, northSeat, me, 'North · Partner'),
                  ),
                  Positioned(
                    left: 6,
                    child: _buildSeatBadge(table, westSeat, me, 'West'),
                  ),
                  Positioned(
                    right: 6,
                    child: _buildSeatBadge(table, eastSeat, me, 'East'),
                  ),
                  _buildCenterTable(table, me, hand, constraints),
                  if (table.phase == Card29Phase.bidding && table.actingSeat == me)
                    Positioned(
                      bottom: 6,
                      left: 12,
                      right: 12,
                      child: Center(child: _biddingControls(table, me)),
                    ),
                  if (table.phase == Card29Phase.trumpSelection &&
                      table.highestBidder == me)
                    Positioned(
                      bottom: 6,
                      left: 12,
                      right: 12,
                      child: Center(child: _trumpSelector(table)),
                    ),
                ],
              );
            },
          ),
        ),
        _actionBannerAndControls(table, me, cards, knownTrump),
        if (hand == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Dealing your cards...',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: _handTray(cards, legal),
          ),
      ],
    );
  }

  Widget _scoreHeader(Card29Table table, int me, Card29PrivateHand? hand) {
    final event = _lastEventText(table, me);
    final myTeamPoints = table.teamPoints[0];
    final myTeamPips = table.matchPips[0];
    final oppTeamPoints = table.teamPoints[1];
    final oppTeamPips = table.matchPips[1];

    final bidText = table.highestBidder < 0
        ? 'Bidding in progress...'
        : 'Bid ${table.highestBid} by ${_name(table.highestBidder, me)}'
            '${table.phase == Card29Phase.playing || table.phase == Card29Phase.trickComplete ? ' · target ${table.bidTarget}' : ''}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF092614),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🛡 Your Team',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                    Text('$myTeamPoints pts · pips $myTeamPips/${Card29Game.pipsToWin}',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bidText,
                  style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Opponents 🔥',
                        style: TextStyle(
                            color: Colors.redAccent.shade100,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                    Text('$oppTeamPoints pts · pips $oppTeamPips/${Card29Game.pipsToWin}',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _statusText(table, me, hand),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
          if (event != null) ...[
            const SizedBox(height: 2),
            Text(
              event,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeatBadge(Card29Table table, int seat, int me, String fallbackLabel) {
    final isTurn = table.currentTurn == seat &&
        (table.phase == Card29Phase.bidding ||
            table.phase == Card29Phase.playing);
    final count = table.handCounts.length > seat ? table.handCounts[seat] : 0;
    final isBidder = table.highestBidder == seat;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isTurn ? Colors.amber : const Color(0x990A1A10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isTurn ? Colors.white : Colors.white24,
              width: isTurn ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_rounded,
                size: 13,
                color: isTurn ? Colors.black87 : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                seat == (me + 2) % 4
                    ? 'North · Partner'
                    : _name(seat, me),
                style: TextStyle(
                  color: isTurn ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              if (isBidder) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isTurn ? Colors.black87 : Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'BID',
                    style: TextStyle(
                      color: isTurn ? Colors.amber : Colors.black87,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 40,
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            alignment: WrapAlignment.center,
            children: List.generate(
              count.clamp(0, 8),
              (_) => const PlayingCardView(
                rank: '',
                suitSymbol: '',
                isRed: false,
                isFaceUp: false,
                width: 8,
                height: 12,
                backColor: Color(0xFF8B0000),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterTable(
      Card29Table table, int me, Card29PrivateHand? hand, BoxConstraints constraints) {
    final tableSize = (min(constraints.maxWidth * 0.56, constraints.maxHeight - 110))
        .clamp(160.0, 260.0);
    final cardW = tableSize * 0.22;
    final cardH = cardW * 1.45;
    final offset = tableSize * 0.16;

    final trump = table.trumpSuit;
    final trumpRevealed = table.trumpRevealed;
    final canReveal = table.canRevealTrump(seat: me, hand: hand?.cards ?? const []);
    final canAsk = table.canAskTrump(seat: me, hand: hand?.cards ?? const []);

    // Placed cards mapped by relative direction
    final trick = table.currentTrick;
    PlayedCard? cardForRelative(int rel) {
      final targetSeat = (me + rel) % 4;
      final found = trick.where((p) => p.playerIndex == targetSeat);
      return found.isNotEmpty ? found.first : null;
    }

    final southCard = cardForRelative(0);
    final eastCard = cardForRelative(1);
    final northCard = cardForRelative(2);
    final westCard = cardForRelative(3);

    return Container(
      width: tableSize,
      height: tableSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xFF1B6638), Color(0xFF134526), Color(0xFF092B15)],
        ),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Trump badge at top
          Positioned(
            top: tableSize * 0.06,
            child: GestureDetector(
              onTap: () {
                if (canReveal) {
                  _act({'type': 'reveal'});
                } else if (canAsk) {
                  _act({'type': 'ask'});
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (canReveal || canAsk)
                      ? Colors.amber.withValues(alpha: 0.3)
                      : const Color(0x88000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (canReveal || canAsk) ? Colors.amber : Colors.amber.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Trump: ',
                        style: TextStyle(color: Colors.white70, fontSize: 10)),
                    if (trumpRevealed && trump != null)
                      Text(
                        '${trump.symbol} ${trump.name}',
                        style: TextStyle(
                          color: (trump == CardSuit.hearts || trump == CardSuit.diamonds)
                              ? Colors.redAccent
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      )
                    else if (canReveal)
                      const Text(
                        'Tap to Reveal',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 10),
                      )
                    else if (canAsk)
                      const Text(
                        'Ask for Trump',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 10),
                      )
                    else
                      const Text(
                        'Hidden',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Watermark when trick is empty
          if (trick.isEmpty)
            Text(
              table.phase == Card29Phase.bidding ? 'BIDDING' : '29 TABLE',
              style: const TextStyle(
                color: Color(0x22FFFFFF),
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),

          // North played card
          if (northCard != null)
            Positioned(
              top: offset,
              child: _playedCardWidget(northCard, cardW, cardH),
            ),
          // South played card
          if (southCard != null)
            Positioned(
              bottom: offset,
              child: _playedCardWidget(southCard, cardW, cardH),
            ),
          // West played card
          if (westCard != null)
            Positioned(
              left: offset * 0.75,
              child: _playedCardWidget(westCard, cardW, cardH),
            ),
          // East played card
          if (eastCard != null)
            Positioned(
              right: offset * 0.75,
              child: _playedCardWidget(eastCard, cardW, cardH),
            ),
        ],
      ),
    );
  }

  Widget _playedCardWidget(PlayedCard play, double width, double height) {
    return PlayingCardView(
      rank: play.card.rank.code,
      suitSymbol: play.card.suit.symbol,
      isRed: play.card.suit == CardSuit.hearts ||
          play.card.suit == CardSuit.diamonds,
      width: width,
      height: height,
    );
  }

  Widget _biddingControls(Card29Table table, int me) {
    final minBid = table.minimumBid();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: _busy ? null : () => _act({'type': 'pass'}),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Pass', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          for (var bid = minBid; bid <= Card29Engine.maxBid && bid < minBid + 3; bid++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ElevatedButton(
                onPressed: _busy ? null : () => _act({'type': 'bid', 'bid': bid}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: Colors.black87,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('Bid $bid', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trumpSelector(Card29Table table) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Choose Trump Suit',
              style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final suit in CardSuit.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            {'type': 'selectTrump', 'suit': suitKey(suit)}),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (suit == CardSuit.hearts ||
                              suit == CardSuit.diamonds)
                          ? Colors.red.shade900
                          : Colors.grey.shade900,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('${suit.symbol} ${suit.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBannerAndControls(
      Card29Table table, int me, List<Card29> cards, CardSuit? knownTrump) {
    final buttons = <Widget>[];

    if (table.phase == Card29Phase.roundOver) {
      buttons.add(_button('Next Deal', () => _act({'type': 'nextDeal'})));
    }
    if (table.phase == Card29Phase.matchOver) {
      buttons.add(_button('New Match', () => _act({'type': 'newMatch'})));
    }
    if (table.canClaimPair(hand: cards, knownTrump: knownTrump)) {
      buttons.add(_button('Claim Pair (Royalty)', () => _act({'type': 'claimRoyalty'})));
    }

    if (buttons.isEmpty) return const SizedBox(height: 2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: buttons,
      ),
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

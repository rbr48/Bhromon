import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/game_zone_portrait_lock.dart';
import '../common/playing_card_view.dart';
import '../common/poker_chip_view.dart';
import 'teen_patti_engine.dart';
import 'teen_patti_game.dart';

/// Keeps chips and the hand in progress while the player visits other screens.
class _TeenPattiSession {
  static TeenPattiGame? game;
  static TeenPattiResult? lastShownResult;
}

class TeenPattiScreen extends StatefulWidget {
  const TeenPattiScreen({super.key});

  @override
  State<TeenPattiScreen> createState() => _TeenPattiScreenState();
}

class _TeenPattiScreenState extends State<TeenPattiScreen>
    with GameZonePortraitLock {
  late final TeenPattiGame _game;
  Timer? _botTimer;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _game = _TeenPattiSession.game ??= TeenPattiGame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_game.hasDealt) {
        _dealNextHand();
      } else {
        _afterStateChange();
      }
    });
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  /// Schedules bots, prompts and dialogs for whatever the table now needs.
  void _afterStateChange() {
    if (!mounted) return;
    setState(() {});
    _botTimer?.cancel();

    switch (_game.phase) {
      case TeenPattiPhase.betting:
        if (!_game.players[_game.currentTurn].isUser) {
          _botTimer = Timer(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            _game.playBotTurn();
            _afterStateChange();
          });
        }
        break;
      case TeenPattiPhase.awaitingSideshowReply:
        _askSideshowReply();
        break;
      case TeenPattiPhase.roundOver:
        final result = _game.result;
        if (result != null &&
            !identical(result, _TeenPattiSession.lastShownResult)) {
          _TeenPattiSession.lastShownResult = result;
          HapticFeedback.heavyImpact();
          _showResultDialog(result);
        }
        break;
    }
  }

  Future<void> _dealNextHand() async {
    if (_game.userNeedsRebuy) {
      final rebuy = await _showRebuyDialog();
      if (!mounted) return;
      if (!rebuy) {
        Navigator.of(context).maybePop();
        return;
      }
      _game.rebuyUser();
    }
    _game.startHand();
    _afterStateChange();
  }

  Future<bool> _showRebuyDialog() async {
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF092614),
        title: const Text('Out of chips',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'You have ${_game.user.chips} chips, but a hand needs at least ${TeenPattiGame.minimumBuyIn} '
          '(boot + one blind). Rebuy to keep playing?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Leave table',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rebuy +${TeenPattiGame.rebuyAmount}'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    return result ?? false;
  }

  Future<void> _askSideshowReply() async {
    if (_dialogOpen) return;
    final request = _game.pendingSideshow;
    if (request == null) return;
    _dialogOpen = true;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF092614),
        title: const Text('Sideshow request',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '${_game.players[request.fromId].name} wants to compare cards with you privately. '
          'The weaker hand packs; if the hands tie, ${_game.players[request.fromId].name} packs.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Decline', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    _game.answerSideshow(accept ?? false);
    _afterStateChange();
  }

  void _showResultDialog(TeenPattiResult result) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF092614),
        title: Text('🏆 ${result.title}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content:
            Text(result.detail, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('View table',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () {
              Navigator.pop(ctx);
              _dealNextHand();
            },
            child: const Text('Next Deal'),
          ),
        ],
      ),
    );
  }

  Future<void> _onNewHandPressed() async {
    if (_game.isHandInProgress && !_game.user.isFolded) {
      final ok = await confirmDiscardGame(
        context,
        title: 'Leave this hand?',
        message:
            'You will pack and lose the chips you have already put in the pot. '
            'The other players settle the hand now.',
        confirmLabel: 'Pack & deal again',
      );
      if (!ok || !mounted) return;
    }
    _botTimer?.cancel();
    if (_game.isHandInProgress) {
      _game.forfeitUserAndFinish();
      _TeenPattiSession.lastShownResult =
          _game.result; // no result popup for a hand you walked away from
    }
    _dealNextHand();
  }

  void _act(void Function() action, {_Haptic haptic = _Haptic.light}) {
    switch (haptic) {
      case _Haptic.light:
        HapticFeedback.lightImpact();
        break;
      case _Haptic.medium:
        HapticFeedback.mediumImpact();
        break;
      case _Haptic.selection:
        HapticFeedback.selectionClick();
        break;
    }
    action();
    _afterStateChange();
  }

  void _showRulesDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teen Patti rules'),
        content: const SingleChildScrollView(
          child: Text(
            'Hand ranks (high to low): Trail, Pure sequence, Sequence, Colour, Pair, High card. '
            'A-K-Q is the top run and A-2-3 the lowest.\n\n'
            '• Everyone pays a boot of ${TeenPattiGame.boot}.\n'
            '• Blind players stake the base bet; seen players stake double (Chaal).\n'
            '• Raise doubles the base bet, up to ${TeenPattiGame.maxBase} (Chaal ${TeenPattiGame.maxBase * 2}).\n'
            '• After ${TeenPattiGame.maxBlindTurns} blind turns your cards open automatically.\n'
            '• Sideshow (Back-Ask): a seen player may ask the previous seen player to compare privately. '
            'They may decline. The weaker hand packs; a tie packs the player who asked.\n'
            '• Show: when two players remain, either may ask for a show. Equal hands split the pot.\n'
            '• At a pot of ${TeenPattiGame.potLimit} everyone still in is shown automatically.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _game.user;
    final isUserTurn = _game.isTurnOf(0);

    return Scaffold(
      backgroundColor: const Color(0xFF0F381E),
      appBar: AppBar(
        title: const Text('Teen Patti (৩ পাত্তি)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF092614),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Rules',
              onPressed: _showRulesDialog),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New Hand',
              onPressed: _onNewHandPressed),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildPotHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // On short screens the seats drop their card row so the table never overflows.
                  final compact = constraints.maxHeight < 190;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _buildPlayerSeat(_game.players[3],
                                    compact: compact)),
                            Expanded(
                                child: _buildPlayerSeat(_game.players[2],
                                    compact: compact)),
                            Expanded(
                                child: _buildPlayerSeat(_game.players[1],
                                    compact: compact)),
                          ],
                        ),
                      ),
                      Expanded(
                          child: LayoutBuilder(
                              builder: (context, c) =>
                                  Center(child: _buildCenterPot(c)))),
                    ],
                  );
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: SingleChildScrollView(
                  child: _buildUserControls(user, isUserTurn)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPotHeader() {
    TextStyle style(Color c, {bool bold = false}) => TextStyle(
        color: c,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontSize: 13);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF092614),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Your Chips: ${_game.user.chips}',
                      style: style(Colors.amber, bold: true)),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.amber.shade800,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Pot: ${_game.pot}',
                    style: style(Colors.white, bold: true)),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('Base Bet: ${_game.baseBet}',
                      style: style(Colors.white70)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _game.status,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSeat(TeenPattiPlayer player, {bool compact = false}) {
    final isTurn = _game.isTurnOf(player.id);
    final state =
        player.isFolded ? 'PACKED' : (player.isSeen ? 'Seen' : 'Blind');
    final reveal = _game.isRoundOver && !player.isFolded;

    return Semantics(
      label: '${player.name}, ${player.chips} chips, $state'
          '${player.lastAction != null ? ', last action ${player.lastAction}' : ''}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isTurn ? Colors.amber : const Color(0x66000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isTurn ? Colors.white : Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy,
                    size: 13, color: isTurn ? Colors.black87 : Colors.white),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    player.name.replaceAll(' (Bot)', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTurn ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text('${player.chips} chips',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
          Text(
            player.lastAction ?? state,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: player.isFolded ? Colors.redAccent : Colors.white70,
              fontSize: 11,
              fontWeight: player.isFolded ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (compact)
            const SizedBox.shrink()
          else if (player.isFolded)
            const SizedBox(height: 42)
          else ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: player.hand.map((c) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: reveal ? _buildMiniCard(c) : _buildCardBack(26, 38),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBack(double width, double height, {Widget? child}) {
    if (child != null) {
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PlayingCardView(
              rank: '',
              suitSymbol: '',
              isRed: false,
              isFaceUp: false,
              width: width,
              height: height,
              backColor: const Color(0xFF8B0000),
            ),
            child,
          ],
        ),
      );
    }
    return PlayingCardView(
      rank: '',
      suitSymbol: '',
      isRed: false,
      isFaceUp: false,
      width: width,
      height: height,
      backColor: const Color(0xFF8B0000),
    );
  }

  Widget _buildCenterPot(BoxConstraints constraints) {
    final potSize = min(constraints.biggest.shortestSide * 0.85, 125.0);
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
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4))
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
                PokerChipView(value: _game.pot, size: 36),
                const SizedBox(height: 3),
                Text(
                  'POT: ৳${_game.pot}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 2,
                          offset: Offset(0, 1))
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserControls(TeenPattiPlayer user, bool isUserTurn) {
    final userEval =
        user.isSeen ? TeenPattiEngine.evaluateHand(user.hand) : null;
    final cost = _game.costFor(user);
    final raiseCost = _game.costFor(user, base: _game.baseBet * 2);
    final canAffordStake = user.chips >= cost;

    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (userEval != null && !user.isFolded)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Your Hand: ${userEval.handType.banglaName}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: user.hand.map((c) {
              final faceUp = user.isSeen || _game.isRoundOver;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: faceUp
                    ? _buildFullCard(c, dimmed: user.isFolded)
                    : Semantics(
                        button: true,
                        label: 'See your cards',
                        child: GestureDetector(
                          onTap: user.isFolded
                              ? null
                              : () => _act(() => _game.see(0),
                                  haptic: _Haptic.selection),
                          child: _buildCardBack(
                            52,
                            76,
                            child: const Center(
                              child: Text(
                                '👀 SEE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          if (isUserTurn) ...[
            if (!canAffordStake)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Not enough chips for ${user.isSeen ? 'Chaal' : 'Blind'} ($cost). You can only Pack.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  style: buttonStyle.merge(OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  )),
                  onPressed: () => _act(() => _game.pack(0)),
                  child: const Text('Pack (Fold)'),
                ),
                if (!user.isSeen)
                  ElevatedButton(
                    style: buttonStyle.merge(ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    )),
                    onPressed: () =>
                        _act(() => _game.see(0), haptic: _Haptic.selection),
                    child: const Text('See Cards'),
                  ),
                ElevatedButton(
                  style: buttonStyle.merge(ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
                  )),
                  onPressed:
                      _game.canBet(0) ? () => _act(() => _game.bet(0)) : null,
                  child: Text(user.isSeen ? 'Chaal ($cost)' : 'Blind ($cost)'),
                ),
                if (_game.baseBet < TeenPattiGame.maxBase)
                  OutlinedButton(
                    style: buttonStyle.merge(OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber,
                      side: const BorderSide(color: Colors.amber),
                    )),
                    onPressed: _game.canRaise(0)
                        ? () =>
                            _act(() => _game.raise(0), haptic: _Haptic.medium)
                        : null,
                    child: Text('Raise ($raiseCost)'),
                  ),
                if (_game.canSideshow(0))
                  ElevatedButton(
                    style: buttonStyle.merge(ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                    )),
                    onPressed: () => _act(() => _game.requestSideshow(0),
                        haptic: _Haptic.medium),
                    child: Text('Sideshow ($cost)'),
                  ),
                if (_game.activePlayers.length == 2)
                  ElevatedButton(
                    style: buttonStyle.merge(ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    )),
                    onPressed: _game.canShow(0)
                        ? () =>
                            _act(() => _game.show(0), haptic: _Haptic.medium)
                        : null,
                    child: Text('Show ($cost)'),
                  ),
              ],
            ),
          ] else if (_game.isRoundOver)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87),
              onPressed: _dealNextHand,
              child: const Text('Deal Next Hand'),
            )
          else
            Text(
              user.isFolded
                  ? 'You packed - watching the rest of the hand.'
                  : 'Waiting for the other players...',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniCard(TeenPattiCard c) {
    final isRed = c.suit == 'H' || c.suit == 'D';
    return Semantics(
      label: '${c.rank} of ${_suitName(c.suit)}',
      child: PlayingCardView(
        rank: c.rank,
        suitSymbol: c.suitSymbol,
        isRed: isRed,
        width: 26,
        height: 38,
        backColor: const Color(0xFF8B0000),
      ),
    );
  }

  Widget _buildFullCard(TeenPattiCard c, {bool dimmed = false}) {
    final isRed = c.suit == 'H' || c.suit == 'D';

    return Semantics(
      label: '${c.rank} of ${_suitName(c.suit)}',
      child: PlayingCardView(
        rank: c.rank,
        suitSymbol: c.suitSymbol,
        isRed: isRed,
        width: 52,
        height: 76,
        dimmed: dimmed,
        highlighted: true,
        backColor: const Color(0xFF1E3A8A),
      ),
    );
  }

  String _suitName(String suit) {
    switch (suit) {
      case 'S':
        return 'spades';
      case 'H':
        return 'hearts';
      case 'D':
        return 'diamonds';
      default:
        return 'clubs';
    }
  }
}

enum _Haptic { light, medium, selection }

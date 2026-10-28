import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../data/vps_quiz_service.dart';
import '../../../../core/localization/app_localizations.dart';

class TourQuizScreen extends StatefulWidget {
  final String tourId;

  const TourQuizScreen({super.key, required this.tourId});

  @override
  State<TourQuizScreen> createState() => _TourQuizScreenState();
}

class _TourQuizScreenState extends State<TourQuizScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final VpsQuizService _quizService = VpsQuizService();

  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;

  List<ServerQuizQuestion> _quiz = [];
  bool _isLoading = true;
  String? _errorMessage;

  int _currentIndex = 0;
  int? _selectedOption;
  bool _isAnswered = false;
  int _score = 0;
  bool _isFinished = false;
  String? _achievedBadge;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _watchGroup();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (!mounted) return;
      final isFirst = _tourGroup == null;
      setState(() {
        _tourGroup = g;
      });
      if (isFirst) {
        _loadQuizQuestions();
      }
    });
  }

  Future<void> _loadQuizQuestions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentIndex = 0;
      _selectedOption = null;
      _isAnswered = false;
      _score = 0;
      _isFinished = false;
      _achievedBadge = null;
    });

    try {
      final dest = _tourGroup?.destination;
      final rawQuestions = await _quizService.fetchQuestions(
        destination: dest,
        limit: 10,
      );

      if (!mounted) return;

      if (rawQuestions.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = context.l10n.translate('tq_not_ready');
        });
        return;
      }

      // Shuffle options for fair gameplay
      final shuffled = rawQuestions.map((q) {
        final order = List<int>.generate(q.options.length, (i) => i)
          ..shuffle(_random);
        return ServerQuizQuestion(
          id: q.id,
          category: q.category,
          destinationTag: q.destinationTag,
          difficulty: q.difficulty,
          question: q.question,
          options: [for (final i in order) q.options[i]],
          correctIndex: order.indexOf(q.correctIndex),
          explanation: q.explanation,
        );
      }).toList();

      setState(() {
        _quiz = shuffled;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'কুইজ লোড করতে সমস্যা হয়েছে। পুনরায় চেষ্টা করুন।';
      });
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  void _onOptionSelected(int index) {
    if (_isAnswered || _currentIndex >= _quiz.length) return;

    setState(() {
      _selectedOption = index;
      _isAnswered = true;
      if (index == _quiz[_currentIndex].correctIndex) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex + 1 < _quiz.length) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
        _isAnswered = false;
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() {
    setState(() {
      _isFinished = true;
    });

    // Submit attempt to server
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _quizService
          .submitQuizAttempt(
        userUid: user.uid,
        userName: user.displayName ?? user.email,
        tourId: widget.tourId,
        score: _score,
        total: _quiz.length,
        destination: _tourGroup?.destination,
      )
          .then((res) {
        if (mounted && res != null && res['badge'] != null) {
          setState(() {
            _achievedBadge = res['badge'] as String;
          });
        }
      });
    }
  }

  void _restartQuiz() {
    _loadQuizQuestions();
  }

  String _formatCategoryLabel(String cat) {
    switch (cat.toLowerCase()) {
      case 'hills_trek':
        return 'পাহাড় ও ট্রেইল ⛰️';
      case 'beaches':
        return 'সৈকত ও সাগর 🌊';
      case 'nature':
        return 'প্রকৃতি ও বনাঞ্চল 🌿';
      case 'heritage':
        return 'ইতিহাস ও প্রত্নতত্ত্ব 🏛️';
      case 'food_culture':
        return 'ঐতিহ্যবাহী খাবার 🍲';
      case 'travel_safety':
        return 'ভ্রমণ নিরাপত্তা 🦺';
      case 'districts_64':
        return 'জেলা ভ্রমণ 🧭';
      case 'transport':
        return 'নদী ও রেলপথ 🚂';
      default:
        return 'ভ্রমণ কুইজ 🎯';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text(
          context.l10n.translate('tq_title_master'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'নতুন প্রশ্ন আনুন',
            icon: const Icon(Icons.refresh, color: Colors.tealAccent),
            onPressed: _restartQuiz,
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.tealAccent),
            SizedBox(height: 16),
            Text(
              'সার্ভার থেকে ১০০০+ প্রিমিয়াম কুইজ লোড হচ্ছে...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('পুনরায় চেষ্টা করুন'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loadQuizQuestions,
              ),
            ],
          ),
        ),
      );
    }

    if (_isFinished) {
      return _buildResultView();
    }

    return _buildQuizView();
  }

  Widget _buildQuizView() {
    final q = _quiz[_currentIndex];
    final progress = (_currentIndex + 1) / _quiz.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress & Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.translate('tq_progress',
                    args: {'n': _currentIndex + 1, 'total': _quiz.length}),
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                context.l10n.translate('tq_score', args: {'score': _score}),
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF263D42),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
            ),
          ),
          const SizedBox(height: 16),

          // Category Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.tealAccent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _formatCategoryLabel(q.category),
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  q.difficulty == 'easy'
                      ? 'সহজ'
                      : (q.difficulty == 'hard' ? 'কঠিন' : 'মাঝারি'),
                  style: TextStyle(
                    color: q.difficulty == 'easy'
                        ? Colors.greenAccent
                        : (q.difficulty == 'hard'
                            ? Colors.orangeAccent
                            : Colors.white70),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Question Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF142C33), Color(0xFF0C1B20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              q.question,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Options List
          ...List.generate(q.options.length, (i) {
            return _buildOptionButton(q, i);
          }),

          // Explanation Banner
          if (_isAnswered) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF183038),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb,
                          color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.translate('tq_explanation_heading'),
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q.explanation,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _nextQuestion,
              child: Text(
                _currentIndex + 1 < _quiz.length
                    ? context.l10n.translate('tq_next')
                    : context.l10n.translate('tq_see_result'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionButton(ServerQuizQuestion q, int index) {
    Color bg = const Color(0xFF142428);
    Color border = Colors.white12;
    Color textColor = Colors.white;

    if (_isAnswered) {
      if (index == q.correctIndex) {
        bg = Colors.green.shade900;
        border = Colors.greenAccent;
        textColor = Colors.greenAccent;
      } else if (index == _selectedOption) {
        bg = Colors.red.shade900;
        border = Colors.redAccent;
        textColor = Colors.redAccent;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onOptionSelected(index),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + index), // A, B, C, D
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  q.options[index],
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isAnswered)
                Icon(
                  index == q.correctIndex
                      ? Icons.check_circle
                      : (index == _selectedOption ? Icons.cancel : null),
                  color: index == q.correctIndex
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultView() {
    final pct = _quiz.isNotEmpty ? (_score / _quiz.length) * 100 : 0.0;
    final dest =
        _tourGroup?.destination ?? context.l10n.translate('tq_default_tour');

    String badge = _achievedBadge ?? context.l10n.translate('tq_badge_learner');
    if (_achievedBadge == null) {
      if (pct >= 85) {
        badge =
            context.l10n.translate('tq_badge_expert', args: {'dest': dest});
      } else if (pct >= 60) {
        badge = context.l10n.translate('tq_badge_skilled');
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 72),
            ),
            const SizedBox(height: 20),
            Text(
              badge,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.translate('tq_result_summary',
                  args: {'score': _score, 'total': _quiz.length}),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'সঠিক উত্তর: ${pct.toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.tealAccent, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text(
                'নতুন ১০টি প্রশ্ন খেলুন',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _restartQuiz,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/localization/app_localizations.dart';

class QuizQuestion {
  final int id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

class TourQuizScreen extends StatefulWidget {
  final String tourId;

  const TourQuizScreen({super.key, required this.tourId});

  @override
  State<TourQuizScreen> createState() => _TourQuizScreenState();
}

class _TourQuizScreenState extends State<TourQuizScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  int _currentIndex = 0;
  int? _selectedOption;
  bool _isAnswered = false;
  int _score = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _watchGroup();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (!mounted) return;
      // Questions are shuffled once; later group changes must not reset a game.
      final first = _tourGroup == null;
      setState(() {
        _tourGroup = g;
        if (first) _prepareQuiz();
      });
    });
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  /// Question bank for the tour's destination. Destinations without a bank
  /// get an empty list, not someone else's quiz.
  List<QuizQuestion> get _baseQuestions {
    final dest = _tourGroup?.destination.toLowerCase() ?? '';

    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return [
        QuizQuestion(
          id: 1,
          question: context.l10n.translate('tq_s_district_question'),
          options: [
            context.l10n.translate('tq_s_district_a'),
            context.l10n.translate('tq_s_district_b'),
            context.l10n.translate('tq_s_district_c'),
            context.l10n.translate('tq_s_district_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_s_district_why'),
        ),
        QuizQuestion(
          id: 2,
          question: context.l10n.translate('tq_s_peak_question'),
          options: [
            context.l10n.translate('tq_s_peak_a'),
            context.l10n.translate('tq_s_peak_b'),
            context.l10n.translate('tq_s_peak_c'),
            context.l10n.translate('tq_s_peak_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_s_peak_why'),
        ),
        QuizQuestion(
          id: 3,
          question: context.l10n.translate('tq_s_transport_question'),
          options: [
            context.l10n.translate('tq_s_transport_a'),
            context.l10n.translate('tq_s_transport_b'),
            context.l10n.translate('tq_s_transport_c'),
            context.l10n.translate('tq_s_transport_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_s_transport_why'),
        ),
        QuizQuestion(
          id: 4,
          question: context.l10n.translate('tq_s_escort_question'),
          options: [
            context.l10n.translate('tq_s_escort_a'),
            context.l10n.translate('tq_s_escort_b'),
            context.l10n.translate('tq_s_escort_c'),
            context.l10n.translate('tq_s_escort_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_s_escort_why'),
        ),
        QuizQuestion(
          id: 5,
          question: context.l10n.translate('tq_s_attraction_question'),
          options: [
            context.l10n.translate('tq_s_attraction_a'),
            context.l10n.translate('tq_s_attraction_b'),
            context.l10n.translate('tq_s_attraction_c'),
            context.l10n.translate('tq_s_attraction_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_s_attraction_why'),
        ),
      ];
    } else if (dest.contains('sylhet') || dest.contains('সিলেট')) {
      return [
        QuizQuestion(
          id: 1,
          question: context.l10n.translate('tq_y_swamp_question'),
          options: [
            context.l10n.translate('tq_y_swamp_a'),
            context.l10n.translate('tq_y_swamp_b'),
            context.l10n.translate('tq_y_swamp_c'),
            context.l10n.translate('tq_y_swamp_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_y_swamp_why'),
        ),
        QuizQuestion(
          id: 2,
          question: context.l10n.translate('tq_y_river_question'),
          options: [
            context.l10n.translate('tq_y_river_a'),
            context.l10n.translate('tq_y_river_b'),
            context.l10n.translate('tq_y_river_c'),
            context.l10n.translate('tq_y_river_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_y_river_why'),
        ),
        QuizQuestion(
          id: 3,
          question: context.l10n.translate('tq_y_citrus_question'),
          options: [
            context.l10n.translate('tq_y_citrus_a'),
            context.l10n.translate('tq_y_citrus_b'),
            context.l10n.translate('tq_y_citrus_c'),
            context.l10n.translate('tq_y_citrus_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_y_citrus_why'),
        ),
        QuizQuestion(
          id: 4,
          question: context.l10n.translate('tq_y_tea_question'),
          options: [
            context.l10n.translate('tq_y_tea_a'),
            context.l10n.translate('tq_y_tea_b'),
            context.l10n.translate('tq_y_tea_c'),
            context.l10n.translate('tq_y_tea_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_y_tea_why'),
        ),
      ];
    } else if (dest.contains('cox') || dest.contains('কক্সবাজার')) {
      return [
        QuizQuestion(
          id: 1,
          question: context.l10n.translate('tq_c_beach_question'),
          options: [
            context.l10n.translate('tq_c_beach_a'),
            context.l10n.translate('tq_c_beach_b'),
            context.l10n.translate('tq_c_beach_c'),
            context.l10n.translate('tq_c_beach_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_c_beach_why'),
        ),
        QuizQuestion(
          id: 2,
          question: context.l10n.translate('tq_c_inani_question'),
          options: [
            context.l10n.translate('tq_c_inani_a'),
            context.l10n.translate('tq_c_inani_b'),
            context.l10n.translate('tq_c_inani_c'),
            context.l10n.translate('tq_c_inani_d')
          ],
          correctIndex: 1,
          explanation: context.l10n.translate('tq_c_inani_why'),
        ),
        QuizQuestion(
          id: 3,
          question: context.l10n.translate('tq_c_danger_question'),
          options: [
            context.l10n.translate('tq_c_danger_a'),
            context.l10n.translate('tq_c_danger_b'),
            context.l10n.translate('tq_c_danger_c'),
            context.l10n.translate('tq_c_danger_d')
          ],
          correctIndex: 1,
          explanation: context.l10n.translate('tq_c_danger_why'),
        ),
        QuizQuestion(
          id: 4,
          question: context.l10n.translate('tq_c_island_question'),
          options: [
            context.l10n.translate('tq_c_island_a'),
            context.l10n.translate('tq_c_island_b'),
            context.l10n.translate('tq_c_island_c'),
            context.l10n.translate('tq_c_island_d')
          ],
          correctIndex: 1,
          explanation: context.l10n.translate('tq_c_island_why'),
        ),
        QuizQuestion(
          id: 5,
          question: context.l10n.translate('tq_c_marine_question'),
          options: [
            context.l10n.translate('tq_c_marine_a'),
            context.l10n.translate('tq_c_marine_b'),
            context.l10n.translate('tq_c_marine_c'),
            context.l10n.translate('tq_c_marine_d')
          ],
          correctIndex: 0,
          explanation: context.l10n.translate('tq_c_marine_why'),
        ),
      ];
    }
    return const [];
  }

  /// Quiz questions with their options shuffled, so the answer is not always
  /// the first one. Built once per attempt.
  List<QuizQuestion> _quiz = const [];
  final Random _random = Random();

  void _prepareQuiz() {
    _quiz = _baseQuestions.map((q) {
      final order = List<int>.generate(q.options.length, (i) => i)
        ..shuffle(_random);
      return QuizQuestion(
        id: q.id,
        question: q.question,
        options: [for (final i in order) q.options[i]],
        correctIndex: order.indexOf(q.correctIndex),
        explanation: q.explanation,
      );
    }).toList();
  }

  void _onOptionSelected(int index) {
    if (_isAnswered) return;

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
      setState(() {
        _isFinished = true;
      });
    }
  }

  void _restartQuiz() {
    setState(() {
      _prepareQuiz();
      _currentIndex = 0;
      _selectedOption = null;
      _isAnswered = false;
      _score = 0;
      _isFinished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tourGroup != null && _quiz.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1A1C),
        appBar: AppBar(
          title: Text(context.l10n.translate('tq_title')),
          backgroundColor: const Color(0xFF142428),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.translate('tq_not_ready'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    if (_quiz.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1A1C),
        body:
            Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text(context.l10n.translate('tq_title_master'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isFinished ? _buildResultView() : _buildQuizView(),
      ),
    );
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
                    fontSize: 13),
              ),
              Text(
                context.l10n.translate('tq_score', args: {'score': _score}),
                style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
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
          const SizedBox(height: 20),

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
                    color: Colors.black38, blurRadius: 8, offset: Offset(0, 4)),
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
                      Text(context.l10n.translate('tq_explanation_heading'),
                          style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q.explanation,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.4),
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
                    borderRadius: BorderRadius.circular(14)),
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

  Widget _buildOptionButton(QuizQuestion q, int index) {
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
                        fontSize: 12),
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
                      fontWeight: FontWeight.w500),
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
    final pct = (_score / _quiz.length) * 100;
    final dest =
        _tourGroup?.destination ?? context.l10n.translate('tq_default_tour');
    String badge = context.l10n.translate('tq_badge_learner');
    if (pct >= 85) {
      badge = context.l10n.translate('tq_badge_expert', args: {'dest': dest});
    } else if (pct >= 60) {
      badge = context.l10n.translate('tq_badge_skilled');
    }

    return Center(
      child: Padding(
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
              style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.translate('tq_result_summary',
                  args: {'score': _score, 'total': _quiz.length}),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.replay),
              label: Text(context.l10n.translate('tq_play_again'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _restartQuiz,
            ),
          ],
        ),
      ),
    );
  }
}

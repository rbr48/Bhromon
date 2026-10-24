import 'package:flutter/material.dart';

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
  int _currentIndex = 0;
  int? _selectedOption;
  bool _isAnswered = false;
  int _score = 0;
  bool _isFinished = false;

  static const List<QuizQuestion> questions = [
    QuizQuestion(
      id: 1,
      question: 'কক্সবাজার সমুদ্র সৈকত পৃথিবীর কততম দীর্ঘতম প্রাকৃতিক অবিচ্ছিন্ন বালুকাময় সৈকত?',
      options: ['প্রথম (১ম)', 'দ্বিতীয় (২য়)', 'তৃতীয় (৩য়)', 'পঞ্চম (৫ম)'],
      correctIndex: 0,
      explanation: 'কক্সবাজার সমুদ্র সৈকত প্রায় ১২০ কিলোমিটার দীর্ঘ এবং এটি পৃথিবীর দীর্ঘতম প্রাকৃতিক অবিচ্ছিন্ন বালুকাময় সমুদ্র সৈকত!',
    ),
    QuizQuestion(
      id: 2,
      question: 'রংপুর থেকে কক্সবাজারের দূরত্ব জাতীয় মহাসড়ক পথে আনুমানিক কত কিলোমিটার?',
      options: ['৫৫০ কি.মি.', '৬৮০ কি.মি.', '৭৮০ - ৮২০ কি.মি.', '৯৫০ কি.মি.'],
      correctIndex: 2,
      explanation: 'রংপুর থেকে ঢাকা হয়ে কক্সবাজারের মোট দূরত্ব প্রায় ৭৮০-৮২০ কিলোমিটার, যা এভারগ্রীন বাসে অতিক্রম করা হয়।',
    ),
    QuizQuestion(
      id: 3,
      question: 'ইনানী বিচের প্রধান ও বিশেষ বৈশিষ্ট্য কী?',
      options: ['লাল কাঁকড়া', 'প্রবাল ও প্রবাল পাথর (Coral Rocks)', 'গভীর খাল', 'ম্যানগ্রোভ বন'],
      correctIndex: 1,
      explanation: 'ইনানী সৈকত তার শান্ত পরিবেশ এবং প্রাকৃতিকভাবে গড়ে ওঠা প্রবাল পাথরের জন্য বিখ্যাত।',
    ),
    QuizQuestion(
      id: 4,
      question: 'সমুদ্র সৈকতে কখন গোসল করা সবচেয়ে বিপজ্জনক?',
      options: ['জোয়ারের সময়', 'ভাটার সময় (Low Tide)', 'সকালের শান্ত বাতাসে', 'দুপুরের রোদে'],
      correctIndex: 1,
      explanation: 'ভাটার সময় পানির টান বা রিপ কারেন্ট সমুদ্রের গভীরে টেনে নেয়, তাই ভাটার সময় গভীর সমুদ্রে নামা অত্যন্ত বিপজ্জনক।',
    ),
    QuizQuestion(
      id: 5,
      question: 'বাংলাদেশের একমাত্র পাহাড়ি দ্বীপ কোনটি?',
      options: ['সেন্টমার্টিন', 'মহেশখালী', 'ছেঁড়াদ্বীপ', 'হাতিয়া'],
      correctIndex: 1,
      explanation: 'মহেশখালী বাংলাদেশের একমাত্র পাহাড়ি দ্বীপ, যেখানে বিখ্যাত আদিনাথ মন্দির ও পানের বরজ রয়েছে।',
    ),
    QuizQuestion(
      id: 6,
      question: 'হিমছড়ি পাহাড়ে কোন প্রাকৃতিক সৌন্দর্য দেখার মতো?',
      options: ['পাহাড়ি ঝর্ণা ও সমুদ্রের ভিউ', 'আইসবর্গ', 'চা বাগান', 'হরিণ প্রজনন কেন্দ্র'],
      correctIndex: 0,
      explanation: 'হিমছড়িতে রয়েছে শীতল পাহাড়ি ঝর্ণা এবং পাহাড়ের চূড়া থেকে বঙ্গোপসাগরের দিগন্ত বিস্তৃত রূপ।',
    ),
    QuizQuestion(
      id: 7,
      question: 'মেরিন ড্রাইভ রোড কোন দুটি স্থানকে সরাসরি সংযুক্ত করেছে?',
      options: ['কক্সবাজার থেকে টেকনাফ', 'কক্সবাজার থেকে চট্টগ্রাম', 'কক্সবাজার থেকে বান্দরবান', 'কক্সবাজার থেকে রাঙ্গামাটি'],
      correctIndex: 0,
      explanation: '৮০ কি.মি. দীর্ঘ মেরিন ড্রাইভ রোড কক্সবাজার কলাতলী থেকে টেকনাফ পর্যন্ত বিস্তৃত, যার একপাশে পাহাড় ও অন্যপাশে সমুদ্র।',
    ),
    QuizQuestion(
      id: 8,
      question: 'বার্মিজ মার্কেটের সবচেয়ে জনপ্রিয় কেনাকাটার আইটেম কোনটি?',
      options: ['বার্মিজ আচার, চকোলেট ও স্যান্ডেল', 'মোবাইল ফোন', 'ল্যাপটপ', 'মাটির হাড়ি'],
      correctIndex: 0,
      explanation: 'বার্মিজ আচার, চকোলেট, স্যান্ডেল, থামি এবং কাঠের হস্তশিল্প পর্যটকদের প্রধান আকর্ষণ।',
    ),
  ];

  void _onOptionSelected(int index) {
    if (_isAnswered) return;

    setState(() {
      _selectedOption = index;
      _isAnswered = true;
      if (index == questions[_currentIndex].correctIndex) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex + 1 < questions.length) {
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
      _currentIndex = 0;
      _selectedOption = null;
      _isAnswered = false;
      _score = 0;
      _isFinished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: const Text('Tour Quiz (ট্যুর কুইজ ও কুইজ মাস্টার)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    final q = questions[_currentIndex];
    final progress = (_currentIndex + 1) / questions.length;

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
                'প্রশ্ন নং ${_currentIndex + 1} / ${questions.length}',
                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'স্কোর: $_score',
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
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
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
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
                BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4)),
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
                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber, size: 16),
                      SizedBox(width: 6),
                      Text('ব্যাখ্যা ও তথ্য', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q.explanation,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _nextQuestion,
              child: Text(
                _currentIndex + 1 < questions.length ? 'পরবর্তী প্রশ্ন' : 'ফলাফল দেখুন',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  q.options[index],
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              if (_isAnswered)
                Icon(
                  index == q.correctIndex ? Icons.check_circle : (index == _selectedOption ? Icons.cancel : null),
                  color: index == q.correctIndex ? Colors.greenAccent : Colors.redAccent,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultView() {
    final pct = (_score / questions.length) * 100;
    String badge = 'পর্যটক শিক্ষার্থী';
    if (pct >= 85) {
      badge = '👑 কক্সবাজার ট্যুর এক্সপার্ট';
    } else if (pct >= 60) {
      badge = '🌟 চৌকস ভ্রমণকারী';
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
              child: const Icon(Icons.emoji_events, color: Colors.amber, size: 72),
            ),
            const SizedBox(height: 20),
            Text(
              badge,
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'আপনি $_score / ${questions.length} প্রশ্নের সঠিক উত্তর দিয়েছেন!',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text('আবার খেলুন', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _restartQuiz,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';

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
  int _currentIndex = 0;
  int? _selectedOption;
  bool _isAnswered = false;
  int _score = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) setState(() => _tourGroup = g);
  }

  List<QuizQuestion> get questions {
    final dest = _tourGroup?.destination.toLowerCase() ?? 'cox';

    if (dest.contains('sajek') || dest.contains('সাজেক')) {
      return const [
        QuizQuestion(
          id: 1,
          question: 'সাজেক ভ্যালি বাংলাদেশের কোন জেলায় অবস্থিত?',
          options: ['রাঙ্গামাটি', 'খাগড়াছড়ি', 'বান্দরবান', 'কক্সবাজার'],
          correctIndex: 0,
          explanation: 'ভৌগোলিকভাবে সাজেক রাঙ্গামাটি জেলার বাঘাইছড়ি উপজেলায় অবস্থিত, তবে যাতায়াত করতে হয় খাগড়াছড়ি দিয়ে।',
        ),
        QuizQuestion(
          id: 2,
          question: 'সাজেক ভ্যালির সর্বোচ্চ পাহাড় চূড়া কোনটি?',
          options: ['কংলাক পাহাড় (Konglak Peak)', 'রুইলুই পাড়া', 'হ্যালিপ্যাড', 'তাজিংডং'],
          correctIndex: 0,
          explanation: 'কংলাক পাহাড় চূড়া সাজেকের সর্বোচ্চ বিন্দু, যেখান থেকে চারপাশের মেঘ ও ভারতের মিজোরাম সীমান্ত দেখা যায়।',
        ),
        QuizQuestion(
          id: 3,
          question: 'সাজেকে যাতায়াতের জন্য প্রধান ও রোমাঞ্চকর বাহন কোনটি?',
          options: ['খোলা চাঁদের গাড়ি (Chander Gari)', 'সিএনজি অটোরিকশা', 'লঞ্চ', 'ট্রেন'],
          correctIndex: 0,
          explanation: 'পাহাড়ি উঁচু-নিচু আঁকাবাঁকা পথে ৪-হুইল ড্রাইভ চাঁদের গাড়িই সাজেক ভ্রমণের প্রধান রোমাঞ্চ।',
        ),
        QuizQuestion(
          id: 4,
          question: 'সাজেকে প্রবেশের জন্য সেনাবাহিনীর এসকর্ট কোথা থেকে শুরু হয়?',
          options: ['দীঘিনালা সেনা ক্যাম্প', 'আলুটিলা', 'মাইজভাণ্ডার', 'মানিকছড়ি'],
          correctIndex: 0,
          explanation: 'নিরাপত্তার স্বার্থে দীঘিনালা থেকে প্রতিদিন সকাল ও দুপুরে সেনাবাহিনীর কনভয় এসকর্ট দিয়ে সাজেক নেওয়া হয়।',
        ),
        QuizQuestion(
          id: 5,
          question: 'সাজেকে সবচেয়ে বিখ্যাত আকর্ষণ কী?',
          options: ['মেঘের সমুদ্র ও মেঘ ছোঁয়া (Sea of Clouds)', 'সমুদ্রের ঢেউ', 'চা বাগান', 'হরিণ প্রজনন'],
          correctIndex: 0,
          explanation: 'ভোরে কটেজের বারান্দা বা হ্যালিপ্যাডে দাঁড়ালে পায়ের নিচে তুলোর মতো ভাসমান মেঘের সমুদ্র দেখা যায়।',
        ),
      ];
    } else if (dest.contains('sylhet') || dest.contains('সিলেট')) {
      return const [
        QuizQuestion(
          id: 1,
          question: 'বাংলাদেশের একমাত্র স্বীকৃত মিঠাপানির জলাবন (Swamp Forest) কোনটি?',
          options: ['রাতারগুল সোয়াম্প ফরেস্ট', 'সুন্দরবন', 'লাউয়াছড়া', 'রেমা-কালেঙ্গা'],
          correctIndex: 0,
          explanation: 'সিলেটের গোয়াইনঘাটে অবস্থিত রাতারগুল হলো মিঠাপানির এক অনন্য ও নৈসর্গিক জলাবন।',
        ),
        QuizQuestion(
          id: 2,
          question: 'ভোলাগঞ্জ সাদা পাথর পয়েন্টে কোন নদী বয়ে চলেছে?',
          options: ['ধলাই নদী (Dhalai)', 'পদ্মা', 'সুরমা', 'কর্ণফুলী'],
          correctIndex: 0,
          explanation: 'মেঘালয় পাহাড় থেকে নেমে আসা স্বচ্ছ শীতল ধলাই নদীর বুকে সাদা পাথরের রাজ্য গড়ে উঠেছে।',
        ),
        QuizQuestion(
          id: 3,
          question: 'সিলেটের ঐতিহ্যবাহী রান্নায় কোন বিশেষ সাইট্রাস ফল ব্যবহার করা হয়?',
          options: ['সাতকড়া (Satkara)', 'আমলকী', 'বাতাবি লেবু', 'কামরাঙা'],
          correctIndex: 0,
          explanation: 'সিলেটের ঐতিহ্যবাহী গরুর মাংস বা মাছে সুগন্ধি সাতকড়া লেবু দিয়ে রান্না করা হয়।',
        ),
        QuizQuestion(
          id: 4,
          question: 'শ্রীমঙ্গলের বিখ্যাত চায়ের বিশেষত্ব কী?',
          options: ['নীলকণ্ঠের ৭ স্তরের সাত রঙের চা', 'আইস টি', 'গ্রিন টি ল্যাটে', 'লেমন গ্রাস টি'],
          correctIndex: 0,
          explanation: 'রমেশ রাম গৌড়ের আবিষ্কৃত এক গ্লাসে ৭ স্তরের বিভিন্ন ঘনত্বের চা দেশজুড়ে বিখ্যাত।',
        ),
      ];
    } else {
      // Default: Cox's Bazar / Universal
      return const [
        QuizQuestion(
          id: 1,
          question: 'কক্সবাজার সমুদ্র সৈকত পৃথিবীর কততম দীর্ঘতম প্রাকৃতিক অবিচ্ছিন্ন বালুকাময় সৈকত?',
          options: ['প্রথম (১ম)', 'দ্বিতীয় (২য়)', 'তৃতীয় (৩য়)', 'পঞ্চম (৫ম)'],
          correctIndex: 0,
          explanation: 'কক্সবাজার সমুদ্র সৈকত প্রায় ১২০ কিলোমিটার দীর্ঘ এবং এটি পৃথিবীর দীর্ঘতম প্রাকৃতিক অবিচ্ছিন্ন বালুকাময় সমুদ্র সৈকত!',
        ),
        QuizQuestion(
          id: 2,
          question: 'ইনানী বিচের প্রধান ও বিশেষ বৈশিষ্ট্য কী?',
          options: ['লাল কাঁকড়া', 'প্রবাল ও প্রবাল পাথর (Coral Rocks)', 'গভীর খাল', 'ম্যানগ্রোভ বন'],
          correctIndex: 1,
          explanation: 'ইনানী সৈকত তার শান্ত পরিবেশ এবং প্রাকৃতিকভাবে গড়ে ওঠা প্রবাল পাথরের জন্য বিখ্যাত।',
        ),
        QuizQuestion(
          id: 3,
          question: 'সমুদ্র সৈকতে কখন গোসল করা সবচেয়ে বিপজ্জনক?',
          options: ['জোয়ারের সময়', 'ভাটার সময় (Low Tide)', 'সকালের শান্ত বাতাসে', 'দুপুরের রোদে'],
          correctIndex: 1,
          explanation: 'ভাটার সময় পানির টান বা রিপ কারেন্ট সমুদ্রের গভীরে টেনে নেয়, তাই ভাটার সময় গভীর সমুদ্রে নামা অত্যন্ত বিপজ্জনক।',
        ),
        QuizQuestion(
          id: 4,
          question: 'বাংলাদেশের একমাত্র পাহাড়ি দ্বীপ কোনটি?',
          options: ['সেন্টমার্টিন', 'মহেশখালী', 'ছেঁড়াদ্বীপ', 'হাতিয়া'],
          correctIndex: 1,
          explanation: 'মহেশখালী বাংলাদেশের একমাত্র পাহাড়ি দ্বীপ, যেখানে বিখ্যাত আদিনাথ মন্দির ও পানের বরজ রয়েছে।',
        ),
        QuizQuestion(
          id: 5,
          question: 'মেরিন ড্রাইভ রোড কোন দুটি স্থানকে সরাসরি সংযুক্ত করেছে?',
          options: ['কক্সবাজার থেকে টেকনাফ', 'কক্সবাজার থেকে চট্টগ্রাম', 'কক্সবাজার থেকে বান্দরবান', 'কক্সবাজার থেকে রাঙ্গামাটি'],
          correctIndex: 0,
          explanation: '৮০ কি.মি. দীর্ঘ মেরিন ড্রাইভ রোড কক্সবাজার কলাতলী থেকে টেকনাফ পর্যন্ত বিস্তৃত, যার একপাশে পাহাড় ও অন্যপাশে সমুদ্র।',
        ),
      ];
    }
  }

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
    final dest = _tourGroup?.destination ?? 'ট্যুর';
    String badge = 'পর্যটক শিক্ষার্থী';
    if (pct >= 85) {
      badge = '👑 $dest এক্সপার্ট';
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

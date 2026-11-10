import 'package:flutter/foundation.dart';

/// An official IBB JAIBB syllabus module (e.g. Module A, Module B).
@immutable
class SyllabusModule {
  final String id;
  final String code; // 'A', 'B', 'C', 'D', 'E'
  final String title;
  final String titleBn;
  final String description;
  final List<String> keywords;

  const SyllabusModule({
    required this.id,
    required this.code,
    required this.title,
    required this.titleBn,
    this.description = '',
    required this.keywords,
  });

  /// Checks if given text matches any keywords belonging to this module
  /// with boundary awareness to prevent false-positive partial substring matches.
  bool matches(String text) {
    if (text.isEmpty) return false;
    for (final kw in keywords) {
      if (kw.isEmpty) continue;
      final escaped = RegExp.escape(kw);
      final pattern = RegExp(
        "(^|[\\s,;:.?!()\\[\\]\\-/\"'])$escaped([\\s,;:.?!()\\[\\]\\-/\"']|\$)",
        caseSensitive: false,
      );
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }
}

/// Catalog defining official IBB JAIBB syllabus modules and deterministic
/// keyword associations for all banking subjects.
class StudySyllabusCatalog {
  const StudySyllabusCatalog._();

  static const Map<String, List<SyllabusModule>> _modules = {
    'LPGB': [
      SyllabusModule(
        id: 'lpgb_mod_a',
        code: 'A',
        title: 'Legal & Regulatory Framework',
        titleBn: 'আইনি ও নিয়ন্ত্রণমূলক কাঠামো',
        description: 'Bank Company Act 1991, BB Order 1972, NI Act 1881',
        keywords: [
          'bank company act',
          'bangladesh bank order',
          'bangladesh bank',
          'central bank',
          'negotiable instruments',
          'বাংলাদেশ ব্যাংক',
          'কেন্দ্রীয় ব্যাংক',
          'ব্যাংক কোম্পানি',
          'বাংলাদেশ ব্যাংক অর্ডার',
          'হস্তান্তরযোগ্য দলিল',
          'নিয়ন্ত্রণমূলক',
          'আইন',
          'section 131',
          'section 45',
          'ধারা',
          'ব্যাংকিং কোম্পানি',
        ],
      ),
      SyllabusModule(
        id: 'lpgb_mod_b',
        code: 'B',
        title: 'Banker-Customer Relationship & Deposits',
        titleBn: 'ব্যাংকার-গ্রাহক সম্পর্ক ও আমানত হিসাব',
        description: 'KYC, CDD, Account operations, Rights & duties',
        keywords: [
          'banker-customer',
          'banker customer',
          'deposit',
          'kyc',
          'cdd',
          'mandate',
          'power of attorney',
          'garnishee',
          'ব্যাংকার ও গ্রাহক',
          'আমানত',
          'হিসাব খোলা',
          'কেওয়াইসি',
          'গার্নিশি অর্ডার',
        ],
      ),
      SyllabusModule(
        id: 'lpgb_mod_c',
        code: 'C',
        title: 'Cheques, Payment Systems & Clearing',
        titleBn: 'চেক, পেমেন্ট সিস্টেম ও ক্লিয়ারিং',
        description: 'Crossing, Endorsement, Dishonour, NPSB, BEFTN, RTGS',
        keywords: [
          'cheque',
          'crossing',
          'endorsement',
          'dishonour',
          'clearing',
          'beftn',
          'rtgs',
          'npsb',
          'চেক',
          'ক্রসিং',
          'পৃষ্ঠাঙ্কন',
          'প্রত্যাখ্যান',
          'পেমেন্ট সিস্টেম',
          'বাচনিক নির্দেশ',
        ],
      ),
      SyllabusModule(
        id: 'lpgb_mod_d',
        code: 'D',
        title: 'Loans, Advances & Security Recovery',
        titleBn: 'ঋণ, অগ্রিম ও জামানত আদায় আইন',
        description: 'Classification, Mortgage, Pledge, Artha Rin Adalat Act',
        keywords: [
          'loan',
          'advance',
          'credit',
          'mortgage',
          'pledge',
          'hypothecation',
          'classification',
          'npl',
          'artha rin',
          'ঋণ',
          'অগ্রিম',
          'বন্ধক',
          'খেলাপি',
          'অর্থ ঋণ আদালত',
          'জামানত',
          'হাইপোথিকেশন',
        ],
      ),
      SyllabusModule(
        id: 'lpgb_mod_e',
        code: 'E',
        title: 'Foreign Exchange & Trade Services',
        titleBn: 'বৈদেশিক বিনিময় ও বাণিজ্য সেবা',
        description: 'Letter of Credit, Incoterms, UCP 600, Remittance',
        keywords: [
          'foreign exchange',
          'letter of credit',
          'l/c',
          'ucp 600',
          'incoterms',
          'remittance',
          'import',
          'export',
          'বৈদেশিক বিনিময়',
          'লেটার অব ক্রেডিট',
          'এলসি',
          'রপ্তানি',
          'আমদানি',
          'রেমিট্যান্স',
          'ইউসিপি',
        ],
      ),
    ],
    'POE': [
      SyllabusModule(
        id: 'poe_mod_a',
        code: 'A',
        title: 'Microeconomics & Market Mechanisms',
        titleBn: 'ব্যষ্টিক অর্থনীতি ও বাজার প্রক্রিয়া',
        description: 'Demand, Supply, Elasticity, Consumer Behavior',
        keywords: [
          'demand',
          'supply',
          'elasticity',
          'utility',
          'consumer',
          'monopoly',
          'চাহিদা',
          'যোগান',
          'স্থিতিস্থাপকতা',
          'উপযোগ',
          'বাজার',
          'একচেটিয়া',
        ],
      ),
      SyllabusModule(
        id: 'poe_mod_b',
        code: 'B',
        title: 'Macroeconomics & National Income',
        titleBn: 'সামষ্টিক অর্থনীতি ও জাতীয় আয়',
        description: 'GDP, GNP, Inflation, Unemployment, Fiscal Policy',
        keywords: [
          'macroeconomic',
          'national income',
          'gdp',
          'gnp',
          'inflation',
          'unemployment',
          'fiscal policy',
          'জাতীয় আয়',
          'জিডিপি',
          'মুদ্রাস্ফীতি',
          'বেকারত্ব',
          'রাজস্ব নীতি',
        ],
      ),
      SyllabusModule(
        id: 'poe_mod_c',
        code: 'C',
        title: 'Monetary Economics & Central Banking',
        titleBn: 'আর্থিক অর্থনীতি ও কেন্দ্রীয় ব্যাংকিং',
        description:
            'Money supply, Monetary policy, Interest rate transmission',
        keywords: [
          'money supply',
          'monetary policy',
          'central bank',
          'interest rate',
          'liquidity preference',
          'মুদ্রা সরবরাহ',
          'আর্থিক নীতি',
          'কেন্দ্রীয় ব্যাংক',
          'সুদের হার',
        ],
      ),
      SyllabusModule(
        id: 'poe_mod_d',
        code: 'D',
        title: 'International Trade & Exchange Rates',
        titleBn: 'আন্তর্জাতিক বাণিজ্য ও বিনিময় হার',
        description: 'Comparative advantage, BoP, Exchange rate systems',
        keywords: [
          'international trade',
          'comparative advantage',
          'balance of payments',
          'bop',
          'exchange rate',
          'আন্তর্জাতিক বাণিজ্য',
          'লেনদেন ভারসাম্য',
          'বিনিময় হার',
          'ট্যারিফ',
        ],
      ),
      SyllabusModule(
        id: 'poe_mod_e',
        code: 'E',
        title: 'Bangladesh Economy & Development',
        titleBn: 'বাংলাদেশ অর্থনীতি ও উন্নয়ন ভাবনা',
        description: 'Five-year plans, Financial inclusion, SDGs, Poverty',
        keywords: [
          'bangladesh economy',
          'development planning',
          'financial inclusion',
          'sdg',
          'poverty',
          'বাংলাদেশ অর্থনীতি',
          'উন্নয়ন পরিকল্পনা',
          'আর্থিক অন্তর্ভুক্তি',
          'দারিদ্র্য বিমোচন',
        ],
      ),
    ],
    'MAFS': [
      SyllabusModule(
        id: 'mafs_mod_a',
        code: 'A',
        title: 'Structure of Financial System',
        titleBn: 'আর্থিক ব্যবস্থার কাঠামো',
        description: 'Financial institutions, Financial markets & instruments',
        keywords: [
          'financial system',
          'financial market',
          'financial institution',
          'financial instrument',
          'আর্থিক ব্যবস্থা',
          'আর্থিক বাজার',
          'আর্থিক প্রতিষ্ঠান',
        ],
      ),
      SyllabusModule(
        id: 'mafs_mod_b',
        code: 'B',
        title: 'Money & Capital Markets',
        titleBn: 'মুদ্রা ও পুঁজিবাজার',
        description: 'Treasury bills, Call money, BSEC, Stock exchanges',
        keywords: [
          'money market',
          'capital market',
          'treasury bill',
          'call money',
          'bsec',
          'stock exchange',
          'মুদ্রাবাজার',
          'পুঁজিবাজার',
          'ট্রেজারি বিল',
          'কল মানি',
          'শেয়ার বাজার',
        ],
      ),
      SyllabusModule(
        id: 'mafs_mod_c',
        code: 'C',
        title: 'Central Banking & Monetary Operations',
        titleBn: 'কেন্দ্রীয় ব্যাংক ও আর্থিক পরিচালনা',
        description:
            'Bangladesh Bank policy tools, CRR, SLR, Repo, Reverse Repo',
        keywords: [
          'crr',
          'slr',
          'repo',
          'reverse repo',
          'monetary management',
          'liquidity',
          'সিআরআর',
          'এসএলআর',
          'রেপো',
          'তারল্য',
          'কেন্দ্রীয় ব্যাংকিং',
        ],
      ),
      SyllabusModule(
        id: 'mafs_mod_d',
        code: 'D',
        title: 'NBFIs & Microfinance Institutions',
        titleBn: 'অ-ব্যাংক আর্থিক প্রতিষ্ঠান ও ক্ষুদ্রঋণ',
        description: 'Leasing companies, MRA, Microcredit, Insurance',
        keywords: [
          'nbfi',
          'non-bank',
          'microfinance',
          'mra',
          'insurance',
          'এনবিএফআই',
          'অ-ব্যাংক',
          'ক্ষুদ্রঋণ',
          'এমআরএ',
          'বীমা',
        ],
      ),
      SyllabusModule(
        id: 'mafs_mod_e',
        code: 'E',
        title: 'Financial Sector Reforms & Global Standards',
        titleBn: 'আর্থিক খাতের সংস্কার ও বৈশ্বিক মানদণ্ড',
        description: 'Basel II/III, IMF, World Bank, Prudential regulations',
        keywords: [
          'basel',
          'reform',
          'capital adequacy',
          'imf',
          'world bank',
          'prudential',
          'ব্যাসেল',
          'মূলধন পর্যাপ্ততা',
          'সংস্কার',
          'আইএমএফ',
        ],
      ),
    ],
    'GFI': [
      SyllabusModule(
        id: 'gfi_mod_a',
        code: 'A',
        title: 'Corporate Governance Foundations',
        titleBn: 'কর্পোরেট গভর্নেন্সের মূলনীতি',
        description: 'Agency theory, Stakeholder theory, OECD principles',
        keywords: [
          'corporate governance',
          'agency theory',
          'stakeholder',
          'oecd',
          'কর্পোরেট গভর্নেন্স',
          'এজেন্সি তত্ত্ব',
          'মূলনীতি',
        ],
      ),
      SyllabusModule(
        id: 'gfi_mod_b',
        code: 'B',
        title: 'Board of Directors & Leadership',
        titleBn: 'পরিচালনা পর্ষদ ও নেতৃত্ব',
        description: 'Independent directors, Board committees, Audit committee',
        keywords: [
          'board of directors',
          'independent director',
          'audit committee',
          'risk management committee',
          'পরিচালনা পর্ষদ',
          'স্বতন্ত্র পরিচালক',
          'অডিট কমিটি',
        ],
      ),
      SyllabusModule(
        id: 'gfi_mod_c',
        code: 'C',
        title: 'Risk Governance & Internal Control',
        titleBn: 'ঝুঁকি ব্যবস্থাপনা ও অভ্যন্তরীণ নিয়ন্ত্রণ',
        description: 'Three lines of defense, Internal audit, Compliance',
        keywords: [
          'risk governance',
          'internal control',
          'internal audit',
          'compliance',
          'three lines',
          'ঝুঁকি ব্যবস্থাপনা',
          'অভ্যন্তরীণ নিয়ন্ত্রণ',
          'কমপ্লায়েন্স',
        ],
      ),
      SyllabusModule(
        id: 'gfi_mod_d',
        code: 'D',
        title: 'Ethics, Transparency & Disclosures',
        titleBn: 'নৈতিকতা, স্বচ্ছতা ও প্রকাশনা',
        description: 'Code of ethics, Whistleblowing, Conflict of interest',
        keywords: [
          'ethics',
          'transparency',
          'disclosure',
          'whistleblower',
          'conflict of interest',
          'নৈতিকতা',
          'স্বচ্ছতা',
          'হুইসেলব্লোয়ার',
          'স্বার্থের দ্বন্দ্ব',
        ],
      ),
      SyllabusModule(
        id: 'gfi_mod_e',
        code: 'E',
        title: 'Regulatory Corporate Governance Guidelines',
        titleBn: 'নিয়ন্ত্রণমূলক কর্পোরেট গভর্নেন্স নির্দেশিকা',
        description: 'BB CG circulars, BSEC CG Code, Accountability',
        keywords: [
          'guidelines',
          'circular',
          'bsec code',
          'bb circular',
          'accountability',
          'নির্দেশিকা',
          'সার্কুলার',
          'দায়বদ্ধতা',
        ],
      ),
    ],
    'OM': [
      SyllabusModule(
        id: 'om_mod_a',
        code: 'A',
        title: 'Management Concepts & Evolution',
        titleBn: 'ব্যবস্থাপনার ধারণা ও বিবর্তন',
        description: 'Classical, Behavioral, Modern management schools',
        keywords: [
          'management',
          'evolution',
          'taylor',
          'fayol',
          'scientific management',
          'ব্যবস্থাপনা',
          'টেইলর',
          'ফায়ল',
          'বৈজ্ঞানিক ব্যবস্থাপনা',
        ],
      ),
      SyllabusModule(
        id: 'om_mod_b',
        code: 'B',
        title: 'Planning & Strategic Decision Making',
        titleBn: 'পরিকল্পনা ও কৌশলগত সিদ্ধান্ত গ্রহণ',
        description: 'SWOT analysis, Decision making process, MBO',
        keywords: [
          'planning',
          'strategic',
          'swot',
          'decision making',
          'mbo',
          'পরিকল্পনা',
          'কৌশলগত',
          'সিদ্ধান্ত গ্রহণ',
          'সট বিশ্লেষণ',
        ],
      ),
      SyllabusModule(
        id: 'om_mod_c',
        code: 'C',
        title: 'Organizing & Structure',
        titleBn: 'সংগঠিতকরণ ও প্রাতিষ্ঠানিক কাঠামো',
        description: 'Delegation, Span of control, Departmentation',
        keywords: [
          'organizing',
          'structure',
          'delegation',
          'span of control',
          'decentralization',
          'সংগঠিতকরণ',
          'ক্ষমতাপ্রদান',
          'নিয়ন্ত্রণ পরিসর',
          'বিকেন্দ্রীকরণ',
        ],
      ),
      SyllabusModule(
        id: 'om_mod_d',
        code: 'D',
        title: 'Leadership & Motivation',
        titleBn: 'নেতৃত্ব ও প্রেষণা',
        description: 'Maslow, Herzberg, Transformational leadership',
        keywords: [
          'leadership',
          'motivation',
          'maslow',
          'herzberg',
          'transformational',
          'নেতৃত্ব',
          'প্রেষণা',
          'ম্যাসলো',
          'হার্জবার্গ',
        ],
      ),
      SyllabusModule(
        id: 'om_mod_e',
        code: 'E',
        title: 'Controlling & Change Management',
        titleBn: 'নিয়ন্ত্রণ ও পরিবর্তন ব্যবস্থাপনা',
        description: 'Control techniques, KPI, Resistance to change',
        keywords: [
          'controlling',
          'kpi',
          'change management',
          'conflict',
          'performance',
          'নিয়ন্ত্রণ',
          'পরিবর্তন ব্যবস্থাপনা',
          'দ্বন্দ',
          'পারফরম্যান্স',
        ],
      ),
    ],
    'BCFI': [
      SyllabusModule(
        id: 'bcfi_mod_a',
        code: 'A',
        title: 'Fundamentals of Communication',
        titleBn: 'যোগাযোগের মৌলিক নীতি',
        description: 'Communication process, Barriers, 7 Cs of communication',
        keywords: [
          'communication process',
          'barriers',
          '7 cs',
          'seven cs',
          'যোগাযোগ প্রক্রিয়া',
          'প্রতিবন্ধকতা',
          '৭ সি',
        ],
      ),
      SyllabusModule(
        id: 'bcfi_mod_b',
        code: 'B',
        title: 'Written Business Communication',
        titleBn: 'ব্যবসায়িক লিখিত যোগাযোগ',
        description: 'Business letters, Memos, Circulars, Office orders',
        keywords: [
          'letter',
          'memo',
          'circular',
          'notice',
          'minutes',
          'agenda',
          'চিঠি',
          'মেমো',
          'সার্কুলার',
          'কার্যবিবরণী',
          'বিজ্ঞপ্তি',
        ],
      ),
      SyllabusModule(
        id: 'bcfi_mod_c',
        code: 'C',
        title: 'Report Writing & Credit Proposals',
        titleBn: 'প্রতিবেদন লিখন ও ঋণ প্রস্তাব',
        description: 'Audit report, Inspection report, Credit memo',
        keywords: [
          'report writing',
          'credit proposal',
          'audit report',
          'inspection report',
          'প্রতিবেদন লিখন',
          'ঋণ প্রস্তাব',
          'অডিট রিপোর্ট',
        ],
      ),
      SyllabusModule(
        id: 'bcfi_mod_d',
        code: 'D',
        title: 'Oral & Interpersonal Communication',
        titleBn: 'মৌখিক ও আন্তঃব্যক্তিক যোগাযোগ',
        description: 'Presentation skills, Negotiation, Meetings, Viva voce',
        keywords: [
          'oral communication',
          'presentation',
          'negotiation',
          'meeting',
          'viva',
          'মৌখিক যোগাযোগ',
          'উপস্থাপনা',
          'নেগোসিয়েশন',
          'মিটিং',
          'ভাইভা',
        ],
      ),
      SyllabusModule(
        id: 'bcfi_mod_e',
        code: 'E',
        title: 'Digital Communication & Media',
        titleBn: 'ডিজিটাল যোগাযোগ ও মিডিয়া',
        description: 'Email etiquette, Electronic communication, Press release',
        keywords: [
          'digital communication',
          'email',
          'electronic',
          'press release',
          'social media',
          'ডিজিটাল যোগাযোগ',
          'ইমেইল',
          'প্রেস বিজ্ঞপ্তি',
        ],
      ),
    ],
    'BA': [
      SyllabusModule(
        id: 'ba_mod_a',
        code: 'A',
        title: 'Fundamentals of Accounting',
        titleBn: 'হিসাববিজ্ঞানের মৌলিক বিষয়াবলি',
        description: 'Accounting equation, Double entry, Journal, Ledger',
        keywords: [
          'accounting equation',
          'double entry',
          'journal',
          'ledger',
          'trial balance',
          'হিসাব সমীকরণ',
          'দুতরফা দাখিলা',
          'জাবেদা',
          'খতিয়ান',
          'রেওয়ামিল',
        ],
      ),
      SyllabusModule(
        id: 'ba_mod_b',
        code: 'B',
        title: 'Financial Statements Preparation',
        titleBn: 'আর্থিক বিবরণী প্রস্তুতকরণ',
        description: 'Income statement, Balance sheet, Cash flow statement',
        keywords: [
          'financial statement',
          'income statement',
          'balance sheet',
          'cash flow',
          'আর্থিক বিবরণী',
          'আয় বিবরণী',
          'উদ্বৃত্তপত্র',
          'নগদ প্রবাহ বিবরণী',
        ],
      ),
      SyllabusModule(
        id: 'ba_mod_c',
        code: 'C',
        title: 'Bank Accounting & Ratio Analysis',
        titleBn: 'ব্যাংক হিসাবরক্ষণ ও অনুপাত বিশ্লেষণ',
        description:
            'Branch accounting, Liquidity ratios, Profitability, CAMELS',
        keywords: [
          'bank accounting',
          'ratio analysis',
          'liquidity ratio',
          'camels',
          'profitability',
          'ব্যাংক হিসাবরক্ষণ',
          'অনুপাত বিশ্লেষণ',
          'তারল্য অনুপাত',
          'ক্যামেলস',
        ],
      ),
      SyllabusModule(
        id: 'ba_mod_d',
        code: 'D',
        title: 'Cost & Management Accounting',
        titleBn: 'ব্যয় ও ব্যবস্থাপনা হিসাববিজ্ঞান',
        description: 'CVP analysis, Break-even point, Budgetary control',
        keywords: [
          'cost accounting',
          'cvp',
          'break-even',
          'bep',
          'budget',
          'ব্যয় হিসাববিজ্ঞান',
          'ব্রেক-ইভেন',
          'সমচ্ছেদ বিন্দু',
          'বাজেট',
        ],
      ),
      SyllabusModule(
        id: 'ba_mod_e',
        code: 'E',
        title: 'Business Analytics in Banking',
        titleBn: 'ব্যাংকিংয়ে বিজনেস অ্যানালিটিক্স',
        description: 'Descriptive & predictive analytics, Data visualization',
        keywords: [
          'business analytics',
          'predictive analytics',
          'data visualization',
          'descriptive',
          'বিজনেস অ্যানালিটিক্স',
          'ডেটা অ্যানালাইসিস',
        ],
      ),
    ],
  };

  /// Returns official syllabus modules for a subject code or book title
  /// (e.g. 'LPGB', 'Laws & Practice of General Banking', 'Principles of Economics').
  static List<SyllabusModule> modulesFor(String subjectCodeOrTitle) {
    final key = subjectCodeOrTitle.toUpperCase();
    if (key.contains('LPGB') ||
        key.contains('GENERAL BANKING') ||
        key.contains('LAWS & PRACTICE') ||
        key.contains('ব্যাংকিং')) {
      return _modules['LPGB'] ?? const [];
    }
    if (key.contains('POE') ||
        key.contains('ECONOMICS') ||
        key.contains('অর্থনীতি')) {
      return _modules['POE'] ?? const [];
    }
    if (key.contains('MAFS') ||
        key.contains('MANAGEMENT ACCOUNTING') ||
        key.contains('ACCOUNTING') ||
        key.contains('হিসাববিজ্ঞান')) {
      return _modules['MAFS'] ?? const [];
    }
    if (key.contains('BCFI') ||
        key.contains('BUSINESS COMMUNICATION') ||
        key.contains('COMMUNICATION') ||
        key.contains('যোগাযোগ')) {
      return _modules['BCFI'] ?? const [];
    }
    if (key.contains('OM') ||
        key.contains('ORGANIZATION') ||
        key.contains('ORGANISATION') ||
        key.contains('সংগঠন')) {
      return _modules['OM'] ?? const [];
    }
    if (key.contains('GFI') ||
        key.contains('GOVERNANCE') ||
        key.contains('FINANCIAL INSTITUTIONS') ||
        key.contains('শাসন')) {
      return _modules['GFI'] ?? const [];
    }
    if (key == 'BA' ||
        key.startsWith('BA ') ||
        key.endsWith(' BA') ||
        key.contains(' BA ') ||
        key.contains('BUSINESS ANALYTICS') ||
        key.contains('BASIC ACCOUNTING') ||
        key.contains('ANALYTICS') ||
        key.contains('অ্যানালিটিক্স')) {
      return _modules['BA'] ?? const [];
    }
    for (final entry in _modules.entries) {
      if (key.contains(entry.key)) {
        return entry.value;
      }
    }
    // Return empty list if subject is not recognized as an IBB banking catalog entry.
    return const [];
  }

  /// Identifies the best matching syllabus module for a given question heading
  /// and content text using score-weighted, length-prioritized keyword matching.
  ///
  /// Tie-breaking is deterministic: in the event of equal cumulative match scores,
  /// the earliest module defined in the catalog order (`score > bestScore`) is preserved.
  static SyllabusModule? identifyModule(
      String subjectText, String questionText) {
    final list = modulesFor(subjectText);
    if (list.isEmpty || questionText.isEmpty) return null;
    SyllabusModule? bestModule;
    int bestScore = 0;

    for (final mod in list) {
      int score = 0;
      for (final kw in mod.keywords) {
        if (kw.isEmpty) continue;
        final escaped = RegExp.escape(kw);
        final pattern = RegExp(
          "(^|[\\s,;:.?!()\\[\\]\\-/\"'])$escaped([\\s,;:.?!()\\[\\]\\-/\"']|\$)",
          caseSensitive: false,
        );
        if (pattern.hasMatch(questionText)) {
          score += kw.length;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestModule = mod;
      }
    }
    return bestModule;
  }
}

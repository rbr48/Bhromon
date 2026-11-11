import '../models/study_subject_models.dart';

/// Represents a pre-packaged, examiner-grade post for JAIBB subject modules (Tips or Past Papers).
class StudyMasterPostDraft {
  const StudyMasterPostDraft({
    required this.title,
    required this.text,
    this.url = '',
  });

  final String title;
  final String text;
  final String url;
}

/// Represents a pre-packaged worked computational or legal problem with reference solution.
class StudyMasterProblemDraft {
  const StudyMasterProblemDraft({
    required this.title,
    required this.text,
    required this.solution,
  });

  final String title;
  final String text;
  final String solution;
}

/// Represents a high-yield glossary term with English and Bengali definitions.
class StudyMasterGlossaryDraft {
  const StudyMasterGlossaryDraft({
    required this.term,
    required this.definition,
  });

  final String term;
  final String definition;
}

/// Master catalog providing structured, examiner-grade preparation materials
/// for all 7 IBB JAIBB examination subjects.
class StudyBankingMasterCatalog {
  const StudyBankingMasterCatalog._();

  /// Supported JAIBB Subject Codes.
  static const String codeBA = 'BA';
  static const String codeLPGB = 'LPGB';
  static const String codePOE = 'POE';
  static const String codeMAFS = 'MAFS';
  static const String codeGFI = 'GFI';
  static const String codeOM = 'OM';
  static const String codeBCFI = 'BCFI';

  /// Supported AIBB Subject Codes.
  static const String codeRMFI = 'RMFI';
  static const String codeCOM = 'COM';
  static const String codeTFFE = 'TFFE';
  static const String codeICTFI = 'ICTFI';
  static const String codeTMFI = 'TMFI';
  static const String codeFCC = 'FCC';
  static const String codeAM = 'AM';
  static const String codeMBFS = 'MBFS';
  static const String codeSF = 'SF';
  static const String codeSBB = 'SBB';
  static const String codeIB = 'IB';
  static const String codeAFI = 'AFI';
  static const String codeMA = 'MA';

  static const List<String> jaibbSubjectCodes = [
    codeBA,
    codeLPGB,
    codePOE,
    codeMAFS,
    codeGFI,
    codeOM,
    codeBCFI,
  ];

  static const List<String> aibbSubjectCodes = [
    codeRMFI,
    codeCOM,
    codeTFFE,
    codeICTFI,
    codeGFI,
    codeTMFI,
    codeFCC,
    codeAM,
    codeMBFS,
    codeSF,
    codeSBB,
    codeIB,
    codeMA,
  ];

  static const List<String> allSubjectCodes = [
    codeBA,
    codeLPGB,
    codePOE,
    codeMAFS,
    codeGFI,
    codeOM,
    codeBCFI,
    codeRMFI,
    codeCOM,
    codeTFFE,
    codeICTFI,
    codeTMFI,
    codeFCC,
    codeAM,
    codeMBFS,
    codeSF,
    codeSBB,
    codeIB,
    codeAFI,
    codeMA,
  ];

  /// Resolves the JAIBB subject code ('BA', 'LPGB', 'POE', 'MAFS', 'GFI', 'OM', 'BCFI')
  /// from a [StudySubject] code or title. Returns null if not recognized as a banking subject.
  static String? resolveSubjectCode(StudySubject subject) {
    return resolveCodeFromText('${subject.code} ${subject.title}');
  }

  /// Resolves the subject code from raw text.
  static String? resolveCodeFromText(String raw) {
    final text = raw.toUpperCase().trim();
    if (text.isEmpty) return null;

    bool hasWord(String needle) {
      final pattern =
          RegExp('(^|[^A-Z0-9])$needle([^A-Z0-9]|\$)', caseSensitive: false);
      return pattern.hasMatch(text);
    }

    // AFI / Accounting for Financial Institutions was an AIBB subject up to 5th BPE,
    // and from 6th BPE was discontinued from AIBB and added to JAIBB under BA (Basic Accounting).
    // Therefore, any reference to AFI/206A resolves to codeBA in JAIBB.
    if (hasWord('AFI') ||
        hasWord('206A') ||
        text.contains('ACCOUNTING FOR FINANCIAL') ||
        text.contains('আর্থিক প্রতিষ্ঠানের হিসাববিজ্ঞান')) {
      return codeBA;
    }

    // MA / Management Accounting (check before MAFS)
    if (raw.trim().toUpperCase() == 'MA' ||
        raw.contains('(MA)') ||
        raw.contains('MA-208A') ||
        hasWord('208A') ||
        text.contains('MANAGEMENT ACCOUNTING') ||
        text.contains('ব্যবস্থাপনা হিসাববিজ্ঞান')) {
      return codeMA;
    }

    // RMFI / Risk Management in Financial Institutions
    if (hasWord('RMFI') ||
        hasWord('201') ||
        text.contains('RISK MANAGEMENT') ||
        text.contains('ঝুঁকি ব্যবস্থাপনা')) {
      return codeRMFI;
    }

    // COM / Credit Operations and Management
    if ((!text.contains('.COM') && hasWord('COM')) ||
        hasWord('202') ||
        text.contains('CREDIT OPERATIONS') ||
        text.contains('CREDIT MANAGEMENT') ||
        text.contains('ক্রেডিট অপারেশন') ||
        text.contains('ক্রেডিট ম্যানেজমেন্ট') ||
        text.contains('ঋণ ব্যবস্থাপনা')) {
      return codeCOM;
    }

    // TFFE / Trade Finance and Foreign Exchange
    if (hasWord('TFFE') ||
        hasWord('203') ||
        text.contains('TRADE FINANCE') ||
        text.contains('FOREIGN EXCHANGE') ||
        text.contains('ট্রেড ফাইন্যান্স') ||
        text.contains('বৈদেশিক বাণিজ্য') ||
        text.contains('বৈদেশিক মুদ্রা')) {
      return codeTFFE;
    }

    // ICTFI / Information & Communication Technology in Financial Institutions
    if (hasWord('ICTFI') ||
        hasWord('204') ||
        text.contains('ICT IN FINANCIAL') ||
        text.contains('ICTFI') ||
        text.contains('INFORMATION & COMMUNICATION') ||
        text.contains('INFORMATION AND COMMUNICATION') ||
        text.contains('আর্থিক প্রতিষ্ঠানে আইসিটি')) {
      return codeICTFI;
    }

    // TMFI / Treasury Management in Financial Institutions
    if (hasWord('TMFI') ||
        hasWord('206') ||
        text.contains('TREASURY MANAGEMENT') ||
        text.contains('TREASURY') ||
        text.contains('ট্রেজারি ম্যানেজমেন্ট') ||
        text.contains('ট্রেজারি')) {
      return codeTMFI;
    }

    // FCC / Financial Crime and Compliance
    if (hasWord('FCC') ||
        hasWord('207') ||
        text.contains('FINANCIAL CRIME') ||
        text.contains('COMPLIANCE') ||
        text.contains('আর্থিক অপরাধ') ||
        text.contains('কমপ্লায়েন্স')) {
      return codeFCC;
    }

    // AM / Agriculture and Microfinance
    if (raw.trim().toUpperCase() == 'AM' ||
        raw.contains('(AM)') ||
        raw.contains('AM-208') ||
        hasWord('208') ||
        text.contains('AGRICULTURE') ||
        text.contains('MICROFINANCE') ||
        text.contains('কৃষি ও ক্ষুদ্রঋণ') ||
        text.contains('ক্ষুদ্রঋণ') ||
        text.contains('কৃষি ব্যাংকিং')) {
      return codeAM;
    }

    // MBFS / Marketing and Branding in Financial Services
    if (hasWord('MBFS') ||
        hasWord('209') ||
        text.contains('MARKETING AND BRANDING') ||
        text.contains('MARKETING & BRANDING') ||
        text.contains('মার্কেটিং ও ব্র্যান্ডিং') ||
        text.contains('আর্থিক সেবায় মার্কেটিং')) {
      return codeMBFS;
    }

    // SF / Sustainable Finance
    if (raw.trim().toUpperCase() == 'SF' ||
        raw.contains('(SF)') ||
        raw.contains('SF-210') ||
        hasWord('210') ||
        text.contains('SUSTAINABLE FINANCE') ||
        text.contains('GREEN BANKING') ||
        text.contains('সাসটেইনেবল ফাইন্যান্স') ||
        text.contains('গ্রিন ব্যাংকিং')) {
      return codeSF;
    }

    // SBB / Shariah-Based Banking
    if (hasWord('SBB') ||
        hasWord('211') ||
        text.contains('SHARIAH-BASED') ||
        text.contains('SHARIAH BASED') ||
        text.contains('SHARIAH BANKING') ||
        text.contains('ISLAMIC BANKING') ||
        text.contains('শরীয়াহ ভিত্তিক') ||
        text.contains('ইসলামী ব্যাংকিং')) {
      return codeSBB;
    }

    // IB / Investment Banking
    if (raw.trim().toUpperCase() == 'IB' ||
        raw.contains('(IB)') ||
        raw.contains('IB-212') ||
        hasWord('212') ||
        text.contains('INVESTMENT BANKING') ||
        text.contains('ইনভেস্টমেন্ট ব্যাংকিং') ||
        text.contains('বিনিয়োগ ব্যাংকিং')) {
      return codeIB;
    }

    // ---------------- JAIBB Subject Checks ----------------
    if (hasWord('BA') ||
        text.contains('BASIC ACCOUNTING') ||
        text.contains('BUSINESS ANALYTICS') ||
        text.contains('বেসিক অ্যাকাউন্টিং') ||
        text.contains('হিসাববিজ্ঞান ও বিজনেস')) {
      return codeBA;
    }
    if (hasWord('LPGB') ||
        text.contains('GENERAL BANKING') ||
        text.contains('LAWS AND PRACTICE') ||
        text.contains('জেনারেল ব্যাংকিং') ||
        text.contains('ব্যাংকিং আইন')) {
      return codeLPGB;
    }
    if (hasWord('POE') ||
        text.contains('PRINCIPLES OF ECONOMICS') ||
        text.contains('ECONOMICS') ||
        text.contains('অর্থনীতি')) {
      return codePOE;
    }
    if (hasWord('MAFS') ||
        text.contains('MONETARY') ||
        text.contains('FINANCIAL SYSTEM') ||
        text.contains('আর্থিক ব্যবস্থা') ||
        text.contains('মুদ্রা ব্যবস্থা')) {
      return codeMAFS;
    }
    if (hasWord('BCFI') ||
        text.contains('BUSINESS COMMUNICATION') ||
        text.contains('COMMUNICATION') ||
        text.contains('ব্যবসায়িক যোগাযোগ') ||
        text.contains('যোগাযোগ')) {
      return codeBCFI;
    }
    if (hasWord('GFI') ||
        text.contains('GOVERNANCE') ||
        text.contains('সুশাসন') ||
        text.contains('করপোরেট গভর্ন্যান্স')) {
      return codeGFI;
    }
    if (hasWord('OM') ||
        text.contains('ORGANIZATION') ||
        text.contains('ORGANISATION') ||
        text.contains('সংগঠন ও ব্যবস্থাপনা') ||
        text.contains('ব্যবস্থাপনা')) {
      return codeOM;
    }

    return null;
  }

  /// Whether the subject corresponds to an official JAIBB banking course.
  static bool isBankingSubject(StudySubject subject) =>
      resolveSubjectCode(subject) != null;

  /// Returns examiner tips & tricks for the given subject code.
  static List<StudyMasterPostDraft> tipsFor(String subjectCode) =>
      _tipsCatalog[subjectCode.toUpperCase()] ?? const [];

  /// Returns worked problems & cases for the given subject code.
  static List<StudyMasterProblemDraft> problemsFor(String subjectCode) =>
      _problemsCatalog[subjectCode.toUpperCase()] ?? const [];

  /// Returns past exam paper indexes & solutions for the given subject code.
  static List<StudyMasterPostDraft> pastPapersFor(String subjectCode) =>
      _pastPapersCatalog[subjectCode.toUpperCase()] ?? const [];

  /// Returns high-yield glossary terms for the given subject code.
  static List<StudyMasterGlossaryDraft> glossaryFor(String subjectCode) =>
      _glossaryCatalog[subjectCode.toUpperCase()] ?? const [];

  // ===========================================================================
  // 1. EXAM TIPS & TRICKS CATALOG
  // ===========================================================================
  static const Map<String, List<StudyMasterPostDraft>> _tipsCatalog = {
    codeBA: [
      StudyMasterPostDraft(
        title: 'BA Exam Blueprint: 3-Hour Time Allocation Strategy',
        text: 'Allocate your 180 minutes strategically:\n'
            '1. Minutes 0–10: Question Scanning. Identify the 2 numerical problems (Depreciation, Bank Reconciliation, or Ratio Analysis) first.\n'
            '2. Minutes 10–70: Solve the 2 numerical problems completely. Working steps, ledger formats, and formula definitions secure full 40 marks.\n'
            '3. Minutes 70–130: Theory questions on GAAP, IAS/IFRS, and Golden Rules of Accounting (Personal, Real, Nominal accounts).\n'
            '4. Minutes 130–170: Business Analytics & Decision Tree / Break-even analysis questions.\n'
            '5. Minutes 170–180: Review math totals, debit/credit matching, and currency units (Taka in Lac/Crore).',
      ),
      StudyMasterPostDraft(
        title: 'Examiner Warning: Bank Reconciliation Pitfalls',
        text: 'Common errors penalised heavily by IBB examiners:\n'
            '• Uncredited Cheques: Deduct from Bank Balance when reconciling Bank to Cash Book, or add to Cash Book.\n'
            '• Dishonoured Cheques / Direct Bank Debits (Interest/Charges): Always deduct from Cash Book Balance.\n'
            '• Always state the opening balance clearly: "Balance as per Cash Book" vs "Overdraft as per Bank Statement".',
      ),
      StudyMasterPostDraft(
        title: 'Financial Ratio Analysis Scoring Formula',
        text: 'When computing Liquidity, Solvency, and Profitability ratios:\n'
            '1. State the standard formula first (e.g. Current Ratio = Current Assets / Current Liabilities).\n'
            '2. Show complete arithmetic substitution with given balance sheet figures.\n'
            '3. Provide the standard industry benchmark (e.g., Current Ratio ideal 2:1, Quick Ratio ideal 1:1) and write an examiner commentary on the bank\'s liquidity position.',
      ),
    ],
    codeLPGB: [
      StudyMasterPostDraft(
        title: 'LPGB Legal Citation Rules: Securing 80%+ Marks',
        text: 'In LPGB, examiners require specific statutory citations:\n'
            '• Section 131 NI Act 1881: Protection to Collecting Banker (crossed cheque collected in good faith without negligence for a verified customer).\n'
            '• Section 85 & 85A NI Act 1881: Protection to Paying Banker on order and bearer cheques.\n'
            '• Section 138 NI Act 1881: Criminal liability for cheque dishonour (bouncing) due to insufficient funds.\n'
            '• Bank Company Act 1991: Section 15B (Board duties), Section 27 (Prohibition on uncollateralized loans to directors), Section 46 (BB power to remove directors).\n'
            '• Money Laundering Prevention Act 2012 (MLPA): Customer Due Diligence (CDD), Suspicious Transaction Reporting (STR/SAR).',
      ),
      StudyMasterPostDraft(
        title: 'Handling Banker-Customer Relationship Scenarios',
        text: 'When analyzing customer mandate problems:\n'
            '1. Identify the legal relationship: Debtor-Creditor (Deposits), Creditor-Debtor (Loans), Bailor-Bailee (Safe Custody), Trustee-Beneficiary (Escrow).\n'
            '2. Garnishee Orders: Order Nisi attaches funds existing at the exact moment of service; subsequent deposits made after the order are NOT attached.\n'
            '3. Deceased Accounts: Stop operations immediately upon receipt of credible notice of death. Disburse only upon Probate, Letters of Administration, or Succession Certificate.',
      ),
    ],
    codePOE: [
      StudyMasterPostDraft(
        title: 'Principles of Economics: Graph & Diagram Mastery',
        text: 'Diagrams are mandatory for high marks in POE:\n'
            '• Price Elasticity of Demand: Draw clear curves for elastic (E_d > 1), unitary (E_d = 1), and inelastic (E_d < 1). Label axes (P on Y-axis, Q on X-axis).\n'
            '• Keynesian Multiplier: Explain k = 1 / (1 - MPC) = 1 / MPS with a numerical table showing round-by-round spending expansions.\n'
            '• Consumer Surplus: Shade the triangle beneath the demand curve above the equilibrium price line.',
      ),
      StudyMasterPostDraft(
        title: 'Inflation & Monetary-Fiscal Policy Interaction',
        text:
            'Differentiate sharply between Demand-Pull and Cost-Push inflation:\n'
            '• Demand-Pull: Aggregate demand outpaces full-employment aggregate supply (AD > AS). Controlled via contractionary monetary policy (raising Policy Repo Rate and CRR).\n'
            '• Cost-Push: Driven by rising raw material, energy, or imported costs. Requires supply-side reforms and fiscal duty adjustments.',
      ),
    ],
    codeMAFS: [
      StudyMasterPostDraft(
        title: 'MAFS Monetary Aggregates Formula Rules',
        text:
            'Master the core formulas for high-powered money and broad money:\n'
            '• Reserve Money (M0): Currency in Circulation + Commercial Bank Deposits with BB + Vault Cash.\n'
            '• Narrow Money (M1): Currency Outside Banks (COB) + Demand Deposits + Other Checkable Deposits.\n'
            '• Broad Money (M2): M1 + Time Deposits (Fixed and Savings Deposits).\n'
            '• Money Multiplier: m = (1 + c) / (c + r_d + e), where c is currency-to-deposit ratio, r_d is required reserve ratio, and e is excess reserve ratio.',
      ),
      StudyMasterPostDraft(
        title: 'Bangladesh Bank Interest Rate Corridor (IRC) Architecture',
        text: 'Explain Bangladesh Bank\'s modern policy corridor:\n'
            '• Upper Ceiling: Standing Lending Facility (SLF) — emergency liquidity to banks.\n'
            '• Midpoint Policy Anchor: Policy Repo Rate (PRR).\n'
            '• Lower Floor: Standing Deposit Facility (SDF) — absorption of excess banking liquidity.\n'
            '• Exchange Rate: Crawling Peg system for USD/BDT within a band around the nominal midpoint.',
      ),
    ],
    codeGFI: [
      StudyMasterPostDraft(
        title: 'GFI Fiduciary Trust & Depositor Ownership Core Principle',
        text:
            'The central thesis of GFI: Banks are 90% public depositor funds and only 10% shareholder equity.\n'
            '• Directors are NOT personal owners of a bank\'s resources; they are fiduciary trustees.\n'
            '• Quote BRPD Circular 11/2013: Delineates the strict boundary between Board policy formulation and Executive Management operational execution.\n'
            '• Three Lines of Defense: 1st line (Business operations), 2nd line (Risk management & Compliance), 3rd line (Internal Audit reporting to Board Audit Committee).',
      ),
      StudyMasterPostDraft(
        title: 'BCBS Corporate Governance 13 Principles',
        text: 'Memorize the core Basel Committee principles:\n'
            '• Board overall responsibility for bank strategy and risk culture.\n'
            '• Board qualifications and composition (Independent directors, Fit & Proper criteria).\n'
            '• Risk governance, internal controls, and independent Chief Risk Officer (CRO).\n'
            '• Conflict of interest resolution, transparent disclosures (Pillar 3 Market Discipline).',
      ),
    ],
    codeOM: [
      StudyMasterPostDraft(
        title: 'OM Management Thought Comparison Table',
        text:
            'Always compare Henri Fayol (Administrative Management) with F.W. Taylor (Scientific Management):\n'
            '• Perspective: Fayol focuses on top executive administration; Taylor focuses on shop-floor worker efficiency.\n'
            '• Unity of Command: Fayol demands single boss reporting; Taylor proposes functional foremanship (8 specialized supervisors).\n'
            '• Universal applicability: Fayol applies to banks, hospitals, and government; Taylor primarily to physical production lines.',
      ),
      StudyMasterPostDraft(
        title: 'Kurt Lewin 3-Stage Change Model in Core Banking Automation',
        text: 'When answering organizational change questions in banking:\n'
            '1. Unfreezing: Overcome status quo inertia, dispel layoff rumors, create psychological safety.\n'
            '2. Changing / Moving: Implement hands-on CBS simulation labs, train-the-trainer peer champions.\n'
            '3. Refreezing: Standardize SOPs, integrate CBS proficiency into KPIs, celebrate branch milestones.',
      ),
    ],
    codeBCFI: [
      StudyMasterPostDraft(
        title: 'BCFI Official Bank Letter & Memo Drafting Standards',
        text: 'Secure maximum marks by including all mandatory components:\n'
            '• Formal Letter: Bank Letterhead, Ref No., Date, Inside Address, Salutation, Subject Line, 3-paragraph Body, Complimentary Close, Signature, Designation, CC list.\n'
            '• Internal Memo: Header grid (TO, FROM, DATE, REF, SUBJECT), clear numbered action points, no complimentary close.\n'
            '• Minutes of Meeting: Quorum confirmation, Review of previous minutes, Agenda resolutions (Res No.), Action By deadline, Chairman signature.',
      ),
      StudyMasterPostDraft(
        title: 'The 7 Cs of Communication in Banking Customer Service',
        text: 'Demonstrate each C with practical banking examples:\n'
            '• Completeness (Provide all required loan documentation checklists).\n'
            '• Conciseness (Eliminate redundant wordiness in notices).\n'
            '• Consideration / "You" Attitude (Highlight customer benefit over bank convenience).\n'
            '• Clarity, Concreteness (Specific numbers and dates), Courtesy, and Correctness (Legal accuracy).',
      ),
    ],
    codeRMFI: [
      StudyMasterPostDraft(
        title: 'RMFI Exam Blueprint: Basel III Pillar 1, 2, 3 Strategy',
        text: 'Allocate your 180 minutes systematically:\n'
            '1. Question Scanning (0–10 min): Target RWA calculations or CAR formula problems first.\n'
            '2. Numerical & Ratio Solutions (10–65 min): Credit, Market, and Operational RWA step-by-step substitutions.\n'
            '3. Core Theory (65–130 min): Three Pillars of Basel III, ICAAP framework, and Stress Testing methodologies.\n'
            '4. BB Circulars (130–170 min): BRPD guidelines on CRAR (min 10% + 2.5% CCB), LCR (>= 100%), and NSFR (>= 100%).\n'
            '5. Revision (170–180 min): Recheck risk weights and capital tier arithmetic.',
      ),
      StudyMasterPostDraft(
        title: 'Examiner Warning: Credit Risk Mitigation (CRM) Haircuts',
        text: 'Common errors penalised in RMFI:\n'
            '• Unadjusted Collateral: Cash margins and FDRs require standard supervisory haircuts under the comprehensive approach.\n'
            '• Off-Balance Sheet Conversions: Credit Conversion Factors (CCF) must be applied (e.g. 20%, 50%, 100%) before risk weighting.\n'
            '• Always state Capital to Risk-weighted Assets Ratio (CRAR) = (Tier 1 + Tier 2 Capital) / Total RWA.',
      ),
    ],
    codeCOM: [
      StudyMasterPostDraft(
        title: 'COM Credit Appraisal & 5 Cs Scoring Strategy',
        text: 'Structure all credit assessment answers around the 5 Cs:\n'
            '• Character: CIB report analysis, track record, integrity, management quality.\n'
            '• Capacity: Cash flow adequacy, Debt Service Coverage Ratio (DSCR min 1.5x), historical turnover.\n'
            '• Capital: Borrower equity contribution, debt-to-equity ratio, net worth.\n'
            '• Collateral: Security perfection, legal title vetting, forced sale value (FSV) vs market value.\n'
            '• Conditions: Macroeconomic environment, industry sector risk, regulatory caps.',
      ),
      StudyMasterPostDraft(
        title: 'Loan Classification & Rescheduling Standards',
        text: 'Master Bangladesh Bank master circular thresholds:\n'
            '• Special Mention Account (SMA): Overdue 60 to 89 days (commercial) with qualitative weakness.\n'
            '• Sub-Standard (SS): Overdue 90 to 179 days, 20% general provision on unhedged portion.\n'
            '• Doubtful (DF): Overdue 180 to 269 days, 50% provision requirement.\n'
            '• Bad/Loss (BL): Overdue 270 days or more, 100% provision requirement.',
      ),
    ],
    codeTFFE: [
      StudyMasterPostDraft(
        title: 'TFFE Statutory Timelines & UCPDC 600 Rules',
        text:
            'Mandatory rules examiners look for in every trade finance paper:\n'
            '• Article 14(b) UCPDC 600: A nominated or issuing bank has a maximum of 5 banking days following the day of presentation to determine compliance.\n'
            '• Article 16: Notice of refusal must be given by telecommunication or expeditious means no later than the close of the 5th banking day, stating all discrepancies.\n'
            '• Strict Compliance vs Substantial Compliance: Documents must appear on their face to constitute a complying presentation.',
      ),
      StudyMasterPostDraft(
        title: 'Incoterms 2020 Risk Transfer Architecture',
        text: 'Differentiate exact risk and cost transfer points:\n'
            '• FOB (Free on Board): Risk passes when goods are on board the vessel. Seller pays export clearance.\n'
            '• CFR/CIF (Cost & Freight / Insurance): Risk passes on board, but seller pays sea freight (and insurance in CIF).\n'
            '• DAP/DDP: Risk passes only when delivered at destination; DDP requires seller to pay import duty and taxes.',
      ),
    ],
    codeICTFI: [
      StudyMasterPostDraft(
        title: 'ICT Security Guideline & Core Banking Architecture',
        text: 'Key standards mandated by Bangladesh Bank:\n'
            '• 3-Tier Architecture: Web tier (DMZ), Application tier, and Database tier must be logically and physically segmented.\n'
            '• Two-Factor Authentication (2FA): Mandatory for internet banking, mobile apps, and administrative access to servers.\n'
            '• Disaster Recovery: Primary and DR sites must be geographically separated (min 20-30 km) with synchronous/asynchronous replication.',
      ),
    ],
    codeTMFI: [
      StudyMasterPostDraft(
        title: 'ALM Framework & Liquidity Risk Architecture',
        text: 'Asset Liability Management guidelines required by examiners:\n'
            '• ALCO Mandate: Monthly ALCO meetings review structural liquidity, IRRBB, and balance sheet growth.\n'
            '• Structural Liquidity Profile: Time buckets (1-14 days, 15-28 days, 29-90 days, etc.) with cumulative mismatch limits.\n'
            '• BB Policy Corridor: Repo rate anchor, Standing Lending Facility (SLF) upper bound, Standing Deposit Facility (SDF) lower bound.',
      ),
    ],
    codeFCC: [
      StudyMasterPostDraft(
        title: 'AML/CFT Statutory Architecture: MLPA 2012 & ATA 2009',
        text: 'Examiner-grade legal principles for compliance officers:\n'
            '• MLPA 2012 Section 25: Mandatory reporting of Cash Transaction Reports (CTR) for transactions of BDT 10 Lac and above within 21 days.\n'
            '• Suspicious Transaction Report (STR): Report immediately upon detecting suspicion, without minimum amount threshold and without tipping off the customer.\n'
            '• Politically Exposed Persons (PEPs): Senior management approval mandatory before account opening; ongoing enhanced monitoring.',
      ),
    ],
    codeAM: [
      StudyMasterPostDraft(
        title: 'Agricultural Credit Policy & Priority Lending Guidelines',
        text: 'Agricultural financing scoring parameters:\n'
            '• Mandatory Target: Banks must disburse at least 2.5% of total net loans to agriculture and rural sectors.\n'
            '• Crop Loan Scale of Finance: Credit limit determined by district-level agricultural technical committees based on acreage and cost.\n'
            '• Revolving Crop Credit: 3-year validity with annual renewal based on clean repayment after harvesting.',
      ),
    ],
    codeMBFS: [
      StudyMasterPostDraft(
        title: '7 Ps of Service Marketing in Digital Banking',
        text: 'Apply the extended services marketing mix:\n'
            '• Product: Tailored retail, SME, and agent banking products.\n'
            '• Price: Interest rate spread, fees, commission transparency.\n'
            '• Place: Omnichannel distribution (Branches, Sub-branches, ATMs, CRMs, Mobile Apps).\n'
            '• Promotion: Financial literacy campaigns, ethical advertising.\n'
            '• People: Well-trained front-office bankers delivering relationship banking.\n'
            '• Process: Digital KYC, instant onboarding, seamless dispute resolution.\n'
            '• Physical Evidence: Modern branch ambiance, intuitive mobile UI/UX.',
      ),
    ],
    codeSF: [
      StudyMasterPostDraft(
        title: 'Sustainable Finance Policy & Green Taxonomy Standards',
        text:
            'Core principles of green and sustainable banking in Bangladesh:\n'
            '• Minimum Green Financing Target: At least 5% of total term loan disbursements must be allocated to verified green products.\n'
            '• Environmental & Social Risk Management (ESRM): Mandatory E&S screening using the sector-specific ESRM Guideline.\n'
            '• Refinance Schemes: Low-cost refinancing available from Bangladesh Bank for 68+ green products/initiatives.',
      ),
    ],
    codeSBB: [
      StudyMasterPostDraft(
        title: 'Islamic Banking Contracts & Shariah Governance',
        text: 'Essential distinctions in Shariah-compliant finance:\n'
            '• Murabaha: Cost-plus markup sale contract where cost and profit are explicitly disclosed to the buyer.\n'
            '• Mudarabah: Partnership where one party provides capital (Rabb-ul-Mal) and the other manages (Mudarib); profit shared by ratio, loss borne by capital.\n'
            '• Musharakah: Joint partnership where all partners contribute capital and share profits according to agreement and losses strictly by capital proportion.',
      ),
    ],
    codeIB: [
      StudyMasterPostDraft(
        title: 'Investment Banking & Capital Market Regulations',
        text: 'Key legal frameworks for investment bankers:\n'
            '• Public Issue Rules: Underwriting commitment (min 35% of total issue size) by registered Merchant Banks.\n'
            '• Book Building Method: Institutional bidding establishes the cut-off price; general public receives shares at a discount.\n'
            '• Syndicated Financing: Lead arranger syndicates multi-bank term loans with inter-creditor agreements and escrow agency.',
      ),
    ],
    codeAFI: [
      StudyMasterPostDraft(
        title: 'First Schedule Banking Companies Act 1991 Financial Reporting',
        text: 'Reporting standards for scheduled banks:\n'
            '• Form A Balance Sheet: Strict layout with Assets on left/top and Liabilities and Shareholders\' Equity on right/bottom.\n'
            '• Form B Profit & Loss Account: Clear demarcation between Interest Income/Expense, Operating Income/Expense, and Provisions.\n'
            '• BRPD Circular 14: Mandatory note disclosures on non-performing loans, CRAR, and maturity groupings of assets/liabilities.',
      ),
    ],
    codeMA: [
      StudyMasterPostDraft(
        title: 'Cost-Volume-Profit (CVP) Analysis in Financial Services',
        text: 'Marginal costing essentials for bank branch profitability:\n'
            '• Contribution Margin = Total Revenue - Total Variable Costs.\n'
            '• Break-Even Point (Units) = Total Fixed Costs / Contribution Margin per Unit.\n'
            '• Margin of Safety = (Actual or Projected Sales - Break-Even Sales) / Actual Sales.',
      ),
    ],
  };

  // ===========================================================================
  // 2. WORKED PROBLEMS & CASES CATALOG
  // ===========================================================================
  static const Map<String, List<StudyMasterProblemDraft>> _problemsCatalog = {
    codeBA: [
      StudyMasterProblemDraft(
        title:
            'Bank Reconciliation Statement (Cash Book vs Pass Book Discrepancies)',
        text:
            'On 31 December 2025, the Cash Book of Apex Trading showed a bank debit balance of Tk. 2,45,000. '
            'Upon comparison with the Bank Statement (Pass Book), the following discrepancies were discovered:\n'
            '1. Cheques issued to suppliers totaling Tk. 68,000 were not presented for payment.\n'
            '2. Cheques deposited into bank amounting to Tk. 42,000 were not credited by the bank.\n'
            '3. A customer directly deposited Tk. 25,000 into the bank account, recorded only in Pass Book.\n'
            '4. Bank charges of Tk. 1,500 and interest on investment collected by bank of Tk. 8,000 were recorded in Pass Book only.\n'
            '5. A cheque of Tk. 10,000 received from a debtor was dishonoured on presentation, not entered in Cash Book.\n\n'
            'Required: Prepare a Bank Reconciliation Statement as of 31 December 2025.',
        solution: '### Bank Reconciliation Statement as of 31 December 2025\n\n'
            '| Particulars | Amount (Tk.) | Amount (Tk.) |\n'
            '| :--- | :---: | :---: |\n'
            '| **Balance as per Cash Book (Dr.)** | | **2,45,000** |\n'
            '| **Add:** | | |\n'
            '| • Cheques issued but not yet presented for payment | 68,000 | |\n'
            '| • Direct deposit by customer into bank | 25,000 | |\n'
            '| • Interest on investment collected directly by bank | 8,000 | 1,01,000 |\n'
            '| **Subtotal** | | **3,46,000** |\n'
            '| **Less:** | | |\n'
            '| • Cheques deposited but not yet credited/collected | 42,000 | |\n'
            '| • Bank charges debited by bank | 1,500 | |\n'
            '| • Dishonoured cheque debited by bank | 10,000 | (53,500) |\n'
            '| **Balance as per Bank Statement (Pass Book - Cr.)** | | **Tk. 2,92,500** |\n\n'
            '> **Examiner Note:** The resulting Tk. 2,92,500 represents the true reconciled credit balance in the Bank Statement.',
      ),
      StudyMasterProblemDraft(
        title:
            'Depreciation Accounting: Straight-Line vs Reducing Balance Method',
        text:
            'On 1 January 2023, National Bank PLC purchased automated teller machine (ATM) hardware for '
            'Tk. 12,00,000. Installation costs were Tk. 1,00,000. Estimated salvage value after 4 years is Tk. 1,00,000.\n\n'
            'Required:\n'
            '1. Calculate annual depreciation under the Straight-Line Method.\n'
            '2. Calculate depreciation for Years 1–3 under the Diminishing Balance Method at 25% p.a.\n'
            '3. Show ledger journal entries for Year 1 under IAS 16.',
        solution: '### 1. Straight-Line Method Calculation:\n'
            'Total Depreciable Cost = Purchase Price + Installation = 12,00,000 + 1,00,000 = Tk. 13,00,000\n'
            'Annual Depreciation = (Cost - Salvage Value) / Useful Life = (13,00,000 - 1,00,000) / 4 = Tk. 3,00,000 per year\n\n'
            '### 2. Reducing / Diminishing Balance Method (25% p.a.):\n'
            '• **Year 1**: 13,00,000 × 25% = Tk. 3,25,000 (Book Value: Tk. 9,75,000)\n'
            '• **Year 2**: 9,75,000 × 25% = Tk. 2,43,750 (Book Value: Tk. 7,31,250)\n'
            '• **Year 3**: 7,31,250 × 25% = Tk. 1,82,812.50 (Book Value: Tk. 5,48,437.50)\n\n'
            '### 3. Journal Entries (Year 1):\n'
            '1. ATM Hardware A/C (Dr.) Tk. 13,00,000\n'
            '   To Bank A/C (Cr.) Tk. 13,00,000 *(Asset acquisition & installation)*\n'
            '2. Depreciation Expense A/C (Dr.) Tk. 3,00,000\n'
            '   To Accumulated Depreciation A/C (Cr.) Tk. 3,00,000 *(Year 1 Straight-line depreciation)*',
      ),
    ],
    codeLPGB: [
      StudyMasterProblemDraft(
        title: 'Collecting Banker Protection under Section 131 NI Act 1881',
        text:
            'A crossed "Account Payee" cheque for Tk. 5,00,000 drawn in favor of "Messrs. Green Builders" was '
            'presented for collection by Mr. X, who opened a new personal current account at City Bank just two days '
            'earlier without proper KYC verification and without introducing referees. The branch collected the funds '
            'and allowed Mr. X to withdraw the entire amount immediately. Later, Green Builders reported the cheque was stolen.\n\n'
            'Required: Analyze whether City Bank can claim statutory protection as a collecting banker under Section 131 of the Negotiable Instruments Act, 1881.',
        solution: '### Legal Analysis & Ruling:\n\n'
            '**Statutory Standard (Section 131 NI Act 1881):**\n'
            'A collecting banker is protected against conversion claims only if four concurrent conditions are satisfied:\n'
            '1. The cheque was crossed generally or specially before arriving at the bank.\n'
            '2. The bank acted strictly in good faith.\n'
            '3. The bank acted **without negligence**.\n'
            '4. The bank collected the proceeds for a verified customer.\n\n'
            '**Application to Scenario:**\n'
            '• **Gross Negligence in Account Opening**: Opening an account without KYC verification, biometric verification, or reference checks breaches Bangladesh Bank BFIU guidelines and constitutes negligence at inception.\n'
            '• **Crossing Violation**: The cheque was explicitly crossed "Account Payee" for "Messrs. Green Builders" (a business enterprise), but collected for Mr. X (a private individual) without inquiring into the title mismatch.\n\n'
            '**Conclusion**: City Bank is guilty of negligence and **cannot claim statutory protection** under Section 131. The bank is legally liable to refund the true owner (Green Builders) Tk. 5,00,000 for conversion.',
      ),
      StudyMasterProblemDraft(
        title: 'Execution of Court Garnishee Order on Customer Deposits',
        text:
            'On 10 March 2026 at 11:30 AM, a court serves a Garnishee Order Nisi for Tk. 3,00,000 on Prime Bank '
            'attaching all debts owing to judgment debtor Mr. Rahim. At that exact time, Rahim\'s accounts stood as:\n'
            '• Savings Account: Credit balance Tk. 2,10,000.\n'
            '• Current Account: Overdrawn balance (Dr.) Tk. 50,000.\n'
            '• Fixed Deposit Receipt (FDR maturing in 6 months): Tk. 4,00,000.\n'
            '• Rahim & Brothers (Partnership firm account): Credit balance Tk. 1,50,000.\n'
            'At 1:00 PM on the same date, Rahim deposits Tk. 1,00,000 in cash into his Savings Account.\n\n'
            'Required: Explain how the branch manager must deal with each account.',
        solution: '### Legal Rules for Garnishee Execution:\n\n'
            '1. **Savings Account (Tk. 2,10,000)**: Attached by the Order Nisi. The branch must freeze Tk. 2,10,000 immediately.\n'
            '2. **Current Account (Debit Tk. 50,000)**: Overdraft represents a debt owed by customer to bank, not a bank debt to customer. Hence, NOT attached.\n'
            '3. **FDR Account (Tk. 4,00,000)**: Although maturing in 6 months, an FDR is a "debt accruing due" (debitum in praesenti, solvendum in futuro). It IS attached. The bank freezes Tk. 90,000 from the FDR to satisfy the remaining court claim of Tk. 3,00,000 (2,10,000 + 90,000 = 3,00,000).\n'
            '4. **Partnership Account (Tk. 1,50,000)**: Partnership funds belong jointly to all partners; cannot be attached for an individual partner\'s personal debts.\n'
            '5. **Subsequent Deposit of Tk. 1,00,000 at 1:00 PM**: Garnishee Order Nisi attaches only balances existing at the exact moment of service (11:30 AM). Deposits made afterwards are unattached.',
      ),
    ],
    codePOE: [
      StudyMasterProblemDraft(
        title: 'Computation of Price Elasticity of Demand and Revenue Impact',
        text:
            'When the price of a banking service drops from Tk. 50 to Tk. 40, the monthly subscription quantity '
            'increases from 20,000 units to 30,000 units.\n\n'
            'Required:\n'
            '1. Calculate the Price Elasticity of Demand (E_d) using the Midpoint (Arc) Elasticity method.\n'
            '2. Interpret the elasticity coefficient.\n'
            '3. Calculate the change in Total Revenue and state the pricing policy recommendation.',
        solution: '### 1. Midpoint (Arc) Elasticity Calculation:\n'
            'Midpoint Price P_m = (50 + 40) / 2 = 45, ΔP = 40 - 50 = -10\n'
            'Midpoint Quantity Q_m = (20,000 + 30,000) / 2 = 25,000, ΔQ = 30,000 - 20,000 = 10,000\n'
            'E_d = | (ΔQ / Q_m) / (ΔP / P_m) | = | (10,000 / 25,000) / (-10 / 45) | = 0.40 / 0.2222 = 1.80\n\n'
            '### 2. Economic Interpretation:\n'
            'Since E_d = 1.80 > 1, demand is **Price Elastic**. A 1% decrease in price produces a 1.8% expansion in quantity demanded.\n\n'
            '### 3. Total Revenue (TR) Impact:\n'
            '• Initial TR: 50 × 20,000 = Tk. 10,00,000\n'
            '• New TR: 40 × 30,000 = Tk. 12,00,000\n'
            '• ΔTR = +Tk. 2,00,000 (20% increase in revenue).\n'
            '**Policy Recommendation**: When demand is elastic, lowering fees increases total revenue.',
      ),
    ],
    codeMAFS: [
      StudyMasterProblemDraft(
        title: 'Computation of Monetary Aggregates (M1, M2 & Reserve Money)',
        text:
            'Given the following monetary statistics for Bangladesh (figures in Billion Taka):\n'
            '• Currency in circulation: Tk. 2,923.60 billion\n'
            '• Currency in tills of commercial banks (Vault Cash): Tk. 241.80 billion\n'
            '• Demand deposits held by commercial banks: Tk. 1,837.40 billion\n'
            '• Other checkable deposits (OCD) with BB: Tk. 6.20 billion\n'
            '• Time deposits (Fixed & Savings): Tk. 13,054.30 billion\n'
            '• Balances of commercial banks with BB: Tk. 1,020.00 billion\n\n'
            'Required: Calculate Currency Outside Banks (COB), Narrow Money (M1), Broad Money (M2), and Reserve Money (M0).',
        solution: '### Step-by-Step Monetary Calculation:\n\n'
            '1. **Currency Outside Banks (COB)**:\n'
            '   COB = Currency in circulation - Vault Cash = 2,923.60 - 241.80 = Tk. 2,681.80 billion\n\n'
            '2. **Narrow Money (M1)**:\n'
            '   M1 = COB + Demand Deposits + OCD\n'
            '   M1 = 2,681.80 + 1,837.40 + 6.20 = Tk. 4,525.40 billion\n\n'
            '3. **Broad Money (M2)**:\n'
            '   M2 = M1 + Time Deposits\n'
            '   M2 = 4,525.40 + 13,054.30 = Tk. 17,579.70 billion\n\n'
            '4. **Reserve Money (M0 / Monetary Base)**:\n'
            '   M0 = Currency in circulation + Bank Balances with BB\n'
            '   M0 = 2,923.60 + 1,020.00 = Tk. 3,943.60 billion',
      ),
    ],
    codeGFI: [
      StudyMasterProblemDraft(
        title: 'Related-Party Lending and Board Governance Breakdown',
        text:
            'A sponsor director of a private bank persuades the Board to sanction a Tk. 50 Crore uncollateralized '
            'term loan to his son-in-law\'s manufacturing firm. The Credit Risk Management (CRM) division had issued '
            'an adverse appraisal noting high default risk and absence of audited balance sheets. The Board approved '
            'the loan without the required Bangladesh Bank prior consent.\n\n'
            'Required: Identify the statutory violations under the Bank Company Act 1991 and BRPD Circular 11/2013, '
            'and detail the regulatory actions Bangladesh Bank can take under Section 46.',
        solution: '### Comprehensive Governance & Legal Findings:\n\n'
            '1. **Statutory Violations**:\n'
            '   • **Section 27 BCA 1991**: Prohibits granting unsecured loans or advances to directors, their family members, or entities in which they have substantial interest.\n'
            '   • **BRPD Circular 11/2013**: Prohibits the Board of Directors from interfering in day-to-day credit appraisals or bypassing CRM negative findings.\n'
            '   • **Failure of Recusal**: The interested sponsor director violated corporate ethics by not disclosing conflict of interest and not recusing himself from deliberations.\n\n'
            '2. **Regulatory Sanctions by Bangladesh Bank**:\n'
            '   • **Section 46 BCA 1991**: Bangladesh Bank has statutory power to remove the involved directors and the compliant CEO from office.\n'
            '   • **5-Year Debarment**: Removed directors are disqualified from holding any directorship in any financial institution for 5 years.\n'
            '   • **100% Provisioning & Clawback**: Enforce immediate loan recall and 100% provisioning against bank capital.',
      ),
    ],
    codeOM: [
      StudyMasterProblemDraft(
        title: 'Overcoming Branch Staff Resistance to Digital Core Banking',
        text:
            'When a scheduled bank rolled out a new cloud Core Banking System (CBS) replacing legacy software, '
            'rural branches experienced severe resistance: cashiers claimed system slowness, created artificial queues, '
            'and spread rumors of upcoming staff layoffs.\n\n'
            'Required: Apply Kurt Lewin\'s 3-Stage Change Model (Unfreezing, Changing, Refreezing) to resolve the crisis.',
        solution: '### Actionable Change Management Solution:\n\n'
            '1. **Stage 1: Unfreezing (গলিয়ে নেওয়া)**:\n'
            '   • Executive reassurance: Board-level guarantee that no staff will be terminated due to CBS automation.\n'
            '   • Town halls: Explain existential necessity of CBS for RTGS, NPSB, and automated regulatory reporting.\n\n'
            '2. **Stage 2: Changing / Moving (পরিবর্তন প্রয়োগ)**:\n'
            '   • "Train the Trainer": Pair junior tech champions with senior officers in hands-on simulation labs.\n'
            '   • Phased rollout: Launch in low-volume rural branches first before migrating high-traffic urban corporate branches.\n\n'
            '3. **Stage 3: Refreezing (স্থায়ীকরণ ও দৃঢ়ীকরণ)**:\n'
            '   • Formalize updated SOPs; tie CBS operational proficiency to annual promotion appraisals.\n'
            '   • Publicly recognize and reward high-efficiency branches at annual zonal conferences.',
      ),
    ],
    codeBCFI: [
      StudyMasterProblemDraft(
        title:
            'Drafting Legal Notice for Loan Recall under Artha Rin Adalat Ain 2003',
        text:
            'Draft a formal legal recall notice from Sonali Bank PLC to a classified defaulting borrower '
            '("Messrs. Apex Textiles") demanding payment of Tk. 3,85,00,000 within 15 days before filing suit under '
            'Artha Rin Adalat Ain 2003 and Section 138 of NI Act 1881.',
        solution: '### Formal Model Legal Demand Notice:\n\n'
            '```text\n'
            'SONALI BANK PLC | MOTIJHEEL CORPORATE BRANCH, DHAKA\n'
            'Ref: SB/MCB/LAW/2026/782                                     Date: 12 March 2026\n'
            'REGISTERED WITH A/D\n\n'
            'To: The Managing Director, Messrs. Apex Textiles Ltd., 45 Dilkusha C/A, Dhaka.\n\n'
            'SUBJECT: FINAL DEMAND NOTICE FOR FULL REPAYMENT OF OVERDUE CASH CREDIT ACCOUNT NO. 0110-449191 WITH OUTSTANDING OF TK. 3,85,00,000/-.\n\n'
            'Dear Sir,\n'
            'We draw your attention to our Sanction Letter dated 15 Jan 2023 granting Cash Credit limit of Tk. 3.50 Crore. The facility expired on 14 Jan 2025 and despite repeated written reminders dated 10 Aug 2025 and 05 Dec 2025, you have failed to regularize the overdue liability.\n\n'
            'The account has been classified as Bad/Loss under Bangladesh Bank BRPD circulars with total outstanding liability of Tk. 3,85,00,000/- as of 10 March 2026.\n\n'
            'YOU ARE HEREBY GIVEN FINAL NOTICE to liquidate the entire liability within 15 (fifteen) calendar days, failing which the Bank will initiate:\n'
            '1. Recovery suit before the Artha Rin Adalat under Artha Rin Adalat Ain, 2003;\n'
            '2. Criminal prosecution under Section 138 of Negotiable Instruments Act, 1881;\n'
            '3. Report names of all directors to CIB as willful defaulters.\n\n'
            'Yours faithfully,\n'
            '(Mohammad Habibur Rahman)\n'
            'Senior Vice President & Head of Branch\n'
            '```',
      ),
    ],
    codeRMFI: [
      StudyMasterProblemDraft(
        title: 'Credit Risk RWA Calculation (Standardized Approach)',
        text:
            'Bank X has loans to AAA rated corporate (BDT 100 Cr, 20% RW), unrated corporate (BDT 200 Cr, 100% RW), and retail SME (BDT 150 Cr, 75% RW). Compute Total Credit Risk Weighted Assets.',
        solution: 'Step 1: Compute RWA per category:\n'
            '• AAA Corporate: 100 * 20% = BDT 20.00 Crore\n'
            '• Unrated Corporate: 200 * 100% = BDT 200.00 Crore\n'
            '• Retail SME: 150 * 75% = BDT 112.50 Crore\n'
            'Step 2: Total Credit RWA = 20.00 + 200.00 + 112.50 = BDT 332.50 Crore.\n'
            'Examiner Note: If regulatory capital required is 10%, minimum capital required = 332.50 * 10% = BDT 33.25 Crore.',
      ),
      StudyMasterProblemDraft(
        title: 'Capital to Risk-Weighted Assets Ratio (CRAR) Computation',
        text:
            'A bank reports Tier 1 Capital of BDT 600 Crore, Tier 2 Capital of BDT 400 Crore, and Total Risk Weighted Assets of BDT 8,000 Crore. Determine whether the bank satisfies Bangladesh Bank CRAR and CCB requirements.',
        solution:
            'Step 1: Total Eligible Regulatory Capital = Tier 1 + Tier 2 = 600 + 400 = BDT 1,000 Crore.\n'
            'Step 2: CRAR = (Total Capital / Total RWA) * 100% = (1,000 / 8,000) * 100% = 12.50%.\n'
            'Step 3: Benchmark comparison: Bangladesh Bank requires minimum CRAR of 10.00% plus Capital Conservation Buffer (CCB) of 2.50%, totaling 12.50%.\n'
            'Verdict: The bank satisfies the statutory 12.50% capital requirement.',
      ),
    ],
    codeCOM: [
      StudyMasterProblemDraft(
        title:
            'Working Capital Limit using Maximum Permissible Bank Finance (MPBF)',
        text:
            'A manufacturing firm projects Total Current Assets of BDT 500 Lac and Other Current Liabilities (excluding bank borrowings) of BDT 100 Lac. Calculate MPBF under Tandon Method II (Borrower brings 25% of TCA from long-term sources).',
        solution: 'Step 1: Total Current Assets (TCA) = BDT 500 Lac.\n'
            'Step 2: Working Capital Gap (WCG) = TCA - OCL = 500 - 100 = BDT 400 Lac.\n'
            'Step 3: Borrower Margin (25% of TCA) = 500 * 25% = BDT 125 Lac.\n'
            'Step 4: MPBF = WCG - Borrower Margin = 400 - 125 = BDT 275 Lac.\n'
            'Step 5: Current Ratio check = TCA / (OCL + MPBF) = 500 / (100 + 275) = 500 / 375 = 1.33:1 (satisfies benchmark).',
      ),
      StudyMasterProblemDraft(
        title: 'Debt Service Coverage Ratio (DSCR) Calculation',
        text:
            'Projected Net Profit after Tax = BDT 40 Lac, Depreciation = BDT 15 Lac, Interest on Term Loan = BDT 20 Lac, Annual Principal Installment = BDT 25 Lac. Compute DSCR and evaluate project bankability.',
        solution:
            'Step 1: Cash Flow Available for Debt Service = Net Profit + Depreciation + Interest = 40 + 15 + 20 = BDT 75 Lac.\n'
            'Step 2: Total Debt Service Obligation = Principal + Interest = 25 + 20 = BDT 45 Lac.\n'
            'Step 3: DSCR = Cash Flow / Debt Service = 75 / 45 = 1.67x.\n'
            'Verdict: DSCR of 1.67x comfortably exceeds standard banking threshold of 1.50x, demonstrating strong repayment capacity.',
      ),
    ],
    codeTFFE: [
      StudyMasterProblemDraft(
        title: 'Export Bill Negotiation & Overdue Interest Calculation',
        text:
            'A bank negotiates an export usance bill of USD 100,000 at TT Buying rate of 117.50 for 90 days. Rate of interest is 9.00% p.a. Compute net proceeds payable to exporter assuming 360 days per year.',
        solution:
            'Step 1: Gross Taka Equivalent = USD 100,000 * 117.50 = BDT 11,750,000.\n'
            'Step 2: Discounting Interest = Gross * Rate * (Days / 360) = 11,750,000 * 0.09 * (90 / 360) = BDT 264,375.\n'
            'Step 3: Net proceeds to exporter = 11,750,000 - 264,375 = BDT 11,485,625.',
      ),
      StudyMasterProblemDraft(
        title: 'Foreign Exchange Rate Quotation: TT & OD Selling Margin',
        text:
            'Interbank USD/BDT spot rate is 117.00 - 117.10. The bank requires an exchange margin of 0.50% on sales. Calculate the merchant TT Selling rate.',
        solution:
            'Step 1: Identify interbank base: In selling foreign currency, bank buys from market at offer rate = 117.10.\n'
            'Step 2: Exchange Margin (0.50%) = 117.10 * 0.005 = 0.5855.\n'
            'Step 3: TT Selling Rate = 117.10 + 0.5855 = BDT 117.6855 (rounded to BDT 117.69).',
      ),
    ],
    codeICTFI: [
      StudyMasterProblemDraft(
        title: 'Disaster Recovery RTO and RPO Impact Analysis',
        text:
            'A bank database server crashes at 2:00 PM. Latest data backup was taken at 12:00 PM. Full service is restored on secondary site at 4:30 PM. Calculate the realized RTO and RPO.',
        solution:
            'Step 1: Recovery Point Objective (RPO) = Data loss window between last backup (12:00 PM) and crash (2:00 PM) = 2 hours of transactional data.\n'
            'Step 2: Recovery Time Objective (RTO) = Downtime duration between crash (2:00 PM) and full restoration (4:30 PM) = 2.5 hours.\n'
            'Examiner Note: For mission-critical CBS, Bangladesh Bank mandates near-zero RPO via synchronous storage replication.',
      ),
    ],
    codeTMFI: [
      StudyMasterProblemDraft(
        title: 'Maturity GAP Analysis & Interest Rate Shock',
        text:
            'In the 1-90 day bucket, a bank has Rate Sensitive Assets (RSA) of BDT 1,200 Crore and Rate Sensitive Liabilities (RSL) of BDT 1,500 Crore. Compute the Gap and the impact on Net Interest Income (NII) if interest rates rise by 1.00% (100 bps).',
        solution:
            'Step 1: Interest Rate GAP = RSA - RSL = 1,200 - 1,500 = -BDT 300 Crore (Negative / Liability Sensitive GAP).\n'
            'Step 2: Change in NII = GAP * Change in Interest Rate = (-300 Cr) * (+1.00%) = -BDT 3.00 Crore.\n'
            'Interpretation: Because the bank has more liabilities repricing upwards than assets, a 1% rate hike reduces Net Interest Income by BDT 3.00 Crore.',
      ),
    ],
    codeFCC: [
      StudyMasterProblemDraft(
        title: 'Smurfing & Structuring Detection Analysis',
        text:
            'A customer deposits BDT 9,50,000 cash in morning, BDT 9,80,000 in afternoon at different branches on the same day. Analyze the compliance reporting obligations under MLPA 2012.',
        solution:
            'Step 1: Structuring / Smurfing Analysis: Individual transactions are deliberately kept below the mandatory CTR threshold of BDT 10 Lac to evade detection.\n'
            'Step 2: Aggregated daily cash deposit = 9.50 + 9.80 = BDT 19.30 Lac, which exceeds CTR threshold.\n'
            'Step 3: Action Required: File an immediate Suspicious Transaction Report (STR) to BFIU within statutory timeline without tipping off the customer, and log for CTR.',
      ),
    ],
    codeAM: [
      StudyMasterProblemDraft(
        title: 'Crop Loan Limit Sizing using Scale of Finance',
        text:
            'A farmer cultivates 5 acres of Boro rice. Approved Scale of Finance is BDT 40,000 per acre. Farmer receives 10% consumption allowance. Calculate sanctioned crop loan limit and repayment schedule.',
        solution:
            'Step 1: Production Cost Component = 5 acres * BDT 40,000 = BDT 200,000.\n'
            'Step 2: Consumption Allowance (10%) = 200,000 * 10% = BDT 20,000.\n'
            'Step 3: Total Sanctioned Crop Loan Limit = 200,000 + 20,000 = BDT 220,000.\n'
            'Repayment: Repayable in single bullet payment 2 months post-harvest (Boro harvest in May, repayment by July 31).',
      ),
    ],
    codeMBFS: [
      StudyMasterProblemDraft(
        title: 'Customer Acquisition Cost (CAC) & Lifetime Value (CLV)',
        text:
            'A digital banking unit spends BDT 50 Lac in marketing acquiring 10,000 new active accounts. Average annual net revenue per user is BDT 1,200 with an expected customer tenure of 5 years. Compute CAC and CLV.',
        solution:
            'Step 1: Customer Acquisition Cost (CAC) = Total Marketing Spend / New Customers Acquired = 5,000,000 / 10,000 = BDT 500 per customer.\n'
            'Step 2: Customer Lifetime Value (CLV) = Annual Revenue * Tenure = 1,200 * 5 = BDT 6,000.\n'
            'Step 3: CLV to CAC Ratio = 6,000 / 500 = 12:1 (indicates highly viable and profitable acquisition model).',
      ),
    ],
    codeSF: [
      StudyMasterProblemDraft(
        title: 'Environmental and Social Risk Rating (ESRR) Evaluation',
        text:
            'A proposed textile dyeing unit seeking term loan of BDT 25 Crore has an Effluent Treatment Plant (ETP) with valid clearance from Department of Environment (DoE). Grade the project under Bangladesh Bank ESRM matrix.',
        solution:
            'Step 1: Sector Screening: Textile wet processing and dyeing belongs to Red Category under DoE Environmental Conservation Rules.\n'
            'Step 2: Mitigation Assessment: Operational biological ETP and valid environmental clearance certificate lower residual risk.\n'
            'Step 3: ESRR Grading: Graded as Medium-Risk subject to covenant requiring continuous real-time effluent monitoring and zero-discharge compliance.',
      ),
    ],
    codeSBB: [
      StudyMasterProblemDraft(
        title: 'Mudarabah Profit Distribution Calculation',
        text:
            'In a Mudarabah investment, bank contributes BDT 1,000,000 capital. Mudarib earns gross profit of BDT 200,000. Profit-sharing ratio is 60:40 (Bank:Mudarib). In Year 2, an unforeseen market loss of BDT 100,000 occurs without negligence. Calculate Year 1 payouts and Year 2 loss allocation.',
        solution: 'Year 1 (Profit):\n'
            '• Bank Share = 200,000 * 60% = BDT 120,000\n'
            '• Mudarib Share = 200,000 * 40% = BDT 80,000\n'
            'Year 2 (Loss):\n'
            '• Under Shariah principles, financial loss is borne 100% by Rabb-ul-Mal (Bank = BDT 100,000).\n'
            '• Mudarib suffers loss of labor/effort and receives zero management remuneration.',
      ),
    ],
    codeIB: [
      StudyMasterProblemDraft(
        title: 'IPO Share Valuation: Book Building Cut-off Price',
        text:
            'Eligible Institutional Investors bid for 10,000,000 IPO shares: 4M shares at BDT 35, 4M shares at BDT 30, and 5M shares at BDT 25. Determine the cut-off price.',
        solution:
            'Step 1: Arrange bids in descending price order with cumulative demand:\n'
            '• BDT 35: 4,000,000 shares (Cumulative: 4,000,000)\n'
            '• BDT 30: 4,000,000 shares (Cumulative: 8,000,000)\n'
            '• BDT 25: 5,000,000 shares (Cumulative: 13,000,000)\n'
            'Step 2: The total issue of 10,000,000 shares is fully subscribed at BDT 25 (where cumulative demand reaches 13M >= 10M).\n'
            'Verdict: Cut-off price is established at BDT 25.00 per share.',
      ),
    ],
    codeAFI: [
      StudyMasterProblemDraft(
        title: 'Bank Profit & Loss Statement & Loan Provisioning',
        text:
            'Interest Income = BDT 800 Cr, Interest Expense = BDT 500 Cr, Commission & Exchange = BDT 120 Cr, Operating Expenses = BDT 150 Cr. Loan loss provision required is BDT 100 Cr, Corporate Tax rate is 37.5%. Calculate Net Profit after Tax.',
        solution:
            'Step 1: Net Interest Income (NII) = 800 - 500 = BDT 300 Crore.\n'
            'Step 2: Total Operating Income = 300 + 120 = BDT 420 Crore.\n'
            'Step 3: Operating Profit = Total Operating Income - Operating Expenses = 420 - 150 = BDT 270 Crore.\n'
            'Step 4: Profit before Tax = Operating Profit - Provisions = 270 - 100 = BDT 170 Crore.\n'
            'Step 5: Corporate Tax (37.5%) = 170 * 37.5% = BDT 63.75 Crore.\n'
            'Step 6: Net Profit after Tax = 170 - 63.75 = BDT 106.25 Crore.',
      ),
    ],
    codeMA: [
      StudyMasterProblemDraft(
        title: 'Break-Even Point (BEP) in Banking Service Delivery',
        text:
            'A bank branch has annual fixed costs of BDT 60 Lac. It earns an average service fee of BDT 500 per transaction with variable cost of BDT 100 per transaction. Calculate BEP in number of transactions and revenue.',
        solution:
            'Step 1: Contribution Margin per transaction = Fee - Variable Cost = 500 - 100 = BDT 400.\n'
            'Step 2: Contribution Margin (CM) Ratio = 400 / 500 = 80%.\n'
            'Step 3: Break-Even Point (Units) = Fixed Costs / CM per unit = 6,000,000 / 400 = 15,000 transactions.\n'
            'Step 4: Break-Even Revenue = Fixed Costs / CM Ratio = 6,000,000 / 0.80 = BDT 75,00,000.',
      ),
    ],
  };

  // ===========================================================================
  // 3. PAST EXAM PAPERS MASTER CATALOG
  // ===========================================================================
  static const Map<String, List<StudyMasterPostDraft>> _pastPapersCatalog = {
    codeBA: [
      StudyMasterPostDraft(
        title: '8th BPE (2026) Basic Accounting Model Solution',
        text:
            'Comprehensive examiner-grade solution for 8th BPE Basic Accounting (BA):\n'
            '• Module A: Golden rules of accounting (Personal, Real, Nominal) vs modern accounting equation.\n'
            '• Module B: Bank Reconciliation Statement for Apex Trading.\n'
            '• Module C: Depreciation ledger schedules (Straight-line vs Diminishing balance).\n'
            '• Module D: Financial Statement ratio analysis and decision tree analytics.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (BA)',
        text:
            'Past exam papers archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Trial balance error correction, suspense account entries.\n'
            '• 97th BPE: Cash flow statement under indirect method (IAS 7).\n'
            '• 98th BPE: Cost of Goods Sold and inventory valuation (FIFO vs Weighted Average under IAS 2).\n'
            '• 99th BPE: Break-even analysis (BEP units & sales value) and margin of safety.',
      ),
    ],
    codeLPGB: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) LPGB Complete Model Solution',
        text:
            'Official dual-language solutions for 7th BPE Laws & Practice of General Banking:\n'
            '• Question 1: Section 131 NI Act collecting banker protection.\n'
            '• Question 2: Garnishee orders and mandate revocations on deceased accounts.\n'
            '• Question 3: Artha Rin Adalat Ain 2003 recovery auction rules.\n'
            '• Question 4: BFIU KYC/CDD and beneficial ownership mandates.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (LPGB)',
        text:
            'Past exam papers archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Endorsement types (blank, special, restrictive, sans recours).\n'
            '• 97th BPE: Banker\'s lien vs pledge vs hypothecation.\n'
            '• 98th BPE: Safe deposit locker liability and customer insolvency.\n'
            '• 99th BPE: Letter of Credit (UCP 600) discrepancy management.',
      ),
    ],
    codePOE: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) Principles of Economics Solutions',
        text: 'Official solutions for 7th BPE Principles of Economics:\n'
            '• Question 1: Price elasticity of demand arc formula and consumer surplus.\n'
            '• Question 2: Keynesian investment multiplier and fiscal stimulus.\n'
            '• Question 3: Bangladesh Bank monetary transmission mechanisms.\n'
            '• Question 4: Balance of Payments (Current Account vs Financial Account).',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (POE)',
        text: 'Past exam archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Perfect competition vs Monopoly equilibrium price and output.\n'
            '• 97th BPE: Phillips curve (short run vs long run trade-off).\n'
            '• 98th BPE: Demand-pull vs Cost-push inflation dynamics.\n'
            '• 99th BPE: Law of Diminishing Marginal Returns and Isoquant analysis.',
      ),
    ],
    codeMAFS: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) MAFS Complete Model Solution',
        text:
            'Official model solution for 7th BPE Monetary and Financial Systems:\n'
            '• Question 1: Measurement of M1, M2, and High-Powered Money M0.\n'
            '• Question 2: Interest rate corridor (SLF, SDF, Policy Repo Rate).\n'
            '• Question 3: Money multiplier math and credit expansion ceiling.\n'
            '• Question 4: Crawling peg exchange rate regime and reserve adequacy.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (MAFS)',
        text: 'Past exam archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Central bank balance sheet and Open Market Operations.\n'
            '• 97th BPE: Call money market interest rate volatility.\n'
            '• 98th BPE: Treasury bill auction mechanics (91, 182, 364 days).\n'
            '• 99th BPE: Role of IMF, World Bank, and BIS in banking regulation.',
      ),
    ],
    codeGFI: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) GFI Complete Model Solution',
        text:
            'Official model solution for 7th BPE Governance in Financial Institutions:\n'
            '• Question 1: True ownership of banks (depositors vs shareholders).\n'
            '• Question 2: BRPD Circular 11/2013 on Board and Management separation.\n'
            '• Question 3: Three Lines of Defense model in banking risk governance.\n'
            '• Question 4: Related-party lending abuse and Section 46 BCA 1991.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (GFI)',
        text: 'Past exam archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: BCBS 13 Corporate Governance Principles.\n'
            '• 97th BPE: Board Audit Committee terms of reference and independent directors.\n'
            '• 98th BPE: Prompt Corrective Action (PCA) framework for distressed banks.\n'
            '• 99th BPE: Whistleblower protection and ethical climate in banking.',
      ),
    ],
    codeOM: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) OM Complete Model Solution',
        text:
            'Official model solution for 7th BPE Organization and Management:\n'
            '• Question 1: Henri Fayol 14 principles vs F.W. Taylor scientific management.\n'
            '• Question 2: Maslow hierarchy vs Herzberg two-factor motivation theory.\n'
            '• Question 3: Overcoming staff resistance to core banking automation (Lewin).\n'
            '• Question 4: 360-degree performance appraisal and halo effect mitigation.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (OM)',
        text: 'Past exam archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Span of control and formal vs informal organization.\n'
            '• 97th BPE: Delegation of authority vs decentralization in branch banking.\n'
            '• 98th BPE: Blake and Mouton Managerial Grid leadership styles.\n'
            '• 99th BPE: Total Quality Management (TQM) in customer service banking.',
      ),
    ],
    codeBCFI: [
      StudyMasterPostDraft(
        title: '7th BPE (2026) BCFI Complete Model Solution',
        text: 'Official model solution for 7th BPE Business Communication:\n'
            '• Question 1: The 7 Cs of business communication with banking examples.\n'
            '• Question 2: Drafting formal legal loan recall demand notice.\n'
            '• Question 3: Drafting internal office memo on AML/KYC compliance.\n'
            '• Question 4: Minutes of meeting format for branch recovery committees.',
      ),
      StudyMasterPostDraft(
        title: '96th–99th BPE Past Exam Solutions Archive (BCFI)',
        text: 'Past exam archive covering 96th, 97th, 98th, and 99th BPE:\n'
            '• 96th BPE: Shannon-Weaver communication process model and noise.\n'
            '• 97th BPE: Semantic and psychological barriers in branch customer service.\n'
            '• 98th BPE: Non-verbal kinesics and active listening in banking.\n'
            '• 99th BPE: Digital banking customer dispute resolution communications.',
      ),
    ],
    codeRMFI: [
      StudyMasterPostDraft(
        title: 'RMFI 96th to 7th BPE Exam Question Index & Trend Analysis',
        text: 'Comprehensive review of past AIBB Risk Management sessions:\n'
            '• 96th & 97th BPE: Core Focus on Credit Risk Weighted Assets, Haircuts, and Internal Credit Risk Rating System (ICRRS).\n'
            '• 98th & 99th BPE: Operational Risk Basic Indicator Approach vs Standardized Approach; Stress Testing scenarios (Minor, Moderate, Major shocks).\n'
            '• 5th, 6th & 7th BPE: Liquidity Coverage Ratio (LCR), Net Stable Funding Ratio (NSFR), Market Risk Duration Gap analysis.',
      ),
    ],
    codeCOM: [
      StudyMasterPostDraft(
        title: 'COM Past Paper Themes & Case Study Master Solution Guide',
        text: 'Frequent examination topics across 7 BPE sessions:\n'
            '• Working Capital Assessment: MPBF Method I vs Method II comparison, Cash Budget method for seasonal industries.\n'
            '• Term Loan Evaluation: Debt Service Coverage Ratio (DSCR), Internal Rate of Return (IRR), Net Present Value (NPV).\n'
            '• Non-Performing Loans: BRPD Circular 16 rescheduling guidelines, write-off procedures, Artha Rin Adalat Ain 2003.',
      ),
    ],
    codeTFFE: [
      StudyMasterPostDraft(
        title: 'TFFE 96th to 7th BPE Exam Solution Blueprint',
        text: 'Master examiner solutions for past Trade Finance exams:\n'
            '• Discrepancies under UCPDC 600: Inconsistent descriptions, late shipment, expired LC, unauthenticated amendments.\n'
            '• Import/Export Financing: Packing Credit, EDF loans, Back-to-Back LC operations, UPAS (Usance Payable at Sight) LC.\n'
            '• Exchange Rate Mechanisms: Cross rate calculation, TT Buying vs BC Selling, Crawling Peg exchange rate band.',
      ),
    ],
    codeICTFI: [
      StudyMasterPostDraft(
        title:
            'ICTFI Exam Trends: Cyber Resilience & Core Banking Architecture',
        text: 'Core exam questions from 96th to 7th BPE:\n'
            '• SWIFT Customer Security Programme (CSP) compliance and mandatory security controls.\n'
            '• Electronic Fund Transfer systems: Real-Time Gross Settlement (RTGS), BEFTN, NPSB, and interoperable MFS.\n'
            '• Information Security Policies: Vulnerability Assessment & Penetration Testing (VAPT), Patch management, Access controls.',
      ),
    ],
    codeTMFI: [
      StudyMasterPostDraft(
        title: 'TMFI Past Exam Solutions & Money Market Instruments',
        text: 'Recurring topics across 7 Treasury Management exam sessions:\n'
            '• Asset Liability Management (ALM): Interest Rate Risk in Banking Book (IRRBB), Duration gap modeling.\n'
            '• Money Market Operations: Treasury Bills (91, 182, 364-day), Treasury Bonds (2, 5, 10, 15, 20-year), Repo and Reverse Repo.\n'
            '• Central Bank Liquidity Tools: CRR (Cash Reserve Ratio), SLR (Statutory Liquidity Ratio), Policy Repo Rate corridor.',
      ),
    ],
    codeFCC: [
      StudyMasterPostDraft(
        title: 'FCC Past Exam Solutions & AML Case Investigations',
        text: 'Key examination areas across 7 BPE compliance sessions:\n'
            '• Statutory Framework: Money Laundering Prevention Act 2012, Anti-Terrorism Act 2009, BFIU Master Circulars.\n'
            '• Customer Due Diligence: Beneficial ownership identification, PEP/IP monitoring, High-risk country transactions.\n'
            '• Trade-Based Money Laundering: Over-invoicing, under-invoicing, phantom shipments, and multiple invoicing.',
      ),
    ],
    codeAM: [
      StudyMasterPostDraft(
        title:
            'AM Exam Trends: Agricultural Financing & Microfinance Regulation',
        text: 'Frequent past paper themes:\n'
            '• Agricultural and Rural Credit Policy: Sector allocation targets, interest rate ceilings, credit disbursement monitoring.\n'
            '• MRA Act 2006: Licensing, governance, and capital requirements for NGO-MFIs in Bangladesh.\n'
            '• Financial Inclusion Mechanisms: Agent banking, mobile financial services, group lending methodologies.',
      ),
    ],
    codeMBFS: [
      StudyMasterPostDraft(
        title: 'MBFS Past Paper Solutions & Financial Services Marketing',
        text: 'Essential exam questions across 7 BPE sessions:\n'
            '• Service Marketing Mix: Managing intangibility, inseparability, variability, and perishability in banking services.\n'
            '• Brand Equity & Customer Loyalty: Brand awareness, perceived quality, brand associations, net promoter score.\n'
            '• Digital Marketing Channels: Social media banking, personalized product recommendations, CRM integration.',
      ),
    ],
    codeSF: [
      StudyMasterPostDraft(
        title: 'SF Past Exam Solutions & Green Banking Taxonomy',
        text:
            'Core exam topics from 96th to 7th BPE Sustainable Finance sessions:\n'
            '• Bangladesh Bank Green Taxonomy: Eligible green categories, renewable energy, energy efficiency, waste management.\n'
            '• Environmental and Social Risk Management (ESRM): E&S Due Diligence checklist, risk rating categorization (High, Medium, Low).\n'
            '• Climate Risk Governance: Board oversight of climate risks, carbon accounting, Green Bond issuance.',
      ),
    ],
    codeSBB: [
      StudyMasterPostDraft(
        title: 'SBB Past Exam Blueprint & Islamic Banking Contracts',
        text: 'Core past paper solutions for Shariah-Based Banking:\n'
            '• Financing Modes: Murabaha, Mudarabah, Musharakah, Bai-Muajjal, Istisna, Salam, Ijarah wa Iqtina.\n'
            '• Shariah Governance Framework: Role of Shariah Supervisory Committee, Shariah Audit, profit distribution mechanisms.\n'
            '• Deposit Products: Mudarabah Savings/Term Deposits, Al-Wadiah Current Accounts, Profit equalization reserve (PER).',
      ),
    ],
    codeIB: [
      StudyMasterPostDraft(
        title: 'IB Past Paper Solutions & Capital Market Operations',
        text: 'Recurring exam themes across 7 Investment Banking sessions:\n'
            '• Primary Market Operations: Public issue management, underwriting responsibilities, prospectus preparation, due diligence.\n'
            '• Corporate Restructuring: Mergers and Acquisitions (M&A), divestitures, corporate debt restructuring (CDR).\n'
            '• Project Financing: Debt-equity structuring, non-recourse financing, concession agreements, escrow mechanisms.',
      ),
    ],
    codeAFI: [
      StudyMasterPostDraft(
        title: 'AFI Past Exam Solutions & Bank Financial Statements',
        text:
            'Comprehensive analysis of 5 BPE Accounting for Financial Institutions sessions:\n'
            '• Statutory Financial Statements: Banking Companies Act 1991 First Schedule Balance Sheet and P&L formatting.\n'
            '• Prudential Provisioning: General provisions on unclassified loans, specific provisions on classified loans (SS, DF, BL).\n'
            '• Investment Valuation: Mark-to-market accounting for government securities (HFT vs HTM portfolio treatment).',
      ),
    ],
    codeMA: [
      StudyMasterPostDraft(
        title: 'MA Past Exam Solutions & Management Accounting Techniques',
        text: 'Core exam topics from 5 Management Accounting sessions:\n'
            '• Marginal Costing & Decision Making: Make or buy, accept or reject special orders, closing unprofitable branches.\n'
            '• Standard Costing & Variance Analysis: Material price and usage variances, labor rate and efficiency variances.\n'
            '• Budgetary Control: Master budget preparation, flexible budgeting, cash budget forecasting.',
      ),
    ],
  };

  // ===========================================================================
  // 4. HIGH-YIELD GLOSSARY CATALOG
  // ===========================================================================
  static const Map<String, List<StudyMasterGlossaryDraft>> _glossaryCatalog = {
    codeBA: [
      StudyMasterGlossaryDraft(
        term: 'Accrual Basis of Accounting (বকেয়া ভিত্তিক হিসাববিজ্ঞান)',
        definition:
            'Revenues are recognized when earned and expenses when incurred, regardless of when cash is exchanged (IAS 1).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Bank Reconciliation Statement (ব্যাংক সমন্বয় বিবরণী)',
        definition:
            'A schedule reconciling differences between cash book bank balance and bank pass book statement due to unpresented cheques, uncredited deposits, or bank charges.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Depreciation (অবচয়)',
        definition:
            'The systematic allocation of the depreciable amount of a tangible asset over its useful economic life (IAS 16).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Current Ratio (চলতি অনুপাত)',
        definition:
            'A liquidity ratio measuring short-term debt-paying ability: Current Assets divided by Current Liabilities (ideal benchmark 2:1).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Break-Even Point (সমচ্ছেদ বিন্দু)',
        definition:
            'The sales volume at which total revenues exactly equal total costs, resulting in zero profit and zero loss.',
      ),
    ],
    codeLPGB: [
      StudyMasterGlossaryDraft(
        term: 'Collecting Banker Protection (আদায়কারী ব্যাংকারের সুরক্ষা)',
        definition:
            'Statutory immunity granted under Section 131 NI Act 1881 to a banker who collects a crossed cheque in good faith and without negligence for a verified customer.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Paying Banker Protection (পরিশোধকারী ব্যাংকারের সুরক্ষা)',
        definition:
            'Statutory protection granted under Section 85 & 85A NI Act 1881 when paying order or bearer cheques in due course without apparent defect.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Garnishee Order (গার্নিশি অর্ডার)',
        definition:
            'A court order issued under Civil Procedure Code directing a bank to freeze and attach deposit balances of a judgment debtor to satisfy a decree.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Banker\'s Lien (ব্যাংকারের পূর্বস্বত্ব বা লিয়েন)',
        definition:
            'The general legal right of a banker to retain customer securities and goods in its lawful possession until all general balance debts are liquidated.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Customer Due Diligence - CDD (গ্রাহক পরিচিতি যাচাই)',
        definition:
            'Mandatory anti-money laundering procedures to identify, verify, and validate customer identity and beneficial ownership before account opening.',
      ),
    ],
    codePOE: [
      StudyMasterGlossaryDraft(
        term: 'Price Elasticity of Demand (চাহিদার দাম স্থিতিস্থাপকতা)',
        definition:
            'The percentage responsiveness of quantity demanded to a percentage change in the price of a good or service.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Keynesian Multiplier (কেইনসীয় বিনিয়োগ গুণক)',
        definition:
            'The factor by which overall national income increases in response to an initial increase in autonomous investment spending: k = 1 / (1 - MPC).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Consumer Surplus (ভোক্তার উদ্বৃত্ত)',
        definition:
            'The economic difference between the maximum price a consumer is willing to pay and the actual lower price paid in the market.',
      ),
      StudyMasterGlossaryDraft(
        term:
            'Monetary Transmission Mechanism (মুদ্রানীতির সঞ্চালন প্রক্রিয়া)',
        definition:
            'The channels (interest rate, bank lending, exchange rate, asset price) through which central bank policy decisions affect aggregate demand and inflation.',
      ),
    ],
    codeMAFS: [
      StudyMasterGlossaryDraft(
        term: 'Reserve Money - M0 (সংরক্ষিত অর্থ / উচ্চক্ষমতাসম্পন্ন মুদ্রা)',
        definition:
            'Total currency issued by Bangladesh Bank plus commercial bank reserves (vault cash and balances with the central bank).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Broad Money - M2 (বিস্তৃত অর্থ সরবরাহ)',
        definition:
            'Narrow money (M1: currency outside banks + demand deposits) plus time and savings deposits held by scheduled commercial banks.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Cash Reserve Ratio - CRR (নগদ জমা অনুপাত)',
        definition:
            'The statutory percentage of demand and time liabilities that scheduled banks must maintain as unencumbered cash with Bangladesh Bank (4.0% bi-weekly, 3.5% daily).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Policy Repo Rate (নীতিগত রেপো সুদহার)',
        definition:
            'The benchmark interest rate at which Bangladesh Bank lends short-term liquidity to commercial banks against government securities.',
      ),
    ],
    codeGFI: [
      StudyMasterGlossaryDraft(
        term: 'Fiduciary Duty (বিশ্বস্ততার দায়িত্ব)',
        definition:
            'The highest legal obligation owed by bank directors and executives to act with undivided loyalty to protect the financial interest of public depositors.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Board Audit Committee (পরিচালনা পর্ষদের নিরীক্ষা কমিটি)',
        definition:
            'A specialized board committee chaired strictly by an independent director, overseeing internal financial reporting, controls, and internal/external audit.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Three Lines of Defense (ঝুঁকি ব্যবস্থাপনার তিন সারি প্রতিরক্ষা)',
        definition:
            'A governance model: 1st line (Business units), 2nd line (Risk management & Compliance), 3rd line (Independent internal audit).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Prompt Corrective Action - PCA (দ্রুত সংশোধনমূলক ব্যবস্থা)',
        definition:
            'A structured supervisory framework by Bangladesh Bank enforcing mandatory operational restrictions on distressed banks breaching capital or NPL limits.',
      ),
    ],
    codeOM: [
      StudyMasterGlossaryDraft(
        term: 'Scalar Chain (স্তরক্রম নীতি / স্কেলার চেইন)',
        definition:
            'The unbroken line of authority and communication running from the highest executive to the lowest employee in an organization (Henri Fayol).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Herzberg\'s Two-Factor Theory (হার্জবার্গের দ্বি-উপাদান তত্ত্ব)',
        definition:
            'Distinguishes between Hygiene factors (salary, conditions) that prevent dissatisfaction and Motivators (achievement, recognition) that stimulate high performance.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Span of Control (নিয়ন্ত্রণের পরিধি)',
        definition:
            'The number of subordinate employees a manager or branch head can directly and effectively supervise.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Management by Objectives - MBO (উদ্দেশ্যভিত্তিক ব্যবস্থাপনা)',
        definition:
            'A strategic process (Peter Drucker) where managers and subordinates jointly establish clear SMART targets and evaluate performance against them.',
      ),
    ],
    codeBCFI: [
      StudyMasterGlossaryDraft(
        term: 'The 7 Cs of Communication (কার্যকর যোগাযোগের ৭টি \'সি\')',
        definition:
            'Seven principles: Completeness, Conciseness, Consideration, Clarity, Concreteness, Courtesy, and Correctness.',
      ),
      StudyMasterGlossaryDraft(
        term: '"You" Attitude (গ্রাহককেন্দ্রিক দৃষ্টিভঙ্গি)',
        definition:
            'The professional mindset of framing messages around the recipient\'s benefits and perspective rather than the sender\'s convenience.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Office Memorandum (অভ্যন্তরীণ স্মারকপত্র / মেমো)',
        definition:
            'An official written document used within an organization to convey administrative directives and notifications between departments.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Minutes of Meeting (সভার কার্যবিবরণী)',
        definition:
            'The official permanent legal record documenting proceedings, discussions, and resolutions passed during a formal meeting.',
      ),
    ],
    codeRMFI: [
      StudyMasterGlossaryDraft(
        term:
            'Capital to Risk-Weighted Assets Ratio - CRAR (মূলধন ও ঝুঁকিভিত্তিক সম্পদ অনুপাত)',
        definition:
            'The ratio of a bank\'s regulatory capital to its total risk-weighted assets (credit, market, operational risk). Bangladesh Bank requires a minimum CRAR of 10% plus 2.5% Capital Conservation Buffer.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Liquidity Coverage Ratio - LCR (তারল্য কভারেজ অনুপাত)',
        definition:
            'The proportion of high-quality liquid assets (HQLA) held by banks to survive a 30-day severe liquidity stress scenario. Statutory minimum is 100%.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Net Stable Funding Ratio - NSFR (নিট স্থিতিশীল তহবিল অনুপাত)',
        definition:
            'The amount of available stable funding relative to required stable funding over a 1-year horizon. Designed to limit over-reliance on short-term wholesale funding.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Internal Capital Adequacy Assessment Process - ICAAP (আইক্যাপ)',
        definition:
            'Pillar 2 framework under Basel III whereby a bank assesses its overall capital adequacy relative to its risk profile beyond minimum regulatory requirements.',
      ),
    ],
    codeCOM: [
      StudyMasterGlossaryDraft(
        term:
            'Maximum Permissible Bank Finance - MPBF (সর্বোচ্চ গ্রহণযোগ্য ব্যাংক ঋণ)',
        definition:
            'The statutory ceiling on working capital finance calculated by deducting borrower equity margin and other current liabilities from total current assets.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Debt Service Coverage Ratio - DSCR (ঋণ পরিশোধ সক্ষমতা অনুপাত)',
        definition:
            'Measures cash flow available for debt service divided by total debt obligations (interest plus principal installments). Benchmark is at least 1.5x.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Credit Information Bureau - CIB (ক্রেডিট ইনফরমেশন ব্যুরো)',
        definition:
            'Bangladesh Bank repository tracking credit history, outstanding obligations, and default status across all lending institutions in the country.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Non-Performing Loan - NPL (খেলাপি ঋণ)',
        definition:
            'A loan where principal or interest remains unpaid past contractual due dates, classified as Sub-standard, Doubtful, or Bad/Loss according to BRPD guidelines.',
      ),
    ],
    codeTFFE: [
      StudyMasterGlossaryDraft(
        term: 'UCPDC 600 (আন্তর্জাতিক ঋণপত্র নীতিমালা)',
        definition:
            'Uniform Customs and Practice for Documentary Credits published by ICC, governing rights, obligations, and standards of document examination for commercial letters of credit.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Incoterms 2020 (আন্তর্জাতিক বাণিজ্যিক শর্তাবলি)',
        definition:
            'Standard international trade rules published by ICC defining division of costs, risks, and transport responsibilities between buyer and seller.',
      ),
      StudyMasterGlossaryDraft(
        term: 'SWIFT MT700 (সুইফট এমটি৭০০ বার্তা)',
        definition:
            'The standard SWIFT message format used by an issuing bank to issue an irrevocable commercial letter of credit to an advising bank.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Nostro & Vostro Accounts (নস্ট্রো ও ভস্ট্রো হিসাব)',
        definition:
            'A Nostro account is our bank\'s account in foreign currency held at a bank abroad. A Vostro account is a foreign bank\'s account in local currency held with our bank.',
      ),
    ],
    codeICTFI: [
      StudyMasterGlossaryDraft(
        term: 'Core Banking Solution - CBS (সেন্ট্রাল কোর ব্যাংকিং সফটওয়্যার)',
        definition:
            'Centralized enterprise banking software enabling real-time transaction processing across all branches, ATMs, and digital banking channels.',
      ),
      StudyMasterGlossaryDraft(
        term: 'National Payment Switch Bangladesh - NPSB (জাতীয় পেমেন্ট সুইচ)',
        definition:
            'The national electronic switching system owned by Bangladesh Bank facilitating interoperability among ATM, POS, and internet banking transactions.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Recovery Time Objective - RTO (পুনরুদ্ধার সময় লক্ষ্যমাত্রা)',
        definition:
            'The maximum tolerable duration of downtime within which a business process and IT infrastructure must be restored after a disaster.',
      ),
      StudyMasterGlossaryDraft(
        term:
            'Security Operations Center - SOC (সাইবার নিরাপত্তা অপারেশন কেন্দ্র)',
        definition:
            'A centralized unit of cybersecurity professionals using SIEM tools to monitor, detect, analyze, and respond to cyber security incidents 24/7.',
      ),
    ],
    codeTMFI: [
      StudyMasterGlossaryDraft(
        term:
            'Asset Liability Committee - ALCO (সম্পদ ও দায় ব্যবস্থাপনা কমিটি)',
        definition:
            'The senior executive decision-making body in a bank responsible for managing balance sheet structure, liquidity gaps, interest rate risks, and pricing strategies.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Net Interest Margin - NIM (নিট সুদ মার্জিন)',
        definition:
            'A key profitability metric calculated as (Interest Income - Interest Expense) divided by total earning assets.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Policy Repo Rate (বাংলাদেশ ব্যাংক রেপো রেট)',
        definition:
            'The key monetary policy signaling rate at which Bangladesh Bank injects liquidity to commercial banks against government securities.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Call Money Market (কল মানি মার্কেট)',
        definition:
            'The overnight interbank money market where banks lend and borrow funds to manage temporary liquidity shortages and meet daily CRR requirements.',
      ),
    ],
    codeFCC: [
      StudyMasterGlossaryDraft(
        term:
            'Bangladesh Financial Intelligence Unit - BFIU (বাংলাদেশ ফিন্যান্সিয়াল ইন্টেলিজেন্স ইউনিট)',
        definition:
            'The central national agency of Bangladesh responsible for receiving, analyzing, and disseminating intelligence on money laundering, terrorist financing, and proliferation financing.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Cash Transaction Report - CTR (নগদ লেনদেন প্রতিবেদন)',
        definition:
            'A mandatory regulatory report filed by banks to BFIU for any physical cash deposit or withdrawal of BDT 10 Lac or above in a single day.',
      ),
      StudyMasterGlossaryDraft(
        term:
            'Suspicious Transaction Report - STR (সন্দেহজনক লেনদেন প্রতিবেদন)',
        definition:
            'An immediate confidential report filed to BFIU whenever a transaction is suspected of involving proceeds of crime or financing terrorism, regardless of amount.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Trade-Based Money Laundering - TBML (বাণিজ্যভিত্তিক অর্থপাচার)',
        definition:
            'The process of disguising the proceeds of crime and moving value through trade transactions using over-invoicing, under-invoicing, or false shipment declarations.',
      ),
    ],
    codeAM: [
      StudyMasterGlossaryDraft(
        term: 'Scale of Finance (ফসলি ঋণ নির্ধারণের অর্থমান)',
        definition:
            'The per-acre cultivation cost benchmark fixed annually by district agricultural credit committees to determine maximum crop loan limits.',
      ),
      StudyMasterGlossaryDraft(
        term:
            'Microcredit Regulatory Authority - MRA (মাইক্রোক্রেডিট রেগুলেটরি অথরিটি)',
        definition:
            'The statutory regulatory body established under MRA Act 2006 to license, monitor, and regulate non-governmental microfinance institutions in Bangladesh.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Financial Inclusion (আর্থিক অন্তর্ভুক্তি)',
        definition:
            'Ensuring access to useful and affordable financial products and services (banking, payments, credit, insurance) to unbanked and marginalized populations.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Lead Bank Scheme (লিড ব্যাংক ব্যবস্থা)',
        definition:
            'An administrative coordination framework where a designated commercial bank takes the lead in coordinating rural credit planning across a district.',
      ),
    ],
    codeMBFS: [
      StudyMasterGlossaryDraft(
        term: 'Extended Marketing Mix - 7 Ps (সেবা বিপণনের ৭টি উপাদান)',
        definition:
            'The service marketing framework encompassing Product, Price, Place, Promotion, People, Process, and Physical Evidence.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Customer Lifetime Value - CLV (গ্রাহক আজীবন মূল্য)',
        definition:
            'The projected total net profit attributed to the entire future relationship with a bank customer across all products and deposit accounts.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Net Promoter Score - NPS (গ্রাহক সন্তুষ্টি সূচক)',
        definition:
            'A customer satisfaction metric measuring likelihood of recommending a bank, categorized into Promoters (9-10), Passives (7-8), and Detractors (0-6).',
      ),
      StudyMasterGlossaryDraft(
        term: 'Agent Banking (এজেন্ট ব্যাংকিং ব্যবস্থা)',
        definition:
            'Delivering regulated banking services outside traditional bank branches through accredited third-party agents using biometric POS terminals and CBS integration.',
      ),
    ],
    codeSF: [
      StudyMasterGlossaryDraft(
        term: 'Green Taxonomy (সবুজ অর্থায়ন শ্রেণিবিন্যাস)',
        definition:
            'Bangladesh Bank\'s comprehensive classification system identifying economic activities and technologies that contribute directly to environmental sustainability.',
      ),
      StudyMasterGlossaryDraft(
        term:
            'Environmental & Social Risk Management - ESRM (পরিবেশ ও সামাজিক ঝুঁকি ব্যবস্থাপনা)',
        definition:
            'A mandatory framework for evaluating and mitigating environmental degradation, pollution, and social impacts of commercial loan proposals.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Green Transformation Fund - GTF (সবুজ রূপান্তর তহবিল)',
        definition:
            'A specialized central bank refinancing window facilitating long-term foreign and local currency financing for green export-oriented industries.',
      ),
      StudyMasterGlossaryDraft(
        term: 'ESG Standards (পরিবেশ, সামাজিক ও সুশাসন মানদণ্ড)',
        definition:
            'Environmental, Social, and Governance criteria used by institutional investors to evaluate corporate ethics, sustainability footprint, and risk resilience.',
      ),
    ],
    codeSBB: [
      StudyMasterGlossaryDraft(
        term: 'Mudarabah & Musharakah (মুদারাবা ও মুশারাকা)',
        definition:
            'Mudarabah is profit-sharing partnership where financier provides capital and manager provides expertise. Musharakah is joint equity partnership where all parties contribute capital.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Murabaha (মুরাবাহা ক্রয়-বিক্রয় চুক্তি)',
        definition:
            'A cost-plus sale contract where the bank purchases an asset on behalf of a customer and sells it to the customer at an agreed markup price with deferred payment.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Bai-Salam & Istisna (বাই-সালাম ও ইসতিসনা)',
        definition:
            'Bai-Salam is advance payment for future delivery of agricultural goods. Istisna is a manufacturing contract where payment and delivery can be staged.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Sukuk (ইসলামী বন্ড / সুকুক)',
        definition:
            'Shariah-compliant investment certificates representing undivided ownership shares in underlying tangible assets, usufructs, or services.',
      ),
    ],
    codeIB: [
      StudyMasterGlossaryDraft(
        term: 'Initial Public Offering - IPO (প্রাথমিক গণপ্রস্তাব)',
        definition:
            'The process through which a private corporation issues shares of common stock to the general public for the first time to raise equity capital.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Book Building Method (বুক বিল্ডিং পদ্ধতি)',
        definition:
            'A price discovery mechanism where institutional bids within an indicative price band determine the final cut-off price of public issue shares.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Underwriting (দায়গ্রহণ চুক্তি)',
        definition:
            'An agreement whereby an investment bank guarantees to purchase any unsold portion of newly issued securities at an agreed price, eliminating issuer risk.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Syndicated Financing (সিন্ডিকেট অর্থায়ন)',
        definition:
            'A financing facility arranged by a lead manager where a group of commercial banks and FIs collectively provide large-scale term loan funds for infrastructure projects.',
      ),
    ],
    codeAFI: [
      StudyMasterGlossaryDraft(
        term:
            'First Schedule Form A & B (ব্যাংক ব্যালান্স শিট ও লাভ-ক্ষতি হিসাব ফরম)',
        definition:
            'The statutory financial statement templates mandated by the Banking Companies Act 1991 for all scheduled banks operating in Bangladesh.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Held for Trading - HFT (লেনদেনের জন্য রক্ষিত সিকিউরিটিজ)',
        definition:
            'Securities acquired primarily for generating profit from short-term price fluctuations, marked-to-market with unrealized gains/losses routed to profit & loss or reserves.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Held to Maturity - HTM (মেয়াদপূর্তি পর্যন্ত রক্ষিত সিকিউরিটিজ)',
        definition:
            'Securities that the bank has positive intent and ability to hold until contractual maturity, carried at amortized cost rather than market valuation.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Loan Loss Provision (ঋণ ক্ষতি সঞ্চিতি)',
        definition:
            'An expense set aside as an allowance for uncollectible loans, calculated strictly according to Bangladesh Bank prudential classification standards.',
      ),
    ],
    codeMA: [
      StudyMasterGlossaryDraft(
        term: 'Break-Even Point - BEP (আয়-ব্যয় সমতা বিন্দু)',
        definition:
            'The volume of sales or transactions at which total revenue exactly equals total costs (both fixed and variable), yielding zero profit and zero loss.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Margin of Safety - MoS (নিরাপত্তা প্রান্ত)',
        definition:
            'The excess of budgeted or actual sales revenue over the break-even sales revenue, representing the buffer before the entity incurs financial losses.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Activity-Based Costing - ABC (কার্যক্রমভিত্তিক ব্যয় নির্ধারণ)',
        definition:
            'A costing methodology that identifies organizational activities and assigns indirect overhead costs to products and banking services based on actual resource consumption.',
      ),
      StudyMasterGlossaryDraft(
        term: 'Contribution Margin (অবদান মার্জিন)',
        definition:
            'Sales revenue minus all variable expenses, representing the incremental cash flow generated to cover fixed overhead costs and produce operational profits.',
      ),
    ],
  };
}

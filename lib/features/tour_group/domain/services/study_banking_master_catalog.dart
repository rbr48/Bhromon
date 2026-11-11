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

  static const List<String> allSubjectCodes = [
    codeBA,
    codeLPGB,
    codePOE,
    codeMAFS,
    codeGFI,
    codeOM,
    codeBCFI,
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
  };
}

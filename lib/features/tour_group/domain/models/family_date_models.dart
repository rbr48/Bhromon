import 'tour_group.dart';

// A date a family keeps: a birthday, an anniversary, a bill, a school day or a
// medicine time. Stored under `tours/{id}/family_dates`. The reminder job
// (`media-server/family_dates.py`) moves its next day on; the app computes the
// same rules in `family_date_rules.dart`.

// What a family date is about. Each kind has its own emoji.
enum FamilyDateKind {
  birthday('🎂'),
  anniversary('💍'),
  bill('🧾'),
  school('🎒'),
  medicine('💊'),
  meeting('🤝'),
  deadline('⏳'),
  exam('📝'),
  rent('🏠'),
  maintenance('🛠️'),
  installment('💰'),
  payout('🎁'),
  event('🎉'),
  custom('📅');

  const FamilyDateKind(this.emoji);

  final String emoji;

  /// An unknown stored kind reads as a custom date, so nothing is lost.
  static FamilyDateKind fromName(Object? raw) => FamilyDateKind.values
      .firstWhere((k) => k.name == raw, orElse: () => FamilyDateKind.custom);
}

/// How often a family date comes round. An unknown stored value reads as once,
/// so an unreadable repeat never reminds people again and again.
enum FamilyRecurrence {
  once,
  monthly,
  yearly;

  static FamilyRecurrence fromName(Object? raw) => FamilyRecurrence.values
      .firstWhere((r) => r.name == raw, orElse: () => FamilyRecurrence.once);
}

/// The reminder choices the app offers, in days before the date.
const List<int> kFamilyRemindChoices = [0, 1, 3, 7];

/// The longest a reminder may come before a date. The rules allow up to this.
const int kFamilyRemindMaxDays = 30;

final RegExp _dayKeyPattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// The day `YYYY-MM-DD` as a date, or null when it is not a real calendar day
/// (30 February, or a month of 13).
DateTime? parseFamilyDay(String? raw) {
  if (raw == null || !_dayKeyPattern.hasMatch(raw)) return null;
  final year = int.parse(raw.substring(0, 4));
  final month = int.parse(raw.substring(5, 7));
  final day = int.parse(raw.substring(8, 10));
  if (month < 1 || month > 12) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

class FamilyDate {
  const FamilyDate({
    required this.id,
    required this.title,
    required this.kind,
    required this.recurrence,
    required this.startOn,
    required this.nextOn,
    required this.remindDays,
    this.remindOn,
    this.note = '',
    this.createdByEmail = '',
  });

  final String id;
  final String title;
  final FamilyDateKind kind;
  final FamilyRecurrence recurrence;

  /// The first day of the date, as `YYYY-MM-DD`.
  final String startOn;

  /// The day the reminder job last left as next. Shown only as a fallback: the
  /// list works out the next day from [startOn] and today.
  final String nextOn;

  /// How many days before the date the reminder goes out.
  final int remindDays;

  /// The day the next reminder is due, or null when none is.
  final String? remindOn;

  final String note;

  /// The member who added the date. Only they, or an admin, change it.
  final String createdByEmail;

  Map<String, dynamic> toMap() => {
        'title': title,
        'kind': kind.name,
        'recurrence': recurrence.name,
        'startOn': startOn,
        'nextOn': nextOn,
        'remindDays': remindDays,
        'remindOn': remindOn,
        'note': note,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored date. Returns null when it has no usable title or start day,
  /// so a damaged record does not break the list.
  static FamilyDate? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final startOn = map['startOn'] as String?;
    if (startOn == null || title.isEmpty || parseFamilyDay(startOn) == null) {
      return null;
    }
    final nextOn = map['nextOn'] as String?;
    final remindOn = map['remindOn'] as String?;
    final remind = map['remindDays'];
    final days = remind is num ? remind.toInt() : kFamilyRemindChoices.first;
    return FamilyDate(
      id: id,
      title: title,
      kind: FamilyDateKind.fromName(map['kind']),
      recurrence: FamilyRecurrence.fromName(map['recurrence']),
      startOn: startOn,
      nextOn: parseFamilyDay(nextOn) != null ? nextOn! : startOn,
      remindDays: days < 0
          ? 0
          : (days > kFamilyRemindMaxDays ? kFamilyRemindMaxDays : days),
      remindOn: parseFamilyDay(remindOn) != null ? remindOn : null,
      note: (map['note'] as String?) ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}

/// A preset template for a group date, tailored to the group's needs.
class GroupDatePresetTemplate {
  const GroupDatePresetTemplate({
    required this.titleEn,
    required this.titleBn,
    required this.kind,
    required this.recurrence,
    this.remindDays = 1,
    this.noteEn = '',
    this.noteBn = '',
  });

  final String titleEn;
  final String titleBn;
  final FamilyDateKind kind;
  final FamilyRecurrence recurrence;
  final int remindDays;
  final String noteEn;
  final String noteBn;
}

/// The available date kinds tailored for [group].
List<FamilyDateKind> kindsForGroup(TourGroup? group) {
  if (group == null) return FamilyDateKind.values;
  if (group.isOffice) {
    return const [
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.anniversary,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (group.isCampus) {
    return const [
      FamilyDateKind.exam,
      FamilyDateKind.deadline,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.meeting,
      FamilyDateKind.custom,
    ];
  }
  if (group.isMess) {
    return const [
      FamilyDateKind.rent,
      FamilyDateKind.bill,
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.custom,
    ];
  }
  if (group.isSociety) {
    return const [
      FamilyDateKind.maintenance,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (group.isSamity) {
    return const [
      FamilyDateKind.installment,
      FamilyDateKind.payout,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (group.isStudy) {
    return const [
      FamilyDateKind.deadline,
      FamilyDateKind.exam,
      FamilyDateKind.meeting,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (!group.isFamily) {
    // Trip
    return const [
      FamilyDateKind.event,
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.custom,
    ];
  }
  // Family / Household
  return const [
    FamilyDateKind.birthday,
    FamilyDateKind.anniversary,
    FamilyDateKind.bill,
    FamilyDateKind.school,
    FamilyDateKind.medicine,
    FamilyDateKind.event,
    FamilyDateKind.custom,
  ];
}

/// Suggested preset templates for [group] to quickly add important milestones.
List<GroupDatePresetTemplate> presetTemplatesFor(TourGroup? group) {
  if (group == null) return const [];
  if (group.isOffice) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Project Sprint Deadline',
        titleBn: 'স্প্রিন্ট ডেডলাইন',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Deliverable submission & QA signoff',
        noteBn: 'প্রজেক্ট ডেলিভারি ও কিউএ সাইন-অফ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Monthly Payroll / Salary',
        titleBn: 'বেতন ও পারিশ্রমিক পরিশোধ',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Disbursement of team salaries and allowances',
        noteBn: 'মাসিক বেতন ও ভাতা বিতরণ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Team Retrospective Meeting',
        titleBn: 'টিম রেট্রোস্পেক্টিভ ও পর্যালোচনা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Monthly progress sync and sprint planning',
        noteBn: 'মাসিক কাজের অগ্রগতি পর্যালোচনা ও পরবর্তী পরিকল্পনা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Quarterly Business Review',
        titleBn: 'কোয়ার্টারলি বিজনেস রিভিউ (QBR)',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 7,
        noteEn: 'Quarterly KPI and OKR evaluation',
        noteBn: 'ত্রৈমাসিক পারফরম্যান্স ও লক্ষ্য মূল্যায়ন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Company Anniversary',
        titleBn: 'কোম্পানি প্রতিষ্ঠা বার্ষিকী',
        kind: FamilyDateKind.anniversary,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 7,
        noteEn: 'Annual foundation celebration',
        noteBn: 'বার্ষিক প্রতিষ্ঠা উদযাপন ও উৎসব',
      ),
    ];
  }
  if (group.isCampus) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Final Examination',
        titleBn: 'সেমিস্টার ফাইনাল পরীক্ষা',
        kind: FamilyDateKind.exam,
        recurrence: FamilyRecurrence.once,
        remindDays: 7,
        noteEn: 'Term final exams commence',
        noteBn: 'সেমিস্টার ফাইনাল পরীক্ষার শুরুর তারিখ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Assignment / Project Submission',
        titleBn: 'অ্যাসাইনমেন্ট / প্রজেক্ট জমা',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Final deadline for report submission',
        noteBn: 'রিপোর্ট বা অ্যাসাইনমেন্ট জমার শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Semester Fee Payment',
        titleBn: 'সেমিস্টার ফি পরিশোধ',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Tuition and registration fee cutoff',
        noteBn: 'টিউশন ফি ও রেজিস্ট্রেশন জমার শেষ তারিখ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Batch Reunion / Rag Day',
        titleBn: 'ব্যাচ রিইউনিয়ন / র‍্যাগ ডে',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 7,
        noteEn: 'Batch celebration and cultural event',
        noteBn: 'ব্যাচের বন্ধুদের পুনর্মিলনী ও অনুষ্ঠান',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Defense / Presentation Day',
        titleBn: 'প্রেজেন্টেশন ও থিসিস ডিফেন্স',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Project presentation in front of the board',
        noteBn: 'বোর্ডের সামনে প্রেজেন্টেশন ও মৌখিক পরীক্ষা',
      ),
    ];
  }
  if (group.isMess) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Monthly House Rent',
        titleBn: 'মাসিক মেস ভাড়া',
        kind: FamilyDateKind.rent,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Flat rent due to landlord',
        noteBn: 'বাড়িওয়ালাকে বাসা ভাড়া পরিশোধের শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Mess Meal Calculation & Audit',
        titleBn: 'মাসিক মিল হিসাব সমাপনী',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Closing meal records and calculating meal rate',
        noteBn: 'মাসের মিল হিসাব ফাইনাল ও মিল রেট নির্ধারণ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Electricity & Utility Bills',
        titleBn: 'বিদ্যুৎ ও গ্যাস বিল',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Monthly utility bill payment',
        noteBn: 'মাসের বিদ্যুৎ, গ্যাস ও ওয়াইফাই বিল পরিশোধ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Bazar Duty Handover',
        titleBn: 'বাজার ডিউটি পরিবর্তন',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Monthly bazar duty rotation',
        noteBn: 'বাজারের দায়িত্ব পরবর্তী সদস্যদের বুঝিয়ে দেওয়া',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Mess General Meeting',
        titleBn: 'মেস সাধারণ সভা ও বৈঠক',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Monthly discussion on mess rules and food menu',
        noteBn: 'খাবারের মান, মেস নিয়মাবলী ও খরচ পর্যালোচনা',
      ),
    ];
  }
  if (group.isSociety) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Monthly Maintenance Charge',
        titleBn: 'মাসিক সার্ভিস চার্জ',
        kind: FamilyDateKind.maintenance,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Flat maintenance collection cutoff',
        noteBn: 'ফ্ল্যাট সার্ভিস ও মেইনটেন্যান্স চার্জ জমার শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Annual General Meeting (AGM)',
        titleBn: 'বার্ষিক সাধারণ সভা (AGM)',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 14,
        noteEn: 'Annual committee report and election',
        noteBn: 'সোসাইটির বাৎসরিক হিসাব ও নতুন কমিটি নির্বাচন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Building Committee Meeting',
        titleBn: 'পরিচালনা পর্ষদের মাসিক সভা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 2,
        noteEn: 'Monthly society executive meeting',
        noteBn: 'বিল্ডিং পরিচালনা পর্ষদের মাসিক বৈঠক',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Water Tank Cleaning & Pest Control',
        titleBn: 'পানির ট্যাংক পরিষ্কার ও পেস্ট কন্ট্রোল',
        kind: FamilyDateKind.maintenance,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Building rooftop and underground tank cleaning',
        noteBn: 'ছাদ ও আন্ডারগ্রাউন্ড পানির ট্যাংক পরিষ্কার',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Generator & Lift Servicing',
        titleBn: 'লিফট ও জেনারেটর সার্ভিসিং',
        kind: FamilyDateKind.maintenance,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Periodic lift and generator inspection',
        noteBn: 'লিফট ও জেনারেটরের মাসিক টেকনিক্যাল অডিট',
      ),
    ];
  }
  if (group.isSamity) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Monthly Installment Due',
        titleBn: 'মাসিক কিস্তি জমার শেষ দিন',
        kind: FamilyDateKind.installment,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Monthly savings contribution deposit',
        noteBn: 'সমিতির মাসিক সঞ্চয় কিস্তি জমা করার শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Lottery Draw & Payout Handover',
        titleBn: 'লটারি ড্র ও কিস্তি হস্তান্তর',
        kind: FamilyDateKind.payout,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 2,
        noteEn: 'Distribution of the rotation fund',
        noteBn: 'লটারি ড্র ও বিজয়ী সদস্যকে জমার টাকা বুঝিয়ে দেওয়া',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Annual Financial Audit',
        titleBn: 'বার্ষিক আর্থিক অডিট ও হিসাব',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 7,
        noteEn: 'Year-end savings review and profit sharing',
        noteBn: 'বাৎসরিক সঞ্চয় ও লাভ-ক্ষতির চূড়ান্ত অডিট',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Executive Committee Meeting',
        titleBn: 'সমিতির কার্যনির্বাহী সভা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Monthly review of member accounts',
        noteBn: 'সদস্যদের জমা হিসাব ও সমিতি পরিচালনা সংক্রান্ত বৈঠক',
      ),
    ];
  }
  if (group.isStudy) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Book Discussion Session',
        titleBn: 'বই আলোচনা ও রিভিউ বৈঠক',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Group exchange on current reading book',
        noteBn: 'চলতি বইয়ের বিষয়বস্তু নিয়ে গ্রুপ ডিসকাশন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Reading Target Deadline',
        titleBn: 'বই শেষ করার নির্ধারিত তারিখ',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Finish reading selected chapters',
        noteBn: 'নির্ধারিত অধ্যায় বা পুরো বই পাঠ সম্পন্ন করা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Study Model Test / Quiz',
        titleBn: 'মডেল টেস্ট বা কুইজ প্রতিযোগিতা',
        kind: FamilyDateKind.exam,
        recurrence: FamilyRecurrence.once,
        remindDays: 5,
        noteEn: 'Evaluation quiz on study topic',
        noteBn: 'পঠিত বিষয়ের উপর প্রস্তুতি ও কুইজ পরীক্ষা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Weekly Study Review',
        titleBn: 'সাপ্তাহিক স্টাডি পর্যালোচনা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        noteEn: 'Weekly recap and next chapter assignment',
        noteBn: 'সাপ্তাহিক সারসংক্ষেপ ও পরবর্তী বই নির্ধারণ',
      ),
    ];
  }
  if (!group.isFamily) {
    // Trip
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Trip Departure Date',
        titleBn: 'ট্যুর যাত্রা শুরুর দিন',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        noteEn: 'Tour start and journey departure',
        noteBn: 'যাত্রার উদ্দেশ্যে রওনা ও চেকপয়েন্ট জমায়েত',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Return & Wrap-up Day',
        titleBn: 'ট্যুর সমাপ্তি ও প্রত্যাবর্তন',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        noteEn: 'Journey back home',
        noteBn: 'গন্তব্য থেকে ঘরে ফেরার দিন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Booking Advance Cutoff',
        titleBn: 'হোটেল বা টিকিট বুকিং অগ্রিম শেষ সময়',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Advance payment for hotels and vehicles',
        noteBn: 'পরিবহন ও হোটেল রিজার্ভেশন কনফার্মেশনের শেষ তারিখ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Pre-trip Briefing Meeting',
        titleBn: 'ট্যুর পূর্ব প্রস্তুতি ও ব্রিফিং সভা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        noteEn: 'Route discussion and luggage guidelines',
        noteBn: 'রুট আলোচনা, রুলস ও লাগেজ চেকলিস্ট পর্যালোচনা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Final Fund Settlement',
        titleBn: 'ট্যুর খরচ ও হিসাব সমাপনী',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Final audit and clearing balances in the ledger',
        noteBn: 'লেজারের চূড়ান্ত খরচ হিসাব ও বাকি টাকা সমন্বয়',
      ),
    ];
  }
  // Household / Family
  return const [
    GroupDatePresetTemplate(
      titleEn: 'Birthday',
      titleBn: 'জন্মদিন',
      kind: FamilyDateKind.birthday,
      recurrence: FamilyRecurrence.yearly,
      remindDays: 3,
      noteEn: 'Annual birthday celebration',
      noteBn: 'পরিবারের সদস্যের শুভ জন্মদিন',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Wedding Anniversary',
      titleBn: 'বিবাহবার্ষিকী',
      kind: FamilyDateKind.anniversary,
      recurrence: FamilyRecurrence.yearly,
      remindDays: 7,
      noteEn: 'Family wedding milestone celebration',
      noteBn: 'বিবাহবার্ষিকী উদযাপন ও শুভেচ্ছা',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Utility Bill Payment',
      titleBn: 'বিদ্যুৎ বা গ্যাস বিল পরিশোধ',
      kind: FamilyDateKind.bill,
      recurrence: FamilyRecurrence.monthly,
      remindDays: 3,
      noteEn: 'Monthly household utility bill cutoff',
      noteBn: 'মাসের গ্যাস, বিদ্যুৎ বা ইন্টারনেট বিল জমার শেষ সময়',
    ),
    GroupDatePresetTemplate(
      titleEn: 'School Term Reopening / Exam',
      titleBn: 'স্কুল খোলা বা পরীক্ষার তারিখ',
      kind: FamilyDateKind.school,
      recurrence: FamilyRecurrence.once,
      remindDays: 3,
      noteEn: 'School fees and examination timeline',
      noteBn: 'বাচ্চাদের নতুন ক্লাস বা পরীক্ষার সময়সূচি',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Medical Checkup & Prescription',
      titleBn: 'স্বাস্থ্য পরীক্ষা ও প্রেসক্রিপশন ফলোআপ',
      kind: FamilyDateKind.medicine,
      recurrence: FamilyRecurrence.once,
      remindDays: 3,
      noteEn: 'Routine doctor visit or medicine refill',
      noteBn: 'ডাক্তারের ফলোআপ ভিজিট বা নিয়মিত ওষুধ সংগ্রহ',
    ),
  ];
}

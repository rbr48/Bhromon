import '../../../../core/localization/app_localizations.dart';
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
  if (group == null) {
    return const [
      FamilyDateKind.event,
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.custom,
    ];
  }
  final effective = group.effectivePreset;
  if (effective == TourGroup.officePreset) {
    return const [
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.anniversary,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.campusPreset) {
    return const [
      FamilyDateKind.exam,
      FamilyDateKind.deadline,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.meeting,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.messPreset) {
    return const [
      FamilyDateKind.rent,
      FamilyDateKind.bill,
      FamilyDateKind.deadline,
      FamilyDateKind.meeting,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.societyPreset) {
    return const [
      FamilyDateKind.maintenance,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.samityPreset) {
    return const [
      FamilyDateKind.installment,
      FamilyDateKind.payout,
      FamilyDateKind.meeting,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.studyPreset) {
    return const [
      FamilyDateKind.deadline,
      FamilyDateKind.exam,
      FamilyDateKind.meeting,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.friendsPreset) {
    return const [
      FamilyDateKind.event,
      FamilyDateKind.birthday,
      FamilyDateKind.meeting,
      FamilyDateKind.deadline,
      FamilyDateKind.bill,
      FamilyDateKind.anniversary,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.schoolPreset) {
    return const [
      FamilyDateKind.exam,
      FamilyDateKind.meeting,
      FamilyDateKind.deadline,
      FamilyDateKind.bill,
      FamilyDateKind.event,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.sportsPreset) {
    return const [
      FamilyDateKind.event,
      FamilyDateKind.meeting,
      FamilyDateKind.deadline,
      FamilyDateKind.bill,
      FamilyDateKind.custom,
    ];
  }
  if (effective == TourGroup.committeePreset) {
    return const [
      FamilyDateKind.meeting,
      FamilyDateKind.maintenance,
      FamilyDateKind.bill,
      FamilyDateKind.deadline,
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
  if (group.isHousehold && effective == null) {
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
  return const [
    FamilyDateKind.event,
    FamilyDateKind.deadline,
    FamilyDateKind.meeting,
    FamilyDateKind.bill,
    FamilyDateKind.custom,
  ];
}

/// Suggested preset templates for [group] to quickly add important milestones.
List<GroupDatePresetTemplate> presetTemplatesFor(TourGroup? group) {
  if (group == null) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Important Event & Milestone',
        titleBn: 'গুরুত্বপূর্ণ অনুষ্ঠান বা আয়োজন',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Special occasion and group milestone',
        noteBn: 'বিশেষ আয়োজন বা গ্রুপের গুরুত্বপূর্ণ দিন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Project / Task Deadline',
        titleBn: 'জরুরি ডেডলাইন',
        kind: FamilyDateKind.deadline,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Deadline for key deliverables',
        noteBn: 'নির্ধারিত কাজ শেষ করার শেষ তারিখ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Group Meeting & Sync',
        titleBn: 'গ্রুপ মিটিং বা আলোচনা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        noteEn: 'Group discussion and alignment',
        noteBn: 'সদস্যদের পারস্পরিক আলোচনা ও প্রস্তুতি',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Due Payment / Contribution',
        titleBn: 'পেমেন্ট বা চাঁদা পরিশোধ',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Payment or contribution cutoff',
        noteBn: 'বিল, চাঁদা বা পাওনা পরিশোধের শেষ সময়',
      ),
    ];
  }
  final effective = group.effectivePreset;
  if (effective == TourGroup.officePreset) {
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
  if (effective == TourGroup.campusPreset) {
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
  if (effective == TourGroup.messPreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Monthly House Rent',
        titleBn: 'মাসিক বাড়ি ভাড়া পরিশোধ',
        kind: FamilyDateKind.rent,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Flat rent due to landlord',
        noteBn: 'বাড়িওয়ালার মাসিক ফ্ল্যাট ভাড়া পরিশোধের শেষ দিন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Monthly Meal Calculation & Bazar',
        titleBn: 'মাসিক মিল ও বাজার হিসাব সমাপনী',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Month-end meal count and balance settlement',
        noteBn: 'মাসের মিল রেট ও বাজার খরচের হিসাব মেলানো',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Mess Committee Meeting',
        titleBn: 'মেস সদস্যদের মাসিক বৈঠক',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Menu, cook salary & chores discussion',
        noteBn: 'খালা বিল, মেনু ও মেসের নতুন নিয়ম আলোচনা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Gas & Electricity Bill',
        titleBn: 'গ্যাস, বিদ্যুৎ ও ওয়াইফাই বিল',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Shared apartment utility bills cutoff',
        noteBn: 'মাসের ইউটিলিটি বিল পরিশোধের শেষ তারিখ',
      ),
    ];
  }
  if (effective == TourGroup.societyPreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Monthly Maintenance Service Charge',
        titleBn: 'মাসিক সার্ভিস চার্জ ও রক্ষণাবেক্ষণ ফি',
        kind: FamilyDateKind.maintenance,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 5,
        noteEn: 'Building upkeep, security & cleanliness dues',
        noteBn: 'ফ্ল্যাট মালিকদের মাসিক সার্ভিস চার্জ জমার শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Annual General Meeting (AGM)',
        titleBn: 'বার্ষিক সাধারণ সভা (AGM)',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 7,
        noteEn: 'Annual society committee election & budget review',
        noteBn: 'সোসাইটির বার্ষিক পর্যালোচনা, নির্বাচন ও বাজেট সভা',
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
  if (effective == TourGroup.samityPreset) {
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
  if (effective == TourGroup.studyPreset) {
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
  if (effective == TourGroup.friendsPreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Weekend Adda & Dinner',
        titleBn: 'উইকেন্ড আড্ডা ও ডিনার',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Casual gathering and food hangout',
        noteBn: 'বন্ধুদের জমজমাট আড্ডা ও খাওয়া-দাওয়া',
      ),
      GroupDatePresetTemplate(
        titleEn: "Friend's Birthday Celebration",
        titleBn: 'বন্ধুর জন্মদিন উদযাপন',
        kind: FamilyDateKind.birthday,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 3,
        noteEn: 'Cake cutting and surprise hangout',
        noteBn: 'কেক কাটা ও বন্ধুদের সারপ্রাইজ পার্টি',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Batch Reunion & Get-together',
        titleBn: 'ব্যাচ পুনর্মিলনী ও আড্ডা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 7,
        noteEn: 'Batch reunion and friends meetup',
        noteBn: 'স্কুল/কলেজ বন্ধুদের পুনর্মিলনী ও দেখা সাক্ষাৎ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Day Tour & Outing Plan',
        titleBn: 'বন্ধুদের ডে ট্যুর / ঘোরাঘুরি',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Day trip or resort hangout',
        noteBn: 'একদিনের ট্যুর বা রিসোর্টে আড্ডা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Friendship Day Celebration',
        titleBn: 'ফ্রেন্ডশিপ ডে উদযাপন',
        kind: FamilyDateKind.anniversary,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 3,
        noteEn: 'Celebrating bond and memories',
        noteBn: 'বন্ধুত্বের বিশেষ দিন ও স্মৃতিচারণ',
      ),
    ];
  }
  if (effective == TourGroup.schoolPreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Term Final Examination',
        titleBn: 'সাময়িক / ফাইনাল পরীক্ষা',
        kind: FamilyDateKind.exam,
        recurrence: FamilyRecurrence.once,
        remindDays: 7,
        noteEn: 'Term final exams commencement',
        noteBn: 'সাময়িক বা বার্ষিক পরীক্ষার শুরুর তারিখ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Parent-Teacher Meeting (PTM)',
        titleBn: 'অভিভাবক ও শিক্ষক সমাবেশ',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Academic progress and discussion',
        noteBn: 'শিক্ষার্থীদের ফলাফল ও অগ্রগতি আলোচনা সভা',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Tuition Fee Due Date',
        titleBn: 'স্কুল ফি বা বেতন জমার শেষ তারিখ',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Monthly school fee cutoff',
        noteBn: 'মাসিক বেতন ও ফি পরিশোধের শেষ সময়',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Annual Sports & Cultural Day',
        titleBn: 'বার্ষিক ক্রীড়া ও সাংস্কৃতিক অনুষ্ঠান',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.yearly,
        remindDays: 7,
        noteEn: 'Annual competitions and prize ceremony',
        noteBn: 'বার্ষিক প্রতিযোগিতা ও পুরস্কার বিতরণী',
      ),
    ];
  }
  if (effective == TourGroup.sportsPreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Tournament Match Day',
        titleBn: 'টুর্নামেন্ট ম্যাচ ডে',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        remindDays: 2,
        noteEn: 'Tournament match fixture',
        noteBn: 'টুর্নামেন্টের গুরুত্বপূর্ণ ম্যাচ',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Weekly Practice & Training',
        titleBn: 'সাপ্তাহিক অনুশীলন ও ট্রেনিং',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 1,
        noteEn: 'Regular team practice session',
        noteBn: 'দলের নিয়মিত ট্রেনিং ও প্রস্তুতি সেশন',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Club Membership Renewal',
        titleBn: 'ক্লাব মেম্বারশিপ ফি পরিশোধ',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Monthly gym or sports club subscription',
        noteBn: 'মাসিক জিম বা স্পোর্টস ক্লাব সাবস্ক্রিপশন',
      ),
    ];
  }
  if (effective == TourGroup.committeePreset) {
    return const [
      GroupDatePresetTemplate(
        titleEn: 'Committee General Meeting',
        titleBn: 'কমিটির সাধারণ সভা',
        kind: FamilyDateKind.meeting,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 2,
        noteEn: 'Community management monthly review',
        noteBn: 'এলাকা পরিচালনা ও উন্নয়ন সংক্রান্ত মাসিক বৈঠক',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Community Cleanliness Drive',
        titleBn: 'এলাকা পরিচ্ছন্নতা অভিযান',
        kind: FamilyDateKind.maintenance,
        recurrence: FamilyRecurrence.once,
        remindDays: 3,
        noteEn: 'Neighborhood cleanup activity',
        noteBn: 'এলাকার পরিবেশ ও পরিচ্ছন্নতা কর্মসূচি',
      ),
      GroupDatePresetTemplate(
        titleEn: 'Community Upkeep Collection',
        titleBn: 'উন্নয়ন ও রক্ষণাবেক্ষণ চাঁদা',
        kind: FamilyDateKind.bill,
        recurrence: FamilyRecurrence.monthly,
        remindDays: 3,
        noteEn: 'Monthly neighbourhood maintenance dues',
        noteBn: 'মাসিক রক্ষণাবেক্ষণ ও নিরাপত্তা চাঁদা সংগ্রহ',
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
  if (group.isHousehold && effective == null) {
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
  // Generic non-household group fallback
  return const [
    GroupDatePresetTemplate(
      titleEn: 'Important Event & Milestone',
      titleBn: 'গুরুত্বপূর্ণ অনুষ্ঠান বা আয়োজন',
      kind: FamilyDateKind.event,
      recurrence: FamilyRecurrence.once,
      remindDays: 3,
      noteEn: 'Special occasion and group milestone',
      noteBn: 'বিশেষ আয়োজন বা গ্রুপের গুরুত্বপূর্ণ দিন',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Project / Task Deadline',
      titleBn: 'জরুরি ডেডলাইন',
      kind: FamilyDateKind.deadline,
      recurrence: FamilyRecurrence.once,
      remindDays: 2,
      noteEn: 'Deadline for key deliverables',
      noteBn: 'নির্ধারিত কাজ শেষ করার শেষ তারিখ',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Group Meeting & Sync',
      titleBn: 'গ্রুপ মিটিং বা আলোচনা',
      kind: FamilyDateKind.meeting,
      recurrence: FamilyRecurrence.once,
      remindDays: 1,
      noteEn: 'Group discussion and alignment',
      noteBn: 'সদস্যদের পারস্পরিক আলোচনা ও প্রস্তুতি',
    ),
    GroupDatePresetTemplate(
      titleEn: 'Due Payment / Contribution',
      titleBn: 'পেমেন্ট বা চাঁদা পরিশোধ',
      kind: FamilyDateKind.bill,
      recurrence: FamilyRecurrence.once,
      remindDays: 2,
      noteEn: 'Payment or contribution cutoff',
      noteBn: 'বিল, চাঁদা বা পাওনা পরিশোধের শেষ সময়',
    ),
  ];
}

/// Returns the localized title of the Important Dates / Calendar screen for [group].
String groupDateScreenTitle(TourGroup? group, AppLocalizations l10n) {
  if (group != null) {
    final effective = group.effectivePreset;
    if (effective == TourGroup.officePreset) {
      return l10n.translate('hub_module_dates_office');
    }
    if (effective == TourGroup.campusPreset) {
      return l10n.translate('hub_module_dates_campus');
    }
    if (effective == TourGroup.messPreset) {
      return l10n.translate('hub_module_dates_mess');
    }
    if (effective == TourGroup.societyPreset) {
      return l10n.translate('hub_module_dates_society');
    }
    if (effective == TourGroup.samityPreset) {
      return l10n.translate('hub_module_dates_samity');
    }
    if (effective == TourGroup.studyPreset) {
      return l10n.translate('hub_module_dates_study');
    }
    if (effective == TourGroup.friendsPreset) {
      return l10n.translate('hub_module_dates_friends');
    }
    if (effective == TourGroup.schoolPreset) {
      return l10n.translate('hub_module_dates_school');
    }
    if (effective == TourGroup.sportsPreset) {
      return l10n.translate('hub_module_dates_sports');
    }
    if (effective == TourGroup.committeePreset) {
      return l10n.translate('hub_module_dates_committee');
    }
    if (!group.isFamily) return l10n.translate('hub_module_dates_trip');
    if (group.isHousehold && effective == null) {
      return l10n.translate('hub_module_family_dates');
    }
  }
  return l10n.translate('hub_module_dates_general');
}

/// Returns the localized subtitle or introduction for the Important Dates / Calendar screen.
String groupDateScreenSubtitle(TourGroup? group, AppLocalizations l10n) {
  if (group != null) {
    final effective = group.effectivePreset;
    if (effective == TourGroup.officePreset) {
      return l10n.translate('hub_module_dates_office_sub');
    }
    if (effective == TourGroup.campusPreset) {
      return l10n.translate('hub_module_dates_campus_sub');
    }
    if (effective == TourGroup.messPreset) {
      return l10n.translate('hub_module_dates_mess_sub');
    }
    if (effective == TourGroup.societyPreset) {
      return l10n.translate('hub_module_dates_society_sub');
    }
    if (effective == TourGroup.samityPreset) {
      return l10n.translate('hub_module_dates_samity_sub');
    }
    if (effective == TourGroup.studyPreset) {
      return l10n.translate('hub_module_dates_study_sub');
    }
    if (effective == TourGroup.friendsPreset) {
      return l10n.translate('hub_module_dates_friends_sub');
    }
    if (effective == TourGroup.schoolPreset) {
      return l10n.translate('hub_module_dates_school_sub');
    }
    if (effective == TourGroup.sportsPreset) {
      return l10n.translate('hub_module_dates_sports_sub');
    }
    if (effective == TourGroup.committeePreset) {
      return l10n.translate('hub_module_dates_committee_sub');
    }
    if (!group.isFamily) return l10n.translate('hub_module_dates_trip_sub');
    if (group.isHousehold && effective == null) {
      return l10n.translate('hub_module_family_dates_sub');
    }
  }
  return l10n.translate('hub_module_dates_general_sub');
}

String groupDateModalHeader(
  TourGroup? group,
  AppLocalizations l10n, {
  required bool isAdd,
  required bool canEdit,
}) {
  final isHousehold =
      group?.isHousehold == true && group?.effectivePreset == null;
  if (!canEdit && !isAdd) {
    if (isHousehold) return l10n.translate('fd_view_title');
    return l10n.translate('fd_view_general');
  }
  if (!isAdd) {
    if (isHousehold) return l10n.translate('fd_edit_title');
    return l10n.translate('fd_edit_general');
  }
  if (group != null) {
    final effective = group.effectivePreset;
    if (effective == TourGroup.officePreset) {
      return l10n.translate('fd_add_office');
    }
    if (effective == TourGroup.campusPreset) {
      return l10n.translate('fd_add_campus');
    }
    if (effective == TourGroup.messPreset) return l10n.translate('fd_add_mess');
    if (effective == TourGroup.societyPreset) {
      return l10n.translate('fd_add_society');
    }
    if (effective == TourGroup.samityPreset) {
      return l10n.translate('fd_add_samity');
    }
    if (effective == TourGroup.studyPreset) {
      return l10n.translate('fd_add_study');
    }
    if (effective == TourGroup.friendsPreset) {
      return l10n.translate('fd_add_friends');
    }
    if (effective == TourGroup.schoolPreset) {
      return l10n.translate('fd_add_school');
    }
    if (effective == TourGroup.sportsPreset) {
      return l10n.translate('fd_add_sports');
    }
    if (effective == TourGroup.committeePreset) {
      return l10n.translate('fd_add_committee');
    }
    if (!group.isFamily) return l10n.translate('fd_add_trip');
    if (isHousehold) return l10n.translate('fd_add_title');
  }
  return l10n.translate('fd_add_general');
}

/// Returns the localized empty state message for the dates list.
String groupDateEmptyText(TourGroup? group, AppLocalizations l10n) {
  final isHousehold =
      group?.isHousehold == true && group?.effectivePreset == null;
  if (isHousehold) {
    return l10n.translate('fd_empty');
  }
  return l10n.translate('fd_empty_general');
}

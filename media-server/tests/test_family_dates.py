"""Family-date reminders: the calendar rules, the reminder plan, the daily run and its timing.

The examples are the ones the app's family_date_rules_test.dart uses, so the app and the
reminders agree on every date.
"""

from datetime import datetime, timezone

import pytest

import family_dates as fd


# ── Day keys and day arithmetic ───────────────────────────────────────────────


def test_dhaka_day_key_reads_the_dhaka_day_which_is_six_hours_ahead():
    # 17:59 UTC is 23:59 in Dhaka, still the same day.
    assert fd.dhaka_day_key(datetime(2026, 10, 31, 17, 59, tzinfo=timezone.utc)) == "2026-10-31"
    # 18:00 UTC is midnight in Dhaka, so the next day.
    assert fd.dhaka_day_key(datetime(2026, 10, 31, 18, 0, tzinfo=timezone.utc)) == "2026-11-01"


def test_dhaka_day_key_refuses_a_naive_time():
    with pytest.raises(ValueError):
        fd.dhaka_day_key(datetime(2026, 10, 31, 18, 0))


def test_days_are_counted_forwards_and_backwards():
    assert fd.days_between("2026-10-31", "2026-11-03") == 3
    assert fd.days_between("2026-11-03", "2026-10-31") == -3
    assert fd.days_between("2026-10-31", "2026-10-31") == 0


def test_days_are_added_across_month_year_and_leap_day_boundaries():
    assert fd.add_days("2026-12-31", 1) == "2027-01-01"
    assert fd.add_days("2028-02-28", 1) == "2028-02-29"
    assert fd.add_days("2026-02-28", 1) == "2026-03-01"
    assert fd.add_days("2026-11-03", -7) == "2026-10-27"


# ── Occurrences ───────────────────────────────────────────────────────────────


def test_a_yearly_date_keeps_its_month_and_day():
    assert fd.occurrence_on_or_after("2000-03-15", "yearly", "2026-10-31") == "2027-03-15"
    assert fd.occurrence_on_or_after("2000-03-15", "yearly", "2026-03-15") == "2026-03-15"
    assert fd.occurrence_on_or_after("2000-03-15", "yearly", "2026-03-16") == "2027-03-15"


def test_a_29_february_date_falls_on_28_february_in_a_common_year():
    assert fd.occurrence_on_or_after("2024-02-29", "yearly", "2026-01-01") == "2026-02-28"
    assert fd.occurrence_on_or_after("2024-02-29", "yearly", "2028-01-01") == "2028-02-29"


def test_a_monthly_date_keeps_its_day_or_the_last_day_of_a_short_month():
    assert fd.occurrence_on_or_after("2026-01-31", "monthly", "2026-02-01") == "2026-02-28"
    assert fd.occurrence_on_or_after("2026-01-31", "monthly", "2026-02-28") == "2026-02-28"
    assert fd.occurrence_on_or_after("2026-01-31", "monthly", "2026-03-01") == "2026-03-31"


def test_a_monthly_date_rolls_over_the_year_end():
    assert fd.occurrence_on_or_after("2026-11-15", "monthly", "2026-12-20") == "2027-01-15"


def test_a_one_time_date_does_not_move():
    assert fd.occurrence_on_or_after("2026-05-01", "once", "2026-10-31") == "2026-05-01"


# ── The reminder plan ─────────────────────────────────────────────────────────


def _record(**extra):
    record = {
        "title": "Asha's birthday",
        "kind": "birthday",
        "recurrence": "yearly",
        "startOn": "2000-11-03",
        "nextOn": "2026-11-03",
        "remindDays": 7,
        "remindOn": "2026-10-27",
    }
    record.update(extra)
    return record


def test_nothing_is_due_before_the_reminder_day():
    assert fd.plan_family_date_reminders(_record(), "2026-10-26") is None


def test_the_reminder_is_sent_and_a_yearly_birthday_moves_to_next_year():
    plan = fd.plan_family_date_reminders(_record(), "2026-10-27")
    assert plan == fd.ReminderPlan(days_left=[7], next_on="2027-11-03", remind_on="2027-10-27")


def test_a_same_day_reminder_is_sent_when_the_date_is_today():
    plan = fd.plan_family_date_reminders(_record(remindDays=0, remindOn="2026-11-03"), "2026-11-03")
    assert plan == fd.ReminderPlan(days_left=[0], next_on="2027-11-03", remind_on="2027-11-03")


def test_a_date_that_passed_while_the_server_was_down_sends_nothing_and_moves_on():
    plan = fd.plan_family_date_reminders(_record(), "2026-11-06")
    assert plan == fd.ReminderPlan(days_left=[], next_on="2027-11-03", remind_on="2027-10-27")


def test_a_monthly_bill_stays_on_the_first_of_each_month():
    record = _record(
        recurrence="monthly",
        startOn="2026-06-01",
        nextOn="2026-11-01",
        remindDays=3,
        remindOn="2026-10-29",
        kind="bill",
        title="Electricity",
    )
    plan = fd.plan_family_date_reminders(record, "2026-10-29")
    assert plan == fd.ReminderPlan(days_left=[3], next_on="2026-12-01", remind_on="2026-11-28")


def test_a_one_time_date_reminds_once_and_then_clears_its_reminder():
    record = _record(recurrence="once", startOn="2026-11-10", nextOn="2026-11-10", remindDays=1, remindOn="2026-11-09")
    assert fd.plan_family_date_reminders(record, "2026-11-09") == fd.ReminderPlan(
        days_left=[1], next_on="2026-11-10", remind_on=None
    )


def test_a_one_time_date_that_passed_clears_its_reminder_without_sending():
    record = _record(recurrence="once", startOn="2026-10-01", nextOn="2026-10-01", remindDays=1, remindOn="2026-09-30")
    assert fd.plan_family_date_reminders(record, "2026-10-31") == fd.ReminderPlan(
        days_left=[], next_on="2026-10-01", remind_on=None
    )


def test_a_29_february_birthday_reminds_about_the_28th_in_a_common_year():
    record = _record(startOn="2024-02-29", nextOn="2026-02-28", remindDays=1, remindOn="2026-02-27")
    assert fd.plan_family_date_reminders(record, "2026-02-27") == fd.ReminderPlan(
        days_left=[1], next_on="2027-02-28", remind_on="2027-02-27"
    )


@pytest.mark.parametrize(
    "override",
    [
        {"nextOn": "2026-02-30"},
        {"remindDays": 1.5},
        {"remindDays": True},
        {"remindDays": 31},
        {"remindDays": -1},
        {"recurrence": "weekly"},
        {"remindOn": None},
        {"startOn": "soon"},
    ],
)
def test_a_record_that_cannot_be_read_is_refused(override):
    assert fd.plan_family_date_reminders(_record(**override), "2026-10-27") is None


# ── The reminder text ─────────────────────────────────────────────────────────


def test_the_reminder_text_says_when_and_leads_with_a_kind_emoji():
    record = {"title": "Asha's birthday", "kind": "birthday"}
    assert fd.family_date_reminder_text(record, 0) == ("🎂 Asha's birthday", "Today")
    assert fd.family_date_reminder_text(record, 1) == ("🎂 Asha's birthday", "Tomorrow")
    assert fd.family_date_reminder_text(record, 5) == ("🎂 Asha's birthday", "In 5 days")


def test_the_reminder_text_falls_back_for_a_blank_title_or_an_unknown_kind():
    assert fd.family_date_reminder_text({"title": "  ", "kind": "bill"}, 2)[0] == "🧾 Family date"
    assert fd.family_date_reminder_text({"title": "Trip", "kind": "other"}, 2)[0] == "📅 Trip"


def test_the_reminder_text_is_in_bengali_for_a_bengali_member():
    record = {"title": "Asha's birthday", "kind": "birthday"}
    assert fd.family_date_reminder_text(record, 0, "bn") == ("🎂 Asha's birthday", "আজ")
    assert fd.family_date_reminder_text(record, 1, "bn") == ("🎂 Asha's birthday", "আগামীকাল")
    assert fd.family_date_reminder_text(record, 12, "bn") == ("🎂 Asha's birthday", "১২ দিন পরে")
    assert fd.family_date_reminder_text({"title": " ", "kind": "bill"}, 2, "bn") == (
        "🧾 পারিবারিক তারিখ",
        "২ দিন পরে",
    )


def test_an_unknown_language_gets_the_reminder_in_english():
    record = {"title": "Asha's birthday", "kind": "birthday"}
    assert fd.family_date_reminder_text(record, 5, "fr") == ("🎂 Asha's birthday", "In 5 days")
    assert fd.family_date_reminder_text(record, 5) == ("🎂 Asha's birthday", "In 5 days")


# ── When the daily run is due ─────────────────────────────────────────────────


def test_the_run_is_due_from_seven_in_dhaka_and_only_once_a_day():
    # 06:59 Dhaka is 00:59 UTC: too early.
    assert fd.is_run_due(datetime(2026, 10, 31, 0, 59, tzinfo=timezone.utc), None, None) is False
    # 07:00 Dhaka is 01:00 UTC.
    assert fd.is_run_due(datetime(2026, 10, 31, 1, 0, tzinfo=timezone.utc), None, None) is True
    # Already ran today.
    assert fd.is_run_due(datetime(2026, 10, 31, 5, 0, tzinfo=timezone.utc), "2026-10-31", None) is False
    # The next Dhaka day, from seven, is due again.
    assert fd.is_run_due(datetime(2026, 11, 1, 1, 0, tzinfo=timezone.utc), "2026-10-31", None) is True


def test_a_failed_run_waits_for_its_retry_time():
    now = datetime(2026, 10, 31, 1, 5, tzinfo=timezone.utc)
    retry = now + fd.RETRY_AFTER
    assert fd.is_run_due(now, None, retry) is False
    assert fd.is_run_due(retry, None, retry) is True


class _Clock:
    def __init__(self, now):
        self.now = now

    def __call__(self):
        return self.now


def test_the_scheduler_runs_once_a_day_and_retries_a_failed_run():
    clock = _Clock(datetime(2026, 10, 31, 0, 59, tzinfo=timezone.utc))  # 06:59 Dhaka
    calls = []

    def run(today):
        calls.append(today)
        if len(calls) == 1:
            raise RuntimeError("firestore unavailable")
        return {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}

    scheduler = fd.FamilyDateReminderScheduler(object(), clock=clock, run=run)
    assert scheduler.run_if_due() is False  # 06:59: not yet
    clock.now = datetime(2026, 10, 31, 1, 0, tzinfo=timezone.utc)  # 07:00
    assert scheduler.run_if_due() is False  # the run fails
    clock.now = datetime(2026, 10, 31, 1, 5, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is False  # still waiting for the retry
    clock.now = datetime(2026, 10, 31, 1, 11, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is True  # the retry succeeds
    clock.now = datetime(2026, 10, 31, 3, 0, tzinfo=timezone.utc)
    assert scheduler.run_if_due() is False  # already ran today
    assert calls == ["2026-10-31", "2026-10-31"]


# ── The daily run, against in-memory Firestore and push fakes ─────────────────


class _Snapshot:
    def __init__(self, record):
        self.exists = record is not None
        self._record = record

    def to_dict(self):
        return dict(self._record) if self._record is not None else None


class _TourRef:
    def __init__(self, tour_id):
        self.id = tour_id


class _DateRef:
    def __init__(self, store, path, tour_id, doc_id):
        self._store = store
        self.path = path
        self.id = doc_id
        self.parent = type("Collection", (), {"parent": _TourRef(tour_id)})()

    def get(self, transaction=None):
        return _Snapshot(self._store.get(self.path))


class _Doc:
    def __init__(self, ref, record):
        self.reference = ref
        self.id = ref.id
        self._record = record

    def to_dict(self):
        return dict(self._record)


class _Query:
    def __init__(self, store, field, value):
        self._store = store
        self._field = field
        self._value = value

    def stream(self):
        docs = []
        for path, record in list(self._store.items()):
            value = record.get(self._field)
            if isinstance(value, str) and value <= self._value:
                tour_id, doc_id = path.split("/")[1], path.split("/")[3]
                docs.append(_Doc(_DateRef(self._store, path, tour_id, doc_id), record))
        return docs


class _CollectionGroup:
    def __init__(self, store):
        self._store = store

    def where(self, field, op, value):
        assert (field, op) == ("remindOn", "<=")
        return _Query(self._store, field, value)


class _Transaction:
    def __init__(self, store):
        self._store = store

    def update(self, ref, fields):
        self._store[ref.path].update(fields)


class _FakeDB:
    def __init__(self, store):
        self.store = store

    def collection_group(self, name):
        assert name == "family_dates"
        return _CollectionGroup(self.store)

    def transaction(self):
        return _Transaction(self.store)


def _fake_transactional(function):
    return lambda transaction, ref: function(transaction, ref)


class _FakeEngine:
    def __init__(self, members_by_tour, failing_tours=(), languages=None):
        self._members = members_by_tour
        self._failing = set(failing_tours)
        self._languages = dict(languages or {})
        self.sent = []
        self.member_reads = []

    def get_active_tour_members(self, tour_id, except_email=""):
        self.member_reads.append(tour_id)
        if tour_id in self._failing:
            raise RuntimeError("membership read failed")
        return list(self._members.get(tour_id, []))

    def get_uids_for_emails(self, emails):
        return [f"uid:{email}" for email in emails]

    def get_push_targets_for_uids(self, uids):
        return [(f"token:{uid}", None, self._languages.get(uid, "en")) for uid in uids]

    def send_localized(self, targets, make_text, data, high_priority=False):
        # The server's contract: one text per language, sent to that language's devices.
        for language in sorted({lang for _, _, lang in targets}):
            title, body = make_text(language)
            self.sent.append((title, body, dict(data), high_priority))
        return len(targets)


def test_a_due_reminder_is_pushed_to_each_device_and_the_date_moves_on():
    store = {"tours/t1/family_dates/d1": _record(createdByEmail="asha@x.com")}
    engine = _FakeEngine({"t1": ["asha@x.com", "babu@x.com"]})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats == {"due": 1, "reminded": 1, "pushes": 2, "errors": 0}
    # One multicast reaches both devices.
    assert engine.sent == [
        ("🎂 Asha's birthday", "In 7 days", {"action": "family_date", "tourId": "t1", "dateId": "d1"}, True),
    ]
    assert store["tours/t1/family_dates/d1"]["nextOn"] == "2027-11-03"
    assert store["tours/t1/family_dates/d1"]["remindOn"] == "2027-10-27"


def test_each_member_gets_the_reminder_in_their_own_language():
    store = {"tours/t1/family_dates/d1": _record(createdByEmail="asha@x.com")}
    engine = _FakeEngine({"t1": ["asha@x.com", "babu@x.com"]}, languages={"uid:babu@x.com": "bn"})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats == {"due": 1, "reminded": 1, "pushes": 2, "errors": 0}
    data = {"action": "family_date", "tourId": "t1", "dateId": "d1"}
    # Bengali first (sorted by language), then the English devices.
    assert engine.sent == [
        ("🎂 Asha's birthday", "৭ দিন পরে", data, True),
        ("🎂 Asha's birthday", "In 7 days", data, True),
    ]


def test_a_second_run_on_the_same_day_sends_nothing():
    store = {"tours/t1/family_dates/d1": _record()}
    engine = _FakeEngine({"t1": ["asha@x.com"]})
    fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)
    engine.sent.clear()

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats == {"due": 0, "reminded": 0, "pushes": 0, "errors": 0}
    assert engine.sent == []


def test_one_broken_circle_does_not_stop_the_other_reminders():
    store = {
        "tours/bad/family_dates/d1": _record(),
        "tours/good/family_dates/d2": _record(title="Rent", kind="bill"),
    }
    engine = _FakeEngine({"good": ["asha@x.com"]}, failing_tours={"bad"})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats == {"due": 2, "reminded": 1, "pushes": 1, "errors": 1}
    assert engine.sent == [("🧾 Rent", "In 7 days", {"action": "family_date", "tourId": "good", "dateId": "d2"}, True)]


def test_a_circle_whose_members_cannot_be_read_keeps_its_date_due_for_the_next_run():
    store = {"tours/t1/family_dates/d1": _record()}
    engine = _FakeEngine({}, failing_tours={"t1"})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats == {"due": 1, "reminded": 0, "pushes": 0, "errors": 1}
    assert engine.sent == []
    # Nothing was claimed, so the date is still due and the next run can remind about it.
    assert store["tours/t1/family_dates/d1"]["remindOn"] == "2026-10-27"
    assert store["tours/t1/family_dates/d1"]["nextOn"] == "2026-11-03"


def test_a_circle_is_read_once_per_run_however_many_of_its_dates_are_due():
    store = {
        "tours/t1/family_dates/d1": _record(),
        "tours/t1/family_dates/d2": _record(title="Rent", kind="bill"),
    }
    engine = _FakeEngine({"t1": ["asha@x.com"]})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats["pushes"] == 2
    assert engine.member_reads == ["t1"]


def test_a_circle_with_no_members_gets_no_push_but_the_date_still_moves_on():
    store = {"tours/t1/family_dates/d1": _record()}
    engine = _FakeEngine({})

    stats = fd.run_family_date_reminders(_FakeDB(store), engine, "2026-10-27", transactional=_fake_transactional)

    assert stats["pushes"] == 0
    assert store["tours/t1/family_dates/d1"]["remindOn"] == "2027-10-27"

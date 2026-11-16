import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/services/incoming_safety_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 16, 12);

SafetyAlert _alert(
  String id, {
  String sender = 'rana@x.com',
  Duration ago = const Duration(minutes: 1),
  bool resolved = false,
  bool pending = false,
}) =>
    SafetyAlert(
      id: id,
      senderEmail: sender,
      senderName: sender.split('@').first,
      createdAt: pending ? null : _now.subtract(ago),
      resolved: resolved,
    );

List<IncomingSafetyAlert> _incoming(
  Map<String, List<SafetyAlert>> alerts, {
  Map<String, String> names = const {'t1': 'Khaurun Complex', 't2': 'Home'},
  Set<String> dismissed = const {},
}) =>
    incomingSafetyAlerts(
      alertsByTour: alerts,
      groupNames: names,
      myEmail: 'me@x.com',
      now: _now,
      dismissed: dismissed,
    );

void main() {
  test('another member\'s open alert is shown with its group', () {
    final shown = _incoming({
      't1': [_alert('a')],
    });
    expect(shown, hasLength(1));
    expect(shown.single.groupName, 'Khaurun Complex');
    expect(shown.single.key, 't1/a');
  });

  test('my own alert is not shown to me', () {
    expect(
      _incoming({
        't1': [_alert('a', sender: 'me@x.com')],
      }),
      isEmpty,
    );
    // The sender's address is stored in lower case; mine is compared the same way.
    expect(
      incomingSafetyAlerts(
        alertsByTour: {
          't1': [_alert('a', sender: 'me@x.com')],
        },
        groupNames: const {'t1': 'G'},
        myEmail: ' Me@X.com ',
        now: _now,
      ),
      isEmpty,
    );
  });

  test('a closed alert, and one past its six hours, are not shown', () {
    expect(
      _incoming({
        't1': [
          _alert('closed', resolved: true),
          _alert('old', ago: const Duration(hours: 6, minutes: 1)),
          _alert('open', ago: const Duration(hours: 5)),
        ],
      }).map((a) => a.alert.id),
      ['open'],
    );
  });

  test('an alert the server has not stamped yet is shown, and comes first', () {
    final shown = _incoming({
      't1': [_alert('earlier', ago: const Duration(minutes: 3))],
      't2': [_alert('just now', pending: true)],
    });
    expect(shown.map((a) => a.alert.id), ['just now', 'earlier']);
  });

  test('alerts from every group come newest first', () {
    final shown = _incoming({
      't1': [_alert('b', ago: const Duration(minutes: 9))],
      't2': [
        _alert('a', ago: const Duration(minutes: 2)),
        _alert('c', ago: const Duration(minutes: 30)),
      ],
    });
    expect(shown.map((a) => a.alert.id), ['a', 'b', 'c']);
  });

  test('a dismissed alert stays hidden, and only that one', () {
    final shown = _incoming(
      {
        't1': [_alert('a'), _alert('b', ago: const Duration(minutes: 2))],
        // The same id in another group is a different alert.
        't2': [_alert('a', ago: const Duration(minutes: 3))],
      },
      dismissed: {'t1/a'},
    );
    expect(shown.map((a) => a.key), ['t1/b', 't2/a']);
  });

  test('an alert of a group that is no longer mine is not shown', () {
    expect(
      _incoming(
        {
          't9': [_alert('a')],
        },
      ),
      isEmpty,
    );
  });

  test('only an alert that was not on the banner sounds', () {
    final before = _incoming({
      't1': [_alert('a')],
    });
    final after = _incoming({
      't1': [_alert('a'), _alert('b', ago: const Duration(seconds: 5))],
    });
    expect(newlyArrivedAlerts(before, after).map((a) => a.alert.id), ['b']);
    expect(newlyArrivedAlerts(after, after), isEmpty);
    expect(newlyArrivedAlerts(const [], before).map((a) => a.alert.id), ['a']);
  });
}

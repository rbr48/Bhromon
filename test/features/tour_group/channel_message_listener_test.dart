import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_message_listener.dart';

void main() {
  setUp(ChannelListenerBudget.reset);

  testWidgets('a mounted listener counts once, and leaving releases it',
      (tester) async {
    final controller = StreamController<List<ChannelMessage>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: ChannelMessageListener(
        stream: controller.stream,
        builder: (context, snapshot) => const SizedBox(),
      ),
    ));
    expect(ChannelListenerBudget.live, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(ChannelListenerBudget.live, 0);
  });

  test('the budget allows its maximum and refuses one more in a debug build',
      () {
    for (var i = 0; i < ChannelListenerBudget.maxLive; i++) {
      ChannelListenerBudget.attach();
    }
    expect(ChannelListenerBudget.live, ChannelListenerBudget.maxLive);
    expect(() => ChannelListenerBudget.attach(), throwsAssertionError);
  });

  test('releasing never takes the count below zero', () {
    ChannelListenerBudget.detach();
    expect(ChannelListenerBudget.live, 0);
  });
}

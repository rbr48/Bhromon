import 'package:bhromon/features/tour_group/domain/services/channel_draft_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldClearEditDraftOnSwitch', () {
    test('switching away from a channel mid-edit clears its edit text', () {
      expect(
        shouldClearEditDraftOnSwitch(
          isEditing: true,
          fromChannelId: 'general',
          toChannelId: 'food',
        ),
        isTrue,
      );
    });

    test('switching channel while not editing clears nothing', () {
      expect(
        shouldClearEditDraftOnSwitch(
          isEditing: false,
          fromChannelId: 'general',
          toChannelId: 'food',
        ),
        isFalse,
      );
    });

    test('tapping the open channel mid-edit keeps the edit text', () {
      expect(
        shouldClearEditDraftOnSwitch(
          isEditing: true,
          fromChannelId: 'general',
          toChannelId: 'general',
        ),
        isFalse,
      );
    });
  });
}

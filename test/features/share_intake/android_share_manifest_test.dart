import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The share target lives in the manifest, which the Android build reads. These checks
/// keep the filters and the launch mode that the native share code depends on.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final activity = RegExp(
        r'<activity\s[^>]*android:name="\.MainActivity"[\s\S]*?</activity>',
      ).firstMatch(manifest)?.group(0) ??
      '';

  test('MainActivity takes single and multiple shares of any file type', () {
    expect(activity, contains('android.intent.action.SEND"'));
    expect(activity, contains('android.intent.action.SEND_MULTIPLE"'));
    expect(activity, contains('android:mimeType="*/*"'));
    expect(activity, contains('android.intent.category.DEFAULT'));
  });

  test('MainActivity stays singleTop, so a share reaches onNewIntent', () {
    expect(activity, contains('android:launchMode="singleTop"'));
  });

  test('the launcher filter is still there', () {
    expect(activity, contains('android.intent.action.MAIN'));
    expect(activity, contains('android.intent.category.LAUNCHER'));
  });
}

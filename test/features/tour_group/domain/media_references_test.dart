import 'package:bhromon/features/tour_group/domain/services/media_references.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ownFile = 'https://bhromon.fun/media/t1/posts/own.jpg';
  const sharedFile = 'https://bhromon.fun/media/t1/posts/shared.jpg';

  test('a file that other content still uses is kept', () {
    expect(
      mediaUrlsSafeToRemove([ownFile, sharedFile], {sharedFile}),
      [ownFile],
    );
  });

  test('when nothing else uses the files, all of them are removed in order',
      () {
    expect(
      mediaUrlsSafeToRemove([sharedFile, ownFile], const {}),
      [sharedFile, ownFile],
    );
  });

  test('a repeated URL is removed once, and empty URLs are dropped', () {
    expect(
      mediaUrlsSafeToRemove([ownFile, '', ownFile], const {}),
      [ownFile],
    );
  });

  test('nothing is removed when every file is still in use', () {
    expect(
      mediaUrlsSafeToRemove([ownFile, sharedFile], {ownFile, sharedFile}),
      isEmpty,
    );
  });
}

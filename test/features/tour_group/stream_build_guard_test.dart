import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Calls that open or share a groups or members stream. A screen reads them in
/// initState, or in a method it calls from there. A read made while the widget builds
/// runs again on every rebuild, which G1 forbids (plan section 6.2).
final _accessor = RegExp(r'\b(watchMyGroups|restartMyGroups|watchMembers)\(');

/// The declarations of those accessors. They are not calls.
final _declaration = RegExp(
    r'^\s*(Stream|Future)<[^=]*>\s+(watchMyGroups|restartMyGroups|watchMembers)\(');

/// A class member starts at two spaces, and a top-level declaration at none.
final _memberStart = RegExp(r'^(?: {2}|)[A-Za-z_]');

/// The name a member declaration gives: the first identifier before its parameters,
/// its body or its initialiser.
final _memberName = RegExp(r'(\w+)\s*(\(|=>|=|\{)');

/// Names of methods that build widgets: `build`, `_build`, `_buildX`, `buildX`.
final _buildName = RegExp(r'^_?build([A-Z]|$)');

/// The member that holds line [index], or null at the top of a file or in a class
/// header.
String? _memberAt(List<String> lines, int index) {
  for (var i = index; i >= 0; i--) {
    final line = lines[i];
    if (!_memberStart.hasMatch(line)) continue;
    final declared = line.trimLeft();
    if (declared.startsWith('class ') ||
        declared.startsWith('mixin ') ||
        declared.startsWith('enum ') ||
        declared.startsWith('extension ')) {
      return null;
    }
    return _memberName.firstMatch(declared)?.group(1);
  }
  return null;
}

/// Each read of a groups or members stream made inside a build method, as text.
List<String> buildPathReads(List<String> lines) {
  final found = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    if (!_accessor.hasMatch(line) || _declaration.hasMatch(line)) continue;
    final member = _memberAt(lines, i);
    if (member != null && _buildName.hasMatch(member)) {
      found.add('line ${i + 1} in $member: ${line.trim()}');
    }
  }
  return found;
}

void main() {
  test('the scan finds a read made inside build, and leaves initState alone',
      () {
    final sample = [
      'class _Screen extends State<Screen> {',
      '  @override',
      '  void initState() {',
      '    super.initState();',
      '    _members = _repo.watchMembers(widget.id);',
      '  }',
      '',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return StreamBuilder(stream: _repo.watchMembers(widget.id));',
      '  }',
      '}',
    ];

    final found = buildPathReads(sample);

    expect(found, hasLength(1));
    expect(found.single, startsWith('line 10 in build'));
  });

  test(
      'the scan finds a read inside a build helper, and inside a closure in build',
      () {
    final sample = [
      'class _Screen extends State<Screen> {',
      '  Widget _buildMembers() {',
      '    return StreamBuilder(stream: _repo.watchMembers(id));',
      '  }',
      '  @override',
      '  Widget build(BuildContext context) {',
      '    return ElevatedButton(',
      '      onPressed: () => setState(() {',
      '        _stream = _repo.restartMyGroups();',
      '      }),',
      '    );',
      '  }',
      '}',
    ];

    final found = buildPathReads(sample);

    expect(found, hasLength(2));
    expect(found[0], startsWith('line 3 in _buildMembers'));
    expect(found[1], startsWith('line 9 in build'));
  });

  test('declarations and comments are not reads', () {
    final sample = [
      'class TourGroupRepository {',
      '  Stream<List<TourMember>> watchMembers(String tourId) {',
      '    // watchMembers(tourId) is shared per tour',
      '    return _sharedMembers.stream(tourId, () => _openMembers(tourId));',
      '  }',
      '  Widget build(BuildContext context) => const SizedBox();',
      '}',
    ];

    expect(buildPathReads(sample), isEmpty);
  });

  test('no widget reads a groups or members stream while it builds', () {
    final found = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      for (final read in buildPathReads(file.readAsLinesSync())) {
        found.add('${file.path}: $read');
      }
    }

    expect(
      found,
      isEmpty,
      reason: 'Read these streams in initState, or in a method called from it, '
          'never while building:\n${found.join('\n')}',
    );
  });
}

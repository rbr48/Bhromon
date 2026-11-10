import 'package:bhromon/features/tour_group/domain/services/media_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSupportedVideoName', () {
    test('accepts the containers the media server stores, in any case', () {
      for (final name in [
        'clip.mp4',
        'clip.MOV',
        'clip.m4v',
        'clip.webm',
        'clip.3gp',
        'clip.mkv',
      ]) {
        expect(isSupportedVideoName(name), isTrue, reason: name);
      }
    });

    test('refuses containers the media server does not store', () {
      for (final name in [
        'clip.avi',
        'clip.mpg',
        'clip.mpeg',
        'clip.wmv',
        'clip.flv',
        'clip.ts',
      ]) {
        expect(isSupportedVideoName(name), isFalse, reason: name);
      }
    });

    test('keeps a name with no extension, which is stored as an mp4', () {
      expect(isSupportedVideoName('1000000012'), isTrue);
      expect(storedExtension('1000000012', 'mp4'), 'mp4');
    });
  });

  group('isSupportedDocName and docContentType', () {
    test('accepts all power document and study pack extensions', () {
      final samples = {
        'notes.md': 'text/markdown',
        'README.MD': 'text/markdown',
        'debug.log': 'text/plain',
        'config.json': 'application/json',
        'spec.yaml': 'application/x-yaml',
        'pipeline.yml': 'application/x-yaml',
        'data.xml': 'application/xml',
        'schema.sql': 'application/sql',
        'doc.odt': 'application/vnd.oasis.opendocument.text',
        'sheet.ods': 'application/vnd.oasis.opendocument.spreadsheet',
        'slides.odp': 'application/vnd.oasis.opendocument.presentation',
        'letter.rtf': 'application/rtf',
        'data.tsv': 'text/tab-separated-values',
        'data.csv': 'text/csv',
        'book.epub': 'application/epub+zip',
        'bundle.zip': 'application/zip',
        'archive.rar': 'application/x-rar-compressed',
        'pack.7z': 'application/x-7z-compressed',
        'source.tar': 'application/x-tar',
        'source.gz': 'application/gzip',
        'doc.pdf': 'application/pdf',
        'doc.docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'slides.pptx':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'calc.xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };

      for (final entry in samples.entries) {
        expect(isSupportedDocName(entry.key), isTrue, reason: entry.key);
        expect(docContentType(entry.key), entry.value, reason: entry.key);
      }
    });

    test('refuses dangerous executable or active web script types', () {
      for (final name in [
        'script.js',
        'index.html',
        'page.htm',
        'app.exe',
        'install.apk',
        'deploy.sh',
        'run.bat',
        'vector.svg',
      ]) {
        expect(isSupportedDocName(name), isFalse, reason: name);
        expect(docContentType(name), isNull, reason: name);
      }
    });

    test('kSupportedDocExtensions contains all registered document types', () {
      expect(kSupportedDocExtensions, contains('md'));
      expect(kSupportedDocExtensions, contains('json'));
      expect(kSupportedDocExtensions, contains('yaml'));
      expect(kSupportedDocExtensions, contains('sql'));
      expect(kSupportedDocExtensions, contains('epub'));
      expect(kSupportedDocExtensions, contains('rar'));
      expect(kSupportedDocExtensions, contains('7z'));
      for (final ext in kSupportedDocExtensions) {
        expect(isSupportedDocName('sample.$ext'), isTrue, reason: ext);
      }
    });
  });
}

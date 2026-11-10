// How a study file opens in the app. A Markdown or text file opens in the Markdown reader, and a PDF in the PDF
// viewer. Any other file opens outside the app.

/// Which in-app reader opens a study file.
enum StudyFileReader { markdown, pdf, none }

/// The reader for a file, by its name or its address: .md, .txt and .log open as Markdown, and .pdf as a PDF.
/// The query of an address is ignored.
StudyFileReader studyFileReader(String nameOrUrl) {
  final path = (Uri.tryParse(nameOrUrl)?.path ?? nameOrUrl).toLowerCase();
  if (path.endsWith('.pdf')) return StudyFileReader.pdf;
  if (path.endsWith('.md') || path.endsWith('.txt') || path.endsWith('.log')) {
    return StudyFileReader.markdown;
  }
  return StudyFileReader.none;
}

/// The media server's address for the study folder of a group: /media/{tourId}/study/{file}.
const String _mediaOrigin = 'https://bhromon.fun/media/';

/// Whether [url] is a file in the study folder of the group [tourId] on the media server. A signed address, with
/// its query, is still such a file. A link to another group's folder, to another folder or host, or to a deeper
/// path is not, so it opens outside the app.
bool isStudyFolderFile(String url, String tourId) {
  if (tourId.isEmpty) return false;
  final folder = '$_mediaOrigin$tourId/study/';
  if (!url.startsWith(folder)) return false;
  final name = url.substring(folder.length).split(RegExp(r'[?#]')).first;
  return name.isNotEmpty && !name.contains('/');
}

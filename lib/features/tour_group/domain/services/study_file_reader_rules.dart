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

// Which study materials open as a chapter's one-tap solution, and what the reader needs to open one.
// A note carries its text. A Markdown file is fetched by the reader from its address. Other files
// (PDFs, images, audio, video and links) are reached from the materials list, not from a solution button.

import '../models/study_material_models.dart';

/// Whether a published material can open from a chapter's solution button.
bool isReadableSolution(StudyMaterial material) {
  if (material.kind == StudyMaterialKind.note) {
    return (material.body ?? '').trim().isNotEmpty;
  }
  return material.kind == StudyMaterialKind.file &&
      (material.url ?? '').isNotEmpty &&
      (material.fileName ?? '').toLowerCase().endsWith('.md');
}

/// Whether a solution is the Bangla version: its title has a Bengali word, or its file name says Bangla.
bool isBanglaSolution(StudyMaterial material) =>
    material.title.contains('বাংলা') ||
    material.title.contains('সমাধান') ||
    (material.fileName?.toLowerCase().contains('bangla') ?? false);

/// Where the reader gets a solution's text. A note gives its text, and a Markdown file gives its address.
/// The other language is paired only when its text is at hand, which is when it is a note, so a file
/// is paired with nothing.
({String? rawContent, String? fileUrl, StudyMaterial? paired}) solutionSource(
  StudyMaterial material,
  StudyMaterial? other,
) {
  final paired = other != null &&
          other.kind == StudyMaterialKind.note &&
          isReadableSolution(other)
      ? other
      : null;
  if (material.kind == StudyMaterialKind.note) {
    return (rawContent: material.body, fileUrl: null, paired: paired);
  }
  return (rawContent: null, fileUrl: material.url, paired: paired);
}

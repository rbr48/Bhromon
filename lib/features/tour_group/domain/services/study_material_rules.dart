import '../models/study_material_models.dart';
import 'media_rules.dart';

/// How long an admin has to decide a reported material, counted from the first report.
const Duration kStudyReportWindow = Duration(hours: 24);

/// The largest file a kind may upload, or null for a kind that uploads nothing. These match the media
/// server's limits and the rules' checks.
int? studyMaterialMaxBytes(StudyMaterialKind kind) => switch (kind) {
      StudyMaterialKind.image => kMaxImageBytes,
      StudyMaterialKind.audio => kMaxAudioBytes,
      StudyMaterialKind.video => kMaxVideoBytes,
      StudyMaterialKind.file => kMaxDocBytes,
      StudyMaterialKind.link || StudyMaterialKind.note => null,
    };

/// The kind a picked file uploads as, from its name, or null when no kind takes it.
StudyMaterialKind? studyKindForFileName(String fileName) {
  if (imageContentType(fileName) != null) return StudyMaterialKind.image;
  if (videoContentType(fileName) != null) return StudyMaterialKind.video;
  if (audioContentType(fileName) != null) return StudyMaterialKind.audio;
  if (docContentType(fileName) != null) return StudyMaterialKind.file;
  return null;
}

/// The content type of a picked file, or null when no kind takes it.
String? studyContentType(String fileName) =>
    imageContentType(fileName) ??
    videoContentType(fileName) ??
    audioContentType(fileName) ??
    docContentType(fileName);

/// The file extensions a kind may upload, for the file picker. They match the media server's allowlist.
List<String> studyMaterialExtensions(StudyMaterialKind kind) => switch (kind) {
      StudyMaterialKind.image => const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'gif',
          'heic',
          'heif'
        ],
      StudyMaterialKind.audio => const [
          'm4a',
          'mp3',
          'aac',
          'wav',
          'ogg',
          'opus'
        ],
      StudyMaterialKind.video => const [
          'mp4',
          'mov',
          'm4v',
          'webm',
          '3gp',
          'mkv'
        ],
      StudyMaterialKind.file => kSupportedDocExtensions,
      StudyMaterialKind.link || StudyMaterialKind.note => const <String>[],
    };

/// Why a picked file cannot be filed as a material of [kind].
enum StudyFileProblem { unsupported, empty, tooLarge }

/// The problem with a picked file for a material of [kind], or null when the file can be filed.
StudyFileProblem? studyFileProblem({
  required StudyMaterialKind kind,
  required String fileName,
  required int sizeBytes,
}) {
  if (!kind.isUpload || studyKindForFileName(fileName) != kind) {
    return StudyFileProblem.unsupported;
  }
  if (sizeBytes <= 0) return StudyFileProblem.empty;
  if (sizeBytes > studyMaterialMaxBytes(kind)!) {
    return StudyFileProblem.tooLarge;
  }
  return null;
}

/// Whether [raw] is a link the app can list: an http or https address with a host. No preview is fetched
/// for it.
bool isStudyLinkValid(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final uri = Uri.tryParse(text);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// The host of a link, without a leading "www.". Empty when the link has none.
String studyLinkDomain(String raw) {
  final host = Uri.tryParse(raw.trim())?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Whether a viewer sees a material in the list. Published material is shown to the group. A pending or
/// hidden one is shown to its uploader and to an admin, who decides it.
bool isStudyMaterialVisibleTo(
  StudyMaterial material, {
  required String viewerEmail,
  required bool isAdmin,
}) =>
    material.isPublished || material.createdByEmail == viewerEmail || isAdmin;

/// Whether a member may report a material: a published one that is not their own.
bool canReportStudyMaterial(
  StudyMaterial material, {
  required String viewerEmail,
}) =>
    material.isPublished && material.createdByEmail != viewerEmail;

/// Whether a viewer may edit a material's title or remove it: its uploader, or an admin.
bool canManageStudyMaterial(
  StudyMaterial material, {
  required String viewerEmail,
  required bool isAdmin,
}) =>
    isAdmin || material.createdByEmail == viewerEmail;

/// Whether a member's material is published at once. An admin's always is; a member's is when the group
/// publishes directly.
bool publishesStudyMaterialDirectly({
  required bool isAdmin,
  required bool needsApproval,
}) =>
    isAdmin || !needsApproval;

/// The group's material policy, as an admin sets it on the tour. A member's material waits for approval
/// unless the group publishes directly; with [onlyAdminsPost], only admins may add materials at all.
class StudyMaterialPolicy {
  const StudyMaterialPolicy({
    this.needsApproval = true,
    this.onlyAdminsPost = false,
  });

  final bool needsApproval;
  final bool onlyAdminsPost;
}

/// Whether a viewer may add a material: an admin always may, a member unless only admins may add.
bool canFileStudyMaterial({
  required bool isAdmin,
  required bool onlyAdminsPost,
}) =>
    isAdmin || !onlyAdminsPost;

/// The status a new material starts with.
StudyMaterialStatus initialStudyMaterialStatus({
  required bool isAdmin,
  required bool needsApproval,
}) =>
    publishesStudyMaterialDirectly(
            isAdmin: isAdmin, needsApproval: needsApproval)
        ? StudyMaterialStatus.published
        : StudyMaterialStatus.pending;

/// Materials newest first. One whose time is not yet known comes first, since it was just filed.
List<StudyMaterial> sortStudyMaterials(Iterable<StudyMaterial> materials) {
  final sorted = materials.toList();
  sorted.sort((a, b) {
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return sorted;
}

/// The materials filed under one chapter, or all of them when [chapterId] is null.
List<StudyMaterial> studyMaterialsInChapter(
  Iterable<StudyMaterial> materials,
  String? chapterId,
) {
  if (chapterId == null) return materials.toList();
  return [
    for (final material in materials)
      if (material.chapterId == chapterId) material,
  ];
}

/// The materials an admin must decide because they were reported: the hidden ones, oldest report first.
/// A report whose time is not yet known comes last.
List<StudyMaterial> studyReviewQueue(Iterable<StudyMaterial> materials) {
  final hidden = [
    for (final material in materials)
      if (material.status == StudyMaterialStatus.hidden) material,
  ];
  hidden.sort((a, b) {
    final ta = a.reportedAt;
    final tb = b.reportedAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });
  return hidden;
}

/// The materials waiting for an admin's approval, newest first.
List<StudyMaterial> studyApprovalQueue(Iterable<StudyMaterial> materials) =>
    sortStudyMaterials(materials.where(
      (material) => material.status == StudyMaterialStatus.pending,
    ));

/// Whether a reported material has gone past the 24-hour window with no decision.
bool isStudyReportOverdue(StudyMaterial material, {required DateTime now}) {
  final at = material.reportedAt;
  return material.status == StudyMaterialStatus.hidden &&
      at != null &&
      now.difference(at) > kStudyReportWindow;
}

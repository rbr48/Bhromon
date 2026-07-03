import 'package:freezed_annotation/freezed_annotation.dart';
import 'cost_item.dart';
import '../value_objects/geo_coordinate.dart';

part 'trip_block.freezed.dart';
part 'trip_block.g.dart';

@freezed
sealed class TripBlock with _$TripBlock {
  const factory TripBlock.text({
    required String id,
    required String content,
    @Default(false) bool isBold,
  }) = TextBlock;

  const factory TripBlock.image({
    required String id,
    required String storageUrl,
    required String caption,
    String? localPath,
  }) = ImageBlock;

  const factory TripBlock.video({
    required String id,
    required String storageUrl,
    required String caption,
    String? localPath,
  }) = VideoBlock;

  const factory TripBlock.costEntry({
    required String id,
    required List<CostItem> items,
    required String currency,
  }) = CostEntryBlock;

  const factory TripBlock.route({
    required String id,
    required List<GeoCoordinate> points,
    String? description,
  }) = RouteBlock;

  const factory TripBlock.safetyNote({
    required String id,
    required String text,
    required String level, // 'info' | 'warning' | 'danger'
  }) = SafetyNoteBlock;

  /// 🎙️ Voice Note — audio diary clip (uses `record` + `audioplayers` packages)
  const factory TripBlock.voiceNote({
    required String id,

    /// Firebase Storage URL (empty string when only stored locally)
    @Default('') String storageUrl,

    /// Duration in seconds
    required int durationSeconds,

    /// Local file path (non-null when recorded offline)
    String? localPath,

    /// Optional auto-transcription text
    String? transcript,
  }) = VoiceNoteBlock;

  factory TripBlock.fromJson(Map<String, dynamic> json) =>
      _$TripBlockFromJson(TripBlock.sanitizeJson(json));

  static Map<String, dynamic> sanitizeJson(Map<String, dynamic> json) {
    const validTypes = {'text', 'image', 'video', 'costEntry', 'route', 'safetyNote', 'voiceNote'};
    // Check runtimeType first, fall back to 'type' (used by legacy docs)
    String? type = json['runtimeType']?.toString();
    if (type == null || !validTypes.contains(type)) {
      type = json['type']?.toString();
    }
    if (type == null || !validTypes.contains(type)) {
      // Infer from field presence
      final sanitized = Map<String, dynamic>.from(json);
      if (sanitized['durationSeconds'] != null) {
        // voiceNote block — identified by durationSeconds field
        type = 'voiceNote';
        sanitized['storageUrl'] ??= '';
        sanitized['durationSeconds'] ??= 0;
      } else if (sanitized['storageUrl'] != null || sanitized['localPath'] != null) {
        final path = (sanitized['storageUrl'] ?? sanitized['localPath']).toString().toLowerCase();
        if (path.contains('.mp4') || path.contains('.mov') || path.contains('.avi') || path.contains('.mkv') || path.contains('video')) {
          type = 'video';
        } else {
          type = 'image';
        }
        sanitized['storageUrl'] ??= '';
        sanitized['caption'] ??= '';
      } else if (sanitized['items'] != null || sanitized['currency'] != null) {
        type = 'costEntry';
        sanitized['items'] ??= <dynamic>[];
        sanitized['currency'] ??= 'BDT';
      } else if (sanitized['points'] != null) {
        type = 'route';
        sanitized['points'] ??= <dynamic>[];
      } else if (sanitized['text'] != null || sanitized['level'] != null) {
        type = 'safetyNote';
        sanitized['text'] ??= '';
        sanitized['level'] ??= 'warning';
      } else {
        type = 'text';
        sanitized['content'] ??= '';
        sanitized['isBold'] ??= false;
      }
      sanitized['runtimeType'] = type;
      sanitized['id'] ??= 'blk_${DateTime.now().microsecondsSinceEpoch}';
      return sanitized;
    }
    // runtimeType or type is valid — ensure runtimeType key is set
    if (json['runtimeType'] == null) {
      final sanitized = Map<String, dynamic>.from(json);
      sanitized['runtimeType'] = type;
      sanitized['id'] ??= 'blk_${DateTime.now().microsecondsSinceEpoch}';
      return sanitized;
    }
    return json;
  }

  @override
  Map<String, dynamic> toJson();
}


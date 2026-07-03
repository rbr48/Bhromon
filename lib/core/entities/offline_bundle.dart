import 'package:freezed_annotation/freezed_annotation.dart';
import 'location_pin.dart';
import 'trip_log.dart';
import 'pro_tip.dart';
import '../value_objects/sync_status.dart';

part 'offline_bundle.freezed.dart';
part 'offline_bundle.g.dart';

@freezed
class OfflineBundle with _$OfflineBundle {
  const factory OfflineBundle({
    required String districtId,
    required String districtName,
    required List<LocationPin> pins,
    required List<TripLog> trips,
    required List<ProTip> tips,
    required List<String> tileKeys,
    required DateTime downloadedAt,
    required int sizeBytes,
    @Default(SyncStatus.synced) SyncStatus syncStatus,
  }) = _OfflineBundle;

  factory OfflineBundle.fromJson(Map<String, dynamic> json) =>
      _$OfflineBundleFromJson(json);
}

import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/repositories/i_ota_repository.dart';

part 'ota_state.freezed.dart';

@freezed
class OtaState with _$OtaState {
  const factory OtaState.initial() = OtaInitial;
  const factory OtaState.checking() = OtaChecking;
  const factory OtaState.updateAvailable({
    required AppVersionInfo info,
    @Default(0.0) double downloadProgress,
    @Default(false) bool isDownloading,
  }) = OtaUpdateAvailable;
  const factory OtaState.upToDate() = OtaUpToDate;
  const factory OtaState.error(String message) = OtaError;
}

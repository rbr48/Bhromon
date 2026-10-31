import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bhromon/app/di/injection.dart';
import 'package:bhromon/core/network/secure_network_client.dart';
import '../../domain/usecases/check_for_updates_usecase.dart';
import 'ota_state.dart';

/// Whether this build may download and install an APK from outside the store. Off by
/// default, so a store build never does it. A build that turns it on
/// (`--dart-define=BHROMON_APK_UPDATES=true`) still keeps only a download whose checksum
/// matches the one published with the version.
bool apkSelfUpdateEnabled() =>
    const bool.fromEnvironment('BHROMON_APK_UPDATES');

@injectable
class OtaCubit extends Cubit<OtaState> {
  // ignore: unused_field
  final CheckForUpdatesUseCase _checkForUpdates;

  OtaCubit(this._checkForUpdates) : super(const OtaInitial());

  Future<void> triggerCheck() async {
    // Disabled: Updates will be managed directly via the Google Play Store releases.
    emit(const OtaUpToDate());
  }

  /// Called by the dialog's INSTALL NOW button after a successful APK open.
  /// Clears the update state so the dialog doesn't reappear in this session.
  void markInstalled() {
    emit(const OtaUpToDate());
  }

  Future<void> startDownload() async {
    if (!apkSelfUpdateEnabled()) return;
    final currentState = state;
    if (currentState is! OtaUpdateAvailable) return;

    emit(currentState.copyWith(isDownloading: true, downloadProgress: 0.0));

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/bhromon-update.apk');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final secureClient = getIt<SecureNetworkClient>();
      await secureClient.dio.download(
        currentState.info.downloadUrl,
        tempFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total).clamp(0.0, 1.0);
            emit(currentState.copyWith(
              isDownloading: true,
              downloadProgress: progress,
            ));
          }
        },
      );

      final digest = await crypto.sha256.bind(tempFile.openRead()).first;
      if (digest.toString() != currentState.info.apkSha256) {
        await tempFile.delete();
        emit(const OtaError('The update did not match its checksum.'));
        return;
      }

      emit(currentState.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
      ));
    } catch (e) {
      emit(OtaError('Download failed: ${e.toString()}'));
    }
  }
}

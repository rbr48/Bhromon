import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';

class AppVersionInfo {
  final String latestVersion;
  final String downloadUrl;
  /// The SHA-256 of the APK at [downloadUrl], in lowercase hex. The download is kept
  /// only when its bytes match it.
  final String apkSha256;
  final bool isMandatory;

  AppVersionInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.apkSha256,
    required this.isMandatory,
  });
}

abstract class IOtaRepository {
  Future<Either<Failure, AppVersionInfo>> getLatestVersion();
}

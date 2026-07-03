import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';

class AppVersionInfo {
  final String latestVersion;
  final String downloadUrl;
  final bool isMandatory;

  AppVersionInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.isMandatory,
  });
}

abstract class IOtaRepository {
  Future<Either<Failure, AppVersionInfo>> getLatestVersion();
}

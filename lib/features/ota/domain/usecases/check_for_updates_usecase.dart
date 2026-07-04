import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../app/config/env.dart';
import '../repositories/i_ota_repository.dart';

@injectable
class CheckForUpdatesUseCase implements NoParamsUseCase<AppVersionInfo?> {
  final IOtaRepository _repository;

  CheckForUpdatesUseCase(this._repository);

  @override
  Future<Either<Failure, AppVersionInfo?>> call() async {
    final result = await _repository.getLatestVersion();
    return result.fold(
      (failure) => Left(failure),
      (info) {
        if (_isNewerVersion(info.latestVersion, Env.appVersion)) {
          return Right(info);
        }
        return const Right(null);
      },
    );
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final cleanLatest = latest.split('+')[0].split('-')[0];
      final cleanCurrent = current.split('+')[0].split('-')[0];

      final latestParts =
          cleanLatest.split('.').map((e) => int.parse(e.trim())).toList();
      final currentParts =
          cleanCurrent.split('.').map((e) => int.parse(e.trim())).toList();

      final length = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (var i = 0; i < length; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (e) {
      logWarning('Error parsing version', e);
    }
    return false;
  }
}

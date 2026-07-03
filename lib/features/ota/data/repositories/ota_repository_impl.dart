import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/secure_network_client.dart';
import '../../domain/repositories/i_ota_repository.dart';

@LazySingleton(as: IOtaRepository)
class OtaRepositoryImpl implements IOtaRepository {
  final SecureNetworkClient _networkClient;

  OtaRepositoryImpl(this._networkClient);

  @override
  Future<Either<Failure, AppVersionInfo>> getLatestVersion() async {
    try {
      final response = await _networkClient.dio.get<dynamic>('https://app.bhromon.fun/version.json');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final String? version;
        
        if (data is Map) {
          version = data['version'] as String?;
        } else if (data is String) {
          final decoded = jsonDecode(data);
          version = decoded is Map ? decoded['version'] as String? : null;
        } else {
          version = null;
        }

        if (version != null) {
          return Right(AppVersionInfo(
            latestVersion: version,
            downloadUrl: 'https://app.bhromon.fun/downloads/bhromon-latest.apk',
            isMandatory: false,
          ));
        }
      }
      return const Left(ServerFailure('Invalid response from version server'));
    } catch (e) {
      return Left(ServerFailure('Failed to check for updates: $e'));
    }
  }
}

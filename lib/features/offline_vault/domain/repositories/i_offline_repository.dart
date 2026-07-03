import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/offline_bundle.dart';
import '../../../../core/entities/outbox_entry.dart';

abstract class IOfflineRepository {
  Future<Either<Failure, List<OfflineBundle>>> getDownloadedBundles();
  Future<Either<Failure, Unit>> downloadBundle(String districtId);
  Future<Either<Failure, Unit>> deleteBundle(String districtId);
  Future<Either<Failure, List<OutboxEntry>>> getPendingOutboxEntries();
  Future<Either<Failure, Unit>> syncOutbox();
}

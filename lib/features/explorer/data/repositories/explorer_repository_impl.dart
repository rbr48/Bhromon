import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../domain/repositories/i_explorer_repository.dart';

/// Used when a caller asks for the top explorers without a limit.
const int kDefaultTopExplorers = 50;

@LazySingleton(as: IExplorerRepository)
class ExplorerRepositoryImpl implements IExplorerRepository {
  final FirebaseFirestore _firestore;

  ExplorerRepositoryImpl(this._firestore);

  @override
  Future<Either<Failure, ExplorerProfile>> getProfile(String uid) async {
    try {
      final doc =
          await _firestore.collection('explorer_profiles').doc(uid).get();
      if (!doc.exists) {
        return Left(
            NotFoundFailure('Explorer profile not found', resourceId: uid));
      }
      final data = doc.data()!;
      data['uid'] = doc.id;
      _fixTimestamp(data);
      return Right(ExplorerProfile.fromJson(data));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ExplorerProfile>>> getTopExplorers(
      {int? limit}) async {
    try {
      // Rank on the server: reading every profile to keep the top few
      // costs one document read per explorer on every feed load.
      final snapshot = await _firestore
          .collection('explorer_profiles')
          .orderBy('explorerScore.value', descending: true)
          .limit(limit ?? kDefaultTopExplorers)
          .get();
      final profiles = snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        _fixTimestamp(data);
        return ExplorerProfile.fromJson(data);
      }).toList();

      return Right(profiles);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  void _fixTimestamp(Map<String, dynamic> data) {
    if (data['createdAt'] is Timestamp) {
      data['createdAt'] =
          (data['createdAt'] as Timestamp).toDate().toIso8601String();
    }
  }
}

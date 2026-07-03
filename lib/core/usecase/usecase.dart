import 'package:dartz/dartz.dart';
import '../errors/failures.dart';

abstract class UseCase<TResult, Params> {
  Future<Either<Failure, TResult>> call(Params params);
}

abstract class NoParamsUseCase<TResult> {
  Future<Either<Failure, TResult>> call();
}

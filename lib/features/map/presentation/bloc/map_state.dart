import 'package:equatable/equatable.dart';
import '../../../../core/entities/location_pin.dart';

abstract class MapState extends Equatable {
  const MapState();
  @override
  List<Object?> get props => [];
}

class MapInitial extends MapState {
  const MapInitial();
}

class MapLoading extends MapState {
  const MapLoading();
}

class MapPinsLoaded extends MapState {
  final List<LocationPin> pins;
  const MapPinsLoaded(this.pins);

  @override
  List<Object?> get props => [pins];
}

class MapError extends MapState {
  final String message;
  const MapError(this.message);

  @override
  List<Object?> get props => [message];
}

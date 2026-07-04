import 'package:equatable/equatable.dart';
import '../../../../core/entities/location_pin.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class LoadPinsEvent extends MapEvent {
  final double lat;
  final double lng;
  final double radiusKm;

  const LoadPinsEvent(
      {required this.lat, required this.lng, this.radiusKm = 50.0});

  @override
  List<Object?> get props => [lat, lng, radiusKm];
}

class AddPinEvent extends MapEvent {
  final LocationPin pin;
  const AddPinEvent(this.pin);

  @override
  List<Object?> get props => [pin];
}

class ConfirmPinEvent extends MapEvent {
  final String pinId;
  const ConfirmPinEvent(this.pinId);

  @override
  List<Object?> get props => [pinId];
}

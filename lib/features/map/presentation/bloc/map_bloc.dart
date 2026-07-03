import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/entities/location_pin.dart';
import '../../domain/usecases/get_nearby_pins_usecase.dart';
import '../../domain/usecases/create_draft_pin_usecase.dart';
import '../../domain/usecases/confirm_pin_usecase.dart';
import 'map_event.dart';
import 'map_state.dart';

@injectable
class MapBloc extends Bloc<MapEvent, MapState> {
  final GetNearbyPinsUseCase _getNearbyPins;
  final CreateDraftPinUseCase _createDraftPin;
  final ConfirmPinUseCase _confirmPin;

  MapBloc(
    this._getNearbyPins,
    this._createDraftPin,
    this._confirmPin,
  ) : super(const MapInitial()) {
    on<LoadPinsEvent>((event, emit) async {
      emit(const MapLoading());
      final result = await _getNearbyPins(GetNearbyPinsParams(
        lat: event.lat,
        lng: event.lng,
        radiusKm: event.radiusKm,
      ));
      result.fold(
        (failure) => emit(MapError(failure.message)),
        (pins) => emit(MapPinsLoaded(pins)),
      );
    });

    on<AddPinEvent>((event, emit) async {
      final currentState = state;
      if (currentState is MapPinsLoaded) {
        final result = await _createDraftPin(event.pin);
        result.fold(
          (failure) => emit(MapError(failure.message)),
          (newPin) {
            final updatedPins = List<LocationPin>.from(currentState.pins)..add(newPin);
            emit(MapPinsLoaded(updatedPins));
          },
        );
      }
    });

    on<ConfirmPinEvent>((event, emit) async {
      final currentState = state;
      if (currentState is MapPinsLoaded) {
        final result = await _confirmPin(event.pinId);
        result.fold(
          (failure) => emit(MapError(failure.message)),
          (_) {
            add(const LoadPinsEvent(lat: 23.6850, lng: 90.3563));
          },
        );
      }
    });
  }
}

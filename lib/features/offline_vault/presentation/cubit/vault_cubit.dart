import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/download_vault_usecase.dart';
import '../../domain/usecases/delete_vault_usecase.dart';
import '../../domain/usecases/sync_outbox_usecase.dart';
import '../../domain/usecases/get_vault_status_usecase.dart';
import '../../../../core/services/tile_downloader.dart' show TileDownloader, MapProgress;
import '../../../../core/database/app_database.dart';
import '../../../../core/entities/outbox_entry.dart';
import 'vault_state.dart';

@injectable
class VaultCubit extends Cubit<VaultState> {
  final DownloadVaultUseCase _downloadVault;
  final DeleteVaultUseCase _deleteVault;
  final SyncOutboxUseCase _syncOutbox;
  final GetVaultStatusUseCase _getVaultStatus;
  final AppDatabase _database;

  StreamSubscription<MapProgress>? _downloadSubscription;

  VaultCubit(
    this._downloadVault,
    this._deleteVault,
    this._syncOutbox,
    this._getVaultStatus,
    this._database,
  ) : super(const VaultState()) {
    _refreshStatus();
    _downloadSubscription = TileDownloader.progressStream.listen((event) {
      if (state.downloadProgress.containsKey(event.districtId)) {
        final updatedProgress = Map<String, double>.from(state.downloadProgress)
          ..[event.districtId] = event.progress;
        emit(state.copyWith(downloadProgress: updatedProgress));
      }
    });
  }

  Future<void> _refreshStatus() async {
    emit(state.copyWith(status: VaultStatus.loading));
    
    List<OutboxEntry> conflicts = [];
    try {
      final jsonStrings = await _database.getConflictsOrdered();
      conflicts = jsonStrings.map((jsonStr) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return OutboxEntry.fromJson(map);
      }).toList();
    } catch (_) {}

    final result = await _getVaultStatus();
    result.fold(
      (failure) => emit(state.copyWith(status: VaultStatus.error, errorMessage: failure.message, conflicts: conflicts)),
      (bundles) {
        final Map<String, int> downloaded = {};
        for (final bundle in bundles) {
          downloaded[bundle.districtId] = bundle.sizeBytes ~/ (1024 * 1024);
        }
        final List<String> list = state.districts.isEmpty ? _getDefaultDistricts() : state.districts;
        emit(state.copyWith(
          downloadedDistricts: downloaded,
          districts: list,
          status: VaultStatus.loaded,
          errorMessage: null,
          conflicts: conflicts,
        ));
      },
    );
  }

  List<String> _getDefaultDistricts() {
    return const [
      'Sylhet',
      'Rangamati',
      'Khulna',
      "Cox's Bazar",
      'Bandarban',
      'Dhaka',
      'Sajek',
    ];
  }

  Future<void> refreshDistricts() async {
    await _refreshStatus();
  }

  Future<void> downloadDistrict(String district) async {
    if (state.downloadProgress.containsKey(district) || state.downloadedDistricts.containsKey(district)) {
      return;
    }

    emit(state.copyWith(
      downloadProgress: Map<String, double>.from(state.downloadProgress)..[district] = 0.0,
    ));

    try {
      final result = await _downloadVault(district);
      result.fold(
        (failure) {
          final updatedProgress = Map<String, double>.from(state.downloadProgress)..remove(district);
          emit(state.copyWith(
            downloadProgress: updatedProgress,
            errorMessage: failure.message,
          ));
        },
        (_) async {
          await _refreshStatus();
          final updatedProgress = Map<String, double>.from(state.downloadProgress)..remove(district);
          emit(state.copyWith(downloadProgress: updatedProgress));
        },
      );
    } catch (e) {
      final updatedProgress = Map<String, double>.from(state.downloadProgress)..remove(district);
      emit(state.copyWith(
        downloadProgress: updatedProgress,
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> close() {
    _downloadSubscription?.cancel();
    return super.close();
  }

  Future<void> deleteDistrict(String district) async {
    await _deleteVault(district);
    await _refreshStatus();
  }

  Future<void> syncPendingData() async {
    emit(state.copyWith(isSyncing: true));
    await _syncOutbox();
    await _refreshStatus();
    emit(state.copyWith(isSyncing: false));
  }

  Future<void> resolveConflictKeepLocal(OutboxEntry entry) async {
    await _database.deleteConflict(entry.id);
    await _database.enqueueOutbox(
      entry.id,
      DateTime.now().millisecondsSinceEpoch,
      jsonEncode(entry.copyWith(status: 'pending', retryCount: 0).toJson()),
      status: 'pending',
    );
    await _refreshStatus();
    await syncPendingData();
  }

  Future<void> resolveConflictKeepServer(OutboxEntry entry) async {
    await _database.deleteConflict(entry.id);
    await _refreshStatus();
  }

  Future<void> resolveConflictMerge(OutboxEntry entry, Map<String, dynamic> mergedPayload) async {
    await _database.deleteConflict(entry.id);
    await _database.enqueueOutbox(
      entry.id,
      DateTime.now().millisecondsSinceEpoch,
      jsonEncode(entry.copyWith(status: 'pending', retryCount: 0, payload: mergedPayload).toJson()),
      status: 'pending',
    );
    await _refreshStatus();
    await syncPendingData();
  }
}

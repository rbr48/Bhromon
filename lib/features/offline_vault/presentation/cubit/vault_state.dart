import 'package:equatable/equatable.dart';
import '../../../../core/entities/outbox_entry.dart';

enum VaultStatus { initial, loading, loaded, error }

class VaultState extends Equatable {
  final List<String> districts;
  final Map<String, int> downloadedDistricts; // 'District' -> size in MB
  final Map<String, double> downloadProgress; // 'District' -> progress (0.0 to 1.0)
  final bool isSyncing;
  final VaultStatus status;
  final String? errorMessage;
  final List<OutboxEntry> conflicts;

  const VaultState({
    this.districts = const [],
    this.downloadedDistricts = const {},
    this.downloadProgress = const {},
    this.isSyncing = false,
    this.status = VaultStatus.initial,
    this.errorMessage,
    this.conflicts = const [],
  });

  VaultState copyWith({
    List<String>? districts,
    Map<String, int>? downloadedDistricts,
    Map<String, double>? downloadProgress,
    bool? isSyncing,
    VaultStatus? status,
    String? errorMessage,
    List<OutboxEntry>? conflicts,
  }) {
    return VaultState(
      districts: districts ?? this.districts,
      downloadedDistricts: downloadedDistricts ?? this.downloadedDistricts,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isSyncing: isSyncing ?? this.isSyncing,
      status: status ?? this.status,
      errorMessage: errorMessage,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  @override
  List<Object?> get props => [
        districts,
        downloadedDistricts,
        downloadProgress,
        isSyncing,
        status,
        errorMessage,
        conflicts,
      ];
}

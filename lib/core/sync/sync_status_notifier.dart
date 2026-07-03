import 'package:flutter/foundation.dart';

enum SyncState { idle, syncing, error, pendingItems }

class SyncStatusNotifier extends ChangeNotifier {
  SyncState _state = SyncState.idle;
  int _pendingCount = 0;
  String? _lastError;

  SyncState get state => _state;
  int get pendingCount => _pendingCount;
  String? get lastError => _lastError;

  void setSyncing() {
    _state = SyncState.syncing;
    notifyListeners();
  }

  void setIdle() {
    _state = SyncState.idle;
    notifyListeners();
  }

  void setPendingItems(int count) {
    _state = SyncState.pendingItems;
    _pendingCount = count;
    notifyListeners();
  }

  void setError(String error) {
    _state = SyncState.error;
    _lastError = error;
    notifyListeners();
  }
}

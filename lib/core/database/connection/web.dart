import 'package:drift/drift.dart';
// Legacy drift web API - intentional until migrating to drift's WASM backend.
// ignore: experimental_member_use, deprecated_member_use
import 'package:drift/web.dart';

QueryExecutor openConnection() {
  return WebDatabase('bhromon_web_db');
}

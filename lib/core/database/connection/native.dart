import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'bhromon_drift.db'));

    // Retrieve or generate a secure database key from secure storage
    const secureStorage = FlutterSecureStorage();
    const keyName = 'drift_encryption_key';
    String? dbKey = await secureStorage.read(key: keyName);
    if (dbKey == null) {
      dbKey = const Uuid().v4(); // Generate a secure password
      await secureStorage.write(key: keyName, value: dbKey);
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        // Enforce SQLCipher encryption key if SQLCipher is compiled in SQLite.
        // If standard SQLite is used, this PRAGMA is ignored without error.
        database.execute("PRAGMA key = '$dbKey';");
      },
    );
  });
}

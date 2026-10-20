import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import '../config.dart';
import '../domain/errors.dart';

/// Tolak penyimpanan sementara dan mode multitab yang tidak aman.
QueryExecutor openConnection() => DatabaseConnection.delayed(
  Future(() async {
    final result = await WasmDatabase.open(
      databaseName: AppConfig.databaseName,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    if (result.chosenImplementation == WasmStorageImplementation.inMemory ||
        result.chosenImplementation ==
            WasmStorageImplementation.unsafeIndexedDb) {
      await result.resolvedExecutor.close();
      throw const QParkException(
        'Browser belum menyediakan penyimpanan yang aman. Gunakan browser terbaru, izinkan penyimpanan situs, dan buka melalui HTTPS atau localhost. Server harus memakai header COOP/COEP.',
      );
    }
    return result.resolvedExecutor;
  }),
);

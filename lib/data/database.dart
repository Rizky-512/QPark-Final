import 'package:drift/drift.dart';

/// SQL eksplisit menjaga skema dan trigger yang sama di native dan browser.
class QParkDatabase extends GeneratedDatabase {
  QParkDatabase(super.executor, this.schema);
  final String schema;
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final statement in schema.split('-- @statement')) {
        if (statement.trim().isNotEmpty) await customStatement(statement);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}

import 'package:sqflite/sqflite.dart';

/// Provides and manages the SQLite database for the Action Scheduler SDK.
///
/// Handles database creation, schema migrations, and provides
/// access to the database instance.
class DatabaseProvider {
  static const String _databaseName = 'action_scheduler.db';
  static const int _databaseVersion = 1;

  Database? _database;

  /// Returns the database instance, creating it if necessary.
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = '$databasesPath/$_databaseName';

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Table for scheduled action definitions
    await db.execute('''
      CREATE TABLE scheduled_actions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        type INTEGER NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        dayOfWeek INTEGER,
        dayOfMonth INTEGER,
        intervalMinutes INTEGER,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        lastRunAt TEXT,
        nextRunAt TEXT,
        hasNotification INTEGER NOT NULL DEFAULT 0,
        notifTitle TEXT,
        notifBody TEXT,
        leadTimeMinutes INTEGER,
        notifEnabled INTEGER,
        metadata TEXT
      )
    ''');

    // Table for execution history / logs
    await db.execute('''
      CREATE TABLE execution_logs (
        id TEXT PRIMARY KEY,
        actionId TEXT NOT NULL,
        scheduledTime TEXT NOT NULL,
        executionTime TEXT,
        status INTEGER NOT NULL,
        durationMs INTEGER NOT NULL DEFAULT 0,
        errorMessage TEXT,
        failureReason INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (actionId) REFERENCES scheduled_actions(id) ON DELETE CASCADE
      )
    ''');

    // Index for efficient querying of logs by action
    await db.execute('''
      CREATE INDEX idx_execution_logs_actionId ON execution_logs(actionId)
    ''');

    // Index for querying logs by time
    await db.execute('''
      CREATE INDEX idx_execution_logs_scheduledTime ON execution_logs(scheduledTime)
    ''');

    // Index for querying logs by status
    await db.execute('''
      CREATE INDEX idx_execution_logs_status ON execution_logs(status)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future schema migrations go here.
  }

  /// Closes the database connection.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Deletes all data from all tables (useful for testing).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('execution_logs');
    await db.delete('scheduled_actions');
  }
}

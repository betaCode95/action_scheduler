import 'package:sqflite/sqflite.dart';

import '../models/scheduled_action.dart';
import 'database_provider.dart';

/// Repository for CRUD operations on scheduled actions.
///
/// All actions are persisted in SQLite, ensuring they survive
/// app restarts and device reboots.
class ActionRepository {
  final DatabaseProvider _dbProvider;

  ActionRepository(this._dbProvider);

  /// Inserts a new scheduled action.
  Future<void> insert(ScheduledAction action) async {
    final db = await _dbProvider.database;
    await db.insert(
      'scheduled_actions',
      action.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates an existing scheduled action.
  Future<void> update(ScheduledAction action) async {
    final db = await _dbProvider.database;
    await db.update(
      'scheduled_actions',
      action.toMap(),
      where: 'id = ?',
      whereArgs: [action.id],
    );
  }

  /// Deletes a scheduled action by its ID.
  Future<void> delete(String id) async {
    final db = await _dbProvider.database;
    await db.delete(
      'scheduled_actions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retrieves a single action by ID.
  Future<ScheduledAction?> getById(String id) async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'scheduled_actions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return ScheduledAction.fromMap(results.first);
  }

  /// Retrieves all registered actions.
  Future<List<ScheduledAction>> getAll() async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'scheduled_actions',
      orderBy: 'createdAt DESC',
    );
    return results.map((m) => ScheduledAction.fromMap(m)).toList();
  }

  /// Retrieves only active actions.
  Future<List<ScheduledAction>> getActive() async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'scheduled_actions',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'nextRunAt ASC',
    );
    return results.map((m) => ScheduledAction.fromMap(m)).toList();
  }

  /// Retrieves actions that are due to run (nextRunAt <= now).
  Future<List<ScheduledAction>> getDueActions() async {
    final db = await _dbProvider.database;
    final now = DateTime.now().toIso8601String();
    final results = await db.query(
      'scheduled_actions',
      where: 'isActive = ? AND nextRunAt IS NOT NULL AND nextRunAt <= ?',
      whereArgs: [1, now],
      orderBy: 'nextRunAt ASC',
    );
    return results.map((m) => ScheduledAction.fromMap(m)).toList();
  }

  /// Updates the next run time and last run time for an action.
  Future<void> updateRunTimes({
    required String id,
    required DateTime? lastRunAt,
    required DateTime? nextRunAt,
  }) async {
    final db = await _dbProvider.database;
    await db.update(
      'scheduled_actions',
      {
        'lastRunAt': lastRunAt?.toIso8601String(),
        'nextRunAt': nextRunAt?.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Toggles the active state of an action.
  Future<void> setActive(String id, bool isActive) async {
    final db = await _dbProvider.database;
    await db.update(
      'scheduled_actions',
      {'isActive': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the count of all registered actions.
  Future<int> count() async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM scheduled_actions');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

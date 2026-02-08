import 'package:sqflite/sqflite.dart';

import '../models/execution_record.dart';
import 'database_provider.dart';

/// Repository for CRUD operations on execution logs.
///
/// Provides a comprehensive audit trail of all action executions,
/// including successes, failures, and missed runs.
class ExecutionRepository {
  final DatabaseProvider _dbProvider;

  ExecutionRepository(this._dbProvider);

  /// Inserts a new execution record.
  Future<void> insert(ExecutionRecord record) async {
    final db = await _dbProvider.database;
    await db.insert(
      'execution_logs',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves execution logs for a specific action.
  ///
  /// Results are ordered by scheduled time (most recent first).
  /// Use [limit] and [offset] for pagination.
  Future<List<ExecutionRecord>> getByActionId(
    String actionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'execution_logs',
      where: 'actionId = ?',
      whereArgs: [actionId],
      orderBy: 'scheduledTime DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((m) => ExecutionRecord.fromMap(m)).toList();
  }

  /// Retrieves all execution logs across all actions.
  Future<List<ExecutionRecord>> getAll({
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'execution_logs',
      orderBy: 'scheduledTime DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((m) => ExecutionRecord.fromMap(m)).toList();
  }

  /// Retrieves only failed executions across all actions.
  Future<List<ExecutionRecord>> getFailures({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'execution_logs',
      where: 'status = ? OR status = ?',
      whereArgs: [ExecutionStatus.failed.index, ExecutionStatus.missed.index],
      orderBy: 'scheduledTime DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((m) => ExecutionRecord.fromMap(m)).toList();
  }

  /// Retrieves only successful executions for a specific action.
  Future<List<ExecutionRecord>> getSuccesses(
    String actionId, {
    int limit = 50,
  }) async {
    final db = await _dbProvider.database;
    final results = await db.query(
      'execution_logs',
      where: 'actionId = ? AND status = ?',
      whereArgs: [actionId, ExecutionStatus.success.index],
      orderBy: 'scheduledTime DESC',
      limit: limit,
    );
    return results.map((m) => ExecutionRecord.fromMap(m)).toList();
  }

  /// Returns execution statistics for a specific action.
  Future<Map<String, int>> getStats(String actionId) async {
    final db = await _dbProvider.database;
    final total = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM execution_logs WHERE actionId = ?',
          [actionId],
        )) ??
        0;
    final successes = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM execution_logs WHERE actionId = ? AND status = ?',
          [actionId, ExecutionStatus.success.index],
        )) ??
        0;
    final failures = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM execution_logs WHERE actionId = ? AND (status = ? OR status = ?)',
          [
            actionId,
            ExecutionStatus.failed.index,
            ExecutionStatus.missed.index,
          ],
        )) ??
        0;
    final avgDuration = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT AVG(durationMs) FROM execution_logs WHERE actionId = ? AND status = ?',
          [actionId, ExecutionStatus.success.index],
        )) ??
        0;

    return {
      'total': total,
      'successes': successes,
      'failures': failures,
      'avgDurationMs': avgDuration,
    };
  }

  /// Deletes all logs for a specific action.
  Future<void> deleteByActionId(String actionId) async {
    final db = await _dbProvider.database;
    await db.delete(
      'execution_logs',
      where: 'actionId = ?',
      whereArgs: [actionId],
    );
  }

  /// Deletes old logs beyond a retention period.
  Future<int> pruneOlderThan(Duration retention) async {
    final db = await _dbProvider.database;
    final cutoff = DateTime.now().subtract(retention).toIso8601String();
    return await db.delete(
      'execution_logs',
      where: 'scheduledTime < ?',
      whereArgs: [cutoff],
    );
  }

  /// Returns the total count of execution records.
  Future<int> count() async {
    final db = await _dbProvider.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM execution_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

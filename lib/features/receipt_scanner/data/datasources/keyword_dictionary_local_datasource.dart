/// The only place SQL is written for the keyword dictionary.
///
/// Throws [CacheException] on failure and returns models; the repository
/// above converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/keyword_match_model.dart';

/// Reads the keyword dictionary in the local encrypted database.
abstract interface class KeywordDictionaryLocalDataSource {
  /// Every row whose keyword matches [text] by its own `match_type`,
  /// highest priority first, then the longer keyword, then by id.
  Future<List<KeywordMatchModel>> matchesFor(String text);
}

/// sqflite implementation of [KeywordDictionaryLocalDataSource].
class KeywordDictionaryLocalDataSourceImpl
    implements KeywordDictionaryLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// No change bus: nothing here writes, and nothing watches the
  /// dictionary. FR-RCP-015's write, when it lands, notifies nobody either
  /// — the next scan simply reads the new row.
  const KeywordDictionaryLocalDataSourceImpl(this._db);

  final Database _db;

  /// DBD §6.2's lookup, with three departures. No `LIMIT 1`, because the
  /// categoriser weighs every candidate (FR-RCP-007). `instr` and `substr`
  /// instead of `LIKE`, because a keyword holding `%` or `_` — which a
  /// user's correction may — would otherwise be a wildcard. And the text
  /// is lower-cased in Dart before it gets here: SQLite's `lower()` folds
  /// ASCII only, and Dart's handles what a receipt can print.
  static const String _lookup = '''
SELECT kd.keyword, kd.category_id, c.name AS category_name,
       kd.match_type, kd.priority, kd.is_user_defined
  FROM keyword_dictionary kd
  JOIN categories c ON c.id = kd.category_id
 WHERE (kd.match_type = 'exact'      AND kd.keyword = ?1)
    OR (kd.match_type = 'contains'   AND instr(?1, kd.keyword) > 0)
    OR (kd.match_type = 'startswith'
        AND substr(?1, 1, length(kd.keyword)) = kd.keyword)
 ORDER BY kd.priority DESC, length(kd.keyword) DESC, kd.id ASC
''';

  @override
  Future<List<KeywordMatchModel>> matchesFor(String text) async {
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return _guard('look up "$text"', () async {
      final rows = await _db.rawQuery(_lookup, [needle]);
      return [for (final row in rows) KeywordMatchModel.fromMap(row)];
    });
  }

  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on CacheException {
      rethrow;
    } on DatabaseException catch (e) {
      throw CacheException('Could not $action.', cause: e);
    }
  }
}

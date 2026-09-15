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

  /// Adds one to `usage_count` on every row that matches [text] by its
  /// own `match_type` and maps to [categoryId]. FR-RCP-009.
  ///
  /// Returns how many rows moved — zero is not an error.
  Future<int> recordApplied({required String text, required int categoryId});
}

/// sqflite implementation of [KeywordDictionaryLocalDataSource].
class KeywordDictionaryLocalDataSourceImpl
    implements KeywordDictionaryLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// No change bus: nothing watches the dictionary. [recordApplied]
  /// notifies nobody, and FR-RCP-015's write, when it lands, will not
  /// either — the next scan simply reads the new row.
  const KeywordDictionaryLocalDataSourceImpl(this._db);

  final Database _db;

  /// Whether a row's keyword matches `?1` by the row's own `match_type`.
  ///
  /// `instr` and `substr` instead of `LIKE`, because a keyword holding `%`
  /// or `_` — which a user's correction may — would otherwise be a
  /// wildcard. The text is lower-cased in Dart before it gets here:
  /// SQLite's `lower()` folds ASCII only, and Dart's handles what a
  /// receipt can print. Shared by the lookup and the usage count so the
  /// two cannot disagree about what "matches" means.
  static const String _matches = '''
   ((kd.match_type = 'exact'      AND kd.keyword = ?1)
    OR (kd.match_type = 'contains'   AND instr(?1, kd.keyword) > 0)
    OR (kd.match_type = 'startswith'
        AND substr(?1, 1, length(kd.keyword)) = kd.keyword))''';

  /// DBD §6.2's lookup, without its `LIMIT 1`: the categoriser weighs
  /// every candidate (FR-RCP-007).
  static const String _lookup =
      '''
SELECT kd.keyword, kd.category_id, c.name AS category_name,
       kd.match_type, kd.priority, kd.is_user_defined
  FROM keyword_dictionary kd
  JOIN categories c ON c.id = kd.category_id
 WHERE $_matches
 ORDER BY kd.priority DESC, length(kd.keyword) DESC, kd.id ASC
''';

  /// The count, on the rows the lookup would have returned for the
  /// category. `keyword_dictionary kd` is aliased so [_matches] reads the
  /// same in both statements.
  static const String _count =
      '''
UPDATE keyword_dictionary
   SET usage_count = usage_count + 1
 WHERE id IN (
   SELECT kd.id FROM keyword_dictionary kd
    WHERE kd.category_id = ?2 AND $_matches)
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

  @override
  Future<int> recordApplied({
    required String text,
    required int categoryId,
  }) async {
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) return 0;
    return _guard(
      'count a use of "$text"',
      () => _db.rawUpdate(_count, [needle, categoryId]),
    );
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

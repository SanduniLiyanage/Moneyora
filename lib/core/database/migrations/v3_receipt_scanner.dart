/// Schema version 3 — Sprint 6's two receipt-scanner fixes. E-31.
///
/// **`receipt_scans.receipt_number`.** FR-RCP-005 parses the receipt's own
/// printed identifier and the DBD's table has nowhere to put it (E-31,
/// item 3). One nullable text column, additive per SDD §5.3: not every
/// receipt prints one legibly.
///
/// **`keyword_dictionary` recreated with `ON DELETE CASCADE`.** DBD §2.2
/// says a category's keywords go with it; v1 built the foreign key without
/// the cascade, so once the dictionary holds rows, deleting an otherwise
/// unused category fails on the constraint — with FR-RCP-015's user-taught
/// keywords the rows most worth keeping and least worth blocking on.
///
/// This is the one place the schema drops a table, against
/// `database_helper.dart`'s additive-only rule, and it is safe for a reason
/// the rule's own rationale supports: the rule guards rows, and this table
/// has never held one. No datasource wrote to `keyword_dictionary` before
/// Sprint 6 and the seed that fills it (`seed/keyword_seed.dart`) runs
/// after migration. Every install upgrading to v3 drops an empty table.
/// The recreated table is otherwise the v1 stanza, so a reader of
/// `v1_initial.dart` is not misled on any column.
library;

/// The version this migration produces.
const int v3SchemaVersion = 3;

/// The statements, in order.
const List<String> v3Statements = <String>[
  'ALTER TABLE receipt_scans ADD COLUMN receipt_number TEXT',
  'DROP INDEX IF EXISTS idx_keyword_dict_keyword',
  'DROP TABLE keyword_dictionary',
  '''
CREATE TABLE keyword_dictionary (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  keyword         TEXT    NOT NULL,
  category_id     INTEGER NOT NULL
                  REFERENCES categories(id) ON DELETE CASCADE,
  match_type      TEXT    NOT NULL DEFAULT 'contains'
                  CHECK(match_type IN ('exact','contains','startswith')),
  priority        INTEGER NOT NULL DEFAULT 5,
  usage_count     INTEGER NOT NULL DEFAULT 0,
  is_user_defined INTEGER NOT NULL DEFAULT 0,
  UNIQUE(keyword, category_id)
)''',
  'CREATE INDEX idx_keyword_dict_keyword '
      'ON keyword_dictionary(keyword, priority DESC)',
];

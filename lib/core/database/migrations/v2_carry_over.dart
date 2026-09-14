/// Schema version 2 — where FR-PLN-014's Carry Over lives. E-33.
///
/// "Carry Over (deduct overspend from next period's allocation)" is a
/// decision taken on one plan that has to reach a plan that does not exist
/// yet, so it has to be stored; the DBD's `plan_allocations` has no column
/// for it. One nullable-by-default integer, additive per SDD §5.3, on the
/// row it was decided for: the amount, in cents (E-06), to deduct from this
/// category in whichever plan comes next. Zero for every existing row and
/// for every row FR-PLN-014 has not touched.
library;

/// The version this migration produces.
const int v2SchemaVersion = 2;

/// The statements, in order.
const List<String> v2Statements = <String>[
  'ALTER TABLE plan_allocations '
      'ADD COLUMN carry_over_cents INTEGER NOT NULL DEFAULT 0 '
      'CHECK(carry_over_cents >= 0)',
];

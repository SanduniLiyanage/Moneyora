/// The rows a brand-new install starts with.
///
/// FR-EXP-003 (15 default expense categories), FR-INC-002 (3 income
/// categories), FR-ACC-001 (a first account). Runs once, inside the same
/// transaction as the v1 migration, so a fresh database is never briefly
/// usable-but-empty.
///
/// ## About the colours
///
/// Category colours are a **categorical palette**: 15 hues that must stay
/// distinguishable from one another, including to the ~8% of men with a colour
/// vision deficiency. They were not chosen by eye — an eyeballed set was tried
/// first and failed hard, with three colours reading as grey, one pair
/// indistinguishable to protanopes, and another pair indistinguishable even
/// with normal vision.
///
/// The set below is validated in **both** light and dark mode against the
/// lightness band, chroma floor, CVD separation, normal-vision floor and
/// surface contrast. Dark is a separately chosen set of steps, not an
/// automatic lightening of the light one.
///
/// Two deliberate consequences:
///
/// * **The order below is the validated order.** Categories display
///   alphabetically, so slot N sits next to slot N±1 on screen, and the
///   validation targets exactly those adjacent pairs. Reordering the list
///   invalidates the result — re-run the validator if you do.
/// * **Colour is never the only encoding.** The worst adjacent pair sits in
///   the 6–8 ΔE band, which is permissible only alongside a second channel.
///   SRS §4.1 already requires the donut chart to carry percentage labels and
///   category icons, and every list row shows an icon and a name. Do not build
///   a view that distinguishes categories by colour alone.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

/// One default row, in display order.
typedef SeedCategory = ({
  String name,
  String icon,
  String colorLight,
  String colorDark,
  String type,
});

/// FR-EXP-003 — the 15 default expense categories, alphabetical.
///
/// Alphabetical order is not cosmetic here: it is the order the validator was
/// run against, and it is the order the Categories drawer renders in.
const List<SeedCategory> defaultExpenseCategories = <SeedCategory>[
  (
    name: 'Bills',
    icon: 'receipt',
    colorLight: '#2a78d6',
    colorDark: '#3987e5',
    type: 'expense',
  ),
  (
    name: 'Car',
    icon: 'car',
    colorLight: '#00897b',
    colorDark: '#00897b',
    type: 'expense',
  ),
  (
    name: 'Clothes',
    icon: 'tshirt',
    colorLight: '#eb6834',
    colorDark: '#d95926',
    type: 'expense',
  ),
  (
    name: 'Communications',
    icon: 'phone',
    colorLight: '#1baf7a',
    colorDark: '#199e70',
    type: 'expense',
  ),
  (
    name: 'Eating Out',
    icon: 'cutlery',
    colorLight: '#ad1457',
    colorDark: '#c2185b',
    type: 'expense',
  ),
  (
    name: 'Entertainment',
    icon: 'cocktail',
    colorLight: '#eda100',
    colorDark: '#c98500',
    type: 'expense',
  ),
  (
    name: 'Food',
    icon: 'basket',
    colorLight: '#7b5ea7',
    colorDark: '#9085e9',
    type: 'expense',
  ),
  (
    name: 'Gifts',
    icon: 'gift',
    colorLight: '#008300',
    colorDark: '#008300',
    type: 'expense',
  ),
  (
    name: 'Health',
    icon: 'thermometer',
    colorLight: '#e87ba4',
    colorDark: '#d55181',
    type: 'expense',
  ),
  (
    name: 'House',
    icon: 'home',
    colorLight: '#7cb342',
    colorDark: '#689f38',
    type: 'expense',
  ),
  (
    name: 'Pets',
    icon: 'cat',
    colorLight: '#d81b60',
    colorDark: '#d81b60',
    type: 'expense',
  ),
  (
    name: 'Sports',
    icon: 'runner',
    colorLight: '#9e9d24',
    colorDark: '#8c8c1f',
    type: 'expense',
  ),
  (
    name: 'Taxi',
    icon: 'taxi',
    colorLight: '#0097a7',
    colorDark: '#0097a7',
    type: 'expense',
  ),
  (
    name: 'Toiletry',
    icon: 'toothbrush',
    colorLight: '#e34948',
    colorDark: '#e66767',
    type: 'expense',
  ),
  (
    name: 'Transport',
    icon: 'train',
    colorLight: '#9c27b0',
    colorDark: '#ab47bc',
    type: 'expense',
  ),
];

/// FR-INC-002 — the 3 default income categories.
///
/// These reuse hues from the expense set, which is safe because the two never
/// share a chart: the donut is expenses only (FR-RPT-001), and income appears
/// in the income-vs-expense bar chart as a single aggregate series.
const List<SeedCategory> defaultIncomeCategories = <SeedCategory>[
  (
    name: 'Deposits',
    icon: 'money-bag',
    colorLight: '#2a78d6',
    colorDark: '#3987e5',
    type: 'income',
  ),
  (
    name: 'Salary',
    icon: 'coins',
    colorLight: '#eda100',
    colorDark: '#c98500',
    type: 'income',
  ),
  (
    name: 'Savings',
    icon: 'piggy-bank',
    colorLight: '#008300',
    colorDark: '#008300',
    type: 'income',
  ),
];

/// Every default category, expense first, in display order.
List<SeedCategory> get defaultCategories => <SeedCategory>[
  ...defaultExpenseCategories,
  ...defaultIncomeCategories,
];

/// The account a new install starts with. FR-ACC-001.
///
/// One Cash account, because the alternative — starting with none — means the
/// first thing a user meets is a form rather than the app.
const ({String name, String icon, String type, String currency})
defaultAccount = (name: 'Cash', icon: 'cash', type: 'cash', currency: 'LKR');

/// Writes the default user, account and categories into a fresh database.
///
/// Idempotent by construction: `categories` carries `UNIQUE(user_id, name,
/// type)` and the user row has a fixed id, so a second call conflicts rather
/// than silently doubling every category — which is what a first-launch check
/// that misfires would otherwise produce.
Future<void> applyDefaultSeed(DatabaseExecutor db) async {
  final now = DateTime.now().toUtc().toIso8601String();

  await db.insert('users', {'id': 1, 'created_at': now});

  await db.insert('accounts', {
    'user_id': 1,
    'name': defaultAccount.name,
    'icon': defaultAccount.icon,
    'type': defaultAccount.type,
    'currency': defaultAccount.currency,
    'initial_balance_date': now.substring(0, 10),
    'created_at': now,
  });

  var order = 0;
  for (final category in defaultCategories) {
    await db.insert('categories', {
      'user_id': 1,
      'name': category.name,
      'icon': category.icon,
      // Only the light value is stored. The dark step is a presentation
      // concern resolved at render time from the same slot, so a user who
      // switches theme does not need every row rewritten.
      'color': category.colorLight,
      'type': category.type,
      'is_default': 1,
      'sort_order': order++,
    });
  }
}

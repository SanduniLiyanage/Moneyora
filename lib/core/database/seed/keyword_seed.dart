/// The keyword dictionary a fresh install starts with. FR-RCP-007, Layer 1.
///
/// The SRS asks for a "pre-built map (e.g., 'Rice' → Food, 'Shampoo' →
/// Toiletry, 'Petrol' → Car)" and the DBD for 200+ entries in a file it
/// names but never wrote. This is that file. The words are the ones that
/// print on Sri Lankan receipts — the brands (Dialog, PickMe, Ceypetco),
/// the staples (samba, dhal, sprats), the eateries (kottu, hoppers) — with
/// the general English a supermarket prints beside them.
///
/// ## Match types
///
/// The lookup compares the whole lower-cased item text with each keyword
/// by the row's `match_type`. `contains` is the default and the right
/// choice for nearly every word: an item prints as `RICE 5KG`, not `rice`,
/// so `exact` almost never fires on a line item. The exceptions:
///
/// - **`startswith` for words of three letters or fewer** (`bus`, `tea`,
///   `oil`, `egg`, `jam`, `gas`), which as substrings would fire inside
///   unrelated words — `robust`, `steak`, `boiled`, `veggie`, `pyjamas`.
///   A short word at the start of a line is usually the product; the same
///   letters inside another word are noise. (A longer word that *begins*
///   with them, `business`, still fires — the price of three letters.)
/// - **`exact` for nothing in the seed.** It is the match type a user's
///   correction can use (FR-RCP-015) when they want one precise line
///   remembered, and the schema keeps it for that.
///
/// A category's keywords are not disjoint from another's on purpose:
/// `hotel` is Eating Out because that is what the word means on a Sri
/// Lankan street, and the categoriser weighs every match, so a word that
/// could go two ways is decided by the merchant and the user's history,
/// not by which keyword happens to be first.
///
/// ## Applying it
///
/// [applyKeywordSeed] runs on every open, not only on first launch, because
/// installs that predate Sprint 6 have the table and nothing in it. It is
/// idempotent — one count on the fast path, `INSERT OR IGNORE` against the
/// `UNIQUE(keyword, category_id)` constraint on the slow one — and it maps
/// each category by its *default name*, so a keyword whose category the
/// user has renamed or deleted is skipped rather than guessed at.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

/// One seed row: the keyword, the default category's name, and how to
/// match.
typedef SeedKeyword = ({String keyword, String category, String match});

SeedKeyword _c(String keyword, String category) =>
    (keyword: keyword, category: category, match: 'contains');

SeedKeyword _s(String keyword, String category) =>
    (keyword: keyword, category: category, match: 'startswith');

/// The dictionary, grouped by category. Every keyword is lower case and
/// every category name is one of `default_seed.dart`'s.
final List<SeedKeyword> defaultKeywords = List.unmodifiable(<SeedKeyword>[
  // Food — groceries.
  _c('rice', 'Food'),
  _c('samba', 'Food'),
  _c('nadu', 'Food'),
  _c('basmati', 'Food'),
  _c('flour', 'Food'),
  _c('wheat', 'Food'),
  _c('bread', 'Food'),
  _s('bun', 'Food'),
  _c('milk', 'Food'),
  _c('yoghurt', 'Food'),
  _c('yogurt', 'Food'),
  _c('curd', 'Food'),
  _c('cheese', 'Food'),
  _c('butter', 'Food'),
  _c('margarine', 'Food'),
  _s('egg', 'Food'),
  _c('chicken', 'Food'),
  _c('beef', 'Food'),
  _c('mutton', 'Food'),
  _c('pork', 'Food'),
  _c('fish', 'Food'),
  _c('tuna', 'Food'),
  _c('sprats', 'Food'),
  _c('prawn', 'Food'),
  _c('sausage', 'Food'),
  _c('dhal', 'Food'),
  _s('dal', 'Food'),
  _c('lentil', 'Food'),
  _c('chickpea', 'Food'),
  _c('sugar', 'Food'),
  _c('salt', 'Food'),
  _c('pepper', 'Food'),
  _c('chilli', 'Food'),
  _c('chili', 'Food'),
  _c('curry powder', 'Food'),
  _c('spice', 'Food'),
  _c('cinnamon', 'Food'),
  _c('turmeric', 'Food'),
  _c('onion', 'Food'),
  _c('garlic', 'Food'),
  _c('ginger', 'Food'),
  _c('potato', 'Food'),
  _c('tomato', 'Food'),
  _c('carrot', 'Food'),
  _c('leeks', 'Food'),
  _c('cabbage', 'Food'),
  _c('beans', 'Food'),
  _c('brinjal', 'Food'),
  _c('pumpkin', 'Food'),
  _c('banana', 'Food'),
  _c('apple', 'Food'),
  _c('mango', 'Food'),
  _c('papaya', 'Food'),
  _c('orange', 'Food'),
  _c('grape', 'Food'),
  _c('coconut', 'Food'),
  _s('oil', 'Food'),
  _c('noodle', 'Food'),
  _c('pasta', 'Food'),
  _c('macaroni', 'Food'),
  _c('biscuit', 'Food'),
  _c('cracker', 'Food'),
  _c('cereal', 'Food'),
  _c('oats', 'Food'),
  _s('tea', 'Food'),
  _c('coffee', 'Food'),
  _c('milo', 'Food'),
  _c('nescafe', 'Food'),
  _c('sauce', 'Food'),
  _c('ketchup', 'Food'),
  _s('jam', 'Food'),
  _c('honey', 'Food'),
  _c('chocolate', 'Food'),
  _c('ice cream', 'Food'),
  _c('juice', 'Food'),
  _c('mineral water', 'Food'),
  _c('soda', 'Food'),
  _c('coca cola', 'Food'),
  _c('coke', 'Food'),
  _c('pepsi', 'Food'),
  _c('sprite', 'Food'),
  _c('grocery', 'Food'),
  _c('vegetable', 'Food'),
  _c('fruit', 'Food'),
  _c('snack', 'Food'),
  _c('chips', 'Food'),
  _c('peanut', 'Food'),
  _c('cashew', 'Food'),
  _c('raisin', 'Food'),
  _c('vinegar', 'Food'),
  _c('soy sauce', 'Food'),

  // Eating Out.
  _c('restaurant', 'Eating Out'),
  _c('cafe', 'Eating Out'),
  _c('hotel', 'Eating Out'),
  _s('kfc', 'Eating Out'),
  _c('mcdonald', 'Eating Out'),
  _c('burger king', 'Eating Out'),
  _c('pizza', 'Eating Out'),
  _c('burger', 'Eating Out'),
  _c('kottu', 'Eating Out'),
  _c('hopper', 'Eating Out'),
  _c('fried rice', 'Eating Out'),
  _c('biryani', 'Eating Out'),
  _c('buriyani', 'Eating Out'),
  _c('kebab', 'Eating Out'),
  _c('shawarma', 'Eating Out'),
  _c('dominos', 'Eating Out'),
  _c('subway', 'Eating Out'),
  _c('bakery', 'Eating Out'),
  _c('bistro', 'Eating Out'),
  _c('canteen', 'Eating Out'),
  _c('eatery', 'Eating Out'),
  _c('takeaway', 'Eating Out'),
  _c('meal', 'Eating Out'),
  _c('lunch', 'Eating Out'),
  _c('dinner', 'Eating Out'),
  _c('breakfast', 'Eating Out'),
  _c('coffee shop', 'Eating Out'),
  _c('barista', 'Eating Out'),
  _c('sushi', 'Eating Out'),
  _c('buffet', 'Eating Out'),
  _c('service charge', 'Eating Out'),

  // Health.
  _c('pharmacy', 'Health'),
  _c('panadol', 'Health'),
  _c('paracetamol', 'Health'),
  _c('amoxicillin', 'Health'),
  _c('antibiotic', 'Health'),
  _c('tablet', 'Health'),
  _c('capsule', 'Health'),
  _c('syrup', 'Health'),
  _c('vitamin', 'Health'),
  _c('supplement', 'Health'),
  _c('doctor', 'Health'),
  _c('clinic', 'Health'),
  _c('hospital', 'Health'),
  _c('channel', 'Health'),
  _c('consultation', 'Health'),
  _c('lab test', 'Health'),
  _c('x-ray', 'Health'),
  _c('dental', 'Health'),
  _c('dentist', 'Health'),
  _c('optical', 'Health'),
  _c('spectacle', 'Health'),
  _c('eye drop', 'Health'),
  _c('bandage', 'Health'),
  _c('plaster', 'Health'),
  _c('cotton wool', 'Health'),
  _c('ointment', 'Health'),
  _c('medicine', 'Health'),
  _c('medical', 'Health'),
  _c('inhaler', 'Health'),
  _c('insulin', 'Health'),
  _c('thermometer', 'Health'),
  _c('face mask', 'Health'),
  _c('sanitizer', 'Health'),
  _c('sanitiser', 'Health'),
  _c('glucose', 'Health'),
  _c('vaccine', 'Health'),
  _c('physio', 'Health'),

  // Toiletry.
  _c('shampoo', 'Toiletry'),
  _c('conditioner', 'Toiletry'),
  _c('soap', 'Toiletry'),
  _c('body wash', 'Toiletry'),
  _c('toothpaste', 'Toiletry'),
  _c('toothbrush', 'Toiletry'),
  _c('mouthwash', 'Toiletry'),
  _c('floss', 'Toiletry'),
  _c('deodorant', 'Toiletry'),
  _c('perfume', 'Toiletry'),
  _c('cologne', 'Toiletry'),
  _c('lotion', 'Toiletry'),
  _c('moisturiser', 'Toiletry'),
  _c('moisturizer', 'Toiletry'),
  _c('face wash', 'Toiletry'),
  _c('sunscreen', 'Toiletry'),
  _c('razor', 'Toiletry'),
  _c('shaving', 'Toiletry'),
  _c('sanitary', 'Toiletry'),
  _c('tampon', 'Toiletry'),
  _c('diaper', 'Toiletry'),
  _c('pampers', 'Toiletry'),
  _c('tissue', 'Toiletry'),
  _c('toilet paper', 'Toiletry'),
  _c('toilet roll', 'Toiletry'),
  _c('wet wipe', 'Toiletry'),
  _c('cotton bud', 'Toiletry'),
  _c('lipstick', 'Toiletry'),
  _c('makeup', 'Toiletry'),
  _c('cosmetic', 'Toiletry'),
  _c('hair oil', 'Toiletry'),
  _c('hair gel', 'Toiletry'),
  _c('comb', 'Toiletry'),
  _c('talc', 'Toiletry'),

  // House.
  _c('detergent', 'House'),
  _c('washing powder', 'House'),
  _c('surf excel', 'House'),
  _c('dishwash', 'House'),
  _c('harpic', 'House'),
  _c('dettol', 'House'),
  _c('bleach', 'House'),
  _s('mop', 'House'),
  _c('broom', 'House'),
  _c('bucket', 'House'),
  _c('bulb', 'House'),
  _c('extension cord', 'House'),
  _c('plug', 'House'),
  _c('socket', 'House'),
  _c('candle', 'House'),
  _c('mosquito', 'House'),
  _c('insecticide', 'House'),
  _c('furniture', 'House'),
  _c('curtain', 'House'),
  _c('bedsheet', 'House'),
  _c('pillow', 'House'),
  _c('mattress', 'House'),
  _c('cookware', 'House'),
  _c('frying pan', 'House'),
  _c('plate', 'House'),
  _c('rent', 'House'),
  _c('lease', 'House'),
  _c('plumber', 'House'),
  _c('electrician', 'House'),
  _c('paint', 'House'),
  _c('cement', 'House'),
  _c('hardware', 'House'),
  _c('garden', 'House'),

  // Bills.
  _c('electricity', 'Bills'),
  _s('ceb', 'Bills'),
  _c('leco', 'Bills'),
  _c('water bill', 'Bills'),
  _c('water board', 'Bills'),
  _c('nwsdb', 'Bills'),
  _s('gas', 'Bills'),
  _c('litro', 'Bills'),
  _c('cylinder', 'Bills'),
  _c('internet', 'Bills'),
  _c('broadband', 'Bills'),
  _s('slt', 'Bills'),
  _c('fibre', 'Bills'),
  _c('fiber', 'Bills'),
  _c('cable tv', 'Bills'),
  _c('dialog tv', 'Bills'),
  _c('peo tv', 'Bills'),
  _c('insurance', 'Bills'),
  _c('premium', 'Bills'),
  _c('assessment', 'Bills'),
  _c('subscription', 'Bills'),
  _c('loan', 'Bills'),
  _c('instalment', 'Bills'),
  _c('installment', 'Bills'),
  _c('bank charge', 'Bills'),
  _c('late fee', 'Bills'),

  // Communications.
  _c('dialog', 'Communications'),
  _c('mobitel', 'Communications'),
  _c('hutch', 'Communications'),
  _c('airtel', 'Communications'),
  _c('reload', 'Communications'),
  _c('top up', 'Communications'),
  _c('topup', 'Communications'),
  _c('recharge', 'Communications'),
  _c('data pack', 'Communications'),
  _c('data plan', 'Communications'),
  _s('sim', 'Communications'),
  _c('phone bill', 'Communications'),
  _c('mobile bill', 'Communications'),
  _c('postage', 'Communications'),
  _c('courier', 'Communications'),
  _c('stamp', 'Communications'),

  // Car.
  _c('petrol', 'Car'),
  _c('diesel', 'Car'),
  _c('fuel', 'Car'),
  _c('octane', 'Car'),
  _c('ceypetco', 'Car'),
  _c('lanka ioc', 'Car'),
  _s('ioc', 'Car'),
  _c('filling station', 'Car'),
  _c('service station', 'Car'),
  _c('engine oil', 'Car'),
  _c('lubricant', 'Car'),
  _c('tyre', 'Car'),
  _c('tire', 'Car'),
  _c('brake', 'Car'),
  _c('car battery', 'Car'),
  _c('car wash', 'Car'),
  _c('car service', 'Car'),
  _c('spare part', 'Car'),
  _c('mechanic', 'Car'),
  _c('garage', 'Car'),
  _c('parking', 'Car'),
  _c('toll', 'Car'),
  _c('revenue licence', 'Car'),
  _c('revenue license', 'Car'),
  _c('motor insurance', 'Car'),
  _c('wiper', 'Car'),
  _c('coolant', 'Car'),

  // Taxi.
  _c('uber', 'Taxi'),
  _c('pickme', 'Taxi'),
  _c('pick me', 'Taxi'),
  _c('taxi', 'Taxi'),
  _s('cab', 'Taxi'),
  _s('tuk', 'Taxi'),
  _c('three wheel', 'Taxi'),
  _c('threewheel', 'Taxi'),
  _c('trishaw', 'Taxi'),
  _c('kangaroo cabs', 'Taxi'),

  // Transport.
  _s('bus', 'Transport'),
  _c('train', 'Transport'),
  _c('railway', 'Transport'),
  _c('fare', 'Transport'),
  _c('expressway', 'Transport'),
  _c('sltb', 'Transport'),
  _c('ferry', 'Transport'),
  _c('flight', 'Transport'),
  _c('airline', 'Transport'),
  _c('airport', 'Transport'),

  // Clothes.
  _c('shirt', 'Clothes'),
  _c('trouser', 'Clothes'),
  _c('jeans', 'Clothes'),
  _c('denim', 'Clothes'),
  _c('dress', 'Clothes'),
  _c('skirt', 'Clothes'),
  _c('saree', 'Clothes'),
  _c('sari', 'Clothes'),
  _c('sarong', 'Clothes'),
  _c('blouse', 'Clothes'),
  _c('jacket', 'Clothes'),
  _c('sock', 'Clothes'),
  _c('underwear', 'Clothes'),
  _c('shoe', 'Clothes'),
  _c('sandal', 'Clothes'),
  _c('slipper', 'Clothes'),
  _c('sneaker', 'Clothes'),
  _c('belt', 'Clothes'),
  _c('uniform', 'Clothes'),
  _c('tailor', 'Clothes'),
  _c('fabric', 'Clothes'),
  _c('garment', 'Clothes'),
  _c('odel', 'Clothes'),
  _c('nolimit', 'Clothes'),
  _c('fashion bug', 'Clothes'),
  _c('cool planet', 'Clothes'),

  // Entertainment.
  _c('netflix', 'Entertainment'),
  _c('spotify', 'Entertainment'),
  _c('youtube', 'Entertainment'),
  _c('disney', 'Entertainment'),
  _c('playstation', 'Entertainment'),
  _c('xbox', 'Entertainment'),
  _c('cinema', 'Entertainment'),
  _c('movie', 'Entertainment'),
  _c('theatre', 'Entertainment'),
  _c('concert', 'Entertainment'),
  _c('novel', 'Entertainment'),
  _c('magazine', 'Entertainment'),
  _c('newspaper', 'Entertainment'),
  _c('music', 'Entertainment'),
  _c('guitar', 'Entertainment'),
  _c('party', 'Entertainment'),
  _s('pub', 'Entertainment'),
  _c('beer', 'Entertainment'),
  _c('wine', 'Entertainment'),
  _c('arrack', 'Entertainment'),
  _c('liquor', 'Entertainment'),
  _c('whisky', 'Entertainment'),
  _c('vodka', 'Entertainment'),
  _c('cigarette', 'Entertainment'),
  _c('tobacco', 'Entertainment'),
  _c('lottery', 'Entertainment'),

  // Gifts.
  _c('gift', 'Gifts'),
  _c('present', 'Gifts'),
  _c('wrapping', 'Gifts'),
  _c('greeting card', 'Gifts'),
  _c('birthday card', 'Gifts'),
  _c('bouquet', 'Gifts'),
  _c('flower', 'Gifts'),
  _c('florist', 'Gifts'),
  _c('donation', 'Gifts'),
  _c('charity', 'Gifts'),
  _c('wedding', 'Gifts'),
  _c('alms', 'Gifts'),
  _c('pooja', 'Gifts'),

  // Pets.
  _c('pet food', 'Pets'),
  _c('dog food', 'Pets'),
  _c('cat food', 'Pets'),
  _c('pedigree', 'Pets'),
  _c('whiskas', 'Pets'),
  _c('kitten', 'Pets'),
  _c('puppy', 'Pets'),
  _s('vet', 'Pets'),
  _c('veterinary', 'Pets'),
  _c('cat litter', 'Pets'),
  _c('aquarium', 'Pets'),
  _c('fish food', 'Pets'),
  _c('bird seed', 'Pets'),
  _c('leash', 'Pets'),
  _c('kennel', 'Pets'),

  // Sports.
  _s('gym', 'Sports'),
  _c('fitness', 'Sports'),
  _c('membership', 'Sports'),
  _c('cricket', 'Sports'),
  _c('football', 'Sports'),
  _c('badminton', 'Sports'),
  _c('shuttlecock', 'Sports'),
  _c('racket', 'Sports'),
  _c('racquet', 'Sports'),
  _c('swimming', 'Sports'),
  _c('yoga', 'Sports'),
  _c('dumbbell', 'Sports'),
  _c('treadmill', 'Sports'),
  _c('jersey', 'Sports'),
  _c('sports', 'Sports'),
  _c('protein', 'Sports'),
  _c('whey', 'Sports'),
  _c('bicycle', 'Sports'),
  _c('helmet', 'Sports'),

  // Income — the DBD's sample seeds these too, and a scanned pay slip is
  // not out of the question.
  _c('salary', 'Salary'),
  _c('wages', 'Salary'),
  _c('payroll', 'Salary'),
  _c('bonus', 'Salary'),
  _c('deposit', 'Deposits'),
  _c('interest', 'Deposits'),
  _c('dividend', 'Deposits'),
  _c('savings', 'Savings'),
  _c('fixed deposit', 'Savings'),
]);

/// Writes [defaultKeywords] into `keyword_dictionary`, once.
///
/// Returns the number of rows inserted: every one on the first run, zero
/// on every run after. Safe on every open — see the library comment.
Future<int> applyKeywordSeed(DatabaseExecutor db) async {
  Future<int> seedRows() async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM keyword_dictionary WHERE is_user_defined = 0',
        ),
      ) ??
      0;

  final before = await seedRows();
  if (before > 0) return 0;

  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: 'user_id = ? AND is_default = 1',
    whereArgs: [1],
  );
  final idByName = {
    for (final row in categories) row['name']! as String: row['id']! as int,
  };

  final batch = db.batch();
  for (final entry in defaultKeywords) {
    final categoryId = idByName[entry.category];
    if (categoryId == null) continue;
    batch.insert('keyword_dictionary', {
      'keyword': entry.keyword,
      'category_id': categoryId,
      'match_type': entry.match,
      'priority': 5,
      'is_user_defined': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  await batch.commit(noResult: true);
  return await seedRows() - before;
}

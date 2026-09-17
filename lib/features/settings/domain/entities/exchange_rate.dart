/// The settings feature's view of [ExchangeRate].
///
/// The type itself lives in `core/ports/` because the accounts feature
/// converts with it (FR-ACC-005); this re-export is so that inside
/// `features/settings/` it reads as the feature's own entity, the way
/// `features/accounts/` re-exports [AccountType].
library;

export '../../../../core/ports/exchange_rate.dart';

/// Whether the device can reach the network right now.
///
/// Pure Dart and abstract, because `domain/` has to be able to ask the
/// question without importing `connectivity_plus` — the implementation lives
/// beside it and is wired in `injection.dart`.
///
/// Nothing core to Moneyora consults this. Every core feature works with the
/// radio off (C-1), so a caller here is by definition an optional enhancement
/// that must degrade gracefully when the answer is false (FR-COP-013).
abstract class NetworkInfo {
  /// True when a connection is available.
  ///
  /// A connection reported here is not a promise that a request will succeed —
  /// a captive portal answers this happily. Callers still handle failure.
  Future<bool> get isConnected;
}

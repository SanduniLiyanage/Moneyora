import 'package:equatable/equatable.dart';

/// Which theme the app draws in. FR-SET-001.
///
/// The domain's own enum rather than Flutter's `ThemeMode`, because
/// `domain/` is pure Dart; presentation maps one to the other. The storage
/// values are the strings the `users.theme` CHECK accepts.
enum AppThemeMode {
  /// Follow the device.
  system('system'),

  /// Always light.
  light('light'),

  /// Always dark.
  dark('dark');

  const AppThemeMode(this.storageValue);

  /// The string the `users.theme` column stores.
  final String storageValue;

  /// Decodes a stored value, refusing anything the CHECK would have refused.
  static AppThemeMode fromStorage(String value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => throw FormatException('Unknown theme mode', value),
  );
}

/// The user's preferences: the single `users` row, as a value. SRS §3.8.
///
/// Every column the DBD's §3.1 gives that row is here except two.
/// `passcode_hash` and `biometric_enabled` are not preferences but the lock
/// screen's state, and they live in the platform keychain beside the database
/// key rather than in the database they gate — E-31 superseded the DBD's bare
/// hash, and a lock that survives a wiped database belongs with the key that
/// does. The columns stay in the schema, unused, because the schema is
/// additive.
///
/// The row is whole here so that later settings add a use case each, not a
/// field each: FR-SET-003's currency, FR-SET-004's first weekday, FR-SET-008's
/// savings target and FR-SET-012's lookback are all already carried.
class UserSettings extends Equatable {
  /// Creates the settings. Defaults match the schema's column defaults.
  const UserSettings({
    this.theme = AppThemeMode.system,
    this.language = 'en',
    this.currency = 'LKR',
    this.firstDayOfWeek = 0,
    this.firstDayOfMonth = 1,
    this.savingsTargetPct = 0,
    this.planAnalysisMonths = 6,
  });

  /// Light, dark, or the device's choice. FR-SET-001.
  final AppThemeMode theme;

  /// ISO 639-1 code. FR-SET-002; English only today.
  final String language;

  /// ISO 4217 code of the base currency. FR-SET-003, FR-ACC-005.
  final String currency;

  /// 0 = Sunday … 6 = Saturday, as the schema's CHECK bounds it. FR-SET-004.
  final int firstDayOfWeek;

  /// 1–28, so every month has it. FR-SET-004.
  final int firstDayOfMonth;

  /// 0–100. FR-SET-008.
  final double savingsTargetPct;

  /// 1–24 months of history for the Money Plan. FR-SET-012, FR-PLN-003.
  final int planAnalysisMonths;

  /// A copy with the given fields replaced.
  UserSettings copyWith({
    AppThemeMode? theme,
    String? language,
    String? currency,
    int? firstDayOfWeek,
    int? firstDayOfMonth,
    double? savingsTargetPct,
    int? planAnalysisMonths,
  }) => UserSettings(
    theme: theme ?? this.theme,
    language: language ?? this.language,
    currency: currency ?? this.currency,
    firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
    firstDayOfMonth: firstDayOfMonth ?? this.firstDayOfMonth,
    savingsTargetPct: savingsTargetPct ?? this.savingsTargetPct,
    planAnalysisMonths: planAnalysisMonths ?? this.planAnalysisMonths,
  );

  @override
  List<Object?> get props => [
    theme,
    language,
    currency,
    firstDayOfWeek,
    firstDayOfMonth,
    savingsTargetPct,
    planAnalysisMonths,
  ];
}

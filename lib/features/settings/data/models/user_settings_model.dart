/// Persistence mapping for [UserSettings].
///
/// Follows `account_model.dart`: the model extends the entity, `Equatable`
/// compares `runtimeType` so [UserSettingsModel.toEntity] converts at the
/// repository boundary, and the columns an edit may not touch are simply
/// absent from [toUpdateMap].
library;

import '../../domain/entities/user_settings.dart';

/// A [UserSettings] that can be written to and read from the `users` row.
class UserSettingsModel extends UserSettings {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const UserSettingsModel({
    super.theme,
    super.language,
    super.currency,
    super.firstDayOfWeek,
    super.firstDayOfMonth,
    super.savingsTargetPct,
    super.planAnalysisMonths,
  });

  /// Wraps an entity so it can be written.
  factory UserSettingsModel.fromEntity(UserSettings settings) =>
      UserSettingsModel(
        theme: settings.theme,
        language: settings.language,
        currency: settings.currency,
        firstDayOfWeek: settings.firstDayOfWeek,
        firstDayOfMonth: settings.firstDayOfMonth,
        savingsTargetPct: settings.savingsTargetPct,
        planAnalysisMonths: settings.planAnalysisMonths,
      );

  /// Rebuilds a model from the `users` row.
  factory UserSettingsModel.fromMap(Map<String, Object?> map) =>
      UserSettingsModel(
        theme: AppThemeMode.fromStorage(map['theme']! as String),
        language: map['language']! as String,
        currency: map['currency']! as String,
        firstDayOfWeek: map['first_day_week']! as int,
        firstDayOfMonth: map['first_day_month']! as int,
        savingsTargetPct: (map['savings_target_pct']! as num).toDouble(),
        planAnalysisMonths: map['plan_analysis_months']! as int,
      );

  /// The columns a preference change may write.
  ///
  /// Deliberately omits `passcode_hash` and `biometric_enabled`, which the
  /// lock screen keeps in the platform keychain and never in this row, and
  /// `created_at`, which is the install's first-launch stamp.
  Map<String, Object?> toUpdateMap() => <String, Object?>{
    'theme': theme.storageValue,
    'language': language,
    'currency': currency,
    'first_day_week': firstDayOfWeek,
    'first_day_month': firstDayOfMonth,
    'savings_target_pct': savingsTargetPct,
    'plan_analysis_months': planAnalysisMonths,
  };

  /// A plain entity, safe to hand to the domain layer.
  UserSettings toEntity() => UserSettings(
    theme: theme,
    language: language,
    currency: currency,
    firstDayOfWeek: firstDayOfWeek,
    firstDayOfMonth: firstDayOfMonth,
    savingsTargetPct: savingsTargetPct,
    planAnalysisMonths: planAnalysisMonths,
  );
}

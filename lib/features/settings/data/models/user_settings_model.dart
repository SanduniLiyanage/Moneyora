/// Persistence mapping for [UserSettings].
///
/// Follows `account_model.dart`: the model extends the entity, `Equatable`
/// compares `runtimeType` so [UserSettingsModel.toEntity] converts at the
/// repository boundary, and the columns an edit may not touch are simply
/// absent from [toUpdateMap].
library;

import '../../../../core/utils/date_utils.dart';
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
    super.budgetAlertsEnabled,
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
        budgetAlertsEnabled: settings.budgetAlertsEnabled,
      );

  /// Rebuilds a model from the `users` row.
  factory UserSettingsModel.fromMap(Map<String, Object?> map) =>
      UserSettingsModel(
        theme: AppThemeMode.fromStorage(map['theme']! as String),
        language: map['language']! as String,
        currency: map['currency']! as String,
        firstDayOfWeek: decodeWeekdayColumn(map['first_day_week']! as int),
        firstDayOfMonth: map['first_day_month']! as int,
        savingsTargetPct: (map['savings_target_pct']! as num).toDouble(),
        planAnalysisMonths: map['plan_analysis_months']! as int,
        budgetAlertsEnabled: map['budget_alerts_enabled'] == 1,
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
    'first_day_week': encodeWeekdayColumn(firstDayOfWeek),
    'first_day_month': firstDayOfMonth,
    'savings_target_pct': savingsTargetPct,
    'plan_analysis_months': planAnalysisMonths,
    'budget_alerts_enabled': budgetAlertsEnabled ? 1 : 0,
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
    budgetAlertsEnabled: budgetAlertsEnabled,
  );
}

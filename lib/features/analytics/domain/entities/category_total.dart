import 'package:equatable/equatable.dart';

/// What one category cost over a period.
///
/// The unit of every spending view: one arc of the donut chart (FR-RPT-001),
/// one row of the category breakdown, one number the Copilot reasons over.
///
/// Pure Dart, so the chart's arithmetic and the plan engine that will consume
/// these can both be tested without a device.
class CategoryTotal extends Equatable {
  /// Creates a total for one category.
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amountCents,
  });

  /// The category this total belongs to.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// The category's colour as stored, e.g. `#FF7043`.
  ///
  /// Carried on the total so the donut chart can draw a slice without a second
  /// query per arc. Never sent anywhere: it identifies nothing, but it is also
  /// of no use to anything off-device.
  final String color;

  /// What was spent, in integer minor units. Always positive (E-06).
  final int amountCents;

  @override
  List<Object?> get props => [categoryId, name, color, amountCents];
}

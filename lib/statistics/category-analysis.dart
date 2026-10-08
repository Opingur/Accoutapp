import 'package:flutter/material.dart';
import 'package:piggybank/categories/category-display-name.dart';
import 'package:piggybank/helpers/records-utility-functions.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';

/// A single category's converted amount for the active statistics selection.
///
/// Both the ranking and the donut view consume these entries, so their totals
/// cannot diverge as the statistics UI evolves.
class CategoryAnalysisEntry {
  const CategoryAnalysisEntry(
    this.category,
    this.amount, {
    this.label,
    this.isOther = false,
  });

  final Category? category;
  final double amount;
  final String? label;
  final bool isOther;

  String get displayName => label ?? categoryDisplayName(category);
}

/// Builds the ordered category totals used by every category analysis view.
/// Transfers and zero-value categories are deliberately excluded here, at the
/// shared aggregation boundary rather than independently by each view.
List<CategoryAnalysisEntry> aggregateCategoryAnalysis(
  Iterable<Record?> records,
  Map<int, String?> walletCurrencyMap, {
  required CategoryType categoryType,
}) {
  final groups = <Category?, List<Record?>>{};
  for (final record in records) {
    if (record == null ||
        record.isTransfer ||
        record.category?.categoryType != categoryType) {
      continue;
    }
    groups.putIfAbsent(record.category, () => []).add(record);
  }

  final entries =
      groups.entries
          .map(
            (entry) => CategoryAnalysisEntry(
              entry.key,
              computeConvertedTotal(
                entry.value,
                walletCurrencyMap,
                isAbsValue: true,
              ).total,
            ),
          )
          .where((entry) => entry.amount > 0)
          .toList()
        ..sort((left, right) => right.amount.compareTo(left.amount));
  return entries;
}

/// Reduces a full ranking to the maximum number of independently readable
/// donut slices. Everything after [maxSlices] is represented by one neutral
/// "其他" entry, while the ranking itself remains complete.
List<CategoryAnalysisEntry> buildPieAnalysisEntries(
  List<CategoryAnalysisEntry> ranking, {
  int maxSlices = 6,
}) {
  assert(maxSlices > 0);
  final sorted = [...ranking]
    ..sort((left, right) => right.amount.compareTo(left.amount));
  if (sorted.length <= maxSlices) return sorted;

  final remaining = sorted
      .skip(maxSlices)
      .fold<double>(0, (sum, entry) => sum + entry.amount);
  return [
    ...sorted.take(maxSlices),
    CategoryAnalysisEntry(null, remaining, label: '其他', isOther: true),
  ];
}

/// A stable display color: use the category's chosen color first, otherwise a
/// deterministic palette derived from its persisted name. "其他" is neutral.
Color categoryAnalysisColor(CategoryAnalysisEntry entry) {
  if (entry.isOther) return const Color(0xFFB9BDC4);
  if (entry.category?.color case final color?) return color;

  const palette = <Color>[
    Color(0xFFE57373),
    Color(0xFF64B5F6),
    Color(0xFF81C784),
    Color(0xFFFFB74D),
    Color(0xFFBA8CE8),
    Color(0xFF4DB6AC),
    Color(0xFFA1887F),
    Color(0xFFFF8A80),
  ];
  var hash = 0;
  for (final codeUnit in entry.displayName.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

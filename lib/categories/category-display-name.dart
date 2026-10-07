import 'package:piggybank/i18n.dart';
import 'package:piggybank/models/category.dart';

/// Converts legacy built-in English category names to their user-facing
/// Chinese counterparts without changing the stored category or records.
///
/// The mapping deliberately lives at the presentation boundary: historical
/// databases keep their original values, while every UI surface can render a
/// consistent, localized category label.
String categoryDisplayName(Category? category) =>
    categoryNameDisplayName(category?.name);

String categoryNameDisplayName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return '未分类';

  const legacyNames = <String, String>{
    'Food': '餐饮',
    'Transport': '交通',
    'House': '居家',
    'Salary': '工资',
  };

  return legacyNames[trimmed] ?? trimmed.i18n;
}

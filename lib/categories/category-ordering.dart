import 'package:piggybank/models/category.dart';

int compareCategoriesSystemFirst(Category? left, Category? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;

  if (left.isSystem != right.isSystem) {
    return left.isSystem ? -1 : 1;
  }

  final orderComparison = (left.sortOrder ?? 0).compareTo(right.sortOrder ?? 0);
  if (orderComparison != 0) return orderComparison;
  return (left.name ?? '').compareTo(right.name ?? '');
}

void sortCategoriesSystemFirst(List<Category?> categories) {
  categories.sort(compareCategoriesSystemFirst);
}

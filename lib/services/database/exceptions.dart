class NotFoundException implements Exception {
  String? cause;
  NotFoundException({this.cause});
}

class ElementAlreadyExists implements Exception {
  String? cause;
  ElementAlreadyExists({this.cause});
}

class SystemCategoryModificationException implements Exception {
  final String? categoryName;

  SystemCategoryModificationException({this.categoryName});
}

class CategoryInUseException implements Exception {
  final String? categoryName;
  final int recordCount;
  final int recurrentPatternCount;

  CategoryInUseException({
    this.categoryName,
    required this.recordCount,
    required this.recurrentPatternCount,
  });
}

class LegacyCategoryHiddenException implements Exception {
  final String? categoryName;

  LegacyCategoryHiddenException({this.categoryName});
}

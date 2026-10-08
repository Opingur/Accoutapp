import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/services/service-config.dart';
import 'package:piggybank/statistics/category-analysis.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

CategoryAnalysisEntry _entry(String name, double amount) =>
    CategoryAnalysisEntry(
      Category(name, categoryType: CategoryType.expense),
      amount,
    );

Record _record(double value, Category category, {int? transferWalletId}) =>
    Record(
      value,
      category.name,
      category,
      DateTime.utc(2026, 10, 1),
      timeZoneName: 'UTC',
      transferWalletId: transferWalletId,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tz.initializeTimeZones();
    ServiceConfig.localTimezone = 'UTC';
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
  });

  group('category analysis pie data', () {
    test('six or fewer categories do not create an other slice', () {
      final entries = List.generate(
        6,
        (index) => _entry('分类$index', (6 - index).toDouble()),
      );

      final slices = buildPieAnalysisEntries(entries);

      expect(slices, hasLength(6));
      expect(slices.where((entry) => entry.isOther), isEmpty);
    });

    test('seven or more categories merge all remaining amounts into other', () {
      final entries = List.generate(
        8,
        (index) => _entry('分类$index', (8 - index).toDouble()),
      );

      final slices = buildPieAnalysisEntries(entries);
      final other = slices.last;

      expect(slices, hasLength(7));
      expect(other.isOther, isTrue);
      expect(other.displayName, '其他');
      expect(other.amount, 3);
    });

    test(
      'slice amounts equal the full ranking total and percentages total 100',
      () {
        final entries = List.generate(
          8,
          (index) => _entry('分类$index', (8 - index).toDouble()),
        );
        final total = entries.fold<double>(
          0,
          (sum, entry) => sum + entry.amount,
        );
        final slices = buildPieAnalysisEntries(entries);

        expect(
          slices.fold<double>(0, (sum, entry) => sum + entry.amount),
          total,
        );
        expect(
          slices.fold<double>(
            0,
            (sum, entry) => sum + entry.amount / total * 100,
          ),
          closeTo(100, 0.0001),
        );
      },
    );

    test('zero total yields no slices', () {
      final slices = buildPieAnalysisEntries(const []);

      expect(slices, isEmpty);
    });

    test(
      'transfers are excluded while archived and legacy categories remain',
      () {
        final food = Category('Food', categoryType: CategoryType.expense);
        final archivedTransport = Category(
          'Transport',
          categoryType: CategoryType.expense,
          isArchived: true,
        );
        final result = aggregateCategoryAnalysis(
          [
            _record(-10, food),
            _record(-20, archivedTransport),
            _record(-99, food, transferWalletId: 2),
          ],
          const {},
          categoryType: CategoryType.expense,
        );

        expect(result.map((entry) => entry.displayName), ['交通', '餐饮']);
        expect(result.map((entry) => entry.amount), [20, 10]);
        expect(result.fold<double>(0, (sum, entry) => sum + entry.amount), 30);
      },
    );

    test(
      'category colors prefer a saved color and otherwise remain stable',
      () {
        final saved = CategoryAnalysisEntry(
          Category(
            '自定义',
            color: Colors.purple,
            categoryType: CategoryType.expense,
          ),
          1,
        );
        final fallback = _entry('餐饮', 1);

        expect(categoryAnalysisColor(saved), Colors.purple);
        expect(
          categoryAnalysisColor(fallback),
          categoryAnalysisColor(fallback),
        );
      },
    );
  });
}

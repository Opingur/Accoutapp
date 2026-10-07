import 'package:flutter_test/flutter_test.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/services/database/sqlite-database.dart';
import 'package:piggybank/services/database/exceptions.dart';
import 'package:piggybank/services/database/sqlite-migration-service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

const List<String> _expenseSystemCategories = [
  '餐饮',
  '购物',
  '日用',
  '交通',
  '蔬菜',
  '水果',
  '零食',
  '运动',
  '娱乐',
  '通讯',
  '服饰',
  '美容',
  '住房',
  '居家',
  '孩子',
  '长辈',
  '社交',
  '旅行',
  '烟酒',
  '数码',
  '汽车',
  '医疗',
  '书籍',
  '学习',
  '宠物',
  '礼金',
  '礼物',
  '办公',
  '其他',
];

const List<String> _incomeSystemCategories = ['工资', '兼职', '理财', '礼金', '其他'];

const Map<String, int> _legacyCategoryTypes = {
  'House': 0,
  'Transport': 0,
  'Food': 0,
  'Salary': 1,
};

Set<String> get _expectedSystemCategoryKeys => {
  for (final name in _expenseSystemCategories) '0:$name',
  for (final name in _incomeSystemCategories) '1:$name',
};

String _categoryKey(Map<String, Object?> row) =>
    '${row['category_type']}:${row['name']}';

/// Opens the category-related portion of a version 32 database.
///
/// The fixture intentionally contains the four legacy defaults and records
/// that reference them. It gives the v33 migration a realistic old database
/// without depending on the current-version onCreate callback.
Future<Database> _openV32CategoryDatabase({
  bool includeExistingChineseCategory = false,
}) async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false, version: 32),
  );

  await db.execute('''
    CREATE TABLE categories (
      name TEXT,
      color TEXT,
      icon INTEGER,
      category_type INTEGER,
      last_used INTEGER,
      record_count INTEGER DEFAULT 0,
      is_archived INTEGER DEFAULT 0,
      sort_order INTEGER DEFAULT 0,
      icon_emoji TEXT,
      PRIMARY KEY (name, category_type)
    )
  ''');

  await db.execute('''
    CREATE TABLE records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      datetime INTEGER,
      timezone TEXT,
      value REAL,
      title TEXT,
      description TEXT,
      category_name TEXT,
      category_type INTEGER,
      recurrence_id TEXT,
      wallet_id INTEGER,
      transfer_wallet_id INTEGER,
      transfer_value REAL,
      profile_id INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE recurrent_record_patterns (
      id TEXT PRIMARY KEY,
      datetime INTEGER,
      timezone TEXT,
      value REAL,
      title TEXT,
      description TEXT,
      category_name TEXT,
      category_type INTEGER,
      last_update INTEGER,
      recurrent_period INTEGER,
      recurrence_id TEXT,
      date_str TEXT,
      tags TEXT,
      end_date INTEGER,
      wallet_id INTEGER,
      transfer_wallet_id INTEGER,
      transfer_value REAL,
      profile_id INTEGER,
      custom_interval_value INTEGER,
      custom_interval_unit INTEGER
    )
  ''');

  for (final entry in _legacyCategoryTypes.entries) {
    await db.insert('categories', {
      'name': entry.key,
      'category_type': entry.value,
      'is_archived': 0,
      'sort_order': 0,
    });
    await db.insert('records', {
      'datetime': DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
      'timezone': 'UTC',
      'value': entry.value == 0 ? -10.0 : 10.0,
      'title': 'Legacy ${entry.key} record',
      'category_name': entry.key,
      'category_type': entry.value,
    });
  }

  if (includeExistingChineseCategory) {
    await db.insert('categories', {
      'name': '餐饮',
      'category_type': CategoryType.expense.index,
      'is_archived': 0,
      'sort_order': 99,
    });
  }

  return db;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('category migration v32 -> v33', () {
    test('current database version targets v33', () {
      expect(SqliteDatabase.version, 33);
    });

    test(
      'initializes every system category exactly once when run repeatedly',
      () async {
        final db = await _openV32CategoryDatabase();
        addTearDown(db.close);

        await SqliteMigrationService.onUpgrade(db, 32, 33);
        await SqliteMigrationService.onUpgrade(db, 32, 33);

        final systemRows = await db.query(
          'categories',
          columns: ['name', 'category_type'],
          where: 'is_system = 1',
        );
        final duplicateRows = await db.rawQuery('''
        SELECT name, category_type, COUNT(*) AS row_count
        FROM categories
        GROUP BY name, category_type
        HAVING COUNT(*) > 1
      ''');

        expect(
          {
            'systemCategoryCount': systemRows.length,
            'systemCategoryKeys': systemRows.map(_categoryKey).toSet(),
            'duplicateNameTypeRows': duplicateRows.length,
          },
          {
            'systemCategoryCount': 34,
            'systemCategoryKeys': _expectedSystemCategoryKeys,
            'duplicateNameTypeRows': 0,
          },
        );
      },
    );

    test('reuses an existing category with the same name and type', () async {
      final db = await _openV32CategoryDatabase(
        includeExistingChineseCategory: true,
      );
      addTearDown(db.close);

      await SqliteMigrationService.onUpgrade(db, 32, 33);

      final rows = await db.query(
        'categories',
        where: 'name = ? AND category_type = ?',
        whereArgs: ['餐饮', CategoryType.expense.index],
      );

      expect(rows.length, 1);
      expect(rows.single['is_system'], 1);
    });

    test(
      'archives legacy defaults without changing their historical records',
      () async {
        final db = await _openV32CategoryDatabase();
        addTearDown(db.close);

        final recordsBefore = await db.query(
          'records',
          columns: ['id', 'title', 'category_name', 'category_type'],
          orderBy: 'id',
        );

        await SqliteMigrationService.onUpgrade(db, 32, 33);

        final legacyRows = await db.query(
          'categories',
          columns: ['name', 'category_type', 'is_archived', 'is_system'],
          where: 'name IN (?, ?, ?, ?)',
          whereArgs: _legacyCategoryTypes.keys.toList(),
          orderBy: 'name',
        );
        final recordsAfter = await db.query(
          'records',
          columns: ['id', 'title', 'category_name', 'category_type'],
          orderBy: 'id',
        );
        final replacementRows = await db.query(
          'categories',
          columns: ['name', 'category_type', 'is_archived', 'is_system'],
          where:
              '(name = ? AND category_type = ?) OR '
              '(name = ? AND category_type = ?) OR '
              '(name = ? AND category_type = ?) OR '
              '(name = ? AND category_type = ?)',
          whereArgs: [
            '餐饮',
            CategoryType.expense.index,
            '交通',
            CategoryType.expense.index,
            '居家',
            CategoryType.expense.index,
            '工资',
            CategoryType.income.index,
          ],
        );

        expect(
          {
            'legacyArchived': legacyRows.every(
              (row) => row['is_archived'] == 1 && row['is_system'] == 0,
            ),
            'recordsUnchanged': recordsAfter,
            'activeReplacementKeys': replacementRows
                .where(
                  (row) => row['is_archived'] == 0 && row['is_system'] == 1,
                )
                .map(_categoryKey)
                .toSet(),
          },
          {
            'legacyArchived': true,
            'recordsUnchanged': recordsBefore,
            'activeReplacementKeys': {'0:餐饮', '0:交通', '0:居家', '1:工资'},
          },
        );
      },
    );

    test('legacy defaults stay archived after the upgrade', () async {
      final db = await _openV32CategoryDatabase();
      addTearDown(db.close);
      await SqliteMigrationService.onUpgrade(db, 32, 33);
      SqliteDatabase.setDatabaseForTesting(db);
      addTearDown(() => SqliteDatabase.setDatabaseForTesting(null));

      await expectLater(
        SqliteDatabase.instance.archiveCategory(
          'Food',
          CategoryType.expense,
          false,
        ),
        throwsA(isA<LegacyCategoryHiddenException>()),
      );

      final legacy = await db.query(
        'categories',
        where: 'name = ? AND category_type = ?',
        whereArgs: ['Food', CategoryType.expense.index],
      );
      expect(legacy.single['is_archived'], 1);
    });
  });

  group('safe category deletion', () {
    late Database rawDatabase;
    late SqliteDatabase categoryDatabase;

    setUp(() async {
      rawDatabase = await TestDatabaseHelper.setupTestDatabase();
      categoryDatabase = SqliteDatabase.instance;
    });

    tearDown(() async {
      SqliteDatabase.setDatabaseForTesting(null);
      await rawDatabase.close();
    });

    test(
      'rejects deletion when a normal record references the category',
      () async {
        const categoryName = '已使用普通分类';
        final category = Category(
          categoryName,
          categoryType: CategoryType.expense,
        );
        await categoryDatabase.addCategory(category);
        final recordId = await rawDatabase.insert('records', {
          'datetime': DateTime.utc(2024, 2, 1).millisecondsSinceEpoch,
          'timezone': 'UTC',
          'value': -25.0,
          'title': 'Referenced record',
          'category_name': categoryName,
          'category_type': CategoryType.expense.index,
        });

        Object? deletionError;
        try {
          await categoryDatabase.deleteCategory(
            categoryName,
            CategoryType.expense,
          );
        } catch (error) {
          deletionError = error;
        }

        final storedCategory = await categoryDatabase.getCategory(
          categoryName,
          CategoryType.expense,
        );
        final storedRecord = await categoryDatabase.getRecordById(recordId);

        expect(
          {
            'deletionRejected': deletionError != null,
            'categoryStillExists': storedCategory != null,
            'recordStillExists': storedRecord != null,
            'recordTitle': storedRecord?.title,
          },
          {
            'deletionRejected': true,
            'categoryStillExists': true,
            'recordStillExists': true,
            'recordTitle': 'Referenced record',
          },
        );
      },
    );

    test(
      'rejects deletion when a recurrent pattern references the category',
      () async {
        const categoryName = '已使用周期分类';
        final category = Category(
          categoryName,
          categoryType: CategoryType.expense,
        );
        await categoryDatabase.addCategory(category);
        const patternId = 'category-delete-guard-pattern';
        await rawDatabase.insert('recurrent_record_patterns', {
          'id': patternId,
          'datetime': DateTime.utc(2024, 3, 1).millisecondsSinceEpoch,
          'timezone': 'UTC',
          'value': -40.0,
          'title': 'Referenced recurrent pattern',
          'category_name': categoryName,
          'category_type': CategoryType.expense.index,
          'recurrent_period': 2,
        });

        Object? deletionError;
        try {
          await categoryDatabase.deleteCategory(
            categoryName,
            CategoryType.expense,
          );
        } catch (error) {
          deletionError = error;
        }

        final storedCategory = await categoryDatabase.getCategory(
          categoryName,
          CategoryType.expense,
        );
        final storedPattern = await categoryDatabase.getRecurrentRecordPattern(
          patternId,
        );

        expect(
          {
            'deletionRejected': deletionError != null,
            'categoryStillExists': storedCategory != null,
            'patternStillExists': storedPattern != null,
            'patternTitle': storedPattern?.title,
          },
          {
            'deletionRejected': true,
            'categoryStillExists': true,
            'patternStillExists': true,
            'patternTitle': 'Referenced recurrent pattern',
          },
        );
      },
    );

    test('physically deletes an unreferenced custom category', () async {
      const categoryName = '未使用自定义分类';
      await categoryDatabase.addCategory(
        Category(categoryName, categoryType: CategoryType.income),
      );

      await categoryDatabase.deleteCategory(categoryName, CategoryType.income);

      final deletedCategory = await categoryDatabase.getCategory(
        categoryName,
        CategoryType.income,
      );
      expect(deletedCategory, isNull);
    });

    test('does not allow a system category to be deleted or edited', () async {
      final system = await categoryDatabase.getCategory(
        '餐饮',
        CategoryType.expense,
      );
      expect(system?.isSystem, isTrue);

      await expectLater(
        categoryDatabase.deleteCategory('餐饮', CategoryType.expense),
        throwsA(isA<SystemCategoryModificationException>()),
      );

      final attemptedEdit = Category.fromMap(system!.toMap())..name = '餐饮改名';
      await expectLater(
        categoryDatabase.updateCategory(
          system.name,
          system.categoryType,
          attemptedEdit,
        ),
        throwsA(isA<SystemCategoryModificationException>()),
      );
    });
  });
}

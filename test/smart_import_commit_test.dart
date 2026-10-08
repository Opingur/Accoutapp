import 'package:flutter_test/flutter_test.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/profile.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/services/database/sqlite-database.dart';
import 'package:piggybank/services/smart_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'helpers/test_database.dart';

void main() {
  late SqliteDatabase database;
  late int profileId;
  late Wallet cash;
  late Category dining;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz.initializeTimeZones();
  });

  setUp(() async {
    await TestDatabaseHelper.setupTestDatabase();
    database = SqliteDatabase.instance;
    profileId = await database.addProfile(Profile('导入测试'));
    cash = Wallet('现金', profileId: profileId);
    cash.id = await database.addWallet(cash);
    dining = (await database.getCategory('餐饮', CategoryType.expense))!;
  });

  tearDown(() => SqliteDatabase.setDatabaseForTesting(null));

  SmartImportCandidate candidate({
    String title = '肯德基',
    double amount = 34,
    SmartImportTransactionType type = SmartImportTransactionType.expense,
    Category? category,
    Wallet? wallet,
    Wallet? transferWallet,
  }) => SmartImportCandidate(
    sourceRow: 2,
    dateTime: DateTime(2026, 10, 1, 12, 30),
    hasExplicitTime: true,
    type: type,
    amount: amount,
    title: title,
    description: '测试备注',
    sourceCategory: '',
    sourceWallet: '',
    sourceTransferWallet: '',
    recurrence: '',
    suggestedCategory:
        category ??
        (type == SmartImportTransactionType.transfer ? null : dining),
    wallet: wallet ?? cash,
    transferWallet: transferWallet,
    issues: [],
  );

  test(
    'commits a user-confirmed record and custom category atomically',
    () async {
      final custom = Category('校园', categoryType: CategoryType.expense);
      final result = await database.commitSmartImport(
        [candidate(category: custom)],
        profileId: profileId,
        timeZoneName: 'Etc/UTC',
      );

      expect(result.imported, 1);
      expect(result.createdCategories, 1);
      final records = await database.getAllRecords(profileId: profileId);
      expect(records.single.title, '肯德基');
      expect(records.single.value, -34);
      expect(records.single.category?.name, '校园');
    },
  );

  test('writes a transfer as one linked transfer record', () async {
    final bank = Wallet('银行卡', profileId: profileId);
    bank.id = await database.addWallet(bank);
    final result = await database.commitSmartImport(
      [
        candidate(
          title: '转入银行卡',
          amount: 88,
          type: SmartImportTransactionType.transfer,
          transferWallet: bank,
        ),
      ],
      profileId: profileId,
      timeZoneName: 'Etc/UTC',
    );

    final record = (await database.getAllRecords(profileId: profileId)).single;
    expect(result.transferCount, 1);
    expect(record.isTransfer, isTrue);
    expect(record.value, -88);
    expect(record.walletId, cash.id);
    expect(record.transferWalletId, bank.id);
    expect(record.transferValue, 88);
  });

  test('writes multiple corrected records and creates a confirmed wallet',
      () async {
    final transport =
        (await database.getCategory('交通', CategoryType.expense))!;
    final campusCard = Wallet('校园卡', profileId: profileId);
    final first = candidate(title: '校易行', amount: 1.9, category: transport);
    final second = candidate(title: '食堂', amount: 12, wallet: campusCard);
    final result = await database.commitSmartImport(
      [first, second],
      profileId: profileId,
      timeZoneName: 'Etc/UTC',
    );

    expect(result.imported, 2);
    expect(result.createdWallets, 1);
    expect((await database.getAllRecords(profileId: profileId)).length, 2);
    expect((await database.getWalletByName('校园卡', profileId))?.id, isNotNull);
  });

  test(
    're-checks exact duplicates at commit and skips them by default',
    () async {
      final first = candidate();
      await database.commitSmartImport(
        [first],
        profileId: profileId,
        timeZoneName: 'Etc/UTC',
      );
      final second = candidate();
      final result = await database.commitSmartImport(
        [second],
        profileId: profileId,
        timeZoneName: 'Etc/UTC',
      );

      expect(result.imported, 0);
      expect(result.skipped, 1);
      expect((await database.getAllRecords(profileId: profileId)).length, 1);
    },
  );

  test('allows an explicitly confirmed duplicate without merging it', () async {
    await database.commitSmartImport(
      [candidate()],
      profileId: profileId,
      timeZoneName: 'Etc/UTC',
    );
    final confirmed = candidate()
      ..duplicateDecision = SmartImportDuplicateDecision.keep;
    final result = await database.commitSmartImport(
      [confirmed],
      profileId: profileId,
      timeZoneName: 'Etc/UTC',
    );

    expect(result.imported, 1);
    expect((await database.getAllRecords(profileId: profileId)).length, 2);
  });

  test('does not write a skipped error row', () async {
    final invalid = candidate()
      ..issues.add('错误：缺少或无法确认的日期')
      ..skipped = true;
    final result = await database.commitSmartImport(
      [invalid],
      profileId: profileId,
      timeZoneName: 'Etc/UTC',
    );

    expect(result.imported, 0);
    expect(result.skipped, 1);
    expect((await database.getAllRecords(profileId: profileId)), isEmpty);
  });

  test(
    'rolls back earlier custom categories when a later write is unsafe',
    () async {
      final custom = Category('应回滚', categoryType: CategoryType.expense);
      final missingSystem = Category(
        '不存在的系统分类',
        categoryType: CategoryType.expense,
        isSystem: true,
      );

      await expectLater(
        database.commitSmartImport(
          [
            candidate(category: custom),
            candidate(title: '第二笔', category: missingSystem),
          ],
          profileId: profileId,
          timeZoneName: 'Etc/UTC',
        ),
        throwsStateError,
      );
      expect(await database.getCategory('应回滚', CategoryType.expense), isNull);
      expect((await database.getAllRecords(profileId: profileId)), isEmpty);
    },
  );

  test('rolls back category creation when wallet validation fails', () async {
    final custom = Category('钱包回滚', categoryType: CategoryType.expense);
    await expectLater(
      database.commitSmartImport(
        [candidate(category: custom, wallet: Wallet(''))],
        profileId: profileId,
        timeZoneName: 'Etc/UTC',
      ),
      throwsStateError,
    );

    expect(await database.getCategory('钱包回滚', CategoryType.expense), isNull);
    expect((await database.getAllRecords(profileId: profileId)), isEmpty);
  });

  test('keeps imports isolated to the requested profile', () async {
    final otherProfile = await database.addProfile(Profile('其他账本'));
    final otherWallet = Wallet('其他现金', profileId: otherProfile);
    otherWallet.id = await database.addWallet(otherWallet);
    await database.commitSmartImport(
      [candidate(wallet: otherWallet)],
      profileId: otherProfile,
      timeZoneName: 'Etc/UTC',
    );

    expect((await database.getAllRecords(profileId: profileId)), isEmpty);
    expect((await database.getAllRecords(profileId: otherProfile)).length, 1);
  });
}

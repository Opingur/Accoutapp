import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'category-type.dart';
import 'category.dart';

/// Canonical categories that are always available before user-created ones.
///
/// Names are intentionally stored in Chinese because they form the stable
/// `(name, category_type)` key for this product's default taxonomy.
class SystemCategories {
  SystemCategories._();

  static List<Category> get all => [...expense, ...income];

  static List<Category> get expense => _build(CategoryType.expense, [
    ('餐饮', FontAwesomeIcons.burger.codePoint),
    ('购物', FontAwesomeIcons.bagShopping.codePoint),
    ('日用', FontAwesomeIcons.toiletPaper.codePoint),
    ('交通', FontAwesomeIcons.bus.codePoint),
    ('蔬菜', FontAwesomeIcons.seedling.codePoint),
    ('水果', FontAwesomeIcons.appleWhole.codePoint),
    ('零食', FontAwesomeIcons.cookie.codePoint),
    ('运动', FontAwesomeIcons.dumbbell.codePoint),
    ('娱乐', FontAwesomeIcons.gamepad.codePoint),
    ('通讯', FontAwesomeIcons.phone.codePoint),
    ('服饰', FontAwesomeIcons.shirt.codePoint),
    ('美容', FontAwesomeIcons.sprayCanSparkles.codePoint),
    ('住房', FontAwesomeIcons.house.codePoint),
    ('居家', FontAwesomeIcons.couch.codePoint),
    ('孩子', FontAwesomeIcons.baby.codePoint),
    ('长辈', FontAwesomeIcons.handHoldingHand.codePoint),
    ('社交', FontAwesomeIcons.solidHandshake.codePoint),
    ('旅行', FontAwesomeIcons.planeDeparture.codePoint),
    ('烟酒', FontAwesomeIcons.wineGlass.codePoint),
    ('数码', FontAwesomeIcons.desktop.codePoint),
    ('汽车', FontAwesomeIcons.car.codePoint),
    ('医疗', FontAwesomeIcons.pills.codePoint),
    ('书籍', FontAwesomeIcons.book.codePoint),
    ('学习', FontAwesomeIcons.graduationCap.codePoint),
    ('宠物', FontAwesomeIcons.paw.codePoint),
    ('礼金', FontAwesomeIcons.wallet.codePoint),
    ('礼物', FontAwesomeIcons.gift.codePoint),
    ('办公', FontAwesomeIcons.briefcase.codePoint),
    ('其他', FontAwesomeIcons.ellipsis.codePoint),
  ]);

  static List<Category> get income => _build(CategoryType.income, [
    ('工资', FontAwesomeIcons.wallet.codePoint),
    ('兼职', FontAwesomeIcons.briefcase.codePoint),
    ('理财', FontAwesomeIcons.chartLine.codePoint),
    ('礼金', FontAwesomeIcons.gift.codePoint),
    ('其他', FontAwesomeIcons.ellipsis.codePoint),
  ]);

  static List<Category> _build(
    CategoryType type,
    List<(String, int)> definitions,
  ) {
    return List.generate(definitions.length, (index) {
      final (name, iconCodePoint) = definitions[index];
      return Category(
        name,
        categoryType: type,
        iconCodePoint: iconCodePoint,
        color: Category.colors[index % Category.colors.length],
        isSystem: true,
        sortOrder: index,
      );
    });
  }
}

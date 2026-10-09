import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:piggybank/components/icon_color_picker_section.dart';
import 'package:piggybank/helpers/alert-dialog-builder.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/services/database/database-interface.dart';
import 'package:piggybank/services/database/exceptions.dart';
import 'package:piggybank/services/service-config.dart';

import '../style.dart';

import 'package:piggybank/i18n.dart';

class EditCategoryPage extends StatefulWidget {
  /// EditCategoryPage is a page containing forms for the editing of a Category object.
  /// EditCategoryPage can take the category object to edit as a constructor parameters
  /// or can create a new Category otherwise.

  final Category? passedCategory;
  final CategoryType? categoryType;

  EditCategoryPage({Key? key, this.passedCategory, this.categoryType})
    : super(key: key);

  @override
  EditCategoryPageState createState() =>
      EditCategoryPageState(passedCategory, categoryType);
}

class EditCategoryPageState extends State<EditCategoryPage> {
  Category? passedCategory;
  Category? category;
  CategoryType? categoryType;

  EditCategoryPageState(this.passedCategory, this.categoryType);

  String? categoryName;

  DatabaseInterface database = ServiceConfig.database;

  final _formKey = GlobalKey<FormState>();

  bool get _isSystemCategory => widget.passedCategory?.isSystem ?? false;

  Category initCategory() {
    Category category = new Category(null);
    if (this.passedCategory == null) {
      category.color = Category.colors[0];
      category.icon = FontAwesomeIcons.question.data;
      category.iconCodePoint = category.icon!.codePoint;
      category.categoryType = categoryType;
    } else {
      category = Category.fromMap(passedCategory!.toMap());
      categoryName = passedCategory!.name;
    }
    return category;
  }

  @override
  void initState() {
    super.initState();
    category = initCategory();
  }

  Widget _getPageSeparatorLabel(String labelText) {
    TextStyle textStyle = TextStyle(
      fontFamily: FontNameDefault,
      fontWeight: FontWeight.w300,
      fontSize: 26.0,
      color: MaterialThemeInstance.currentTheme?.colorScheme.onSurface,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(15, 15, 0, 5),
        child: Text(labelText, style: textStyle, textAlign: TextAlign.left),
      ),
    );
  }

  Widget _createCategoryCirclePreview() {
    return Container(
      margin: EdgeInsets.all(10),
      child: ClipOval(
        child: Material(
          color: category!.color, // Button color
          child: InkWell(
            splashColor: category!.color, // InkWell color
            child: SizedBox(
              width: 70,
              height: 70,
              child: category!.iconEmoji != null
                  ? Center(
                      // Center the content
                      child: Text(
                        category!.iconEmoji!, // Display the emoji
                        style: TextStyle(
                          fontSize: 30, // Adjust the font size for the emoji
                        ),
                      ),
                    )
                  : Icon(
                      category!.icon, // Fallback to the icon
                      color: category!.color != null
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      size: 30,
                    ),
            ),
            onTap: () {},
          ),
        ),
      ),
    );
  }

  Widget _getTextField() {
    return Expanded(
      child: Form(
        key: _formKey,
        child: Container(
          margin: EdgeInsets.all(10),
          child: TextFormField(
            enabled: !_isSystemCategory,
            onChanged: _isSystemCategory
                ? null
                : (text) {
                    setState(() {
                      categoryName = text;
                    });
                  },
            validator: (value) {
              if (value!.isEmpty) {
                return "Please enter the category name".i18n;
              }
              return null;
            },
            initialValue: categoryName,
            style: TextStyle(
              fontSize: 22.0,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: "Category name".i18n,
              errorStyle: TextStyle(fontSize: 16.0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _getAppBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: isDark
          ? colorScheme.surfaceContainer
          : const Color(0xFFFFD400),
      foregroundColor: isDark ? colorScheme.onSurface : const Color(0xFF252525),
      title: Text(_isSystemCategory ? '系统分类' : "Edit category".i18n),
      actions: <Widget>[
        Visibility(
          visible: widget.passedCategory != null,
          child: IconButton(
            icon: widget.passedCategory == null
                ? const Icon(Icons.archive)
                : !(widget.passedCategory!.isArchived)
                ? const Icon(Icons.archive)
                : const Icon(Icons.unarchive),
            tooltip: widget.passedCategory == null
                ? ""
                : !(widget.passedCategory!.isArchived)
                ? "Archive".i18n
                : "Unarchive".i18n,
            onPressed: () async {
              bool isCurrentlyArchived = widget.passedCategory!.isArchived;

              String dialogMessage = !isCurrentlyArchived
                  ? "Do you really want to archive the category?".i18n
                  : "Do you really want to unarchive the category?".i18n;

              // Prompt confirmation
              AlertDialogBuilder archiveDialog = AlertDialogBuilder(
                dialogMessage,
              ).addTrueButtonName("Yes".i18n).addFalseButtonName("No".i18n);

              if (!isCurrentlyArchived) {
                archiveDialog.addSubtitle(
                  "Archiving the category you will NOT remove the associated records"
                      .i18n,
                );
              }

              var continueArchivingAction = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return archiveDialog.build(context);
                },
              );

              if (continueArchivingAction) {
                try {
                  await database.archiveCategory(
                    widget.passedCategory!.name!,
                    widget.passedCategory!.categoryType!,
                    !isCurrentlyArchived,
                  );
                  if (context.mounted) Navigator.pop(context);
                } on LegacyCategoryHiddenException {
                  if (!context.mounted) return;
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('保留的旧分类'),
                      content: const Text('该旧默认分类仅用于显示历史账单，不能重新用于新增账单。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
          ),
        ),
        Visibility(
          visible: widget.passedCategory != null && !_isSystemCategory,
          child: PopupMenuButton<int>(
            icon: Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10.0)),
            ),
            onSelected: (index) async {
              if (index == 1) {
                // Prompt confirmation
                AlertDialogBuilder deleteDialog =
                    AlertDialogBuilder(
                          "Do you really want to delete the category?".i18n,
                        )
                        .addSubtitle('删除仅限没有账单或周期账单引用的自定义分类；已使用分类请改为归档。')
                        .addTrueButtonName("Yes".i18n)
                        .addFalseButtonName("No".i18n);

                var continueDelete = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return deleteDialog.build(context);
                  },
                );

                if (continueDelete) {
                  try {
                    await database.deleteCategory(
                      widget.passedCategory!.name,
                      widget.passedCategory!.categoryType,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } on CategoryInUseException {
                    if (!context.mounted) return;
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('无法删除分类'),
                        content: const Text('该分类已有账单或周期账单引用。历史数据会保留，请改为归档。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              }
            },
            itemBuilder: (BuildContext context) {
              var deleteStr = "Delete".i18n;
              return {deleteStr: 1}.entries.map((entry) {
                return PopupMenuItem<int>(
                  padding: EdgeInsets.all(20),
                  value: entry.value,
                  child: Text(entry.key, style: TextStyle(fontSize: 16)),
                );
              }).toList();
            },
          ),
        ),
      ],
    );
  }

  Widget _getIconColorPickerSection() {
    return IconColorPickerSection(
      initialIconEmoji: category!.iconEmoji,
      initialIcon: category!.icon,
      initialColor: category!.color,
      onChange: (iconEmoji, icon, iconCodePoint, color) {
        setState(() {
          category!.iconEmoji = iconEmoji;
          category!.icon = icon;
          category!.iconCodePoint = iconCodePoint;
          category!.color = color;
        });
      },
    );
  }

  Widget _getPreviewAndTitleCard() {
    return Container(
      child: Column(
        children: [
          _getPageSeparatorLabel("Name".i18n),
          Divider(thickness: 0.5),
          Container(
            child: Row(
              children: <Widget>[
                Container(child: _createCategoryCirclePreview()),
                Container(child: _getTextField()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  saveCategory() async {
    if (_isSystemCategory) return;
    if (_formKey.currentState!.validate()) {
      if (category!.name == null) {
        // Then it is a newly created category
        // Call the method add category
        category!.name = categoryName;
        await database.addCategory(category);
      } else {
        // If category.name is already set
        // I'm editing an existing category
        // Call the method updateCategory
        String? existingName = category!.name;
        var existingType = category!.categoryType;
        category!.name = categoryName;
        await database.updateCategory(existingName, existingType, category);
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _getAppBar() as PreferredSizeWidget?,
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            _getPreviewAndTitleCard(),
            if (!_isSystemCategory) _getIconColorPickerSection(),
            if (_isSystemCategory)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('系统分类由应用维护，可归档以在新增账单时隐藏。'),
              ),
            SizedBox(height: 75),
          ],
        ),
      ),
      floatingActionButton: _isSystemCategory
          ? null
          : FloatingActionButton(
              heroTag: null,
              onPressed: saveCategory,
              tooltip: 'Add a new category'.i18n,
              child: const Icon(Icons.save),
            ),
    );
  }
}

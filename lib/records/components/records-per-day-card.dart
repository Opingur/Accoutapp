import 'package:flutter/material.dart';
import 'package:piggybank/categories/category-display-name.dart';
import 'package:piggybank/helpers/datetime-utility-functions.dart';
import 'package:piggybank/helpers/records-utility-functions.dart';
import 'package:piggybank/i18n.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/models/records-per-day.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/records/edit-record-page.dart';
import 'package:piggybank/services/profile-service.dart';
import 'package:piggybank/services/service-config.dart';
import 'package:piggybank/services/transfer-icon-service.dart';

import '../../components/category_icon_circle.dart';
import '../../services/database/database-interface.dart';
import '../../settings/constants/preferences-keys.dart';
import '../../settings/preferences-utils.dart';
import 'home_compact_metrics.dart';

class RecordsPerDayCard extends StatefulWidget {
  /// RecordsCard renders a MovementPerDay object as a Card
  /// The card contains an header with date and the balance of the day
  /// and a body, containing the list of movements included in the MovementsPerDay object
  /// refreshParentMovementList is a callback method called every time the card may change
  /// for example, from the deletion of a record or the editing of the record.
  /// The callback should re-fetch the newest version of the records list from the database and rebuild the card

  final Function? onListBackCallback;
  final RecordsPerDay _movementDay;
  final Map<int, String?> walletCurrencyMap;
  final bool isSelectMode;
  final Set<int> selectedRecordIds;
  final void Function(int)? onRecordLongPressed;
  final void Function(int)? onRecordTapped;

  /// Called with the day's date when the date header is tapped (e.g. to
  /// start a new entry pre-dated to that day). Null means no action.
  final void Function(DateTime date)? onDateTapped;

  const RecordsPerDayCard(
    this._movementDay, {
    this.onListBackCallback,
    this.walletCurrencyMap = const {},
    this.isSelectMode = false,
    this.selectedRecordIds = const {},
    this.onRecordLongPressed,
    this.onRecordTapped,
    this.onDateTapped,
  });

  @override
  _RecordsPerDayCardState createState() => _RecordsPerDayCardState();
}

class _RecordsPerDayCardState extends State<RecordsPerDayCard>
    with AutomaticKeepAliveClientMixin {
  final _currencyFontStyle = const TextStyle(
    fontSize: HomeCompactMetrics.recordAmount,
    fontWeight: FontWeight.w700,
  );

  late int _numberOfNoteLinesToShow;
  late bool _visualiseTags;
  late bool _showWalletInRecordList;
  Map<int, Wallet> _walletsById = {};
  final DatabaseInterface _database = ServiceConfig.database;

  @override
  bool get wantKeepAlive => true;

  /// Effective wallet→currency map: uses the passed-in map when non-empty,
  /// otherwise falls back to each wallet's own currency from _walletsById.
  Map<int, String?> get _effectiveCurrencyMap {
    if (widget.walletCurrencyMap.isNotEmpty) return widget.walletCurrencyMap;
    final defaultCurrency = getDefaultCurrency();
    return {
      for (final entry in _walletsById.entries)
        entry.key:
            (entry.value.currency != null && entry.value.currency!.isNotEmpty)
            ? entry.value.currency
            : defaultCurrency,
    };
  }

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  void _loadPreferences() {
    final prefs = ServiceConfig.sharedPreferences!;
    _numberOfNoteLinesToShow = PreferencesUtils.getOrDefault<int>(
      prefs,
      PreferencesKeys.homepageRecordNotesVisible,
    )!;
    _visualiseTags = PreferencesUtils.getOrDefault<bool>(
      prefs,
      PreferencesKeys.visualiseTagsInMainPage,
    )!;
    _showWalletInRecordList = PreferencesUtils.getOrDefault<bool>(
      prefs,
      PreferencesKeys.showWalletInRecordList,
    )!;
  }

  Future<void> _loadWallets() async {
    if (!ServiceConfig.walletsEnabled) {
      if (mounted && _walletsById.isNotEmpty) {
        setState(() {
          _walletsById = {};
        });
      }
      return;
    }
    final wallets = await _database.getAllWallets(
      profileId: ProfileService.instance.activeProfileId,
    );
    if (!mounted) return;
    setState(() {
      _walletsById = {
        for (final w in wallets)
          if (w.id != null) w.id!: w,
      };
    });
  }

  Color? _amountColor(Record record) =>
      getRecordAmountColor(record, Theme.of(context).brightness);

  Widget _buildRecordAmountWidget(Record record) {
    final wallet = record.walletId != null
        ? _walletsById[record.walletId]
        : null;

    final effectiveMap = _effectiveCurrencyMap;
    // For destination-view copies, the received amount is in the destination
    // wallet's currency, so look up transferWalletId instead of walletId.
    final currencyWalletId = record.isDestinationTransferView
        ? record.transferWalletId
        : record.walletId;
    final recordCurrency = currencyWalletId != null
        ? effectiveMap[currencyWalletId]
        : wallet?.currency;

    final color = _amountColor(record);
    final style = color != null
        ? _currencyFontStyle.copyWith(color: color)
        : _currencyFontStyle;

    // No currency info at all — fall back to plain number
    final Widget content;
    if (recordCurrency == null || recordCurrency.isEmpty) {
      content = Text(getCurrencyValueString(record.value), style: style);
    } else {
      content = buildAmountWithCurrencyWidget(
        record.value!,
        recordCurrency,
        mainStyle: style,
        brightness: Theme.of(context).brightness,
        neutralColor: color == null,
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: ServiceConfig.privacyModeHiddenNotifier,
      builder: (context, hidden, _) =>
          hidden ? obscuredAmountTextWidget(style) : content,
    );
  }

  Iterable<Record?> get _incomeRecords =>
      (widget._movementDay.records ?? const <Record?>[]).where(
        (record) =>
            record != null &&
            !record.isTransfer &&
            record.category?.categoryType == CategoryType.income,
      );

  Iterable<Record?> get _expenseRecords =>
      (widget._movementDay.records ?? const <Record?>[]).where(
        (record) =>
            record != null &&
            !record.isTransfer &&
            record.category?.categoryType == CategoryType.expense,
      );

  Widget _buildMovements() {
    /// Returns a ListView with all the movements contained in the MovementPerDay object
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: widget._movementDay.records!.length,
      separatorBuilder: (context, index) {
        return const Divider(thickness: 0.5, endIndent: 12, indent: 56);
      },
      padding: EdgeInsets.zero,
      itemBuilder: /*1*/ (context, i) {
        return _buildMovementRow(widget._movementDay.records![i]!);
      },
    );
  }

  Widget _buildLeading(Record movement, bool isSelected) {
    final transferIcon = TransferIconService.icon;
    final transferEmoji = TransferIconService.iconEmoji;
    final isUncategorizedTransfer =
        movement.isTransfer && movement.category == null;
    final base = CategoryIconCircle(
      iconEmoji: isUncategorizedTransfer
          ? transferEmoji
          : movement.category?.iconEmoji,
      iconDataFromDefaultIconSet: isUncategorizedTransfer
          ? transferIcon
          : movement.category?.icon ?? Icons.swap_horiz,
      backgroundColor: isUncategorizedTransfer
          ? TransferIconService.color
          : movement.category?.color,
      overlayIcon: movement.recurrencePatternId != null ? Icons.repeat : null,
      topOverlayIcon:
          movement.isTransfer &&
              movement.category != null &&
              transferEmoji == null
          ? transferIcon
          : null,
      topOverlayEmoji: movement.isTransfer && movement.category != null
          ? transferEmoji
          : null,
      topOverlayBackgroundColor:
          movement.isTransfer && movement.category != null
          ? TransferIconService.color
          : null,
      circleSize: HomeCompactMetrics.recordIconCircle,
      mainIconSize: HomeCompactMetrics.recordIcon,
      overlayIconSize: 13,
    );
    if (!widget.isSelectMode) return base;
    return Stack(
      alignment: Alignment.center,
      children: [
        base,
        AnimatedOpacity(
          opacity: isSelected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: HomeCompactMetrics.recordIconCircle,
            height: HomeCompactMetrics.recordIconCircle,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.88),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildMovementRow(Record movement) {
    /// Returns a ListTile rendering the single movement row

    final isSelected =
        widget.isSelectMode &&
        movement.id != null &&
        widget.selectedRecordIds.contains(movement.id);
    final canSelect = !movement.isFutureRecord && movement.id != null;
    final titleStyle = TextStyle(
      fontSize: HomeCompactMetrics.recordTitle,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    );

    final listTile = ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      minVerticalPadding: 2,
      minTileHeight: HomeCompactMetrics.recordRowHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      horizontalTitleGap: 10,
      onTap: widget.isSelectMode && canSelect
          ? () => widget.onRecordTapped?.call(movement.id!)
          : !widget.isSelectMode
          ? () async {
              // Destination-view copies carry a modified value (received
              // amount, not original) — always edit the canonical DB record.
              final recordToEdit =
                  movement.isDestinationTransferView && movement.id != null
                  ? (await _database.getRecordById(movement.id!)) ?? movement
                  : movement;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditRecordPage(
                    passedRecord: recordToEdit,
                    readOnly: movement.isFutureRecord,
                  ),
                ),
              );
              if (widget.onListBackCallback != null)
                await widget.onListBackCallback!();
            }
          : null,
      onLongPress:
          widget.isSelectMode || movement.isFutureRecord || movement.id == null
          ? null
          : () => widget.onRecordLongPressed?.call(movement.id!),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayRecordTitle(movement),
            style: titleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_numberOfNoteLinesToShow > 0 &&
              movement.description != null &&
              movement.description!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                movement.description!,
                style: TextStyle(
                  fontSize: HomeCompactMetrics.recordSecondary,
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color, // Lighter color
                ),
                softWrap: true,
                maxLines:
                    _numberOfNoteLinesToShow, // if index is 4, do not wrap
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (ServiceConfig.walletsEnabled &&
              _showWalletInRecordList &&
              !movement.isFutureRecord &&
              movement.walletId != null &&
              _walletsById.containsKey(movement.walletId))
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                movement.isTransfer &&
                        movement.transferWalletId != null &&
                        _walletsById.containsKey(movement.transferWalletId)
                    ? "${_walletsById[movement.walletId]!.name} → ${_walletsById[movement.transferWalletId]!.name}"
                    : _walletsById[movement.walletId]!.name,
                style: TextStyle(
                  fontSize: HomeCompactMetrics.recordSecondary,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          if (_visualiseTags && movement.tags.isNotEmpty)
            _buildTagChipsRow(movement.tags),
        ],
      ),
      trailing: _buildRecordAmountWidget(movement),
      leading: _buildLeading(movement, isSelected),
    );

    Widget result = Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.4)
          : Theme.of(context).colorScheme.surface,
      child: listTile,
    );

    // Apply reduced opacity for future records
    if (movement.isFutureRecord) {
      return Opacity(opacity: 0.5, child: result);
    }

    return result;
  }

  String _displayRecordTitle(Record movement) {
    final title = movement.title?.trim();
    if (title != null && title.isNotEmpty) return title;

    return movement.category == null
        ? 'Transfer'.i18n
        : categoryDisplayName(movement.category);
  }

  Widget _buildTagChipsRow(Set<String> tags) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          List<Widget> tagChips = [];
          for (final tag in tags) {
            final chip = Container(
              margin: EdgeInsets.symmetric(horizontal: 1),
              child: Chip(
                label: Text(tag, style: const TextStyle(fontSize: 11.0)),
                visualDensity: VisualDensity.compact,
              ),
            );
            tagChips.add(chip);
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tagChips),
          );
        },
      ),
    );
  }

  /// Day header (day number plus weekday/month). Tapping it starts a new
  /// entry pre-dated to that day when [RecordsPerDayCard.onDateTapped] is set.
  Widget _buildDateHeader() {
    final date = widget._movementDay.dateTime!;
    final headerKey = ValueKey(
      'records-day-header-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    );
    final content = Row(
      children: [
        Text(
          '${date.month}月${date.day}日 ${extractWeekdayString(date)}',
          style: const TextStyle(
            fontSize: HomeCompactMetrics.dayHeader,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final onDateTapped = widget.onDateTapped;
    if (onDateTapped == null) {
      return KeyedSubtree(key: headerKey, child: content);
    }
    return InkWell(
      key: headerKey,
      onTap: () => onDateTapped(widget._movementDay.dateTime!),
      borderRadius: BorderRadius.circular(4),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _loadPreferences();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildDateHeader()),
                const SizedBox(width: 6),
                Flexible(
                  flex: 7,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _DailyTotals(
                      income: _incomeRecords,
                      expenses: _expenseRecords,
                      currencyMap: _effectiveCurrencyMap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(thickness: 0.5, height: 1),
          _buildMovements(),
        ],
      ),
    );
  }
}

class _DailyTotals extends StatelessWidget {
  const _DailyTotals({
    required this.income,
    required this.expenses,
    required this.currencyMap,
  });

  final Iterable<Record?> income;
  final Iterable<Record?> expenses;
  final Map<int, String?> currencyMap;

  String _format(Iterable<Record?> records) =>
      formatRecordsTotalResult(computeConvertedTotal(records, currencyMap));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurface.withValues(alpha: 0.56);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomeColor = isDark
        ? const Color(0xFF6DCEA0)
        : const Color(0xFF278C63);
    final expenseColor = isDark
        ? const Color(0xFFFF8D8D)
        : const Color(0xFFC44848);
    return ValueListenableBuilder<bool>(
      valueListenable: ServiceConfig.privacyModeHiddenNotifier,
      builder: (context, hidden, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '收入 ',
              style: TextStyle(
                fontSize: HomeCompactMetrics.dayTotal,
                color: muted,
              ),
            ),
            hidden
                ? obscuredAmountTextWidget(
                    const TextStyle(fontSize: HomeCompactMetrics.dayTotal),
                  )
                : Text(
                    _format(income),
                    style: TextStyle(
                      fontSize: HomeCompactMetrics.dayTotal,
                      color: incomeColor,
                    ),
                  ),
            const SizedBox(width: 5),
            Text(
              '支出 ',
              style: TextStyle(
                fontSize: HomeCompactMetrics.dayTotal,
                color: muted,
              ),
            ),
            hidden
                ? obscuredAmountTextWidget(
                    const TextStyle(fontSize: HomeCompactMetrics.dayTotal),
                  )
                : Text(
                    _format(expenses),
                    style: TextStyle(
                      fontSize: HomeCompactMetrics.dayTotal,
                      color: expenseColor,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

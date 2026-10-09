import 'package:flutter/material.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/services/profile-service.dart';
import 'package:piggybank/services/service-config.dart';
import 'package:piggybank/statistics/compact-statistics-page.dart';

/// Root statistics tab. Its internal week/month/year control is state only,
/// not a route, so switching root tabs never grows the Navigator stack.
class StatisticsPage extends StatefulWidget {
  const StatisticsPage(
    this.from,
    this.to,
    this.initialRecords, {
    super.key,
    this.walletCurrencyMap = const {},
    this.walletMap = const {},
  });

  /// Kept for existing detail callers. The shell root omits these fields and
  /// loads the active profile itself.
  final DateTime? from;
  final DateTime? to;
  final List<Record?>? initialRecords;
  final Map<int, String?> walletCurrencyMap;
  final Map<int, Wallet> walletMap;

  @override
  StatisticsPageState createState() => StatisticsPageState();
}

class StatisticsPageState extends State<StatisticsPage> {
  List<Record?>? _records;
  Map<int, String?> _walletCurrencyMap = const {};

  @override
  void initState() {
    super.initState();
    if (widget.initialRecords != null) {
      _records = widget.initialRecords;
      _walletCurrencyMap = widget.walletCurrencyMap;
    } else {
      refresh();
    }
  }

  /// Reloads persisted data after the add-record flow returns while keeping
  /// this root tab and its selected statistics period alive.
  Future<void> refresh() async {
    final profileId = ProfileService.instance.activeProfileId;
    final records = await ServiceConfig.database.getAllRecords(
      profileId: profileId,
    );
    final wallets = await ServiceConfig.database.getAllWallets(
      profileId: profileId,
    );
    if (!mounted) return;
    setState(() {
      _records = records;
      _walletCurrencyMap = {
        for (final wallet in wallets)
          if (wallet.id != null) wallet.id!: wallet.currency,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    if (records == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return CompactStatisticsPage(
      records: records,
      walletCurrencyMap: _walletCurrencyMap,
    );
  }
}

/// Visual metrics shared by the compact records home experience.
///
/// These values deliberately affect presentation only.  Keeping them here
/// makes the month overview, record rows, and bottom navigation scale as one
/// composition without changing records, filtering, or navigation behavior.
abstract final class HomeCompactMetrics {
  static const double monthYear = 12;
  static const double monthValue = 21;
  static const double overviewLabel = 12;
  static const double overviewAmount = 27;
  static const double overviewSecondaryLabel = 11;
  static const double overviewSecondaryAmount = 16;

  static const double dayHeader = 13;
  static const double dayTotal = 11;
  static const double recordTitle = 14;
  static const double recordAmount = 15;
  static const double recordSecondary = 12;
  static const double recordIconCircle = 36;
  static const double recordIcon = 18;

  static const double bottomBarHeight = 64;
  static const double bottomIcon = 23;
  static const double bottomLabel = 10;
  static const double primaryActionSize = 54;
  static const double primaryActionIcon = 29;
  static const double recordRowHeight = 52;
  static const double homeHeaderHeight = 154;
}

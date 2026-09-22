/// Production mapping of TigerBay branch names → DesignMyNight Collins Venue IDs.
///
/// Keys are normalised (trimmed + lower-cased) so callers do not need to worry
/// about casing or whitespace. Both the short and full "TigerBay <name>" forms
/// are included so the lookup works regardless of how the branch name is stored
/// in the Supabase `branches` table.
///
/// Fallback: if an unrecognised branch name is passed, the Kingsbury venue ID
/// is returned so the user always sees *something* rather than a blank WebView.
class CollinsVenueMapper {
  CollinsVenueMapper._();

  static const Map<String, String> _venueMap = {
    // Kingsbury
    'kingsbury': '5d5e6d8d0b1083654f5080cd',
    'tigerbay kingsbury': '5d5e6d8d0b1083654f5080cd',

    // Hounslow
    'hounslow': '6973724f9c12d51f4f2dd402',
    'tigerbay hounslow': '6973724f9c12d51f4f2dd402',

    // Enfield
    'enfield': '663e2d5f170c331d9b554b3f',
    'tigerbay enfield': '663e2d5f170c331d9b554b3f',

    // Hanger Lane
    'hanger lane': '5d5e6db30b108365ab6d9c5f',
    'hanger_lane': '5d5e6db30b108365ab6d9c5f',
    'tigerbay hanger lane': '5d5e6db30b108365ab6d9c5f',
  };

  /// DesignMyNight booking page base URL.
  static const String widgetBaseUrl =
      'https://www.designmynight.com';

  /// Returns the production DesignMyNight Collins Venue ID for [branchTitle].
  ///
  /// Lookup is case- and whitespace-insensitive. Falls back to the Kingsbury
  /// ID when no match is found.
  static String getCollinsId(String branchTitle) {
    final key = branchTitle.trim().toLowerCase();
    return _venueMap[key] ?? '5d5e6d8d0b1083654f5080cd';
  }

  /// Builds the full Collins booking URL for [branchTitle].
  ///
  /// Uses the official DesignMyNight booking-URL format:
  /// https://www.designmynight.com/book?venue_id=VENUEID&source=partner
  static String widgetUrlFor(String branchTitle) {
    final venueId = getCollinsId(branchTitle);
    return '$widgetBaseUrl/book?venue_id=$venueId&source=partner';
  }

  /// Returns the Supabase integer branch ID for [branchIdentifier] (name, ID, or Collins ID).
  /// Default is 2 (Kingsbury).
  static int getBranchNumericId(String? branchIdentifier) {
    if (branchIdentifier == null || branchIdentifier.trim().isEmpty) return 2;
    final key = branchIdentifier.trim().toLowerCase();
    if (key.contains('kingsbury') || key == '5d5e6d8d0b1083654f5080cd' || key == '2') return 2;
    if (key.contains('hounslow') || key == '6973724f9c12d51f4f2dd402' || key == '1') return 1;
    if (key.contains('hanger') || key == '5d5e6db30b108365ab6d9c5f' || key == '3') return 3;
    if (key.contains('enfield') || key == '663e2d5f170c331d9b554b3f' || key == '4') return 4;
    return int.tryParse(branchIdentifier) ?? 2;
  }

  /// Returns all mapped branch display names (original casing).
  static List<String> get mappedBranches => const [
        'TigerBay Kingsbury',
        'TigerBay Hounslow',
        'TigerBay Enfield',
        'TigerBay Hanger Lane',
      ];
}

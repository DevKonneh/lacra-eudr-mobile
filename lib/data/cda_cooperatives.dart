/// Cooperative Development Agency (CDA) of Liberia - registered
/// cooperative/producer-group registry.
///
/// *** IMPORTANT - PLACEHOLDER DATA, NOT THE OFFICIAL CDA EXPORT ***
/// No machine-readable CDA registry export was available at the time this
/// list was built. The entries below are a small illustrative seed (a mix
/// of publicly documented Liberian cooperative names, e.g. from FAO/UNDP
/// reporting on Liberia's cooperative sector) so the searchable-dropdown UI
/// and "Other / Not Listed" fallback can be built and tested end-to-end now.
///
/// TO REPLACE WITH THE REAL REGISTRY:
///   1. Obtain the official CDA cooperative list (name, registration
///      number/ID if any, county) as CSV/JSON from CDA/LACRA.
///   2. Replace the `entries` list below with the real data - keep the
///      same `CdaCooperative` shape (or extend it) so
///      FarmerPersonalInfoStep's search/selection UI needs no changes.
///   3. Consider loading this from a bundled JSON asset instead of Dart
///      source if the real list is large or needs periodic updates without
///      an app rebuild.
///
/// Sentinel value used for the "Other / Not Listed" option, which triggers
/// a free-text "Enter Cooperative Name" field and tags the resulting record
/// with `cooperativeSource = OTHER` so it can be reconciled against the
/// real CDA registry later (see FarmerPersonalInfoStep/
/// FarmerRegistrationModel.cooperativeSource).
const String kCdaOtherCooperativeSentinel = '__OTHER_NOT_LISTED__';

class CdaCooperative {
  final String name;
  final String? county;

  const CdaCooperative({required this.name, this.county});
}

class CdaCooperatives {
  CdaCooperatives._();

  static const List<CdaCooperative> entries = [
    CdaCooperative(name: 'Tungban Union Farmers Cooperative', county: 'Bong'),
    CdaCooperative(name: 'Lofa Cocoa Farmers Union', county: 'Lofa'),
    CdaCooperative(name: 'Gbarnga Cocoa Growers Cooperative', county: 'Bong'),
    CdaCooperative(
      name: 'Nimba Farmers Multipurpose Cooperative',
      county: 'Nimba',
    ),
    CdaCooperative(
      name: 'Bong County Cocoa Farmers Cooperative Society',
      county: 'Bong',
    ),
    CdaCooperative(
      name: 'Grand Bassa Rural Farmers Cooperative',
      county: 'Grand Bassa',
    ),
    CdaCooperative(
      name: 'Sinoe Farmers Cooperative Society',
      county: 'Sinoe',
    ),
    CdaCooperative(
      name: 'Maryland Agriculture Cooperative Union',
      county: 'Maryland',
    ),
    CdaCooperative(
      name: 'Margibi Smallholder Farmers Cooperative',
      county: 'Margibi',
    ),
    CdaCooperative(
      name: 'Foya Cocoa Farmers Cooperative',
      county: 'Lofa',
    ),
  ];

  /// Case-insensitive substring search over cooperative names, used by the
  /// searchable dropdown (e.g. typing "Gbarnga" matches "Gbarnga Cocoa
  /// Growers Cooperative").
  static List<CdaCooperative> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((c) => c.name.toLowerCase().contains(q))
        .toList(growable: false);
  }
}

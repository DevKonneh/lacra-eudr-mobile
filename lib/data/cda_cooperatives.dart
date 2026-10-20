/// Cooperative Development Agency (CDA) of Liberia - registered
/// cooperative/producer-group registry.
///
/// *** UPDATED: now backed by the real CDA registry ***
/// Previously this file held a small, explicitly-fake 10-entry placeholder
/// list. The real CDA registry (95 cooperatives, parsed from the official
/// "CDA COOPERATIVE LISTING 2025" letter) is now stored server-side in the
/// backend's `Cooperative` table and served via `GET /api/cooperatives`
/// (see ApiService.getCooperatives() and CooperativeRegistryService).
///
/// `CdaCooperative` below keeps the same shape (`name`, `county`) the UI
/// already depended on, plus the extra fields the backend provides
/// (commodities, membership, contact) for future use, so
/// FarmerPersonalInfoStep's search/selection UI needed no structural
/// changes - only the data source became dynamic instead of static.
///
/// `CdaCooperatives.entries` is no longer a `const` list: it is populated
/// at runtime by `CooperativeRegistryService` (fetched from the backend,
/// cached offline via shared_preferences, with this file's small built-in
/// `_offlineFallbackSeed` as an absolute last resort if a brand-new install
/// has never been online yet). `CdaCooperatives.search()` still works the
/// same way callers already use it.
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
  final String? location;
  final List<String> commodities;
  final int? membershipTotal;
  final int? membershipMale;
  final int? membershipFemale;
  final String? contactName;
  final String? contactRole;
  final List<String> contactPhones;

  const CdaCooperative({
    required this.name,
    this.county,
    this.location,
    this.commodities = const [],
    this.membershipTotal,
    this.membershipMale,
    this.membershipFemale,
    this.contactName,
    this.contactRole,
    this.contactPhones = const [],
  });

  /// Parses one record out of `GET /api/cooperatives`'s `data` array
  /// (a serialized `Cooperative` entity - see backend
  /// src/entities/Cooperative.ts), or out of the locally-cached JSON copy
  /// of that same response (see CooperativeRegistryService).
  factory CdaCooperative.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic raw) {
      if (raw is List) {
        return raw.whereType<Object>().map((e) => e.toString()).toList();
      }
      return const [];
    }

    return CdaCooperative(
      name: (json['name'] as String?)?.trim() ?? '',
      county: (json['county'] as String?)?.trim(),
      location: (json['location'] as String?)?.trim(),
      commodities: stringList(json['commodities']),
      membershipTotal: json['membershipTotal'] as int?,
      membershipMale: json['membershipMale'] as int?,
      membershipFemale: json['membershipFemale'] as int?,
      contactName: (json['contactName'] as String?)?.trim(),
      contactRole: (json['contactRole'] as String?)?.trim(),
      contactPhones: stringList(json['contactPhones']),
    );
  }

  /// Mirrors fromJson, used by CooperativeRegistryService to write the
  /// offline cache back to shared_preferences in the same shape it reads.
  Map<String, dynamic> toJson() => {
    'name': name,
    'county': county,
    'location': location,
    'commodities': commodities,
    'membershipTotal': membershipTotal,
    'membershipMale': membershipMale,
    'membershipFemale': membershipFemale,
    'contactName': contactName,
    'contactRole': contactRole,
    'contactPhones': contactPhones,
  };
}

class CdaCooperatives {
  CdaCooperatives._();

  /// Absolute last-resort seed, only ever used by CooperativeRegistryService
  /// when a device has never once successfully reached the backend AND has
  /// no cached copy yet (e.g. very first launch, offline, no connectivity).
  /// Intentionally tiny - this is not meant to be a substitute for the real
  /// registry, just enough that the picker isn't completely empty.
  static const List<CdaCooperative> offlineFallbackSeed = [
    CdaCooperative(
      name: 'Tungban Union Farmers Cooperative',
      county: 'Bong',
    ),
    CdaCooperative(name: 'Lofa Cocoa Farmers Union', county: 'Lofa'),
    CdaCooperative(
      name: 'Nimba Farmers Multipurpose Cooperative',
      county: 'Nimba',
    ),
  ];

  /// Mutable, runtime-populated registry. Starts out as the tiny offline
  /// fallback seed so the UI always has *something* to show immediately
  /// (no null/loading flash on first paint), then
  /// CooperativeRegistryService.load() replaces this with the real
  /// cached/fetched data as soon as it's available.
  static List<CdaCooperative> entries = List.unmodifiable(
    offlineFallbackSeed,
  );

  /// Case-insensitive substring search over cooperative name AND county,
  /// used by the searchable dropdown (e.g. typing "Gbarnga" or "Lofa"
  /// matches accordingly).
  ///
  /// When [county] is provided (non-empty), results are first narrowed to
  /// only cooperatives whose `county` exactly matches it (case-insensitive)
  /// before the free-text [query] is applied on top - this is what powers
  /// FarmerLocationStep's "only show cooperatives in the selected county"
  /// behaviour, so the enumerator never has to scroll the full ~95-entry
  /// national registry once a county has been chosen.
  static List<CdaCooperative> search(String query, {String? county}) {
    final q = query.trim().toLowerCase();
    final c = county?.trim().toLowerCase();

    Iterable<CdaCooperative> base = entries;
    if (c != null && c.isNotEmpty) {
      base = base.where((e) => (e.county?.trim().toLowerCase() ?? '') == c);
    }

    if (q.isEmpty) return base.toList(growable: false);
    return base
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              (e.county?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false);
  }
}

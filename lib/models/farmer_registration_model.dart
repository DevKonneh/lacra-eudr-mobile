class FarmerRegistrationModel {
  // Personal Information
  final String fullName;
  final String gender;
  final String? dob;
  final String phone;
  final String? nationality;
  final String? idType;
  final String? idTypeOther;
  final String? nationalId;
  final String? email;

  // Cooperative / Enumerator affiliation (EUDR traceability - mirrors
  // admin panel's RegisterFarmer.tsx "Group/Cooperative Affiliation" +
  // enumeratorId fields, backend Farmer.cooperativeName/cooperativeId/
  // enumeratorId columns).
  final String? cooperativeName;
  final String? cooperativeId;
  final String? enumeratorId;

  // Location Information
  final String county;
  final String? district;
  final String community;
  final String inspectorName;
  final double? lat;
  final double? lng;
  final String? directions;

  // Farm Information
  final String farmName;
  final String crop;
  final String ownership;
  final String? regStatus;
  final String? farmSizeManual;
  final String? farmUnitManual;
  final String? farmNotes;

  // EUDR due-diligence farm attributes (mirrors admin panel's
  // RegisterFarmer.tsx farms[] fields, backend Farm entity columns).
  final String? numberOfTrees;
  final String? yearsInCultivation;
  final String? harvestSeason;
  final String? averageYield;
  final String? buyers;
  final bool useChemicals;
  final bool extensionServices;
  final String? farmAddress;

  // Mapping Information
  final String? areaHa;
  final String? areaAc;
  final String? boundaryJson;
  // EUDR Point + Photo mode: per-point geotagged evidence, each entry
  // {sequence, lat, lng, accuracy, timestamp, photoPath (LOCAL file path)}.
  // Attached via a follow-up PUT /farms/:id/boundary-evidence call after
  // registration succeeds and the new farm's id is known.
  final List<Map<String, dynamic>>? boundaryEvidence;

  // Consent
  final bool consent;

  // File paths (for multipart upload)
  final String? farmerPhotoPath;
  final String? nationalIdPath;
  final String? farmSelfiePath;
  final String? signaturePath;
  final List<String>? farmPhotosPaths;

  // EUDR compliance documents (National ID, Land Deed, Lease Agreement,
  // Customary/Community Authorization, Cooperative Membership Document).
  // Each entry: {'type': <DocumentType label>, 'path': <local file path>}.
  final List<Map<String, String>>? complianceDocuments;

  FarmerRegistrationModel({
    required this.fullName,
    required this.gender,
    this.dob,
    required this.phone,
    this.nationality,
    this.idType,
    this.idTypeOther,
    this.nationalId,
    this.email,
    this.cooperativeName,
    this.cooperativeId,
    this.enumeratorId,
    required this.county,
    this.district,
    required this.community,
    required this.inspectorName,
    this.lat,
    this.lng,
    this.directions,
    required this.farmName,
    required this.crop,
    required this.ownership,
    this.regStatus,
    this.farmSizeManual,
    this.farmUnitManual,
    this.farmNotes,
    this.numberOfTrees,
    this.yearsInCultivation,
    this.harvestSeason,
    this.averageYield,
    this.buyers,
    this.useChemicals = false,
    this.extensionServices = false,
    this.farmAddress,
    this.areaHa,
    this.areaAc,
    this.boundaryJson,
    this.boundaryEvidence,
    required this.consent,
    this.farmerPhotoPath,
    this.nationalIdPath,
    this.farmSelfiePath,
    this.signaturePath,
    this.farmPhotosPaths,
    this.complianceDocuments,
  });

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'gender': gender,
      if (dob != null) 'dob': dob,
      'phone': phone,
      if (nationality != null) 'nationality': nationality,
      if (idType != null) 'idType': idType,
      if (idTypeOther != null) 'idTypeOther': idTypeOther,
      if (nationalId != null) 'nationalId': nationalId,
      if (email != null) 'email': email,
      if (cooperativeName != null) 'cooperativeName': cooperativeName,
      if (cooperativeId != null) 'cooperativeId': cooperativeId,
      if (enumeratorId != null) 'enumeratorId': enumeratorId,
      'county': county,
      if (district != null) 'district': district,
      'community': community,
      'inspectorName': inspectorName,
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
      if (directions != null) 'directions': directions,
      'farmName': farmName,
      'crop': crop,
      'ownership': ownership,
      if (regStatus != null) 'regStatus': regStatus,
      if (farmSizeManual != null) 'farmSizeManual': farmSizeManual,
      if (farmUnitManual != null) 'farmUnitManual': farmUnitManual,
      if (farmNotes != null) 'farmNotes': farmNotes,
      if (numberOfTrees != null) 'numberOfTrees': numberOfTrees,
      if (yearsInCultivation != null) 'yearsInCultivation': yearsInCultivation,
      if (harvestSeason != null) 'harvestSeason': harvestSeason,
      if (averageYield != null) 'averageYield': averageYield,
      if (buyers != null) 'buyers': buyers,
      'useChemicals': useChemicals,
      'extensionServices': extensionServices,
      if (farmAddress != null) 'farmAddress': farmAddress,
      if (areaHa != null) 'areaHa': areaHa,
      if (areaAc != null) 'areaAc': areaAc,
      if (boundaryJson != null) 'boundaryJson': boundaryJson,
      'consent': consent,
    };
  }

  /// Full round-trip serialization, including local file paths and
  /// boundary evidence - used ONLY for persisting a registration to the
  /// local offline-sync queue (SharedPreferences) so that a registration
  /// captured while offline can later be replayed through the exact same
  /// multipart [ApiService.registerFarmer] call used for a live/online
  /// submission, instead of being downgraded to a JSON-only sync that
  /// cannot carry photos/signature at all.
  ///
  /// NOT used for talking to the backend directly - [toJson] (JSON-only
  /// fields, no file paths) is what's actually sent over the wire for the
  /// live submission; the files themselves are added separately by
  /// [ApiService.registerFarmer] as multipart file parts.
  Map<String, dynamic> toFullJson() {
    return {
      'fullName': fullName,
      'gender': gender,
      'dob': dob,
      'phone': phone,
      'nationality': nationality,
      'idType': idType,
      'idTypeOther': idTypeOther,
      'nationalId': nationalId,
      'email': email,
      'cooperativeName': cooperativeName,
      'cooperativeId': cooperativeId,
      'enumeratorId': enumeratorId,
      'county': county,
      'district': district,
      'community': community,
      'inspectorName': inspectorName,
      'lat': lat,
      'lng': lng,
      'directions': directions,
      'farmName': farmName,
      'crop': crop,
      'ownership': ownership,
      'regStatus': regStatus,
      'farmSizeManual': farmSizeManual,
      'farmUnitManual': farmUnitManual,
      'farmNotes': farmNotes,
      'numberOfTrees': numberOfTrees,
      'yearsInCultivation': yearsInCultivation,
      'harvestSeason': harvestSeason,
      'averageYield': averageYield,
      'buyers': buyers,
      'useChemicals': useChemicals,
      'extensionServices': extensionServices,
      'farmAddress': farmAddress,
      'areaHa': areaHa,
      'areaAc': areaAc,
      'boundaryJson': boundaryJson,
      'boundaryEvidence': boundaryEvidence,
      'consent': consent,
      'farmerPhotoPath': farmerPhotoPath,
      'nationalIdPath': nationalIdPath,
      'farmSelfiePath': farmSelfiePath,
      'signaturePath': signaturePath,
      'farmPhotosPaths': farmPhotosPaths,
      'complianceDocuments': complianceDocuments,
    };
  }

  /// Reconstructs a [FarmerRegistrationModel] from [toFullJson]'s output -
  /// used when flushing the offline-sync queue to rebuild the exact
  /// registration (including local file paths still on-device) so it can
  /// be resubmitted through [ApiService.registerFarmer].
  factory FarmerRegistrationModel.fromFullJson(Map<String, dynamic> json) {
    return FarmerRegistrationModel(
      fullName: json['fullName'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      dob: json['dob'] as String?,
      phone: json['phone'] as String? ?? '',
      nationality: json['nationality'] as String?,
      idType: json['idType'] as String?,
      idTypeOther: json['idTypeOther'] as String?,
      nationalId: json['nationalId'] as String?,
      email: json['email'] as String?,
      cooperativeName: json['cooperativeName'] as String?,
      cooperativeId: json['cooperativeId'] as String?,
      enumeratorId: json['enumeratorId'] as String?,
      county: json['county'] as String? ?? '',
      district: json['district'] as String?,
      community: json['community'] as String? ?? '',
      inspectorName: json['inspectorName'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      directions: json['directions'] as String?,
      farmName: json['farmName'] as String? ?? '',
      crop: json['crop'] as String? ?? '',
      ownership: json['ownership'] as String? ?? '',
      regStatus: json['regStatus'] as String?,
      farmSizeManual: json['farmSizeManual'] as String?,
      farmUnitManual: json['farmUnitManual'] as String?,
      farmNotes: json['farmNotes'] as String?,
      numberOfTrees: json['numberOfTrees'] as String?,
      yearsInCultivation: json['yearsInCultivation'] as String?,
      harvestSeason: json['harvestSeason'] as String?,
      averageYield: json['averageYield'] as String?,
      buyers: json['buyers'] as String?,
      useChemicals: json['useChemicals'] as bool? ?? false,
      extensionServices: json['extensionServices'] as bool? ?? false,
      farmAddress: json['farmAddress'] as String?,
      areaHa: json['areaHa'] as String?,
      areaAc: json['areaAc'] as String?,
      boundaryJson: json['boundaryJson'] as String?,
      boundaryEvidence: (json['boundaryEvidence'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      consent: json['consent'] as bool? ?? false,
      farmerPhotoPath: json['farmerPhotoPath'] as String?,
      nationalIdPath: json['nationalIdPath'] as String?,
      farmSelfiePath: json['farmSelfiePath'] as String?,
      signaturePath: json['signaturePath'] as String?,
      farmPhotosPaths: (json['farmPhotosPaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      complianceDocuments: (json['complianceDocuments'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
    );
  }

  // Create a copy with updated fields
  FarmerRegistrationModel copyWith({
    String? fullName,
    String? gender,
    String? dob,
    String? phone,
    String? nationality,
    String? idType,
    String? idTypeOther,
    String? nationalId,
    String? email,
    String? cooperativeName,
    String? cooperativeId,
    String? enumeratorId,
    String? county,
    String? district,
    String? community,
    String? inspectorName,
    double? lat,
    double? lng,
    String? directions,
    String? farmName,
    String? crop,
    String? ownership,
    String? regStatus,
    String? farmSizeManual,
    String? farmUnitManual,
    String? farmNotes,
    String? numberOfTrees,
    String? yearsInCultivation,
    String? harvestSeason,
    String? averageYield,
    String? buyers,
    bool? useChemicals,
    bool? extensionServices,
    String? farmAddress,
    String? areaHa,
    String? areaAc,
    String? boundaryJson,
    List<Map<String, dynamic>>? boundaryEvidence,
    bool? consent,
    String? farmerPhotoPath,
    String? nationalIdPath,
    String? farmSelfiePath,
    String? signaturePath,
    List<String>? farmPhotosPaths,
    List<Map<String, String>>? complianceDocuments,
  }) {
    return FarmerRegistrationModel(
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      phone: phone ?? this.phone,
      nationality: nationality ?? this.nationality,
      idType: idType ?? this.idType,
      idTypeOther: idTypeOther ?? this.idTypeOther,
      nationalId: nationalId ?? this.nationalId,
      email: email ?? this.email,
      cooperativeName: cooperativeName ?? this.cooperativeName,
      cooperativeId: cooperativeId ?? this.cooperativeId,
      enumeratorId: enumeratorId ?? this.enumeratorId,
      county: county ?? this.county,
      district: district ?? this.district,
      community: community ?? this.community,
      inspectorName: inspectorName ?? this.inspectorName,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      directions: directions ?? this.directions,
      farmName: farmName ?? this.farmName,
      crop: crop ?? this.crop,
      ownership: ownership ?? this.ownership,
      regStatus: regStatus ?? this.regStatus,
      farmSizeManual: farmSizeManual ?? this.farmSizeManual,
      farmUnitManual: farmUnitManual ?? this.farmUnitManual,
      farmNotes: farmNotes ?? this.farmNotes,
      numberOfTrees: numberOfTrees ?? this.numberOfTrees,
      yearsInCultivation: yearsInCultivation ?? this.yearsInCultivation,
      harvestSeason: harvestSeason ?? this.harvestSeason,
      averageYield: averageYield ?? this.averageYield,
      buyers: buyers ?? this.buyers,
      useChemicals: useChemicals ?? this.useChemicals,
      extensionServices: extensionServices ?? this.extensionServices,
      farmAddress: farmAddress ?? this.farmAddress,
      areaHa: areaHa ?? this.areaHa,
      areaAc: areaAc ?? this.areaAc,
      boundaryJson: boundaryJson ?? this.boundaryJson,
      boundaryEvidence: boundaryEvidence ?? this.boundaryEvidence,
      consent: consent ?? this.consent,
      farmerPhotoPath: farmerPhotoPath ?? this.farmerPhotoPath,
      nationalIdPath: nationalIdPath ?? this.nationalIdPath,
      farmSelfiePath: farmSelfiePath ?? this.farmSelfiePath,
      signaturePath: signaturePath ?? this.signaturePath,
      farmPhotosPaths: farmPhotosPaths ?? this.farmPhotosPaths,
      complianceDocuments: complianceDocuments ?? this.complianceDocuments,
    );
  }
}

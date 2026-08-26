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
    );
  }
}

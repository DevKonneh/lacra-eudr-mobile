class FarmerRegistrationModel {
  // Personal Information
  final String fullName;
  final String gender;
  final String? dob;
  final String phone;
  final String? nationality;
  final String? nationalId;
  final String? email;
  
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
  
  // Mapping Information
  final String? areaHa;
  final String? areaAc;
  final String? boundaryJson;
  
  // Consent
  final bool consent;
  
  // File paths (for multipart upload)
  final String? farmerPhotoPath;
  final String? nationalIdPath;
  final String? farmSelfiePath;
  final List<String>? farmPhotosPaths;

  FarmerRegistrationModel({
    required this.fullName,
    required this.gender,
    this.dob,
    required this.phone,
    this.nationality,
    this.nationalId,
    this.email,
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
    this.areaHa,
    this.areaAc,
    this.boundaryJson,
    required this.consent,
    this.farmerPhotoPath,
    this.nationalIdPath,
    this.farmSelfiePath,
    this.farmPhotosPaths,
  });

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'gender': gender,
      if (dob != null) 'dob': dob,
      'phone': phone,
      if (nationality != null) 'nationality': nationality,
      if (nationalId != null) 'nationalId': nationalId,
      if (email != null) 'email': email,
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
    String? nationalId,
    String? email,
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
    String? areaHa,
    String? areaAc,
    String? boundaryJson,
    bool? consent,
    String? farmerPhotoPath,
    String? nationalIdPath,
    String? farmSelfiePath,
    List<String>? farmPhotosPaths,
  }) {
    return FarmerRegistrationModel(
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      phone: phone ?? this.phone,
      nationality: nationality ?? this.nationality,
      nationalId: nationalId ?? this.nationalId,
      email: email ?? this.email,
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
      areaHa: areaHa ?? this.areaHa,
      areaAc: areaAc ?? this.areaAc,
      boundaryJson: boundaryJson ?? this.boundaryJson,
      consent: consent ?? this.consent,
      farmerPhotoPath: farmerPhotoPath ?? this.farmerPhotoPath,
      nationalIdPath: nationalIdPath ?? this.nationalIdPath,
      farmSelfiePath: farmSelfiePath ?? this.farmSelfiePath,
      farmPhotosPaths: farmPhotosPaths ?? this.farmPhotosPaths,
    );
  }
}

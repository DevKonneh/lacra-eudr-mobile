/// Official first-level (county) and second-level (district) administrative
/// divisions of Liberia, used to drive the Location & GPS step's County and
/// District dropdowns (see FarmerLocationStep).
///
/// Source: Republic of Liberia administrative divisions (15 counties, 136
/// districts) - compiled from the National Elections Commission / GoL
/// administrative boundary references (also documented on
/// https://en.wikipedia.org/wiki/Administrative_divisions_of_Liberia).
///
/// NOTE: District names/counts for some rural counties vary slightly between
/// sources (e.g. some district splits like "Sanquin District #1/#2/#3" or
/// "Karluway District #1/#2"). This list uses the commonly-referenced set.
/// If CDA/LACRA maintains its own authoritative administrative gazetteer,
/// replace this list with that source - the dropdown wiring in
/// FarmerLocationStep does not need to change, only this data file.
class LiberiaLocations {
  LiberiaLocations._();

  /// Ordered list of all 15 Liberian counties.
  static const List<String> counties = [
    'Bomi',
    'Bong',
    'Gbarpolu',
    'Grand Bassa',
    'Grand Cape Mount',
    'Grand Gedeh',
    'Grand Kru',
    'Lofa',
    'Margibi',
    'Maryland',
    'Montserrado',
    'Nimba',
    'River Cess',
    'River Gee',
    'Sinoe',
  ];

  /// County name -> ordered list of its districts. Used to populate the
  /// District dropdown so it only ever shows districts that actually belong
  /// to the currently-selected County (per the ID-mismatch-reduction
  /// requirement).
  static const Map<String, List<String>> districtsByCounty = {
    'Bomi': [
      'Dewoin District',
      'Klay District',
      'Senjeh District',
      'Suehn Mecca District',
    ],
    'Bong': [
      'Boinsen District',
      'Fuamah District',
      'Jorquelleh District',
      'Kokoyah District',
      'Kpaai District',
      'Panta District',
      'Salala District',
      'Sanoyeah District',
      'Suakoko District',
      'Tukpahblee District',
      'Yeallequelleh District',
      'Zota District',
    ],
    'Gbarpolu': [
      'Belleh District',
      'Bokomu District',
      'Bopolu District',
      'Gbarma District',
      'Gounwolaila District',
      'Kongba District',
    ],
    'Grand Bassa': [
      'Commonwealth District',
      'District #1',
      'District #2',
      'District #3',
      'District #4',
      'Neekreen District',
      'Owensgrove District',
      'St. John River District',
    ],
    'Grand Cape Mount': [
      'Commonwealth District',
      'Garwula District',
      'Gola Konneh District',
      'Porkpa District',
      'Tewor District',
    ],
    'Grand Gedeh': [
      "B'hai District",
      'Cavala District',
      'Gbao District',
      'Gboe-Ploe District',
      'Glio-Twarbo District',
      'Konobo District',
      'Putu District',
      'Tchien District',
    ],
    'Grand Kru': [
      'Barclayville District',
      'Bleebo District',
      'Bolloh District',
      'Buah District',
      'Dorbor District',
      'Dweh District',
      'Felo-Jekwi District',
      'Fenetoe District',
      'Forpoh District',
      'Garraway District',
      'Gee District',
      'Grand Cess Wedabo District',
      'Upper Jloh District',
      'Lower Jloh District',
      'Kpi District',
      'Nrokwia-Wesldow District',
      'Trenbo District',
      'Wlogba District',
    ],
    'Lofa': [
      'Foya District',
      'Kolahun District',
      'Quardu Gboni District',
      'Salayea District',
      'Vahun District',
      'Voinjama District',
      'Zorzor District',
    ],
    'Margibi': [
      'Firestone District',
      'Gibi District',
      'Kakata District',
      'Mambah Kaba District',
    ],
    'Maryland': [
      'Gwelekpoken District',
      'Harper District',
      'Karluway District #1',
      'Karluway District #2',
      'Nyorken District',
      'Pleebo/Sodoken District',
      'Whojah District',
    ],
    'Montserrado': [
      'Commonwealth District',
      'Careysburg District',
      'Greater Monrovia District',
      'St. Paul River District',
      'Todee District',
    ],
    'Nimba': [
      'Boe & Quilla District',
      'Buu-Yao District',
      'Doe District',
      'Garr-Bain District',
      'Gbehlay-Geh District',
      'Gbi & Doru District',
      'Gbor District',
      'Kparblee District',
      'Leewehpea-Mahn District',
      'Meinpea-Mahn District',
      'Sanniquellie-Mahn District',
      'Twan River District',
      'Wee-Gbehy-Mahn District',
      'Yarmein District',
      'Yarpea-Mahn District',
      'Yarwein Mehnsonnoh District',
      'Zoe-Gbao District',
    ],
    'River Cess': [
      'Beawor District',
      'Central River Cess District',
      'Doedain District',
      'Fen River District',
      'Jo River District',
      'Norwein District',
      'Sam Gbalor District',
      'Zarflahn District',
    ],
    'River Gee': [
      'Chedepo District',
      'Gbeapo District',
      'Glaro District',
      'Karforh District',
      'Nanee District',
      'Nyenawliken District',
      'Nyenebo District',
      'Potupo District',
      'Sarbo District',
      'Tuobo District',
    ],
    'Sinoe': [
      'Bodae District',
      'Bokon District',
      'Butaw District',
      'Dugbe River District',
      'Greenville District',
      'Jaedae District',
      'Jaedepo District',
      'Juarzon District',
      'Kpayan District',
      'Kulu Shaw Boe District',
      'Plahn Nyarn District',
      'Pynes Town District',
      'Sanquin District #1',
      'Sanquin District #2',
      'Sanquin District #3',
      'Seekon District',
      'Wedjah District',
    ],
  };

  /// Returns the districts for [county], or an empty list if [county] is
  /// null/unrecognized.
  static List<String> districtsFor(String? county) {
    if (county == null) return const [];
    return districtsByCounty[county] ?? const [];
  }
}

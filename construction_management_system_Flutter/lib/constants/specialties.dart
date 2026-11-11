class Specialties {
  static const all = <String>[
    'electrical', 'plumbing', 'welding', 'carpentry', 'masonry',
    'painting', 'tiling', 'scaffolding', 'roofing', 'equipment',
  ];

  static String label(String value) => switch (value) {
    'electrical' => 'Electrical', 'plumbing' => 'Plumbing',
    'welding' => 'Welding', 'carpentry' => 'Carpentry',
    'masonry' => 'Masonry', 'painting' => 'Painting', 'tiling' => 'Tiling',
    'scaffolding' => 'Scaffolding', 'roofing' => 'Roofing',
    'equipment' => 'Equipment', _ => value,
  };
}

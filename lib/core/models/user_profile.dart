class UserProfile {
  const UserProfile({
    required this.addressStyle,
    required this.name,
    required this.personality,
    this.voiceGender = 'male',
  });

  final String addressStyle;
  final String name;
  final String personality;
  final String voiceGender;

  String get preferredAddress => switch (addressStyle) {
    'mr' => name.isEmpty ? 'Sir' : 'Mr. $name',
    'maam' => name.isEmpty ? 'Ma’am' : 'Ms. $name',
    'name' => name,
    _ => name,
  };
}

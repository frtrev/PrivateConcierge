import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user_profile.dart';

class UserProfileService {
  UserProfileService(this._preferences);

  static const _addressKey = 'profile.address';
  static const _nameKey = 'profile.name';
  static const _personalityKey = 'profile.personality';
  static const _voiceGenderKey = 'profile.voiceGender';

  final SharedPreferences _preferences;

  UserProfile? load() {
    final address = _preferences.getString(_addressKey);
    if (address == null) return null;
    return UserProfile(
      addressStyle: address,
      name: _preferences.getString(_nameKey) ?? '',
      personality: _preferences.getString(_personalityKey) ?? 'warm',
      voiceGender: _preferences.getString(_voiceGenderKey) ?? 'male',
    );
  }

  Future<void> save(UserProfile profile) async {
    await _preferences.setString(_addressKey, profile.addressStyle);
    await _preferences.setString(_nameKey, profile.name);
    await _preferences.setString(_personalityKey, profile.personality);
    await _preferences.setString(_voiceGenderKey, profile.voiceGender);
  }
}

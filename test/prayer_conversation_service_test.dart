import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/prayer.dart';
import 'package:private_concierge/services/prayers/prayer_conversation_service.dart';
import 'package:private_concierge/services/storage/private_data_store.dart';

class MemoryPrayerStore implements PrayerStore {
  final values = <Prayer>[];
  final routines = <PrayerRoutine>[];

  @override
  Future<Prayer> savePrayer({
    String? name,
    required String text,
    int? id,
  }) async {
    final now = DateTime(2026, 8, 17, 10, 30);
    if (id != null) {
      final index = values.indexWhere((prayer) => prayer.id == id);
      final old = values[index];
      return values[index] = Prayer(
        id: id,
        name: old.name,
        text: text,
        createdAt: old.createdAt,
        updatedAt: now,
      );
    }
    final prayer = Prayer(
      id: values.length + 1,
      name: name!,
      text: text,
      createdAt: now,
      updatedAt: now,
    );
    values.add(prayer);
    return prayer;
  }

  @override
  Future<List<Prayer>> prayers() async => [...values];
  @override
  Future<void> deletePrayer(int id) async =>
      values.removeWhere((prayer) => prayer.id == id);
  @override
  Future<void> renamePrayer(int id, String name) async {}
  @override
  Future<void> deletePrayerRoutine(int id) async {}
  @override
  Future<List<PrayerRoutine>> prayerRoutines() async => [...routines];
  @override
  Future<PrayerRoutine> savePrayerRoutine({
    int? id,
    required String name,
    required List<int> prayerIds,
  }) async => throw UnimplementedError();
}

void main() {
  test('records prayer text then asks for and stores its name', () async {
    final store = MemoryPrayerStore();
    final service = PrayerConversationService(store);

    expect(
      (await service.handle('Can you record this prayer?'))!.spokenResponse,
      contains("I'm listening"),
    );
    expect(
      (await service.handle('Please protect my family.'))!.spokenResponse,
      'What do you want to name this prayer?',
    );
    expect(
      (await service.handle('Family prayer'))!.spokenResponse,
      'I saved the prayer as Family prayer.',
    );
    expect(store.values.single.text, 'Please protect my family.');
    expect(store.values.single.createdAt, DateTime(2026, 8, 17, 10, 30));
  });

  test('plays a named prayer and lists tappable choices for a miss', () async {
    final store = MemoryPrayerStore();
    await store.savePrayer(name: 'Morning', text: 'Thank you for this day.');
    final service = PrayerConversationService(store);

    await service.handle("Let's pray");
    final found = await service.handle('Morning');
    expect(found!.spokenResponse, contains('Thank you for this day.'));

    await service.handle('I want to pray');
    final missing = await service.handle('Evening');
    expect(missing!.prayerChoices.single.name, 'Morning');
  });

  test('editing replaces text without asking for a new name', () async {
    final store = MemoryPrayerStore();
    final prayer = await store.savePrayer(name: 'Grace', text: 'Old text');
    final service = PrayerConversationService(store)..beginEdit(prayer);

    final result = await service.handle('New prayer text');
    expect(result!.spokenResponse, 'I updated Grace.');
    expect(store.values.single.name, 'Grace');
    expect(store.values.single.text, 'New prayer text');
  });
}

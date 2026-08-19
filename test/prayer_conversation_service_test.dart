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
    required List<PrayerRoutineStep> steps,
  }) async => throw UnimplementedError();
}

void main() {
  test('records prayer text then asks for and stores its name', () async {
    final store = MemoryPrayerStore();
    final service = PrayerConversationService(store);

    expect(
      (await service.handle('Can you record this prayer?'))!.spokenResponse,
      "Of course, you can start praying after the beep, I'll be listening.",
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
    expect(found!.spokenResponse, "Let's begin.");
    expect(found.context.lastIntent, 'playPrayer');
    expect(found.prayerChoices.single.isRoutine, isFalse);

    await service.handle('I want to pray');
    final missing = await service.handle('Evening');
    expect(missing!.prayerChoices.single.name, 'Morning');
  });

  test('natural pray request offers prayers and routines', () async {
    final store = MemoryPrayerStore();
    final prayer = await store.savePrayer(
      name: 'Our Father',
      text: 'Our Father in heaven.',
    );
    store.routines.add(
      PrayerRoutine(
        id: 9,
        name: 'Morning Rosary',
        steps: [
          PrayerRoutineStep(
            type: PrayerRoutineStepType.prayer,
            referenceId: prayer.id,
            name: prayer.name,
            repeatCount: 1,
            prayer: prayer,
          ),
        ],
        createdAt: DateTime(2026, 8, 18),
      ),
    );
    final service = PrayerConversationService(store);

    expect(
      (await service.handle('I would like to pray'))!.spokenResponse,
      'Which prayer or prayer routine would you like?',
    );
    final routine = await service.handle('Morning Rosary');
    expect(routine!.context.lastIntent, 'playPrayer');
    expect(routine.prayerChoices.single.isRoutine, isTrue);

    await service.handle("I'd like to pray");
    final missing = await service.handle('Something else');
    expect(missing!.prayerChoices, hasLength(2));
    expect(missing.prayerChoices.last.isRoutine, isTrue);
  });

  test('editing replaces text without asking for a new name', () async {
    final store = MemoryPrayerStore();
    final prayer = await store.savePrayer(name: 'Grace', text: 'Old text');
    final service = PrayerConversationService(store)..beginEdit(prayer);

    final result = await service.handle('New prayer text');
    expect(result!.spokenResponse, 'I updated Grace.');
    expect(store.values.single.name, 'Grace');
    expect(store.values.single.text, 'New prayer text.');
  });

  test('normalizes dictated prayer punctuation before saving', () async {
    final store = MemoryPrayerStore();
    final service = PrayerConversationService(store)..beginRecording();

    await service.handle('lord hear me, guide my family');
    await service.handle('Evening prayer');

    expect(store.values.single.text, 'Lord hear me, guide my family.');
  });
}

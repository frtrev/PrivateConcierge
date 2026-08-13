import '../../core/models/assistant_result.dart';
import '../../core/models/parking_event.dart';
import '../../core/models/visit_session.dart';
import '../../core/models/visited_place.dart';
import '../storage/private_data_store.dart';

class TrackingQueryEngine {
  TrackingQueryEngine(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PrivateDataStore store;
  final DateTime Function() _clock;
  VisitSession? _selectedSession;
  VisitedPlace? _selectedPlace;
  PlaceResult? _selectedTrackingResult;

  Future<AssistantResult?> answer(String input) async {
    final text = _normalize(input);
    if (RegExp(
          r'^(yes|yes please|sure|navigate|directions|show it on the map)$',
        ).hasMatch(text) &&
        _selectedTrackingResult != null) {
      final place = _selectedTrackingResult!;
      return AssistantResult(
        response: 'Starting directions to ${place.name}.',
        spokenResponse: 'Starting directions to ${place.name}.',
        type: AssistantResultType.navigation,
        places: [place],
        actions: [
          AssistantAction(
            type: AssistantActionType.navigate,
            placeId: place.id,
          ),
        ],
        context: AssistantConversationState(
          lastIntent: 'trackingNavigation',
          selectedPlaceId: place.id,
        ),
      );
    }
    if (!_looksLikeTrackingQuestion(text)) return null;
    final sessions = await store.visitSessions();
    final places = await store.mostVisited();
    final range = _dateRange(text, _clock());
    final place = _matchPlace(text, places);
    final category = _matchCategory(text);
    var matching = sessions.where((session) {
      if (place != null && session.poiId != place.poiId) return false;
      if (category != null && !_matchesCategory(session.category, category)) {
        return false;
      }
      if (range != null &&
          (session.arrival.isBefore(range.$1) ||
              !session.arrival.isBefore(range.$2))) {
        return false;
      }
      return true;
    }).toList();

    if (_isContextFollowUp(text) && place == null && category == null) {
      final selected = _selectedSession;
      if (selected != null) matching = [selected];
    }

    final result = await _respond(
      text,
      matching,
      sessions,
      places,
      place,
      range,
    );
    if (matching.isNotEmpty) _selectedSession = matching.first;
    if (place != null) _selectedPlace = place;
    return result;
  }

  Future<AssistantResult> _respond(
    String text,
    List<VisitSession> matching,
    List<VisitSession> allSessions,
    List<VisitedPlace> places,
    VisitedPlace? place,
    (DateTime, DateTime)? range,
  ) async {
    if (_containsAny(text, [
      'where did i park',
      'where is my car',
      'parking spot',
      'what time did i park',
      'how long has the car',
    ])) {
      return _parking(text, await store.parkingEvents());
    }
    if (_containsAny(text, [
      'what tracking data',
      'what data do you have',
      'how many visit records',
      'how far back',
    ])) {
      if (allSessions.isEmpty) {
        return _message('I do not have any completed visit sessions yet.');
      }
      final oldest = allSessions.last.arrival;
      return _message(
        'I have ${allSessions.length} completed visit sessions across ${places.length} recognized places, dating back to ${_date(oldest)}. This history is stored locally on this device.',
      );
    }
    if (_containsAny(text, [
      'is background tracking',
      'background location permission',
    ])) {
      return _message(
        'You can verify background tracking permission in Settings under Privacy and tracking.',
      );
    }
    if (_containsAny(text, ['most visited', 'visit most often', 'top '])) {
      final filtered = _filterAggregate(places, text);
      final limit = _requestedLimit(text);
      if (filtered.isEmpty) return _noMatch(place, range);
      final selected = filtered.take(limit).toList();
      return _placeList(
        'Your most visited ${_matchCategory(text) ?? 'places'} are ${selected.map((p) => '${p.name}, ${p.visitCount} visits').join('; ')}.',
        selected,
      );
    }
    if (_containsAny(text, [
      'how many places did i visit',
      'how many visits did i make',
      'how many unique places',
    ])) {
      final unique = matching.map((session) => session.poiId).toSet().length;
      if (text.contains('unique') || text.contains('places')) {
        return _message(
          'You visited $unique unique ${_plural(unique, 'place')} in that period.',
        );
      }
      return _message(
        'I found ${matching.length} recorded ${_plural(matching.length, 'visit')} in that period.',
      );
    }
    if (_containsAny(text, ['how many times', 'how often', 'visit count'])) {
      if (place == null) {
        return _message('Which place would you like a visit count for?');
      }
      final count = matching.length;
      return _message(
        range == null
            ? 'You have ${place.visitCount} recorded visits to ${place.name}.'
            : 'I found $count completed ${_plural(count, 'visit')} to ${place.name} in that period.',
      );
    }
    if (RegExp(
      r'^(did i (go|visit)|have i (ever been|been here)|was i at)\b',
    ).hasMatch(text)) {
      final label = place?.name ?? _matchCategory(text) ?? 'a matching place';
      return _message(
        matching.isEmpty
            ? 'I could not find a recorded visit to $label in that period.'
            : 'Yes. I found ${matching.length} recorded ${_plural(matching.length, 'visit')} to $label in that period.',
      );
    }
    if (_containsAny(text, [
      'how long',
      'time did i spend',
      'stay longer',
      'longest',
      'shortest',
      'average visit',
      'total time',
    ])) {
      if (matching.isEmpty) return _noMatch(place, range);
      final completed = matching.where((s) => s.departure != null).toList();
      if (completed.isEmpty) {
        return _message(
          'That visit does not have a recorded departure time yet.',
        );
      }
      final durations = completed
          .map((s) => s.departure!.difference(s.arrival))
          .toList();
      Duration duration;
      String prefix;
      if (text.contains('longest')) {
        duration = durations.reduce((a, b) => a > b ? a : b);
        prefix = 'Your longest matching visit was';
      } else if (text.contains('shortest')) {
        duration = durations.reduce((a, b) => a < b ? a : b);
        prefix = 'Your shortest matching visit was';
      } else if (text.contains('average')) {
        duration = Duration(
          milliseconds:
              durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds) ~/
              durations.length,
        );
        prefix = 'Your average matching visit was';
      } else if (text.contains('total') || text.contains('time did i spend')) {
        duration = Duration(
          milliseconds: durations.fold<int>(
            0,
            (sum, d) => sum + d.inMilliseconds,
          ),
        );
        prefix = 'Your total recorded time was';
      } else {
        duration = durations.first;
        prefix = 'You were at ${matching.first.name} for';
      }
      return _message('$prefix ${_duration(duration)}.');
    }
    if (_containsAny(text, [
      'what time did i arrive',
      'when did i arrive',
      'when did i get',
      'arrival time',
      'arrive earlier',
      'arrive later',
      'usually arrive',
      'average arrival',
      'earliest arrival',
      'latest arrival',
    ])) {
      if (matching.isEmpty) return _noMatch(place, range);
      final session = _arrivalSelection(text, matching);
      if (text.contains('usually') || text.contains('average')) {
        final minute =
            matching.fold<int>(
              0,
              (sum, s) => sum + s.arrival.hour * 60 + s.arrival.minute,
            ) ~/
            matching.length;
        return _message(
          'Your average arrival time at ${session.name} is ${_minuteTime(minute)} based on ${matching.length} visits.',
        );
      }
      return _message(
        'You arrived at ${session.name} at ${_time(session.arrival)} on ${_date(session.arrival)}.',
      );
    }
    if (_containsAny(text, [
      'what time did i leave',
      'when did i leave',
      'departure time',
      'usually leave',
      'average departure',
      'earliest departure',
      'latest departure',
    ])) {
      if (matching.isEmpty) return _noMatch(place, range);
      final completed = matching.where((s) => s.departure != null).toList();
      if (completed.isEmpty) {
        return _message(
          'That visit does not have a recorded departure time yet.',
        );
      }
      if (text.contains('usually') || text.contains('average')) {
        final minute =
            completed.fold<int>(
              0,
              (sum, s) => sum + s.departure!.hour * 60 + s.departure!.minute,
            ) ~/
            completed.length;
        return _message(
          'Your average departure time from ${completed.first.name} is ${_minuteTime(minute)} based on ${completed.length} visits.',
        );
      }
      final session = text.contains('earliest')
          ? completed.reduce(
              (a, b) => a.departure!.isBefore(b.departure!) ? a : b,
            )
          : text.contains('latest')
          ? completed.reduce(
              (a, b) => a.departure!.isAfter(b.departure!) ? a : b,
            )
          : completed.first;
      return _message(
        'You left ${session.name} at ${_time(session.departure!)} on ${_date(session.departure!)}.',
      );
    }
    if (!_containsAny(text, ['go after', 'before', 'do next']) &&
        _containsAny(text, [
          'where was i',
          'where have i been',
          'where did i go',
          'places did i visit',
          'show my visits',
          'recent visits',
          'last place',
          'first place',
        ])) {
      if (matching.isEmpty) return _noMatch(place, range);
      final ordered = text.contains('first')
          ? matching.reversed.toList()
          : matching;
      final singleResult = _containsAny(text, [
        'most recently',
        'where was i last',
        'last place',
        'last stop',
        'first place',
        'first stop',
      ]);
      final limit = singleResult ? 1 : _requestedLimit(text);
      final selected = ordered.take(limit).toList();
      return _sessionList(
        selected.length == 1
            ? 'You were at ${selected.first.name} from ${_time(selected.first.arrival)} to ${_time(selected.first.departure!)} on ${_date(selected.first.arrival)}.'
            : 'I found ${selected.length} visits, and here is the list:',
        selected,
        places,
      );
    }
    if (_containsAny(text, [
      'where did i go after',
      'what did i do next',
      'where was i before',
      'visit before that',
    ])) {
      final anchor = matching.isNotEmpty ? matching.first : _selectedSession;
      if (anchor == null) {
        return _message(
          'I need a recorded visit to use as the reference point.',
        );
      }
      final chronological = allSessions.reversed.toList();
      final index = chronological.indexWhere((s) => s.id == anchor.id);
      final targetIndex = text.contains('before') ? index - 1 : index + 1;
      if (index < 0 || targetIndex < 0 || targetIndex >= chronological.length) {
        return _message(
          'I could not find another recorded visit in that direction.',
        );
      }
      final target = chronological[targetIndex];
      _selectedSession = target;
      return _message(
        '${text.contains('before') ? 'Before' : 'After'} ${anchor.name}, you visited ${target.name} on ${_date(target.arrival)} at ${_time(target.arrival)}.',
      );
    }
    if (_containsAny(text, [
      'usual schedule',
      'what days do i usually',
      'weekday',
      'routine',
      'normal for me',
    ])) {
      if (matching.isEmpty) return _noMatch(place, range);
      final weekdays = <int, int>{};
      for (final session in matching) {
        weekdays.update(
          session.arrival.weekday,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
      }
      final common = weekdays.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final arrival =
          matching.fold<int>(
            0,
            (sum, s) => sum + s.arrival.hour * 60 + s.arrival.minute,
          ) ~/
          matching.length;
      final departures = matching.where((s) => s.departure != null).toList();
      final departure = departures.isEmpty
          ? null
          : departures.fold<int>(
                  0,
                  (sum, s) =>
                      sum + s.departure!.hour * 60 + s.departure!.minute,
                ) ~/
                departures.length;
      return _message(
        'Your recorded pattern for ${matching.first.name} is most often on ${_weekday(common.key)}, arriving around ${_minuteTime(arrival)}${departure == null ? '' : ' and leaving around ${_minuteTime(departure)}'}, based on ${matching.length} visits.',
      );
    }
    if (matching.isNotEmpty) {
      return _sessionList(
        matching.length == 1
            ? 'I found 1 visit.'
            : 'I found ${matching.length} visits, and here is the list:',
        matching.take(10).toList(),
        places,
      );
    }
    return _noMatch(place, range);
  }

  AssistantResult _parking(String text, List<ParkingEvent> events) {
    if (events.isEmpty) {
      return _message('I do not have a saved parking location yet.');
    }
    final event = events.first;
    if (text.contains('what time')) {
      return _message(
        'Parking was detected at ${_time(event.at)} on ${_date(event.at)}.',
      );
    }
    if (text.contains('how long')) {
      return _message(
        'The car has been parked for about ${_duration(_clock().difference(event.at))}.',
      );
    }
    final place = PlaceResult(
      id: 'parking-${event.id}',
      name: 'Parked car',
      latitude: event.coordinates.latitude,
      longitude: event.coordinates.longitude,
      address: '',
      category: 'parking',
    );
    _selectedTrackingResult = place;
    return AssistantResult(
      response:
          'Your latest parking location was saved at ${_time(event.at)} on ${_date(event.at)}.',
      spokenResponse:
          'Your latest parking location was saved at ${_time(event.at)}. Would you like directions to your car?',
      type: AssistantResultType.place,
      places: [place],
      actions: [
        AssistantAction(type: AssistantActionType.navigate, placeId: place.id),
      ],
      context: AssistantConversationState(
        lastIntent: 'parking',
        selectedPlaceId: place.id,
      ),
    );
  }

  AssistantResult _sessionList(
    String message,
    List<VisitSession> sessions,
    List<VisitedPlace> places,
  ) {
    final byId = {for (final place in places) place.poiId: place};
    final results = sessions.map((session) {
      final place = byId[session.poiId];
      return PlaceResult(
        id: session.poiId,
        name: session.name,
        latitude: place?.coordinates.latitude ?? 0,
        longitude: place?.coordinates.longitude ?? 0,
        address: place?.address ?? '',
        category: session.category,
        arrival: session.arrival,
        departure: session.departure,
      );
    }).toList();
    return AssistantResult(
      response: message,
      spokenResponse: message,
      type: results.length == 1
          ? AssistantResultType.place
          : AssistantResultType.placeList,
      places: results,
      context: AssistantConversationState(
        lastIntent: 'tracking',
        selectedPlaceId: results.length == 1 ? results.first.id : null,
      ),
    );
  }

  AssistantResult _placeList(String message, List<VisitedPlace> places) =>
      AssistantResult(
        response: message,
        spokenResponse: message,
        type: places.length == 1
            ? AssistantResultType.place
            : AssistantResultType.placeList,
        places: places
            .map(
              (p) => PlaceResult(
                id: p.poiId,
                name: p.name,
                latitude: p.coordinates.latitude,
                longitude: p.coordinates.longitude,
                address: p.address,
                category: p.category,
              ),
            )
            .toList(),
        context: const AssistantConversationState(
          lastIntent: 'trackingRanking',
        ),
      );

  AssistantResult _message(String message) => AssistantResult(
    response: message,
    spokenResponse: message,
    type: AssistantResultType.message,
    context: const AssistantConversationState(lastIntent: 'tracking'),
  );

  AssistantResult _noMatch(
    VisitedPlace? place,
    (DateTime, DateTime)? range,
  ) => _message(
    'I could not find a completed recorded visit${place == null ? '' : ' to ${place.name}'}${range == null ? '' : ' in that period'}.',
  );

  List<VisitedPlace> _filterAggregate(List<VisitedPlace> places, String text) {
    final category = _matchCategory(text);
    return places
        .where(
          (p) => category == null || _matchesCategory(p.category, category),
        )
        .toList();
  }

  VisitedPlace? _matchPlace(String text, List<VisitedPlace> places) {
    final ordered = [...places]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final place in ordered) {
      if (text.contains(_normalize(place.name))) return place;
    }
    if (_containsAny(text, ['home', 'work', 'office', 'gym'])) {
      for (final place in ordered) {
        if (text.contains(_normalize(place.name)) ||
            text.contains(_normalize(place.category))) {
          return place;
        }
      }
    }
    return _isContextFollowUp(text) ? _selectedPlace : null;
  }

  String? _matchCategory(String text) {
    const categories = {
      'restaurant': ['restaurant', 'place to eat'],
      'gas': ['gas station', 'fuel station'],
      'shopping': ['store', 'shopping'],
      'church': ['church'],
      'pharmacy': ['pharmacy', 'drugstore'],
      'grocery': ['grocery', 'supermarket'],
      'cafe': ['cafe', 'coffee shop'],
    };
    for (final entry in categories.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return null;
  }

  bool _matchesCategory(String actual, String requested) {
    final value = _normalize(actual);
    return value.contains(requested) || requested.contains(value);
  }

  (DateTime, DateTime)? _dateRange(String text, DateTime now) {
    DateTime day(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    if (text.contains('today')) {
      return (day(now), day(now).add(const Duration(days: 1)));
    }
    if (text.contains('yesterday')) {
      final start = day(now).subtract(const Duration(days: 1));
      return (start, start.add(const Duration(days: 1)));
    }
    if (text.contains('this week')) {
      final start = day(now).subtract(Duration(days: now.weekday - 1));
      return (start, start.add(const Duration(days: 7)));
    }
    if (text.contains('last week')) {
      final end = day(now).subtract(Duration(days: now.weekday - 1));
      return (end.subtract(const Duration(days: 7)), end);
    }
    if (text.contains('this month')) {
      return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    }
    if (text.contains('last month')) {
      return (DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
    }
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    for (var i = 0; i < names.length; i++) {
      if (text.contains('last ${names[i]}')) {
        var delta = (now.weekday - (i + 1)) % 7;
        if (delta == 0) delta = 7;
        final start = day(now).subtract(Duration(days: delta));
        return (start, start.add(const Duration(days: 1)));
      }
    }
    return null;
  }

  VisitSession _arrivalSelection(String text, List<VisitSession> sessions) {
    if (text.contains('earliest')) {
      return sessions.reduce((a, b) => a.arrival.isBefore(b.arrival) ? a : b);
    }
    if (text.contains('latest')) {
      return sessions.reduce((a, b) => a.arrival.isAfter(b.arrival) ? a : b);
    }
    return sessions.first;
  }

  int _requestedLimit(String text) {
    final digit = RegExp(r'\b(\d{1,2})\b').firstMatch(text);
    if (digit != null) return int.parse(digit.group(1)!).clamp(1, 10);
    const words = {
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
    };
    for (final entry in words.entries) {
      if (text.contains(' ${entry.key} ')) return entry.value;
    }
    return 10;
  }

  bool _looksLikeTrackingQuestion(String text) => _containsAny(text, [
    'did i ',
    'have i ',
    'was i ',
    'where was i',
    'where have i been',
    'where did i go',
    'what was the first place',
    'what was the last place',
    'what was my first stop',
    'what was my last stop',
    'how many places did i visit',
    'how many visits did i make',
    'unique places did i visit',
    'which days did i visit',
    'when did i last visit',
    'when did i first visit',
    'days has it been since',
    'what did i visit between',
    'stops did i make',
    'visits in order',
    'my route of visited places',
    'directly from',
    'usual schedule',
    'what days do i usually',
    'normal routine',
    'compare my visits',
    'new places did i visit',
    'places have i visited near',
    'visited place is closest',
    'unknown places',
    'tracking working',
    'last location update',
    'gaps in tracking',
    'gps noise',
    'location ambiguous',
    'what time did i arrive',
    'when did i arrive',
    'when did i get',
    'what time did i leave',
    'when did i leave',
    'how long was i',
    'how long did i stay',
    'time did i spend',
    'most visited',
    'visit most often',
    'how many times',
    'how often do i',
    'my visits',
    'visit history',
    'recorded visit',
    'usual schedule',
    'usually arrive',
    'usually leave',
    'where did i park',
    'where is my car',
    'parking spot',
    'what time did i park',
    'tracking data',
    'visit records',
    'background tracking',
    'there',
    'that visit',
  ]);

  bool _isContextFollowUp(String text) => _containsAny(text, [
    'there',
    'that visit',
    'before that',
    'did i leave',
    'how long was i',
  ]);
  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  String _plural(int count, String word) => count == 1 ? word : '${word}s';
  String _date(DateTime value) =>
      '${_month(value.month)} ${value.day}, ${value.year}';
  String _time(DateTime value) => _minuteTime(value.hour * 60 + value.minute);
  String _minuteTime(int minute) {
    final hour = (minute ~/ 60) % 24;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:${(minute % 60).toString().padLeft(2, '0')} $suffix';
  }

  String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours == 0) return '$minutes ${_plural(minutes, 'minute')}';
    if (minutes == 0) return '$hours ${_plural(hours, 'hour')}';
    return '$hours ${_plural(hours, 'hour')} and $minutes ${_plural(minutes, 'minute')}';
  }

  String _weekday(int day) => const [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][day];
  String _month(int month) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month];
}

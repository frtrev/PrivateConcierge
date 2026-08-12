import '../../core/models/assistant_result.dart';
import '../../core/models/poi.dart';

class PlaceDetailAnswer {
  const PlaceDetailAnswer(this.message, {this.action});
  final String message;
  final AssistantActionType? action;
}

class PlaceDetailFollowUpResolver {
  PlaceDetailFollowUpResolver({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  bool recognizes(String text) {
    final value = _normalize(text);
    return _asksClosing(value) ||
        _asksOpen(value) ||
        _asksPhone(value) ||
        _asksCall(value) ||
        _asksWebsite(value);
  }

  PlaceDetailAnswer resolve(String text, PointOfInterest? place) {
    if (place == null) {
      return const PlaceDetailAnswer(
        'I do not have a selected place yet. Find a place first.',
      );
    }
    final value = _normalize(text);
    if (_asksPhone(value) || _asksCall(value)) {
      final phone = place.phoneNumber?.trim();
      if (phone == null || phone.isEmpty) {
        return PlaceDetailAnswer(
          "I don't have a phone number for ${place.name} in the place data.",
        );
      }
      if (_asksCall(value)) {
        return PlaceDetailAnswer(
          'Calling ${place.name} at $phone.',
          action: AssistantActionType.call,
        );
      }
      return PlaceDetailAnswer('${place.name}’s phone number is $phone.');
    }
    if (_asksWebsite(value)) {
      return place.website == null
          ? PlaceDetailAnswer(
              "I don't have a website for ${place.name} in the place data.",
            )
          : PlaceDetailAnswer(
              'Opening ${place.name}’s website.',
              action: AssistantActionType.openWebsite,
            );
    }
    final hours = place.openingHours;
    if (hours == null) {
      return PlaceDetailAnswer(
        "I don't have reliable opening hours for ${place.name}.",
      );
    }
    final now = _clock();
    if (_asksOpen(value)) {
      return PlaceDetailAnswer(
        '${place.name} is ${hours.isOpenAt(now) ? 'open' : 'closed'} right now.',
      );
    }
    final closing = hours.nextClosingTime(now);
    if (closing == null) {
      return PlaceDetailAnswer('${place.name} is closed right now.');
    }
    return PlaceDetailAnswer(
      '${place.name} closes at ${_formatTime(closing)}.',
    );
  }

  String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  bool _asksClosing(String value) =>
      RegExp(r'\b(what time|when).*(close|closing)\b').hasMatch(value);
  bool _asksOpen(String value) =>
      RegExp(r'\b(are|is).*(open now|open)\b').hasMatch(value);
  bool _asksPhone(String value) =>
      RegExp(r'\b(phone number|telephone|number)\b').hasMatch(value);
  bool _asksCall(String value) =>
      RegExp(r'\b(call|phone) (them|it|this place)\b').hasMatch(value);
  bool _asksWebsite(String value) => RegExp(
    r'\b(open|show|visit).*(their|its|the)?\s*website\b',
  ).hasMatch(value);

  String _formatTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}

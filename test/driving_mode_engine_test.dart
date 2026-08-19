import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/services/driving/driving_mode_engine.dart';

void main() {
  test(
    'requires sustained vehicle-like movement before entering driving mode',
    () {
      final detector = DrivingModeDetector();
      final start = DateTime(2026, 8, 10, 8);
      detector.observe(const Coordinates(35, -90), start);

      final first = detector.observe(
        const Coordinates(35.003, -90),
        start.add(const Duration(seconds: 30)),
      );
      expect(first.mode, isNot(MotionMode.driving));

      final second = detector.observe(
        const Coordinates(35.006, -90),
        start.add(const Duration(seconds: 60)),
      );
      expect(second.mode, isNot(MotionMode.driving));
      final third = detector.observe(
        const Coordinates(35.009, -90),
        start.add(const Duration(seconds: 90)),
      );
      expect(third.mode, MotionMode.driving);
      expect(third.speedMetersPerSecond, greaterThan(4.5));
    },
  );

  test('does not classify walking or one GPS jump as driving', () {
    final detector = DrivingModeDetector();
    final start = DateTime(2026, 8, 10, 8);
    detector.observe(const Coordinates(35, -90), start);
    final walking = detector.observe(
      const Coordinates(35.0003, -90),
      start.add(const Duration(seconds: 30)),
    );
    expect(walking.mode, isNot(MotionMode.driving));
    final jump = detector.observe(
      const Coordinates(35.01, -90),
      start.add(const Duration(seconds: 60)),
    );
    expect(jump.mode, isNot(MotionMode.driving));
  });

  test('leaves driving mode after sustained stopped samples', () {
    final detector = DrivingModeDetector();
    final start = DateTime(2026, 8, 10, 8);
    detector.observe(const Coordinates(35, -90), start);
    detector.observe(
      const Coordinates(35.003, -90),
      start.add(const Duration(seconds: 30)),
    );
    detector.observe(
      const Coordinates(35.006, -90),
      start.add(const Duration(seconds: 60)),
    );
    detector.observe(
      const Coordinates(35.009, -90),
      start.add(const Duration(seconds: 90)),
    );
    expect(detector.mode, MotionMode.driving);
    for (var i = 1; i <= 4; i++) {
      detector.observe(
        const Coordinates(35.009, -90),
        start.add(Duration(seconds: 90 + i * 30)),
      );
    }
    expect(detector.mode, MotionMode.stationary);
  });

  test('an update gap does not turn driving into a parking transition', () {
    final detector = DrivingModeDetector();
    final start = DateTime(2026, 8, 10, 8);
    for (var i = 0; i <= 3; i++) {
      detector.observe(
        Coordinates(35 + i * .003, -90),
        start.add(Duration(seconds: i * 30)),
      );
    }
    expect(detector.mode, MotionMode.driving);

    final afterGap = detector.observe(
      const Coordinates(35.009, -90),
      start.add(const Duration(minutes: 10)),
    );
    expect(afterGap.observationAccepted, isFalse);
    expect(afterGap.reason, 'update_gap');
    expect(afterGap.mode, MotionMode.driving);
  });

  test('poor accuracy and uncertainty-sized drift cannot start driving', () {
    final detector = DrivingModeDetector();
    final start = DateTime(2026, 8, 10, 8);
    detector.observe(
      const Coordinates(35, -90, horizontalAccuracyMeters: 80),
      start,
    );
    for (var i = 1; i <= 4; i++) {
      final estimate = detector.observe(
        Coordinates(
          35 + i * .001,
          -90,
          horizontalAccuracyMeters: 80,
          reportedSpeedMetersPerSecond: 0,
        ),
        start.add(Duration(seconds: i * 30)),
      );
      expect(estimate.mode, isNot(MotionMode.driving));
      expect(estimate.observationAccepted, isFalse);
      expect(estimate.reason, 'poor_accuracy');
    }
  });
}

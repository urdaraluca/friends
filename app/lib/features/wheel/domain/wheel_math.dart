import 'dart:math';

/// The geometry of the wheel.
///
/// Slice `i` of `n` covers the wheel angles `[i·s, (i+1)·s)` with
/// `s = 2π/n`, measured clockwise from 12 o'clock. Turning the wheel
/// clockwise by `θ` puts wheel angle `a` at screen angle `a + θ`, so the
/// pointer at the top (screen angle 0) points at wheel angle `−θ mod 2π`.
abstract final class WheelMath {
  static const double fullTurn = 2 * pi;

  /// The fewest and most extra full turns of a spin.
  static const minTurns = 5;
  static const maxTurns = 7;

  /// How far from a slice's middle a spin may stop, as a share of the slice
  /// (±0.35 keeps it well inside the slice).
  static const maxJitter = 0.35;

  /// The angle of one slice of [count].
  static double sliceAngle(int count) => fullTurn / count;

  /// The rotation that stops slice [index] of [count] under the pointer,
  /// shifted by [jitter] (a share of a slice, within ±[maxJitter]), at least
  /// [turns] full turns clockwise past [current].
  ///
  /// This is `θ = current + 2π·turns − (index + 0.5)·s + jitter·s`, kept in
  /// the right slice whatever [current] is: the last term is taken modulo a
  /// full turn from [current]'s position.
  static double targetRotation({
    required double current,
    required int index,
    required int count,
    required int turns,
    double jitter = 0,
  }) {
    assert(count > 0 && index >= 0 && index < count, 'bad slice');
    final s = sliceAngle(count);
    final stop = -(index + 0.5) * s + jitter * s;
    final offset = _mod(stop - current, fullTurn);
    return current + turns * fullTurn + offset;
  }

  /// The slice under the pointer when the wheel is turned by [rotation].
  static int sliceAtPointer(double rotation, int count) {
    final angle = _mod(-rotation, fullTurn);
    return min(angle ~/ sliceAngle(count), count - 1);
  }

  /// Turns and jitter for a spin, derived from [seed] so a replay of the
  /// same spin looks the same.
  static ({int turns, double jitter}) spinShape(int seed) {
    final random = Random(seed);
    return (
      turns: minTurns + random.nextInt(maxTurns - minTurns + 1),
      jitter: (random.nextDouble() * 2 - 1) * maxJitter,
    );
  }

  static double _mod(double value, double modulus) {
    final result = value % modulus;
    return result < 0 ? result + modulus : result;
  }
}

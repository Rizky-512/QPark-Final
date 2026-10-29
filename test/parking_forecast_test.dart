import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/data/parking_forecast.dart';

Map<String, dynamic> dataset({bool singleClass = false}) {
  final random = Random(42);
  const first = 1790800000.0;
  final rows = List.generate(700, (i) {
    final n = random.nextInt(20),
        a = random.nextInt(singleClass ? 5 : 9),
        d = random.nextInt(5);
    return <num>[n, 2 + 2 * a, a, d, first + i * 900];
  });
  return {
    'version': 2,
    'capacity': 20,
    'current': 10,
    'target_time': first + 700 * 900 + 1800,
    'live': [10, 8, 2, first + 700 * 900],
    'samples': rows,
  };
}

void main() {
  test('OLS learns arrivals effect and evaluates on unseen future data', () {
    final f = ParkingForecast(dataset());
    expect(f.predicted, closeTo(18, 1e-6));
    expect(f.testMetrics['mae'], lessThan(1e-6));
    expect(f.testMetrics['baseline_mae'], greaterThan(1));
    expect(f.trainCount + f.validationCount + f.testCount, lessThan(f.samples));
  });
  test('logistic learns an inclusive 80 percent event independently', () {
    final source = dataset();
    final high = ParkingForecast(source);
    source['live'] = [10, 0, 2, (source['live'] as List)[3]];
    final low = ParkingForecast(source);
    expect(high.probability, greaterThan(.7));
    expect(low.probability, lessThan(.2));
    expect(
      high.testMetrics['brier'],
      lessThan(high.testMetrics['baseline_brier']!),
    );
  });
  test('single-class and insufficient history do not invent probabilities', () {
    expect(ParkingForecast(dataset(singleClass: true)).probability, isNull);
    final source = dataset()..['samples'] = <List<num>>[];
    expect(ParkingForecast(source).predicted, isNull);
    expect(ParkingForecast(source).probability, isNull);
  });
  test('constant and collinear inputs remain numerically stable', () {
    final source = dataset();
    for (final r in source['samples'] as List<List<num>>) {
      r[0] = r[2] * 2;
      r[3] = 0;
    }
    source['live'] = [16, 8, 0, (source['live'] as List)[3]];
    final f = ParkingForecast(source);
    expect(f.predicted, closeTo(18, 1e-6));
    expect(f.testMetrics['mae'], lessThan(1e-6));
  });
  test('future labels do not change trained raw inference', () {
    final source = dataset();
    final before = ParkingForecast(source);
    final rows = source['samples'] as List<List<num>>;
    for (var i = 560; i < rows.length; i++) {
      rows[i][1] = 20;
    }
    final after = ParkingForecast(source);
    expect(after.rawPredicted, closeTo(before.rawPredicted!, 1e-9));
    expect(after.testMetrics['mae'], greaterThan(before.testMetrics['mae']!));
  });
  test('WIB day/hour features use calendar values at observation time', () {
    final t = DateTime.utc(2026, 10, 26, 17).millisecondsSinceEpoch / 1000;
    final x = ParkingForecast.features([1, 2, 3, 4, t]);
    expect(x[3], closeTo(0, 1e-9));
    expect(x[4], closeTo(1, 1e-9));
    expect(x[5], 1); // Tuesday 00:00 WIB
  });
}

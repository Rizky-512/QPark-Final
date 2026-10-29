import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/data/parking_forecast.dart';

ParkingForecast fit(List<List<num>> rows, {int current = 10}) =>
    ParkingForecast({
      'capacity': 20,
      'current': current,
      'target_time': 1800,
      'samples': rows,
    });

void main() {
  test('insufficient or constant history does not invent predictions', () {
    expect(fit([]).probability, isNull);
    final constant = fit(List.generate(60, (_) => [5, 5]));
    expect(constant.predicted, isNull);
    expect(constant.probability, isNull);
  });
  test('linear fit recovers a known relationship and bounds counts', () {
    final rows = List.generate(60, (i) => [i % 10, 2 * (i % 10) + 1]);
    expect(fit(rows, current: 4).predicted, closeTo(9, 1e-8));
    expect(fit(rows, current: 20).predicted, 20);
  });
  test('logistic learns higher risk, with inclusive 80 percent threshold', () {
    final rows = List.generate(100, (i) => [i % 20, i % 20 >= 10 ? 16 : 15]);
    final low = fit(rows, current: 0).probability!;
    final high = fit(rows, current: 19).probability!;
    expect(low, lessThan(.2));
    expect(high, greaterThan(.8));
    expect(high, lessThanOrEqualTo(1));
  });
  test('one-class history permits linear but not logistic prediction', () {
    final result = fit(List.generate(60, (i) => [i % 10, i % 10]));
    expect(result.predicted, isNotNull);
    expect(result.probability, isNull);
  });
}

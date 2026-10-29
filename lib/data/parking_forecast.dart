import 'dart:math' as math;

/// Supervised models: OLS for counts, logistic regression for the >=80% label.
/// All scaling and fitting use only the oldest 60%; later periods stay unseen.
class ParkingForecast {
  ParkingForecast(Map<String, dynamic> source) {
    capacity = (source['capacity'] as num).toInt();
    current = (source['current'] as num).toInt();
    targetTime = (source['target_time'] as num).toDouble();
    final rows = (source['samples'] as List).cast<List>();
    samples = rows.length;
    if (source['version'] != 2) {
      reason = 'Data model perlu diperbarui oleh pengelola.';
      return;
    }
    if (capacity <= 0 || samples < 80) return;
    final first = (rows.first[4] as num).toDouble();
    final span = (rows.last[4] as num).toDouble() - first;
    final valStart = first + span * .6, testStart = first + span * .8;
    final train = rows.where((r) => (r[4] as num) + 1800 < valStart).toList();
    final valid = rows
        .where(
          (r) => (r[4] as num) >= valStart && (r[4] as num) + 1800 < testStart,
        )
        .toList();
    final test = rows.where((r) => (r[4] as num) >= testStart).toList();
    trainCount = train.length;
    validationCount = valid.length;
    testCount = test.length;
    if (train.length < 48 || valid.length < 12 || test.length < 12) return;
    final x = train.map(features).toList();
    final y = train.map((r) => (r[1] as num).toDouble()).toList();
    if (y.toSet().length < 2) return;
    final means = List.generate(
      11,
      (j) => x.map((r) => r[j]).reduce((a, b) => a + b) / x.length,
    );
    final scales = List.generate(11, (j) {
      final variance =
          x.map((r) => math.pow(r[j] - means[j], 2)).reduce((a, b) => a + b) /
          x.length;
      return variance < 1e-12 ? 1.0 : math.sqrt(variance);
    });
    List<double> scaled(List<double> row) => [
      1,
      ...List.generate(11, (j) => (row[j] - means[j]) / scales[j]),
    ];
    final z = x.map(scaled).toList();
    final ols = _LeastSquares(z, y);
    final labels = y
        .map((v) => v >= (capacity * .8).ceil() ? 1.0 : 0.0)
        .toList();
    final positives = labels.where((v) => v == 1).length;
    final logisticReady = positives >= 10 && labels.length - positives >= 10;
    final weights = List<double>.filled(12, 0);
    final prevalence = positives / labels.length;
    if (logisticReady) {
      weights[0] = math.log(prevalence / (1 - prevalence));
      for (var step = 0; step < 800; step++) {
        final gradient = List<double>.filled(12, 0);
        for (var i = 0; i < z.length; i++) {
          final residual = sigmoid(dot(weights, z[i])) - labels[i];
          for (var j = 0; j < 12; j++) {
            gradient[j] += residual * z[i][j];
          }
        }
        for (var j = 0; j < 12; j++) {
          weights[j] -=
              .05 * (gradient[j] / z.length + (j == 0 ? 0 : .01 * weights[j]));
        }
      }
    }
    Map<String, double> evaluate(List<List> group) {
      double ae = 0,
          squared = 0,
          baseline = 0,
          brier = 0,
          baseBrier = 0,
          tp = 0,
          fp = 0,
          fn = 0,
          tn = 0;
      for (final r in group) {
        final row = scaled(features(r)), truth = (r[1] as num).toDouble();
        final error = ols.predict(row) - truth;
        ae += error.abs();
        squared += error * error;
        baseline += ((r[0] as num) - truth).abs();
        final label = truth >= (capacity * .8).ceil() ? 1.0 : 0.0;
        final probability = sigmoid(dot(weights, row));
        brier += math.pow(probability - label, 2);
        baseBrier += math.pow(prevalence - label, 2);
        if (probability >= .5) {
          if (label == 1) {
            tp++;
          } else {
            fp++;
          }
        } else {
          if (label == 1) {
            fn++;
          } else {
            tn++;
          }
        }
      }
      return {
        'mae': ae / group.length,
        'rmse': math.sqrt(squared / group.length),
        'baseline_mae': baseline / group.length,
        'brier': brier / group.length,
        'baseline_brier': baseBrier / group.length,
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'tn': tn,
        'precision': tp + fp == 0 ? 0 : tp / (tp + fp),
        'recall': tp + fn == 0 ? 0 : tp / (tp + fn),
      };
    }

    validationMetrics = evaluate(valid);
    testMetrics = evaluate(test);
    if (!logisticReady) {
      for (final m in [validationMetrics, testMetrics]) {
        m.removeWhere(
          (key, _) => !['mae', 'rmse', 'baseline_mae'].contains(key),
        );
      }
    }
    final live = (source['live'] as List);
    final liveX = scaled(features([live[0], 0, live[1], live[2], live[3]]));
    rawPredicted = ols.predict(liveX);
    final linearPass = [
      validationMetrics,
      testMetrics,
    ].every((m) => m['mae']! < m['baseline_mae']!);
    if (linearPass) predicted = rawPredicted!.clamp(0, capacity).toDouble();
    final logisticPass =
        logisticReady &&
        [
          validationMetrics,
          testMetrics,
        ].every((m) => m['brier']! < m['baseline_brier']!);
    if (logisticPass) probability = sigmoid(dot(weights, liveX));
    reason = predicted != null || probability != null
        ? 'Perkiraan dari pola riwayat parkir, bukan kepastian.'
        : 'Model belum cukup andal. Riwayat berikutnya akan membantu model belajar.';
    logisticReason = !logisticReady
        ? 'Contoh hampir penuh dan tidak penuh belum cukup.'
        : !logisticPass
        ? 'Model peluang belum lebih baik dari pembanding pada data validasi dan uji.'
        : null;
  }

  // N(t), arrivals, departures, cyclic WIB hour, Tue-Sun one-hot indicators.
  static List<double> features(List row) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      ((row[4] as num) * 1000).round(),
      isUtc: true,
    ).add(const Duration(hours: 7));
    final angle = 2 * math.pi * (t.hour + t.minute / 60) / 24;
    return [
      (row[0] as num).toDouble(),
      (row[2] as num).toDouble(),
      (row[3] as num).toDouble(),
      math.sin(angle),
      math.cos(angle),
      ...List.generate(6, (i) => t.weekday == i + 2 ? 1.0 : 0.0),
    ];
  }

  static double sigmoid(double z) => 1 / (1 + math.exp(-z.clamp(-30, 30)));
  static double dot(List<double> a, List<double> b) {
    double sum = 0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  late final int capacity, current, samples;
  late final double targetTime;
  int trainCount = 0, validationCount = 0, testCount = 0;
  double? predicted, rawPredicted, probability;
  String reason = 'Riwayat belum cukup untuk membuat perkiraan.';
  String? logisticReason = 'Riwayat belum cukup.';
  Map<String, double> validationMetrics = {}, testMetrics = {};
}

/// Rank-aware modified Gram-Schmidt OLS; constant/collinear columns are skipped.
class _LeastSquares {
  _LeastSquares(List<List<double>> rows, List<double> y) {
    final basis = <List<double>>[];
    for (var j = 0; j < rows.first.length; j++) {
      final column = rows.map((r) => r[j]).toList();
      final projections = <double>[];
      for (final q in basis) {
        final p = ParkingForecast.dot(q, column);
        projections.add(p);
        for (var i = 0; i < column.length; i++) {
          column[i] -= p * q[i];
        }
      }
      final norm = math.sqrt(ParkingForecast.dot(column, column));
      if (norm < 1e-7) continue;
      final q = column.map((v) => v / norm).toList();
      basis.add(q);
      indices.add(j);
      norms.add(norm);
      transforms.add(projections);
      coefficients.add(ParkingForecast.dot(q, y));
    }
  }
  final indices = <int>[];
  final norms = <double>[], coefficients = <double>[];
  final transforms = <List<double>>[];
  double predict(List<double> row) {
    final q = <double>[];
    for (var j = 0; j < indices.length; j++) {
      double value = row[indices[j]];
      for (var k = 0; k < j; k++) {
        value -= transforms[j][k] * q[k];
      }
      q.add(value / norms[j]);
    }
    return ParkingForecast.dot(coefficients, q);
  }
}

import 'dart:math' as math;

/// Paired observations N(t), N(t+30m), ordered chronologically by the server.
/// Fit only on completed pairs. The selected report dates never affect training.
class ParkingForecast {
  ParkingForecast(Map<String, dynamic> source) {
    capacity = (source['capacity'] as num).toInt();
    current = (source['current'] as num).toInt();
    targetTime = (source['target_time'] as num).toDouble();
    final rows = (source['samples'] as List).cast<List>();
    samples = rows.length;
    if (capacity <= 0 || samples < 48) return;
    final xs = rows.map((r) => (r[0] as num).toDouble()).toList();
    final ys = rows.map((r) => (r[1] as num).toDouble()).toList();
    final mx = xs.reduce((a, b) => a + b) / samples;
    final my = ys.reduce((a, b) => a + b) / samples;
    double variance = 0, covariance = 0;
    for (var i = 0; i < samples; i++) {
      variance += math.pow(xs[i] - mx, 2);
      covariance += (xs[i] - mx) * (ys[i] - my);
    }
    if (variance < 1e-9) return;
    final slope = covariance / variance;
    predicted = (my + slope * (current - mx)).clamp(0, capacity).toDouble();
    final labels = ys
        .map((y) => y >= (capacity * .8).ceil() ? 1.0 : 0.0)
        .toList();
    final positive = labels.where((y) => y == 1).length;
    if (positive < 10 || samples - positive < 10) return;
    final scale = math.sqrt(variance / samples);
    double intercept = math.log(positive / (samples - positive)), weight = 0;
    // Standardized one-feature logistic regression, L2 penalty on slope only.
    for (var step = 0; step < 600; step++) {
      double gi = 0, gw = 0;
      for (var i = 0; i < samples; i++) {
        final x = (xs[i] - mx) / scale;
        final residual = sigmoid(intercept + weight * x) - labels[i];
        gi += residual;
        gw += residual * x;
      }
      intercept -= .1 * gi / samples;
      weight -= .1 * (gw / samples + .01 * weight);
    }
    probability = sigmoid(intercept + weight * (current - mx) / scale);
  }

  static double sigmoid(double z) => 1 / (1 + math.exp(-z.clamp(-30, 30)));
  late final int capacity, current, samples;
  late final double targetTime;
  double? predicted, probability;
}

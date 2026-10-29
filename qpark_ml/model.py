"""Offline OLS training and portable JSON inference; no pickle loading."""
import math
import platform
from .data import FEATURES, HORIZON, iso, timestamp


def metrics(truth, predicted):
    if not truth:
        return dict(n=0, mae=None, rmse=None, r2=None)
    residuals = [a-b for a, b in zip(truth, predicted)]
    mse = sum(e*e for e in residuals)/len(truth)
    mean = sum(truth)/len(truth)
    total = sum((v-mean)**2 for v in truth)
    return dict(n=len(truth), mae=sum(abs(e) for e in residuals)/len(truth),
                rmse=math.sqrt(mse), r2=1-sum(e*e for e in residuals)/total
                if len(truth) > 1 and total > 0 else None)


def split(rows):
    if len(rows) < 5:
        return [], [], [], None, None
    first, last = rows[0]['observed_at'], rows[-1]['observed_at']
    validation_start = first + .6*(last-first)
    test_start = first + .8*(last-first)
    train = [r for r in rows if r['target_at'] < validation_start]
    validation = [r for r in rows if r['observed_at'] >= validation_start and r['target_at'] < test_start]
    test = [r for r in rows if r['observed_at'] >= test_start]
    return train, validation, test, validation_start, test_start


def raw_predict(model, x):
    return model['intercept'] + sum(c*v for c, v in zip(model['coefficients'], x))


def train(history, until=None):
    rows, rejected = history.dataset()
    if until is not None:
        cutoff = timestamp(until)
        rows = [r for r in rows if r['target_at'] <= cutoff]
    train_rows, validation, test, val_start, test_start = split(rows)
    report = dict(status='insufficient_data', source_kind=history.kind,
                  sessions=len(history.entered), samples=len(rows), rejected_windows=rejected,
                  period=[iso(rows[0]['observed_at']), iso(rows[-1]['target_at'])] if rows else None,
                  split_counts=dict(train=len(train_rows), validation=len(validation), test=len(test)),
                  metrics=None)
    # Engineering guard, not a scientific sufficiency claim; 4-8 weeks recommended.
    if (not history.entered or len(train_rows) < 48 or len(validation) < 12 or len(test) < 12
            or len({r['y'] for r in train_rows}) < 2):
        report['reason'] = 'Perlu riwayat sesi, variasi target, >=48 latih dan >=12 validasi/uji.'
        return report, None
    import numpy as np
    import scipy
    import sklearn
    from sklearn.linear_model import LinearRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    pipeline = make_pipeline(StandardScaler(), LinearRegression())
    pipeline.fit([r['x'] for r in train_rows], [r['y'] for r in train_rows])
    scaler, linear = pipeline.steps[0][1], pipeline.steps[1][1]
    coefficients = linear.coef_/scaler.scale_
    model = dict(version=1, features=FEATURES, horizon_seconds=HORIZON, capacity=20,
                 source_kind=history.kind, coefficients=coefficients.tolist(),
                 intercept=float(linear.intercept_ - np.dot(coefficients, scaler.mean_)),
                 trained_through=train_rows[-1]['target_at'],
                 evaluated_through=test[-1]['target_at'],
                 versions=dict(python=platform.python_version(), sklearn=sklearn.__version__,
                               numpy=np.__version__, scipy=scipy.__version__))
    scores = {}
    for name, group in [('validation', validation), ('test', test)]:
        def score(part):
            return dict(model=metrics([r['y'] for r in part], [raw_predict(model, r['x']) for r in part]),
                        persistence=metrics([r['y'] for r in part], [r['x'][0] for r in part]))
        scores[name] = dict(score(group),
                            period=[iso(group[0]['observed_at']), iso(group[-1]['target_at'])],
                            weekdays=score([r for r in group if not any(r['x'][-2:])]),
                            weekends=score([r for r in group if any(r['x'][-2:])]))
    improves = all(scores[g]['model']['mae'] < scores[g]['persistence']['mae'] for g in scores)
    model['baseline_passed'] = improves
    report.update(status='ok' if improves else 'insufficient_data',
                  reason='MAE lebih rendah dari persistence pada validasi dan uji.' if improves
                  else 'Model belum mengungguli persistence; hanya untuk eksperimen.',
                  metrics=scores, versions=model['versions'],
                  split_cutoffs=dict(validation=iso(val_start), test=iso(test_start)),
                  purged_samples=len(rows)-len(train_rows)-len(validation)-len(test),
                  train_period=[iso(train_rows[0]['observed_at']), iso(train_rows[-1]['target_at'])])
    return report, model


def validate_model(model):
    if not isinstance(model, dict):
        raise ValueError('Model harus objek JSON.')
    if (model.get('version') != 1 or model.get('features') != FEATURES
            or model.get('horizon_seconds') != HORIZON or model.get('capacity') != 20
            or model.get('source_kind') not in ('simulation', 'operational')
            or type(model.get('baseline_passed')) is not bool):
        raise ValueError('Kontrak model tidak sesuai.')
    values = model.get('coefficients', [])
    if not isinstance(values, list) or len(values) != len(FEATURES):
        raise ValueError('Koefisien tidak sesuai.')
    if any(type(v) not in (int, float) or not math.isfinite(v)
           for v in values + [model.get('intercept')]):
        raise ValueError('Model tidak finite.')
    if timestamp(model['trained_through']) > timestamp(model['evaluated_through']):
        raise ValueError('Periode model tidak valid.')


def predict(model, history, as_of):
    validate_model(model)
    t = timestamp(as_of)
    if model['source_kind'] != history.kind:
        raise ValueError('Model simulasi dan data operasional tidak boleh dicampur.')
    if t <= timestamp(model['evaluated_through']):
        raise ValueError('Prediksi harus sesudah periode evaluasi model.')
    if not model['baseline_passed'] or not history.entered or not history.covered(t, future=False):
        return dict(status='insufficient_data', source_kind=history.kind)
    x = history.features(t)
    raw = raw_predict(model, x)
    if not math.isfinite(raw) or not 0 <= x[0] <= 20:
        raise ValueError('Prediksi/keterisian tidak valid.')
    return dict(status='ok', source_kind=history.kind, as_of=iso(t), target_at=iso(t+HORIZON),
                horizon_minutes=30, capacity=20, occupied_now=x[0],
                expected_occupied_raw=raw, expected_occupied_bounded=max(0, min(20, raw)))

"""Research tests use only in-memory fixtures or isolated temporary files."""
import copy
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from qpark_ml.data import FEATURES, History, read_sqlite, timestamp
from qpark_ml.model import metrics, predict, raw_predict, split, train, validate_model
from qpark_ml.simulation import generate, upload_sql
from qpark_ml.__main__ import read_json, write_new

NOW = timestamp('2026-10-29T00:00:00+07:00')


def source(sessions=None):
    return dict(source_kind='simulation', complete_history=True,
                coverage=[dict(start=0, end=200000, capacity=20)],
                capacity_changes=[], sessions=sessions or [])


class FeatureTest(unittest.TestCase):
    def test_exact_boundaries_and_carry_in(self):
        h = History(source([dict(id='a', entered_at=-300, exited_at=1800),
                            dict(id='b', entered_at=0, exited_at=None),
                            dict(id='c', entered_at=1800, exited_at=3600)]), NOW)
        self.assertEqual(h.features(1800)[:3], [2, 1, 1])
        self.assertEqual(h.occupied(3600), 1)
        self.assertEqual(h.dataset()[0][0]['y'], 1)

    def test_future_exit_does_not_leak_into_features(self):
        a = source([dict(id='a', entered_at=0, exited_at=4000)])
        b = copy.deepcopy(a)
        b['sessions'][0]['exited_at'] = 8000
        self.assertEqual(History(a, NOW).features(1800), History(b, NOW).features(1800))

    def test_calendar_uses_wib_and_monday_reference(self):
        h = History(source(), NOW)
        x = h.features(timestamp('2026-10-26T00:00:00+07:00'))
        self.assertAlmostEqual(x[3], 0)
        self.assertAlmostEqual(x[4], 1)
        self.assertEqual(x[5:], [0]*6)
        self.assertEqual(h.features(timestamp('2026-10-25T17:00:00Z')), x)

    def test_coverage_gaps_and_mature_labels(self):
        s = source()
        s['coverage'] = [dict(start=0, end=7200, capacity=20), dict(start=10000, end=16000, capacity=20)]
        rows, _ = History(s, NOW).dataset()
        self.assertTrue(all((r['observed_at']-1800 >= 0 and r['target_at'] <= 7200) or
                            (r['observed_at']-1800 >= 10000 and r['target_at'] <= 16000) for r in rows))
        s['coverage'][0]['end'] = NOW+1
        with self.assertRaises(ValueError):
            History(s, NOW)

    def test_capacity_change_and_return_excludes_crossing_window(self):
        s = source()
        s['capacity_changes'] = [dict(at=2000, capacity=10), dict(at=4000, capacity=20)]
        h = History(s, NOW)
        self.assertFalse(h.covered(2700))
        self.assertFalse(h.covered(4500))
        self.assertTrue(h.covered(6300))
        self.assertGreater(h.dataset()[1], 0)

    def test_invalid_events_fail_closed(self):
        for bad in [None, [], dict(source(), sessions=None), dict(source(), coverage=[None])]:
            with self.subTest(snapshot=bad), self.assertRaises(ValueError):
                History(bad, NOW)
        for event in [dict(id='a', entered_at=2, exited_at=1),
                      dict(id='a', entered_at=float('nan'), exited_at=None),
                      dict(id='a', entered_at=NOW+1, exited_at=None)]:
            with self.subTest(event=event), self.assertRaises(ValueError):
                History(source([event]), NOW)
        s = source([dict(id='a', entered_at=0, exited_at=None)]*2)
        with self.assertRaises(ValueError):
            History(s, NOW)
        with self.assertRaises(ValueError):
            timestamp('2026-01-01')

    def test_missing_coverage_is_not_zero_observation(self):
        s = source()
        s['coverage'] = []
        self.assertEqual(History(s, NOW).dataset(), ([], 0))
        s['complete_history'] = False
        with self.assertRaises(ValueError):
            History(s, NOW)

    def test_over_capacity_between_grid_points_rejected(self):
        s = source([dict(id=str(i), entered_at=10, exited_at=20) for i in range(21)])
        with self.assertRaises(ValueError):
            History(s, NOW)

    def test_extraction_read_only_and_no_pii(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'test.db'
            with closing(sqlite3.connect(path)) as db:
                db.executescript('CREATE TABLE sessions(id,entered_at,exited_at,plate);'
                                 'CREATE TABLE audit(server_time,event_type,result);'
                                 "INSERT INTO sessions VALUES('a',0,NULL,'PRIVATE');")
                db.commit()
            before = path.read_bytes()
            result = read_sqlite(path, source())
            self.assertEqual(path.read_bytes(), before)
            self.assertNotIn('PRIVATE', json.dumps(result))
            self.assertEqual(result['sessions'], [dict(id='a', entered_at=0, exited_at=None)])
            with self.assertRaises(sqlite3.OperationalError):
                read_sqlite(Path(tmp)/'absent.db', source())
            self.assertFalse((Path(tmp)/'absent.db').exists())

    def test_outputs_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'out.json'
            write_new(path, {'a': 1})
            with self.assertRaises(FileExistsError):
                write_new(path, {'a': 2})
            self.assertEqual(json.loads(path.read_text()), {'a': 1})
            invalid = Path(tmp)/'invalid.json'
            write_new(invalid, [])
            with self.assertRaises(ValueError):
                read_json(invalid)

    def test_simulator_reproducible_bounded_and_labelled(self):
        s = generate(days=7)
        self.assertEqual(s, generate(days=7))
        h = History(s, NOW)
        self.assertEqual(h.kind, 'simulation')
        self.assertTrue(all(0 <= r['y'] <= 20 for r in h.dataset()[0]))
        sql = upload_sql(s, "run'quoted")
        self.assertIn("'run''quoted'", sql)
        self.assertNotIn('public.qpark_parking_sessions', sql)
        self.assertIn('ON CONFLICT', sql)
        s['source_kind'] = 'operational'
        with self.assertRaises(ValueError):
            upload_sql(s, 'run')


class ModelTest(unittest.TestCase):
    def test_metrics_known_errors_and_undefined_r2(self):
        self.assertEqual(metrics([1, 3], [2, 2]), dict(n=2, mae=1, rmse=1, r2=0))
        self.assertIsNone(metrics([2, 2], [1, 3])['r2'])
        self.assertIsNone(metrics([2], [1])['r2'])
        self.assertIsNone(metrics([], [])['mae'])

    def test_empty_is_insufficient_without_ml_dependencies(self):
        report, model = train(History(source(), NOW))
        self.assertEqual(report['status'], 'insufficient_data')
        self.assertIsNone(report['metrics'])
        self.assertIsNone(model)

    def test_temporal_split_purges_labels_even_with_gaps(self):
        rows = History(generate(days=7), NOW).dataset()[0][::3]
        a, b, c, val, test = split(rows)
        self.assertLess(max(r['target_at'] for r in a), min(r['observed_at'] for r in b))
        self.assertLess(max(r['target_at'] for r in b), min(r['observed_at'] for r in c))

    @unittest.skipUnless(importlib.util.find_spec('sklearn'), 'Optional ML environment required')
    def test_training_evaluation_and_no_future_training_leakage(self):
        h = History(generate(days=14), NOW)
        report, model = train(h)
        self.assertIsNotNone(model)
        self.assertEqual(model['features'], FEATURES)
        validate_model(model)
        self.assertGreater(report['metrics']['test']['model']['n'], 0)
        rows, _ = h.dataset()
        a, _, _, _, test_start = split(rows)
        # Alter only final-test labels. Fitted coefficients must remain identical.
        altered = copy.deepcopy(rows)
        for r in altered:
            if r['observed_at'] >= test_start:
                r['y'] = 20-r['y']
        h.dataset = lambda: (altered, 0)
        _, changed_model = train(h)
        self.assertEqual(model['coefficients'], changed_model['coefficients'])
        self.assertEqual(model['intercept'], changed_model['intercept'])
        # Independent comparison against the fitted sklearn pipeline.
        from sklearn.pipeline import make_pipeline
        from sklearn.preprocessing import StandardScaler
        from sklearn.linear_model import LinearRegression
        p = make_pipeline(StandardScaler(), LinearRegression()).fit([r['x'] for r in a], [r['y'] for r in a])
        self.assertAlmostEqual(raw_predict(model, rows[-1]['x']), p.predict([rows[-1]['x']])[0], places=10)

    def test_prediction_gates_and_raw_versus_bounded(self):
        with self.assertRaises(ValueError):
            validate_model([])
        h = History(source([dict(id='a', entered_at=0, exited_at=None)]), NOW)
        model = dict(version=1, features=FEATURES, capacity=20, horizon_seconds=1800,
                     source_kind='simulation', coefficients=[0]*11, intercept=25,
                     trained_through=0, evaluated_through=1800, baseline_passed=True)
        result = predict(model, h, 3600)
        self.assertEqual((result['expected_occupied_raw'], result['expected_occupied_bounded']), (25, 20))
        with self.assertRaises(ValueError):
            predict(model, h, 1800)
        model['baseline_passed'] = False
        self.assertEqual(predict(model, h, 3600)['status'], 'insufficient_data')
        model['source_kind'] = 'operational'
        with self.assertRaises(ValueError):
            predict(model, h, 3600)
        model['intercept'] = float('inf')
        with self.assertRaises(ValueError):
            validate_model(model)

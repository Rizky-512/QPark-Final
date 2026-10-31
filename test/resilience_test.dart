import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_customer_sync_test.dart' show FakeAuth, MemoryCustomers;
import 'package:qpark/logic/customer_auth.dart';

class ControlledRepository extends RemoteRepository {
  ControlledRepository({Duration timeout = const Duration(seconds: 12)})
    : super('', requestTimeout: timeout);
  Future<Json> Function(String method, String path, Json? body)? handler;
  final calls = <String>[];
  @override
  Future<Json> performRequest(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    calls.add('$method $path');
    if (handler != null) return handler!(method, path, body);
    return {'server_time': 1000, 'session': null, 'sessions': <Json>[]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test(
    'concurrent synchronization is shared and old plate response is discarded',
    () async {
      final repository = ControlledRepository();
      final first = Completer<Json>();
      repository.handler = (_, path, _) async {
        if (path.contains('plate=A1')) return first.future;
        return {
          'server_time': 1000,
          'session': path.contains('plate=B2')
              ? {'plate': 'B2', 'id': 'b'}
              : null,
        };
      };
      final service = RemoteService(repository, prefs)..selected = 'A1';
      addTearDown(service.dispose);
      final a = service.sync(), b = service.sync();
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.where((c) => c.contains('/capacity')).length, 1);
      final changed = service.selectPlate('B2');
      first.complete({
        'session': {'plate': 'A1', 'id': 'a'},
      });
      await Future.wait([a, b, changed]);
      expect(service.ticket?['plate'], 'B2');
      expect(service.syncing, isFalse);
    },
  );

  testWidgets(
    'polling stops in background and resumes once with adaptive delay',
    (tester) async {
      final repository = ControlledRepository();
      final service = RemoteService(repository, prefs);
      service.start();
      await tester.pump();
      expect(repository.calls.length, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(repository.calls.length, 1);
      service.setForeground(false);
      await tester.pump(const Duration(minutes: 2));
      expect(repository.calls.length, 1);
      service.setForeground(true);
      await tester.pump();
      expect(repository.calls.length, 2);
      service.dispose();
    },
  );

  test(
    'failure backoff increases, success resets, timeout unlocks sync',
    () async {
      final repository = ControlledRepository(
        timeout: const Duration(milliseconds: 5),
      );
      repository.handler = (_, _, _) => Completer<Json>().future;
      final service = RemoteService(repository, prefs);
      addTearDown(service.dispose);
      await service.sync();
      expect(service.pollDelay.inSeconds, 5);
      await service.sync();
      expect(service.pollDelay.inSeconds, 10);
      expect(service.syncing, isFalse);
      expect(repository.metrics.timeouts, 2);
      repository.handler = null;
      await service.sync();
      expect(service.online, isTrue);
      expect(service.consecutiveFailures, 0);
      expect(service.pollDelay.inSeconds, 30);
    },
  );

  test('429 and timeout retain exact operation key across restart', () async {
    final keys = <String>[];
    final repository = ControlledRepository();
    repository.handler = (method, _, body) async {
      if (method == 'POST') {
        keys.add(body!['operation_key'] as String);
        throw const ApiError('Busy', 'rate_limit', 429);
      }
      return {};
    };
    final service = RemoteService(repository, prefs);
    await expectLater(
      service.post('/api/payment', {'invoice_id': 'i'}, idempotent: true),
      throwsA(isA<ApiError>()),
    );
    expect(service.pending.length, 1);
    service.dispose();
    final nextRepository = ControlledRepository();
    nextRepository.handler = (method, _, body) async {
      if (method == 'POST') keys.add(body!['operation_key'] as String);
      return {'server_time': 1000};
    };
    final restarted = RemoteService(nextRepository, prefs);
    addTearDown(restarted.dispose);
    await restarted.retryPending();
    expect(keys.length, 2);
    expect(keys.first, keys.last);
    expect(restarted.pending, isEmpty);
  });

  test(
    'pending transactions from account A are never sent as account B',
    () async {
      const a = CustomerIdentity(id: 'a', displayName: 'A');
      const b = CustomerIdentity(id: 'b', displayName: 'B');
      final auth = FakeAuth(a);
      final repository = ControlledRepository();
      repository.handler = (method, _, _) async {
        if (method == 'POST') throw const ApiError('lost', 'offline', 0);
        return {'server_time': 1000};
      };
      final service = RemoteService(
        repository,
        prefs,
        customerAuth: auth,
        customerData: MemoryCustomers(),
      );
      addTearDown(service.dispose);
      addTearDown(auth.changes.close);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        service.post('/api/payment', {
          'invoice_id': 'a-only',
        }, idempotent: true),
        throwsA(isA<ApiError>()),
      );
      auth.identity = b;
      auth.changes.add(b);
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isEmpty);
      final before = repository.calls.where((c) => c.startsWith('POST')).length;
      await service.retryPending();
      expect(
        repository.calls.where((c) => c.startsWith('POST')).length,
        before,
      );
      auth.identity = a;
      auth.changes.add(a);
      expect(service.pending.length, 1);
    },
  );

  test('rapid duplicate payment clicks send only one request', () async {
    final repository = ControlledRepository();
    final response = Completer<Json>();
    repository.handler = (method, _, _) async =>
        method == 'POST' ? response.future : <String, dynamic>{};
    final service = RemoteService(repository, prefs);
    addTearDown(service.dispose);
    final a = service.post('/api/payment', {
      'invoice_id': 'i',
    }, idempotent: true);
    final b = service.post('/api/payment', {
      'invoice_id': 'i',
    }, idempotent: true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.where((c) => c.startsWith('POST')).length, 1);
    response.complete({'outcome': 'SUCCESS'});
    await Future.wait([a, b]);
    expect(service.pending, isEmpty);
  });

  test(
    'malformed or old queues are not replayed into current account',
    () async {
      await prefs.setString(
        'qpark_pending_v4',
        jsonEncode([
          {'path': 99},
          null,
          'bad',
        ]),
      );
      final service = RemoteService(ControlledRepository(), prefs);
      addTearDown(service.dispose);
      expect(service.pending, isEmpty);
      await service.retryPending();
    },
  );
}

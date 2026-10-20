import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/domain/rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  test(
    'AT01/02 local CRUD persists, normalized duplicate rejected, no session mutation',
    () async {
      final mutations = <String>[];
      final client = MockClient((req) async {
        if (req.method == 'POST') mutations.add(req.url.path);
        return http.Response(
          jsonEncode(
            req.url.path.endsWith('capacity')
                ? {
                    'total': 20,
                    'occupied': 1,
                    'available': 19,
                    'full': false,
                    'server_time': 1000,
                  }
                : {'session': null, 'server_time': 1000},
          ),
          200,
        );
      });
      final service = RemoteService(
        RemoteRepository('http://test', client: client),
        prefs,
      );
      await service.savePlate('b 123 ab');
      expect(service.plates, ['B123AB']);
      await expectLater(service.savePlate('B123AB'), throwsException);
      await service.savePlate('b234ab', replacing: 'B123AB');
      expect(service.selected, 'B234AB');
      final reloaded = RemoteService(RemoteRepository('http://test'), prefs);
      expect(reloaded.plates, ['B234AB']);
      reloaded.dispose();
      await service.removePlate('B234AB');
      expect(service.plates, isEmpty);
      expect(mutations, isEmpty);
      service.dispose();
    },
  );
  test(
    'AT30 lost response retries exact operation key and reconciles',
    () async {
      final keys = <String>[];
      bool lose = true;
      final client = MockClient((req) async {
        if (req.url.path == '/api/payment') {
          keys.add((jsonDecode(req.body) as Json)['operation_key'] as String);
          if (lose) {
            lose = false;
            throw http.ClientException('response lost');
          }
          return http.Response(
            jsonEncode({'outcome': 'SUCCESS', 'server_time': 1000}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'total': 20,
            'occupied': 0,
            'available': 20,
            'full': false,
            'server_time': 1000,
          }),
          200,
        );
      });
      final service = RemoteService(
        RemoteRepository('http://test', client: client),
        prefs,
      );
      await expectLater(
        service.post('/api/payment', {
          'invoice_id': 'INV1',
          'outcome': 'SUCCESS',
        }, idempotent: true),
        throwsA(isA<ApiError>()),
      );
      expect(service.pending.length, 1);
      expect(service.online, isFalse);
      await service.retryPending();
      expect(keys.length, 2);
      expect(keys[0], keys[1]);
      expect(service.pending, isEmpty);
      service.dispose();
    },
  );
  test(
    'AT39 offline logout immediately locks UI, queues revocation, then revokes',
    () async {
      bool offline = true;
      int revocations = 0;
      final client = MockClient((req) async {
        if (offline) throw http.ClientException('offline');
        if (req.url.path == '/api/logout') revocations++;
        return http.Response(
          jsonEncode({
            'server_time': 1000,
            'available': 20,
            'occupied': 0,
            'total': 20,
            'full': false,
          }),
          200,
        );
      });
      final service =
          RemoteService(RemoteRepository('http://test', client: client), prefs)
            ..token = 'token-test'
            ..username = 'petugas';
      await service.logout();
      expect(service.officer, isFalse);
      expect(service.revoked, ['token-test']);
      offline = false;
      await service.sync();
      expect(revocations, 1);
      expect(service.revoked, isEmpty);
      service.dispose();
    },
  );
  test(
    'AT32 display clock anchored to server, not system wall clock',
    () async {
      final service = RemoteService(RemoteRepository('http://test'), prefs);
      service.observe({'server_time': 1000});
      expect(service.serverNow, closeTo(1000, 1));
      service.dispose();
    },
  );
  test(
    'customer demo logout and restart; Google inactive without network',
    () async {
      final calls = <String>[];
      final service = RemoteService(
        RemoteRepository(
          'http://test',
          client: MockClient((req) async {
            calls.add(req.url.path);
            return http.Response(
              jsonEncode({'server_time': 1000, 'session': null}),
              200,
            );
          }),
        ),
        prefs,
      );
      expect(service.signedIn, isFalse);
      expect(service.customerAuth.googleAvailable, isFalse);
      await expectLater(service.loginCustomerGoogle(), throwsException);
      expect(calls, isEmpty);
      expect(service.signedIn, isFalse);
      service.enterCustomerDemo();
      expect(service.signedIn, isTrue);
      await service.savePlate('B123');
      await service.logout();
      expect(service.signedIn, isFalse);
      expect(service.plates, ['B123']);
      service.enterCustomerDemo();
      final restarted = RemoteService(RemoteRepository('http://test'), prefs);
      expect(restarted.signedIn, isFalse);
      expect(restarted.plates, ['B123']);
      restarted.dispose();
      service.dispose();
    },
  );
  test('normalization does not guess ambiguous plate characters', () {
    expect(normalizePlate(' b 1 o0 '), 'B1O0');
    for (final value in ['', 'B-123', '車123']) {
      expect(() => normalizePlate(value), throwsException);
    }
  });
}

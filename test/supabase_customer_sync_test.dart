import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qpark/data/customer_repository.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/customer_auth.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth implements CustomerAuthProvider {
  FakeAuth(this.identity);

  CustomerIdentity? identity;
  final changes = StreamController<CustomerIdentity?>.broadcast(sync: true);

  @override
  Stream<CustomerIdentity?> get authStateChanges => changes.stream;
  @override
  CustomerIdentity? get currentIdentity => identity;
  @override
  bool get googleAvailable => true;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {
    identity = null;
    changes.add(null);
  }
}

class MemoryCustomers implements CustomerRepository {
  final values = <String, List<String>>{};

  @override
  Future<void> addVehicle(String userId, String plate) async {
    values.putIfAbsent(userId, () => []).add(plate);
  }

  @override
  Future<List<String>> listVehicles(String userId) async =>
      List<String>.from(values[userId] ?? []);

  @override
  Future<void> removeVehicle(String userId, String plate) async {
    values[userId]?.remove(plate);
  }

  @override
  Future<void> replaceVehicle(
    String userId,
    String oldPlate,
    String newPlate,
  ) async {
    final index = values[userId]!.indexOf(oldPlate);
    values[userId]![index] = newPlate;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Google account vehicles stay separate from local demo vehicles',
    () async {
      SharedPreferences.setMockInitialValues({
        'qpark_plates_v3': ['B111DEMO'],
        'qpark_selected_v3': 'B111DEMO',
      });
      final preferences = await SharedPreferences.getInstance();
      const identity = CustomerIdentity(id: 'user-a', displayName: 'Ayu');
      final auth = FakeAuth(identity);
      final customers = MemoryCustomers()..values['user-a'] = ['B222CLOUD'];
      final client = MockClient((request) async {
        final body = request.url.path.endsWith('/capacity')
            ? {
                'total': 20,
                'occupied': 0,
                'available': 20,
                'full': false,
                'server_time': 1000,
              }
            : {'session': null, 'server_time': 1000};
        return http.Response(jsonEncode(body), 200);
      });
      final service = RemoteService(
        RemoteRepository('http://test', client: client),
        preferences,
        customerAuth: auth,
        customerData: customers,
      );

      await Future<void>.delayed(Duration.zero);
      expect(service.customerIdentity?.id, 'user-a');
      expect(service.plates, ['B222CLOUD']);
      expect(service.selected, 'B222CLOUD');

      await service.savePlate('b 333 new');
      expect(customers.values['user-a'], ['B222CLOUD', 'B333NEW']);
      expect(preferences.getStringList('qpark_plates_v3'), ['B111DEMO']);

      await service.logout();
      expect(service.signedIn, isFalse);
      service.enterCustomerDemo();
      expect(service.plates, ['B111DEMO']);
      expect(service.selected, 'B111DEMO');

      service.dispose();
      await auth.changes.close();
    },
  );
}

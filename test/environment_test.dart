import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'test environment cannot inherit demo vehicles or device identity',
    () async {
      SharedPreferences.setMockInitialValues({
        'qpark_device_key_v1': 'a' * 48,
        'qpark_plates_v3': ['DEMO1'],
      });
      final prefs = await SharedPreferences.getInstance();
      final demo = RemoteService(RemoteRepository('http://demo'), prefs);
      final test = RemoteService(
        RemoteRepository('http://test'),
        prefs,
        storageNamespace: 'test.',
      );
      expect(demo.plates, ['DEMO1']);
      expect(test.plates, isEmpty);
      expect(test.repository.customerKey, isNot(demo.repository.customerKey));
      await test.preferences.setStringList('qpark_plates_v3', ['TEST1']);
      expect(prefs.getStringList('qpark_plates_v3'), ['DEMO1']);
      demo.dispose();
      test.dispose();
    },
  );
}

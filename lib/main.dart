import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'bootstrap.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    MobileScannerPlatform.instance.setWebBarcodeReader(
      WebBarcodeReader.zxingJs,
    );
    MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
      'vendor/zxing-0.23.0.min.js',
    );
  }
  runApp(QParkApp(initialize: bootstrap));
}

import 'package:flutter/material.dart';
import 'bootstrap.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(QParkApp(initialize: bootstrap));
}

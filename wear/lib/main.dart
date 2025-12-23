import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/log.dart';

void main() {
  log.i('App starting');
  WidgetsFlutterBinding.ensureInitialized();
  log.i('Flutter binding initialized');
  runApp(const BroWearApp());
}

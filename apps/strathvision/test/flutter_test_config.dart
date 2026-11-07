import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden candidates must use the bundled icon glyphs rather than square fallbacks.
/// Native applications load this asset automatically; widget tests do not.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  await testMain();
}

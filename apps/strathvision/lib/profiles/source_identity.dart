import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hash bytes rather than names. Stream large recordings without retaining them.
Future<String> sourceHash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

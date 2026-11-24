import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The iOS data container can move when an app is updated or restored. Keep
/// references to our own durable files relative to Application Support in the
/// database, and expose ordinary local paths to the rest of the app.
/// https://developer.apple.com/library/archive/technotes/tn2285/
class StoredPaths {
  StoredPaths({bool? onIOS, Future<Directory> Function()? supportDirectory})
    : _onIOS = onIOS ?? Platform.isIOS,
      _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const _scheme = 'strathvision-support';
  static const _uuid =
      r'[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}';
  final bool _onIOS;
  final Future<Directory> Function() _supportDirectory;
  Future<String>? _root;

  Future<String> _support() =>
      _root ??= _supportDirectory().then((directory) => directory.path);

  // iOS can report the same sandbox through /var or /private/var.
  String _normalized(String path) {
    final normalized = p.posix.normalize(path);
    return normalized.startsWith('/private/var/')
        ? normalized.substring('/private'.length)
        : normalized;
  }

  bool _owned(String relative) {
    final parts = p.posix.split(relative);
    return parts.length >= 2 &&
        (parts.first == 'profiles' || parts.first == 'imported_clips') &&
        parts.every(
          (part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              !part.contains('\\') &&
              !part.contains('\u0000'),
        ) &&
        !p.posix.isAbsolute(relative);
  }

  Future<String> encode(String path) async {
    if (!_onIOS || path.isEmpty) return path;
    final root = _normalized(await _support());
    final absolute = _normalized(path);
    if (!p.posix.isWithin(root, absolute)) return path;
    final relative = p.posix.relative(absolute, from: root);
    return _owned(relative)
        ? Uri(scheme: _scheme, path: '/$relative').toString()
        : path;
  }

  Future<String> decode(String path) async {
    if (!_onIOS || path.isEmpty) return path;
    final uri = Uri.tryParse(path);
    if (uri?.scheme == _scheme) {
      final decoded = Uri.decodeComponent(uri!.path);
      if (uri.hasAuthority ||
          uri.hasQuery ||
          uri.hasFragment ||
          !decoded.startsWith('/') ||
          !_owned(decoded.substring(1))) {
        throw const FormatException('Invalid stored app file reference');
      }
      return p.posix.join(await _support(), decoded.substring(1));
    }

    // Compatibility with releases that saved absolute paths. Only rebase the
    // known owned folders under the same iOS container hierarchy. Never guess
    // a path for an external file, temporary picker export or arbitrary suffix.
    final root = _normalized(await _support());
    final marker = RegExp(
      '/Containers/Data/Application/$_uuid/Library/Application Support\$',
    ).firstMatch(root);
    if (marker == null) return path;
    final prefix = root.substring(0, marker.start);
    final old = RegExp(
      '^${RegExp.escape(prefix)}/Containers/Data/Application/$_uuid/'
      'Library/Application Support/(.+)\$',
    ).firstMatch(_normalized(path));
    final relative = old?.group(1);
    return relative != null && _owned(relative)
        ? p.posix.join(await _support(), relative)
        : path;
  }
}

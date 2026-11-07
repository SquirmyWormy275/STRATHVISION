import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart' show PackDefinition;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';

import 'analysis/analysis_controller.dart';
import 'data/database.dart';
import 'design/sv_theme.dart';
import 'media/thumbnail_service.dart';
import 'screens/footage_library_screen.dart';
import 'packs/pack_registry.dart';
import 'profiles/inbox.dart';
import 'screens/carne_screen.dart';
import 'screens/library_screen.dart';
import 'screens/profile_builder_screen.dart';
import 'screens/workspace_route.dart';
import 'screens/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  LicenseRegistry.addLicense(() async* {
    for (final name in ['Barlow', 'SourceSans']) {
      yield LicenseEntryWithLineBreaks([
        'STRATHVISION UI fonts',
      ], await rootBundle.loadString('assets/fonts/OFL-$name.txt'));
    }
  });
  final packs = await loadPacks(rootBundle);
  final db = AppDatabase();
  runApp(StrathvisionApp(db: db, packs: packs));
  final inbox = await db.watchSetting(inboxFolderKey).first;
  if (inbox != null) {
    final support = await getApplicationSupportDirectory();
    await scanInbox(db, inbox, Directory(p.join(support.path, 'profiles')));
  }
}

class StrathvisionApp extends StatelessWidget {
  const StrathvisionApp({
    super.key,
    required this.db,
    this.pickPath = pickProfileFile,
    this.pickClip = pickClipFile,
    this.playerFactory = defaultStagePlayer,
    this.analysisRunner,
    this.packs = const [],
    this.pickClips,
    this.pickFiles,
    this.saveFile,
    this.profileStore,
    this.thumbnails,
    this.sourceSignature = presentationSignature,
  });
  final Future<Directory> Function()? profileStore;
  final AppDatabase db;
  final ThumbnailService? thumbnails;
  final Future<String?> Function(String path) sourceSignature;
  final ProfilePathPicker pickPath;
  final ClipPathPicker pickClip;
  final StagePlayerFactory playerFactory;
  final AnalysisRunner? analysisRunner;
  final List<PackDefinition> packs;
  final ClipsPicker? pickClips;
  final AnyFilesPicker? pickFiles;
  final Future<String?> Function(String fileName, List<int> bytes)? saveFile;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'STRATHVISION',
    debugShowCheckedModeBanner: false,
    theme: SvTheme.light(),
    darkTheme: SvTheme.dark(),
    home: FootageLibraryScreen(
      db: db,
      packs: packs,
      pickClip: pickClip,
      playerFactory: playerFactory,
      analysisRunner: analysisRunner,
      thumbnails: thumbnails,
      sourceSignature: sourceSignature,
      toolsBuilder: (_) => LibraryScreen(
        db: db,
        profileStore: profileStore,
        pickPath: pickPath,
        pickClip: pickClip,
        playerFactory: playerFactory,
        analysisRunner: analysisRunner,
        packs: packs,
        pickClips: pickClips ?? pickReferenceClips,
        pickFiles: pickFiles ?? pickAnyFiles,
        saveFile: saveFile ?? savePackageCopy,
      ),
    ),
  );
}

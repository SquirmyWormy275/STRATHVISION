import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart' show PackDefinition;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';

import 'analysis/analysis_controller.dart';
import 'data/database.dart';
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
  final packs = await loadPacks(rootBundle);
  final db = AppDatabase();
  runApp(StrathvisionApp(db: db, packs: packs));
  // Packages dropped into the shared inbox folder since last time.
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
  });

  final AppDatabase db;
  final ProfilePathPicker pickPath;
  final ClipPathPicker pickClip;
  final StagePlayerFactory playerFactory;
  final AnalysisRunner? analysisRunner;
  final List<PackDefinition> packs;

  /// Test hooks for the platform file dialogs (null = real dialogs).
  final ClipsPicker? pickClips;
  final AnyFilesPicker? pickFiles;
  final Future<String?> Function(String fileName, List<int> bytes)? saveFile;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B6E5A), brightness: b),
        );
    return MaterialApp(
      title: 'STRATHVISION',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: LibraryScreen(
        db: db,
        pickPath: pickPath,
        pickClip: pickClip,
        playerFactory: playerFactory,
        analysisRunner: analysisRunner,
        packs: packs,
        pickClips: pickClips ?? pickReferenceClips,
        pickFiles: pickFiles ?? pickAnyFiles,
        saveFile: saveFile ?? savePackageCopy,
      ),
    );
  }
}

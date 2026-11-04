import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'analysis/analysis_controller.dart';
import 'data/database.dart';
import 'screens/library_screen.dart';
import 'screens/workspace_route.dart';
import 'screens/workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(StrathvisionApp(db: AppDatabase()));
}

class StrathvisionApp extends StatelessWidget {
  const StrathvisionApp({
    super.key,
    required this.db,
    this.pickPath = pickProfileFile,
    this.pickClip = pickClipFile,
    this.playerFactory = defaultStagePlayer,
    this.analysisRunner,
  });

  final AppDatabase db;
  final ProfilePathPicker pickPath;
  final ClipPathPicker pickClip;
  final StagePlayerFactory playerFactory;
  final AnalysisRunner? analysisRunner;

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
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(StrathvisionApp(db: AppDatabase()));
}

class StrathvisionApp extends StatelessWidget {
  const StrathvisionApp({
    super.key,
    required this.db,
    this.pickPath = pickProfileFile,
  });

  final AppDatabase db;
  final ProfilePathPicker pickPath;

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
      home: LibraryScreen(db: db, pickPath: pickPath),
    );
  }
}

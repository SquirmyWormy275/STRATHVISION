"""One-time guarded integration edits for the isolated footage-first UI branch."""
from pathlib import Path
ROOT = Path('apps/strathvision')

def change(name, old, new, count=None):
    path = ROOT / name
    text = path.read_text()
    found = text.count(old)
    if not found:
        if new in text:
            return
        raise RuntimeError(f'Expected fragment absent: {name}: {old[:70]!r}')
    if count is not None and found != count:
        raise RuntimeError(f'Unexpected match count in {name}: {found} != {count}')
    path.write_text(text.replace(old, new))

change('lib/screens/footage_library_screen.dart', "import '../workspace/project.dart';", "import '../workspace/project.dart' show Project;", 1)
change('lib/screens/footage_library_screen.dart', 'cacheExtent: 120,', '', 1)
change('lib/workspace/review_presentation.dart', "import 'dart:convert';", "import 'dart:convert';\nimport 'package:drift/drift.dart';", 1)
change('lib/workspace/workspace_controller.dart', '}) : _project = project,', '}) : _project = project, // ignore: prefer_initializing_formals', 1)
change('lib/media/thumbnail_service.dart', 'return bytes == null ? null : bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);', 'if (bytes == null) { return null; }\n    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);', 1)

# Existing package/builder/workbench tools stay available one level down.
change('lib/screens/library_screen.dart', '          pack: pack,\n          pickClip:', '          pack: pack,\n          availablePacks: packs,\n          pickClip:', 1)
change('lib/screens/library_screen.dart', "title: const Text('Library'),", "title: const Text('Profiles & tools'),", 1)
change('lib/screens/analysis_panel.dart', "Text('Compare with', style: muted)", "Text('Profile', style: muted)", 1)
change('lib/screens/analysis_panel.dart', "child: Text('Nobody')", "child: Text('Measurements only')", 1)
change('lib/screens/analysis_panel.dart', '          if (error != null)\n', "          if (analysis.missingProfileKey != null) Text('Saved profile ${analysis.missingProfileKey} is unavailable. Choose another explicitly; video review still works.', style: muted),\n          if (error != null)\n", 1)
change('lib/screens/analysis_panel.dart', 'style: theme.textTheme.displaySmall?.copyWith(', 'style: theme.textTheme.titleLarge?.copyWith(', 1)
change('test/comparison_test.dart', "find.text('Nobody')", "find.text('Measurements only')")

# Preserve baseline assertions while changing only navigation and explicit context.
for name in ['test/workspace_screen_test.dart', 'test/analysis_test.dart']:
    if name.endswith('workspace_screen_test.dart'):
        change(name, "import 'package:strathvision/main.dart';", "import 'package:strathvision/main.dart';\nimport 'package:strathvision/packs/placeholder_pack.dart';", 1)
    change(name, '    await tester.pumpWidget(StrathvisionApp(\n      db: db,', "    await tester.runAsync(() => db.setSetting(AppDatabase.activeEventKey, placeholderPack.key));\n    await tester.pumpWidget(StrathvisionApp(\n      db: db,\n      packs: [placeholderDefinition],\n      sourceSignature: (path) async => 'test:$path',", 1)

name = 'test/workspace_screen_test.dart'
change(name, "    await pumpApp(tester);\n    await tap(tester, 'open-workspace');\n    final a = players[0], b = players[1];\n\n    // Load both", "    await pumpApp(tester);\n    clipQueue.add('/clips/coach.mp4');\n    await tap(tester, 'open-workspace');\n    final a = players[0], b = players[1];\n\n    // Load both", 1)
change(name, "    clipQueue.addAll(['/clips/coach.mp4', '/clips/athlete.mp4']);\n    await tap(tester, 'load-A');", "    clipQueue.add('/clips/athlete.mp4');", 1)
change(name, "    await tap(tester, 'open-workspace');\n    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);\n    await tap(tester, 'load-A');", "    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);\n    await tap(tester, 'open-workspace');", 1)
change(name, "    await tap(tester, 'open-workspace');\n    final a = players[0], b = players[1];\n    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);\n    await tap(tester, 'load-A');", "    clipQueue.addAll(['/clips/one.mp4', '/clips/two.mp4']);\n    await tap(tester, 'open-workspace');\n    final a = players[0], b = players[1];", 1)
change(name, "    await tap(tester, 'open-workspace');\n    clipQueue.add('/clips/one.mp4');\n    await tap(tester, 'load-A');", "    clipQueue.add('/clips/one.mp4');\n    await tap(tester, 'open-workspace');", 1)
change(name, "find.text('Not synced')", "find.text('Not linked')")
change(name, 'Locked · B', 'Linked · B')
change(name, "find.text('coach'), findsOneWidget", "find.textContaining('coach'), findsWidgets", 1)
change(name, "find.text('athlete'), findsOneWidget", "find.textContaining('athlete'), findsWidgets", 1)

name = 'test/analysis_test.dart'
change(name, "    await tester.pumpAndSettle();\n    await tester.tap(find.byKey(const Key('open-workspace')));\n    await tester.pumpAndSettle();", "    await tester.pumpAndSettle();", 1)
change(name, "await tap(tester, 'load-A');", "await tap(tester, 'open-workspace');", 4)
change(name, 'narrow layout puts the panel under the video', 'narrow details close back to the same video', 1)
change(name, '    expect(panel.top, greaterThan(stage.top));', "    expect(panel.overlaps(stage), isTrue);\n    await tap(tester, 'analysis-close');\n    expect(find.byKey(const Key('stage-A')), findsOneWidget);", 1)

name = 'test/widget_test.dart'
change(name, 'WidgetTester tester, {String? path})', 'WidgetTester tester, {String? path, String? clip})', 1)
change(name, '      db: db,', "      db: db,\n      pickClip: () async => clip,\n      sourceSignature: (path) async => 'test:$path',", 1)
change(name, "    await pumpApp(tester);\n    expect(find.text('Library'), findsOneWidget);", "    await pumpApp(tester, clip: '/clips/session.mp4');\n    expect(find.text('Your footage'), findsOneWidget);", 1)
change(name, "find.textContaining('Review ')", "find.text('session')", 1)
change(name, "expect(find.byKey(const Key('stage-B')), findsOneWidget);", "expect(find.byKey(const Key('stage-B')), findsNothing);", 1)
change(name, "    expect(find.text('Library'), findsOneWidget);\n    expect(find.text('Reviews'), findsOneWidget);", "    expect(find.text('Your footage'), findsOneWidget);\n    expect(find.byType(Scrollable), findsWidgets);", 1)
change(name, '    await pumpApp(tester, path: path);', "    await pumpApp(tester, path: path);\n    await tester.tap(find.byKey(const Key('library-tools')));\n    await tester.pumpAndSettle();", 1)
change(name, '    await pumpApp(tester, path: bad.path);', "    await pumpApp(tester, path: bad.path);\n    await tester.tap(find.byKey(const Key('library-tools')));\n    await tester.pumpAndSettle();", 1)

name = 'test/packs_test.dart'
change(name, '      db: db,', "      db: db,\n      sourceSignature: (path) async => 'test:$path',", 1)
change(name, "    await tester.pumpAndSettle();\n    expect(find.text('Underhand'), findsOneWidget);", "    await tester.pumpAndSettle();\n    expect(find.text('Just video'), findsOneWidget);\n    await tester.tap(find.byKey(const Key('event-picker')));\n    await tester.pumpAndSettle();\n    await tester.tap(find.byKey(const Key('event-timber/underhand')));\n    await tester.pumpAndSettle();\n    expect(find.text('Underhand'), findsOneWidget);", 1)
change(name, "    await tester.tap(find.byKey(const Key('load-A')));\n    await tester.pumpAndSettle();\n", '', 1)
change(name, "    expect(saved, 'timber/standing_block');", "    expect(saved, 'timber/standing_block');\n    final project = (await tester.runAsync(() => db.select(db.projectRows).get()))!.single;\n    await tester.tap(find.byKey(Key('project-${project.projectId}')));\n    await tester.pumpAndSettle();\n    expect(find.text('Underhand'), findsOneWidget);\n    expect(find.byKey(const Key('attr-Slope')), findsOneWidget);", 1)

name = 'integration_test/app_e2e_test.dart'
change(name, "    await idle(tester, 1500);\n    expect(find.text('Underhand'), findsOneWidget);", "    await idle(tester, 1500);\n    await tap('event-picker');\n    await tap('event-timber/underhand');\n    expect(find.text('Underhand'), findsOneWidget);", 1)
change(name, "    await tap('open-workspace', after: 1000);\n    clipQueue.addAll(['$clipDir/clip30.mp4', '$clipDir/clip25.mp4']);\n    await tap('load-A', after: 3000);", "    clipQueue.addAll(['$clipDir/clip30.mp4', '$clipDir/clip25.mp4']);\n    await tap('open-workspace', after: 3000);", 1)
change(name, "    await tap('open-workspace', after: 1000);\n    clipQueue.add('$clipDir/cleave.webm');\n    await tap('load-A', after: 2000);", "    clipQueue.add('$clipDir/cleave.webm');\n    await tap('open-workspace', after: 2000);", 1)
change(name, "    await wait(tester, find.textContaining('Review '));\n    await tester.tap(find.textContaining('Review ').last);", "    final reviews = await tester.runAsync(() => db.select(db.projectRows).get());\n    final firstReview = reviews!.firstWhere((r) => r.name == 'clip30');\n    await tester.tap(find.byKey(Key('project-${firstReview.projectId}')));", 1)
change(name, "    await tap('build-profile', after: 800);", "    await tap('library-tools');\n    await tap('build-profile', after: 800);", 1)
change(name, "    await tap('open-workspace', after: 1000);\n    clipQueue.add('$clipDir/cleave.webm');\n    await tap('load-A', after: 1500);", "    await back();\n    clipQueue.add('$clipDir/cleave.webm');\n    await tap('open-workspace', after: 2000);", 1)
change(name, '    // ---- Trend, export', "    await tap('library-tools');\n\n    // ---- Trend, export", 1)
change(name, 'Not synced', 'Not linked')
change(name, 'Locked ·', 'Linked ·')
print('Applied guarded integration changes; baseline behavioral assertions retained.')

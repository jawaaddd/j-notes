// Renders each designed screen at the Figma frame size (1440×900) from API
// responses captured off the mock backend (test/fixtures), with the clock
// pinned to when they were captured. Compare test/goldens/*.png against the
// Figma frames; regenerate with:
//
//   flutter test test/screens_test.dart --update-goldens
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_app/api/client.dart';
import 'package:notes_app/state/data.dart';
import 'package:notes_app/state/session.dart';
import 'package:notes_app/state/ui.dart';
import 'package:notes_app/theme/tokens.dart';
import 'package:notes_app/ui/calendar/calendar_view.dart';
import 'package:notes_app/ui/shell/shell.dart';
import 'package:notes_app/util/dates.dart';
import 'package:shared_preferences/shared_preferences.dart';

final capturedAt = DateTime.parse(File('test/fixtures/captured-at.txt').readAsStringSync().trim()).toLocal();

/// Serves the captured fixtures by path.
/// Notes the app saved, as sent: one blocks list per PUT.
final savedNotes = <List<dynamic>>[];

final fixtureClient = MockClient((req) async {
  if (req.method == 'PUT' && req.url.path.endsWith('/notes')) {
    savedNotes.add((jsonDecode(req.body) as Map<String, dynamic>)['blocks'] as List<dynamic>);
    return http.Response(jsonEncode({'updatedAt': '2026-10-06T12:00:00Z'}), 200, headers: {'content-type': 'application/json'});
  }
  final name = switch (req.url.path) {
    '/api/boards' => 'boards',
    final p when RegExp(r'^/api/boards/(\d+)$').hasMatch(p) => 'board-${p.split('/').last}',
    final p when RegExp(r'^/api/boards/(\d+)/cards$').hasMatch(p) => 'cards-${p.split('/')[3]}',
    final p when p.startsWith('/api/cards/') => 'card-${p.split('/').last}',
    '/api/inbox' => 'inbox',
    '/api/sources' => 'sources',
    '/api/tokens' => 'tokens',
    _ => null,
  };
  final file = File('test/fixtures/$name.json');
  if (name == null || !file.existsSync()) {
    return http.Response(
      jsonEncode({
        'error': {'code': 'NOT_FOUND', 'message': 'no fixture for ${req.url.path}', 'details': {}},
      }),
      404,
    );
  }
  return http.Response.bytes(file.readAsBytesSync(), 200, headers: {'content-type': 'application/json'});
});

class _ReadySession extends SessionNotifier {
  @override
  SessionState build() => SessionState(
    phase: SessionPhase.ready,
    serverUrl: 'http://localhost:8080',
    api: ApiClient(Uri.parse('http://localhost:8080'), token: 'test', httpClient: fixtureClient),
  );
}

class _FixedNow extends NowNotifier {
  @override
  DateTime build() => capturedAt;
}

class _FixedCalendar extends CalendarNotifier {
  @override
  CalendarState build() => CalendarState(dateOnly(capturedAt), false);
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await family('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf']);
  await family('GeistMono', ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf', 'GeistMono-SemiBold.ttf']);
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/dev/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

/// Pumps the signed-in shell, runs [setup], and writes the golden.
Future<void> shoot(WidgetTester tester, String name, Future<void> Function(WidgetTester t, ProviderContainer c) setup) async {
  final container = await pumpShell(tester);
  await setup(tester, container);
  await settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox()); // dispose the shell and its timers
}

/// Pumps a few frames: enough for fixtures to load and fades to finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps the signed-in shell at the frame size and waits for it to load.
Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sessionProvider.overrideWith(_ReadySession.new),
        nowProvider.overrideWith(_FixedNow.new),
        calendarProvider.overrideWith(_FixedCalendar.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Scaffold(body: Shell()),
      ),
    ),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(Shell)));
}

void main() {
  setUpAll(_loadFonts);
  // The selected board is remembered in preferences; start each screen fresh.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('board', (t) => shoot(t, 'board', (t, c) async {}));

  testWidgets(
    'board filtered',
    (t) => shoot(t, 'board-filtered', (t, c) async {
      c.read(boardFilterProvider.notifier).toggleTag(21); // Urgent
      await t.pump();
      await t.tap(find.text('Filter'));
    }),
  );

  testWidgets(
    'personal, switcher open',
    (t) => shoot(t, 'personal-switcher', (t, c) async {
      c.read(selectedBoardIdProvider.notifier).select(2);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.tap(find.text('Personal').first);
    }),
  );

  testWidgets('dragging a card', (t) async {
    TestGesture? gesture;
    await shoot(t, 'dragging', (t, c) async {
      // Pick up Policy memo and hold it over In Progress, above Lab 3.
      gesture = await t.startGesture(t.getCenter(find.text('Policy memo (2 pages)')));
      await gesture!.moveBy(const Offset(0, -20));
      await t.pump();
      await gesture!.moveTo(t.getTopLeft(find.text('Lab 3: A* path planner')) + const Offset(40, -10));
      await t.pump();
    });
    await gesture?.up();
  });

  testWidgets('inbox', (t) => shoot(t, 'inbox', (t, c) async => c.read(viewProvider.notifier).show(AppView.inbox)));

  testWidgets('card modal', (t) => shoot(t, 'modal', (t, c) async => c.read(openCardProvider.notifier).open(105)));

  testWidgets('calendar', (t) => shoot(t, 'calendar', (t, c) async => c.read(viewProvider.notifier).show(AppView.calendar)));

  testWidgets('manage boards', (t) => shoot(t, 'manage', (t, c) async => c.read(viewProvider.notifier).show(AppView.manage)));

  group('notes', () {
    Future<ProviderContainer> openCard(WidgetTester t) async {
      final c = await pumpShell(t);
      c.read(openCardProvider.notifier).open(105);
      await settle(t);
      return c;
    }

    Finder field(Finder of) => find.ancestor(of: of, matching: find.byType(TextField));

    /// Types [text] into the focused field, cursor at the end.
    Future<void> type(WidgetTester t, Finder f, String text) async {
      await t.enterText(f, text);
      await t.pump();
    }

    testWidgets('a todo can be renamed', (t) async {
      await openCard(t);
      final todo = find.text('Implement the priority queue');
      await t.tap(todo);
      await t.pump();
      final field = t.widget<TextField>(find.ancestor(of: todo, matching: find.byType(TextField)));
      expect(field.focusNode!.hasFocus, isTrue, reason: 'clicking a todo should focus it');
      await t.enterText(find.ancestor(of: todo, matching: find.byType(TextField)), 'Implement the heap');
      await t.pump();
      expect(find.text('Implement the heap'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('edits save on their own, without closing the card', (t) async {
      savedNotes.clear();
      await openCard(t);
      final todo = find.text('Implement the priority queue');
      await t.enterText(field(todo), 'Implement the heap');
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(savedNotes, hasLength(1));
      expect(savedNotes.last.map((b) => b['text']), contains('Implement the heap'));
      expect(find.textContaining('Saved automatically'), findsOneWidget);
      // Nothing changed since, so closing doesn't save again.
      await t.pumpWidget(const SizedBox());
      expect(savedNotes, hasLength(1));
    });

    testWidgets('a todo list can be named', (t) async {
      savedNotes.clear();
      await openCard(t);
      final header = find.byWidgetPredicate(
        (w) => w is TextField && w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('todo-list-name-'),
      );
      expect(header, findsOneWidget);
      await t.enterText(header, 'Milestones');
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      final firstTodo = savedNotes.last.firstWhere((b) => b['type'] == 'todo') as Map<String, dynamic>;
      expect(firstTodo['title'], 'Milestones');
      expect(find.text('Milestones'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    /// Focuses the block showing [text] with the cursor at [offset].
    Future<void> cursorIn(WidgetTester t, String text, int offset) async {
      final f = field(find.text(text));
      await t.tap(f);
      await t.pump();
      t.widget<TextField>(f).controller!.selection = TextSelection.collapsed(offset: offset);
      await t.pump();
    }

    TextField focused(WidgetTester t) => t.widgetList<TextField>(find.byType(TextField)).where((f) => f.focusNode?.hasFocus == true).single;

    Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
      await t.sendKeyEvent(key);
      await settle(t);
    }

    testWidgets('Backspace on an empty todo turns it into a text line', (t) async {
      savedNotes.clear();
      await openCard(t);
      await cursorIn(t, 'Test cases for fully blocked grids', 0);
      await t.enterText(field(find.text('Test cases for fully blocked grids')), '');
      await t.pump();
      await press(t, LogicalKeyboardKey.backspace);
      expect(find.text('2/3'), findsOneWidget);
      expect(focused(t).maxLines, isNull, reason: 'the line is text now');
      t.testTextInput.enterText('Plain words');
      await t.pump(const Duration(seconds: 1));
      expect(savedNotes.last.firstWhere((b) => b['text'] == 'Plain words')['type'], 'text');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Backspace at the start of a todo joins it to the text above', (t) async {
      await openCard(t);
      await cursorIn(t, 'Re-read lecture 7 slides on informed search', 0);
      await press(t, LogicalKeyboardKey.backspace);
      expect(find.text('1/3'), findsOneWidget);
      final text = focused(t).controller!;
      expect(text.text, endsWith('priority queue.\nRe-read lecture 7 slides on informed search'));
      expect(text.selection.baseOffset, text.text.indexOf('Re-read'));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Enter at the start of a list opens a line above it', (t) async {
      savedNotes.clear();
      await openCard(t);
      // Clear the text so the list comes first, then Backspace on the empty line.
      final intro = field(find.textContaining('Grid planner'));
      await t.tap(intro);
      await t.enterText(intro, '');
      await t.pump();
      await press(t, LogicalKeyboardKey.backspace);
      expect(focused(t).controller!.text, 'Re-read lecture 7 slides on informed search');
      await press(t, LogicalKeyboardKey.enter);
      expect(focused(t).maxLines, isNull);
      t.testTextInput.enterText('Above the list');
      await t.pump(const Duration(seconds: 1));
      expect(savedNotes.last.first, {'id': anything, 'type': 'text', 'text': 'Above the list'});
      expect(find.text('2/4'), findsOneWidget, reason: 'the list is untouched');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Enter splits a todo; Enter on an empty todo ends the list', (t) async {
      await openCard(t);
      await cursorIn(t, 'Test cases for fully blocked grids', 'Test cases'.length);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('Test cases'), findsOneWidget);
      expect(find.text(' for fully blocked grids'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      await cursorIn(t, ' for fully blocked grids', ' for fully blocked grids'.length);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('2/6'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('2/5'), findsOneWidget);
      expect(focused(t).maxLines, isNull, reason: 'the empty todo became a text line');
      t.testTextInput.enterText('After the list');
      await t.pump();
      expect(find.text('After the list'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('arrow keys move between blocks', (t) async {
      await openCard(t);
      await cursorIn(t, 'Re-read lecture 7 slides on informed search', 0);
      await press(t, LogicalKeyboardKey.arrowUp);
      expect(focused(t).controller!.text, startsWith('Grid planner'));
      expect(focused(t).controller!.selection.baseOffset, focused(t).controller!.text.length, reason: 'Up lands at the end');
      await press(t, LogicalKeyboardKey.arrowDown);
      expect(focused(t).controller!.text, 'Re-read lecture 7 slides on informed search');
      await press(t, LogicalKeyboardKey.arrowLeft);
      expect(focused(t).controller!.text, startsWith('Grid planner'));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('clicking below the notes writes after the last block', (t) async {
      await openCard(t);
      await t.tap(find.byKey(const ValueKey('notes-end')));
      await settle(t);
      expect(focused(t).maxLines, isNull);
      expect(focused(t).controller!.text, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"/" alone opens nothing; "/todo" + Space makes a todo to type into', (t) async {
      await openCard(t);
      await t.tap(find.text('+ Text'));
      await settle(t);
      final blank = find.byWidgetPredicate((w) => w is TextField && w.focusNode?.hasFocus == true);
      await type(t, blank, '/');
      expect(find.byType(PopupMenuItem<Object>), findsNothing);
      await type(t, blank, '/todo');
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(t);
      expect(find.text('/todo'), findsNothing);
      expect(find.text('2/4'), findsOneWidget, reason: 'the first list is unchanged');
      expect(find.text('0/1'), findsOneWidget, reason: 'after a text block, the todo starts a new list');
      final focused = t.widgetList<TextField>(find.byType(TextField)).where((f) => f.focusNode?.hasFocus == true).single;
      expect(focused.maxLines, 1, reason: 'the new todo has focus');
      t.testTextInput.enterText('Buy milk');
      await t.pump();
      expect(find.text('Buy milk'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"/todo" + Enter on the last line of a text block splits it', (t) async {
      await openCard(t);
      final first = field(find.textContaining('Grid planner'));
      await t.tap(first);
      await t.pump();
      final before = t.widget<TextField>(first).controller!.text;
      await type(t, first, '$before\n/todo');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(t);
      expect(t.widget<TextField>(field(find.textContaining('Grid planner'))).controller!.text, before);
      expect(find.text('2/5'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('unknown commands stay text', (t) async {
      await openCard(t);
      await t.tap(find.text('+ Text'));
      await settle(t);
      final blank = find.byWidgetPredicate((w) => w is TextField && w.focusNode?.hasFocus == true);
      await type(t, blank, '/tod');
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(t);
      expect(find.text('2/4'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Ctrl+N asks for a new card from any view', (t) async {
    final c = await pumpShell(t);
    c.read(viewProvider.notifier).show(AppView.inbox);
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    expect(find.text('New card'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

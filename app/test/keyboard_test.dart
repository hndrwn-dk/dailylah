import 'package:dailylah/ui/keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leaving a page closes the keyboard first', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [KeyboardNavigatorObserver()],
      builder: (context, child) => KeyboardRepaint(child: child!),
      home: const Scaffold(body: Text('setup')),
    ));
    key.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: TextField(autofocus: true)),
    ));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('setup'), findsOneWidget);

    // Keyboard closing triggers a fresh frame without errors.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a keyboard height left over from the background does not cut the page', (tester) async {
    // Back from the background, Android can still report the keyboard's height although no
    // keyboard is up: the Scaffold shrank its body by that much and the lower part of every tab
    // stayed blank. With no text field focused, the height is ignored.
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => KeyboardRepaint(child: child!),
      home: Scaffold(
        body: Column(children: [TextField(focusNode: field), const Expanded(child: SizedBox.expand(key: Key('body')))]),
      ),
    ));
    final full = tester.getBottomLeft(find.byKey(const Key('body'))).dy;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(const Key('body'))).dy, full);

    // A focused field keeps room for the keyboard.
    field.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(const Key('body'))).dy, full - 300 / tester.view.devicePixelRatio);

    // Focus gone, the page is whole again at once.
    field.unfocus();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(const Key('body'))).dy, full);
  });
}

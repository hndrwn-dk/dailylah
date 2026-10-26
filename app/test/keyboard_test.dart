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
}

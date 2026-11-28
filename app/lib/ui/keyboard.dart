import 'package:flutter/material.dart';

/// Closes the keyboard whenever a page, sheet or dialog opens or closes. Leaving a screen
/// while the keyboard was up left the screen below half drawn on some phones (blank where
/// the keyboard had been).
class KeyboardNavigatorObserver extends NavigatorObserver {
  void _close() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _close();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _close();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _close();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _close();
}

/// Draws a fresh frame of the whole app once the keyboard has gone, so no screen keeps a
/// blank area where the keyboard was. A forced frame lays out, paints and composites the
/// full layer tree again, even when nothing in the app changed.
///
/// It also ignores a keyboard height while no text field has focus: back from the background,
/// Android can still report the height of a keyboard that is no longer up, and every Scaffold
/// then shrank its body by that much, leaving the lower part of each tab blank. Only a focused
/// text field shows a keyboard, so without one the page keeps its full height.
class KeyboardRepaint extends StatefulWidget {
  const KeyboardRepaint({super.key, required this.child});
  final Widget child;

  @override
  State<KeyboardRepaint> createState() => _KeyboardRepaintState();
}

class _KeyboardRepaintState extends State<KeyboardRepaint> with WidgetsBindingObserver {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  /// Whether the focused widget is a text field (the only thing that shows a keyboard).
  static bool _typing() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && context.mounted && context.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final open = views.first.viewInsets.bottom > 0;
    if (_open && !open) {
      // Once now and once after the keyboard animation has settled.
      WidgetsBinding.instance.scheduleForcedFrame();
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) WidgetsBinding.instance.scheduleForcedFrame();
      });
    }
    _open = open;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.viewInsets.bottom <= 0 || _typing()) return widget.child;
    return MediaQuery(data: media.removeViewInsets(removeBottom: true), child: widget.child);
  }
}

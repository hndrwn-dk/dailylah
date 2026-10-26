import 'package:flutter/material.dart';

import 'keyboard.dart';

/// Wraps every route of the app (MaterialApp.builder).
///
/// Android draws apps edge to edge (target SDK 35+), so content can sit under the system
/// navigation bar. Most lists use a fixed bottom padding, which is enough with gesture
/// navigation but not with the taller 3-button bar, where the last item (e.g. Setup's Save
/// button) was hidden. Keeping the whole app above the bar fixes every screen, sheet and
/// dialog at once; the strip behind the bar gets the page colour.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: KeyboardRepaint(child: child),
        ),
      );
}

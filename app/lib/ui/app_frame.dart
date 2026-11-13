import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

import 'keyboard.dart';

/// The widest the app's content gets, in logical pixels. On a wider window (an unfolded
/// foldable, a tablet, a phone on its side) the app stays in a centred column of this width.
const double kMaxContentWidth = 600;

/// Wraps every route of the app (MaterialApp.builder).
///
/// Android draws apps edge to edge (target SDK 35+), so content can sit under the system
/// navigation bar. Most lists use a fixed bottom padding, which is enough with gesture
/// navigation but not with the taller 3-button bar, where the last item (e.g. Setup's Save
/// button) was hidden. Keeping the whole app above the bar fixes every screen, sheet and
/// dialog at once; the strip behind the bar gets the page colour.
///
/// The screens are laid out for a phone. Where the window is wider than [kMaxContentWidth],
/// every route, sheet, dialog and the bottom bar sit in one centred column of that width and
/// the page colour fills the rest, so cards and buttons do not stretch from edge to edge.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Before SafeArea takes it away: what the system keeps on the left (a cutout on its side).
    final left = MediaQuery.paddingOf(context).left;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final content = KeyboardRepaint(child: child);
            // A phone: exactly as without the column.
            if (box.maxWidth <= kMaxContentWidth) return content;
            // Code that asks MediaQuery for the width (sheets, dialogs) must get the column's
            // width, and a fold or hinge its place as seen from the column.
            final media = MediaQuery.of(context);
            final shift = Offset(left + (box.maxWidth - kMaxContentWidth) / 2, 0);
            return Center(
              child: SizedBox(
                width: kMaxContentWidth,
                child: MediaQuery(
                  data: media.copyWith(
                    size: Size(kMaxContentWidth, media.size.height),
                    displayFeatures: [
                      for (final f in media.displayFeatures)
                        DisplayFeature(bounds: f.bounds.shift(-shift), type: f.type, state: f.state),
                    ],
                  ),
                  child: content,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

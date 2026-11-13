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
///
/// The frame is one entry of an [Overlay] that covers the whole window. Flutter puts the
/// Cut/Copy/Paste toolbar of a text field into the topmost overlay and places it by window
/// coordinates; with the Navigator's own overlay on top, moved to the column, the toolbar
/// would sit beside its field and partly where taps do not reach.
class AppFrame extends StatefulWidget {
  const AppFrame({super.key, required this.child});
  final Widget child;

  @override
  State<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends State<AppFrame> {
  late final OverlayEntry _entry = OverlayEntry(builder: (context) => _Framed(child: widget.child));

  @override
  void didUpdateWidget(AppFrame old) {
    super.didUpdateWidget(old);
    // The entry builds on its own: tell it when MaterialApp hands over another child.
    if (!identical(old.child, widget.child)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entry.markNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});
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
            // The same widgets on a phone and in the column, so folding, unfolding and
            // turning the phone keep the state below (focus, the keyboard repaint).
            final wide = box.maxWidth > kMaxContentWidth;
            final media = MediaQuery.of(context);
            final shift = Offset(left + (box.maxWidth - kMaxContentWidth) / 2, 0);
            return Center(
              child: SizedBox(
                // A phone: the full width, exactly as without the column.
                width: wide ? kMaxContentWidth : box.maxWidth,
                child: MediaQuery(
                  // Code that asks MediaQuery for the width (sheets, dialogs) must get the
                  // column's width, and a fold or hinge its place as seen from the column.
                  data: !wide
                      ? media
                      : media.copyWith(
                          size: Size(kMaxContentWidth, media.size.height),
                          displayFeatures: [
                            for (final f in media.displayFeatures)
                              if (_inColumn(f.bounds.shift(-shift)) case final bounds?)
                                DisplayFeature(bounds: bounds, type: f.type, state: f.state),
                          ],
                        ),
                  child: KeyboardRepaint(child: child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// A feature's bounds cut to the column; null when it lies wholly beside it.
  static Rect? _inColumn(Rect r) {
    if (r.right < 0 || r.left > kMaxContentWidth) return null;
    return Rect.fromLTRB(r.left.clamp(0, kMaxContentWidth), r.top, r.right.clamp(0, kMaxContentWidth), r.bottom);
  }
}

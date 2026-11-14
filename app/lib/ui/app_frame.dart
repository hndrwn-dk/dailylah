import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

import 'keyboard.dart';

/// The widest a page laid out in one column gets, in logical pixels. On a wider window (an
/// unfolded foldable upright, a small tablet, a phone on its side) the app stays in a centred
/// column of this width.
const double kMaxContentWidth = 600;

/// From this width on (after the side insets) the tabs show their cards in two columns: a
/// foldable opened flat and held on its side, a tablet.
const double kTwoColumnMinWidth = 840;

/// The widest the two-column layout gets; a wider window has the page colour beside it.
const double kMaxWideWidth = 1040;

/// The narrowest column, at 100% text, that the cards are laid out and tested for.
const double kMinCardColumnWidth = 320;

/// Space between the two columns of cards.
const double kColumnGap = 16;

/// How wide the app is in a window with [room] logical pixels after the side insets, at
/// [textScale] (1.0 = 100% text).
///
/// Up to [kMaxContentWidth] all of it; then one column of that width; from
/// [kTwoColumnMinWidth] on the two-column width, up to [kMaxWideWidth]. With large text the two
/// columns would each be narrower than a small phone showing normal text, so the app stays in
/// one column then.
double frameWidth(double room, double textScale) {
  if (room <= kMaxContentWidth) return room;
  if (room < kTwoColumnMinWidth) return kMaxContentWidth;
  final wide = room < kMaxWideWidth ? room : kMaxWideWidth;
  // 16 dp of page padding on each side of the cards.
  final column = (wide - 2 * 16 - kColumnGap) / 2;
  return column / textScale >= kMinCardColumnWidth ? wide : kMaxContentWidth;
}

/// Whether this page has the room for two columns of cards: only the tabs on a wide window.
/// Pages opened from them sit in a [PhoneColumn] and are never wide.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kTwoColumnMinWidth;

/// [media] as seen from a column [width] wide that starts [left] pixels into it: its width,
/// and folds, hinges and cutouts moved to the column, cut to it, or dropped when beside it.
MediaQueryData _columnMedia(MediaQueryData media, double width, double left) => media.copyWith(
      size: Size(width, media.size.height),
      displayFeatures: [
        for (final f in media.displayFeatures)
          if (_inColumn(f.bounds.shift(Offset(-left, 0)), width) case final bounds?)
            DisplayFeature(bounds: bounds, type: f.type, state: f.state),
      ],
    );

/// A feature's bounds cut to a column [width] wide; null when it lies wholly beside it.
Rect? _inColumn(Rect r, double width) {
  if (r.right < 0 || r.left > width) return null;
  return Rect.fromLTRB(r.left.clamp(0, width), r.top, r.right.clamp(0, width), r.bottom);
}

/// Keeps a page that is laid out for a phone (every page opened from a tab, and first-run
/// Setup) in a centred column of [kMaxContentWidth] where the app is wider, with the page
/// colour beside it. Pages pushed with a `MaterialPageRoute` get it from
/// [ColumnPageTransitionsBuilder]; nothing else needs to add it.
class PhoneColumn extends StatelessWidget {
  const PhoneColumn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width > kMaxContentWidth;
    final width = wide ? kMaxContentWidth : media.size.width;
    // The same widgets at every width, so folding and unfolding keep the page's state.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          width: width,
          child: MediaQuery(
            data: wide ? _columnMedia(media, width, (media.size.width - width) / 2) : media,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The app's page transition, with every pushed page in a [PhoneColumn]. The first page (the
/// tabs) is left alone: it uses the whole width of the frame.
class ColumnPageTransitionsBuilder extends PageTransitionsBuilder {
  const ColumnPageTransitionsBuilder();

  static const _inner = FadeForwardsPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _inner.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _inner.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _inner.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        route.settings.name == Navigator.defaultRouteName ? child : PhoneColumn(child: child),
      );
}

/// Wraps every route of the app (MaterialApp.builder).
///
/// Android draws apps edge to edge (target SDK 35+), so content can sit under the system
/// navigation bar. Most lists use a fixed bottom padding, which is enough with gesture
/// navigation but not with the taller 3-button bar, where the last item (e.g. Setup's Save
/// button) was hidden. Keeping the whole app above the bar fixes every screen, sheet and
/// dialog at once; the strip behind the bar gets the page colour.
///
/// Where the window is wider than [kMaxContentWidth], every route, sheet, dialog and the
/// bottom bar sit in one centred column ([frameWidth]: one column of cards, or two from
/// [kTwoColumnMinWidth] on) and the page colour fills the rest, so cards and buttons do not
/// stretch from edge to edge.
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
            final media = MediaQuery.of(context);
            final width = frameWidth(box.maxWidth, media.textScaler.scale(16) / 16);
            return Center(
              child: SizedBox(
                // A phone: the full width, exactly as without the column.
                width: width,
                child: MediaQuery(
                  // Code that asks MediaQuery for the width (the tabs, sheets, dialogs) must
                  // get the column's width, and a fold or hinge its place as seen from it.
                  // Wider than a phone, the column's own place counts also when it fills the
                  // room beside a side cutout (two columns at 840 to 1040 dp).
                  data: box.maxWidth > kMaxContentWidth
                      ? _columnMedia(media, width, left + (box.maxWidth - width) / 2)
                      : media,
                  child: KeyboardRepaint(child: child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

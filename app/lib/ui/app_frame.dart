import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, ImageFilter;

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

/// How strongly the app is blurred the moment the window changes width (a foldable opening or
/// closing, a phone turned), in logical pixels of blur.
const double kFoldBlurSigma = 14;

/// How long the blur stays whole before it starts to clear. A foldable switches to its other
/// screen while the app is already drawing at the new width, and the system plays its own
/// unfold animation; without this wait the blur was over before the screen showed it.
const Duration kFoldBlurSettle = Duration(milliseconds: 350);

/// How long the blur takes to wipe off, from the left edge to the right one.
const Duration kFoldBlurClear = Duration(milliseconds: 650);

/// The longest the blur waits, from the change, for a foldable that is still half open to open
/// flat or close.
const Duration kFoldBlurHold = Duration(milliseconds: 900);

/// The softer band at the edge of the wipe, between the sharp left part and the blurred rest.
const double kFoldBlurEdge = 72;

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
                child: FoldBlur(
                  width: box.maxWidth,
                  halfOpen: media.displayFeatures.any((f) => f.state == DisplayFeatureState.postureHalfOpened),
                  reduceMotion: media.disableAnimations,
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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Blurs the app for a moment when the window changes [width]: a foldable opening or closing, a
/// phone turned on its side. The page jumps from one layout to the other (one column to two),
/// and the blur hides the jump: the whole app is blurred at the change, stays so for
/// [kFoldBlurSettle] (and while the hinge is still [halfOpen], at most [kFoldBlurHold] in all),
/// then the blur wipes off from the left edge to the right in [kFoldBlurClear], with a softer
/// band at the moving edge. With animations turned off on the phone ([reduceMotion]) there is
/// no blur.
///
/// The blur is a layer over the app ([BackdropFilter]); the app itself is the same widget with or
/// without it, so its state is kept.
class FoldBlur extends StatefulWidget {
  const FoldBlur({
    super.key,
    required this.width,
    required this.halfOpen,
    required this.reduceMotion,
    required this.child,
  });
  final double width;
  final bool halfOpen;
  final bool reduceMotion;
  final Widget child;

  @override
  State<FoldBlur> createState() => _FoldBlurState();
}

class _FoldBlurState extends State<FoldBlur> with SingleTickerProviderStateMixin {
  // 1 = clear. Running from 0 to 1 is the blur wiping off.
  late final AnimationController _clear = AnimationController(vsync: this, duration: kFoldBlurClear, value: 1);
  Timer? _settle;
  Timer? _limit;
  bool _settled = true;

  @override
  void didUpdateWidget(FoldBlur old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion) {
      _release(animate: false);
    } else if ((old.width - widget.width).abs() >= 1) {
      _cancelTimers();
      _clear.value = 0;
      _settled = false;
      _settle = Timer(kFoldBlurSettle, () {
        _settled = true;
        _maybeRelease();
      });
      _limit = Timer(kFoldBlurHold, _release);
    } else {
      _maybeRelease();
    }
  }

  bool get _waiting => _settle != null || _limit != null;

  void _maybeRelease() {
    if (_waiting && _settled && !widget.halfOpen) _release();
  }

  void _cancelTimers() {
    _settle?.cancel();
    _limit?.cancel();
    _settle = null;
    _limit = null;
  }

  void _release({bool animate = true}) {
    _cancelTimers();
    _settled = true;
    if (!mounted) return;
    if (animate) {
      if (_clear.value < 1) _clear.forward();
    } else {
      _clear.value = 1;
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    _clear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _clear,
                builder: (context, _) {
                  if (_clear.value >= 1) return const SizedBox.shrink();
                  final wipe = Curves.easeInOutCubic.transform(_clear.value);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _blurFrom(wipe, edge: true),
                      _blurFrom(wipe, edge: false),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      );

  /// The blurred part right of the wipe: the soft band at its edge ([edge]) or the rest.
  Widget _blurFrom(double wipe, {required bool edge}) {
    final sigma = edge ? kFoldBlurSigma / 2 : kFoldBlurSigma;
    return ClipRect(
      clipper: _WipeClipper(wipe, edge: edge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Where the blur still is, [wipe] (0 to 1) of the way through: everything right of the moving
/// edge, or only the soft band at the edge ([edge]). The edge starts left of the screen, so at
/// 0 the whole width is fully blurred, and ends right of it, so at 1 nothing is.
class _WipeClipper extends CustomClipper<Rect> {
  const _WipeClipper(this.wipe, {required this.edge});
  final double wipe;
  final bool edge;

  @override
  Rect getClip(Size size) {
    final x = wipe * (size.width + kFoldBlurEdge) - kFoldBlurEdge;
    return edge
        ? Rect.fromLTRB(x, 0, x + kFoldBlurEdge, size.height)
        : Rect.fromLTRB(x + kFoldBlurEdge, 0, size.width + 1, size.height);
  }

  @override
  bool shouldReclip(_WipeClipper old) => old.wipe != wipe || old.edge != edge;
}

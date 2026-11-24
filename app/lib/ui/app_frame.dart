import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show DisplayFeature, DisplayFeatureState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'keyboard.dart';
import 'theme.dart' show DL;

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

/// How long the new right half stays folded away (edge on, the page colour in its place) before
/// it swings open. A foldable switches to its other screen while the app already draws at the new
/// width, and the system plays its own unfold animation; without this wait the flap would be
/// over before the screen showed it.
const Duration kFoldFlapSettle = Duration(milliseconds: 300);

/// How long the right half takes to swing open from the fold line and lie flat.
const Duration kFoldFlapOpen = Duration(milliseconds: 650);

/// The longest the flap waits, from the change, for a foldable that is still half open to open
/// flat.
const Duration kFoldFlapHold = Duration(milliseconds: 900);

/// The hard sticker shadow under the flap while it turns, in logical pixels down and right.
const double kFoldFlapShadow = 6;

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
                child: FoldFlap(
                  width: box.maxWidth,
                  twoColumns: width >= kTwoColumnMinWidth,
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

/// Opens the app like a sheet of paper when its layout turns into two columns (a foldable
/// opened flat, a tablet turned): the left half is the new layout at once, the right half swings
/// open from the fold line in the middle, with a hard sticker shadow and shaded while it faces
/// away, and lies flat in [kFoldFlapOpen]. Before it moves it waits [kFoldFlapSettle], and while
/// the hinge is still [halfOpen], at most [kFoldFlapHold] in all; until then the right half shows
/// the page colour.
///
/// The app is drawn once: the flap is a snapshot of the new layout taken on the first frame at
/// the new width, laid over the live app, which shows through when the flap is flat. The app
/// itself is the same widgets with or without the flap, so its state is kept. Folding, a
/// window that stays one column (large text) or was two columns already, and animations turned
/// off on the phone ([reduceMotion]) have no flap.
class FoldFlap extends StatefulWidget {
  const FoldFlap({
    super.key,
    required this.width,
    required this.twoColumns,
    required this.halfOpen,
    required this.reduceMotion,
    required this.child,
  });
  final double width;

  /// Whether the app is laid out in two columns now ([frameWidth] at or above
  /// [kTwoColumnMinWidth]). The flap runs only when this turns on: a wider window that stays one
  /// column (large text) or was two columns already (a tablet, a window being resized) has none.
  final bool twoColumns;
  final bool halfOpen;
  final bool reduceMotion;
  final Widget child;

  /// The page colour over the right half while the flap is turned away (for tests).
  static const coverKey = ValueKey('fold-flap-cover');

  /// The turning flap (for tests): a [Transform] that rotates about the fold line.
  static const flapKey = ValueKey('fold-flap');

  @override
  State<FoldFlap> createState() => _FoldFlapState();
}

class _FoldFlapState extends State<FoldFlap> with SingleTickerProviderStateMixin {
  // 1 = flat (or nothing to show). Running from 0 to 1 is the flap swinging open.
  late final AnimationController _open = AnimationController(vsync: this, duration: kFoldFlapOpen, value: 1)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  final _app = GlobalKey(debugLabel: 'fold flap app');
  ui.Image? _image;
  bool _active = false;
  bool _settled = true;
  Timer? _settle;
  Timer? _limit;

  @override
  void didUpdateWidget(FoldFlap old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion) {
      _finish();
    } else if (widget.twoColumns && !old.twoColumns) {
      _start();
    } else if (!widget.twoColumns || old.width - widget.width >= 1) {
      // Back to one column, or narrower while it runs: the snapshot no longer fits.
      _finish();
    } else {
      _maybeRelease();
    }
  }

  void _start() {
    _cancelTimers();
    _dropImage();
    _active = true;
    _settled = false;
    _open.value = 0;
    // The new layout is painted at the end of this frame; take it then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    _settle = Timer(kFoldFlapSettle, () {
      _settled = true;
      _maybeRelease();
    });
    _limit = Timer(kFoldFlapHold, _release);
  }

  void _capture() {
    if (!mounted || !_active) return;
    final boundary = _app.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return _finish();
    try {
      final image = boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      setState(() => _image = image);
    } catch (_) {
      _finish();
    }
  }

  bool get _waiting => _settle != null || _limit != null;

  void _maybeRelease() {
    if (_waiting && _settled && !widget.halfOpen) _release();
  }

  void _release() {
    _cancelTimers();
    _settled = true;
    if (!mounted || !_active) return;
    _open.forward();
  }

  void _finish() {
    _cancelTimers();
    _settled = true;
    _open.value = 1;
    if (!_active && _image == null) return;
    _active = false;
    _dropImage();
    if (mounted) setState(() {});
  }

  void _cancelTimers() {
    _settle?.cancel();
    _limit?.cancel();
    _settle = null;
    _limit = null;
  }

  void _dropImage() {
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    _dropImage();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.passthrough,
        children: [
          RepaintBoundary(key: _app, child: widget.child),
          Positioned.fill(child: _active ? _overlay(context) : const SizedBox.shrink()),
        ],
      );

  Widget _overlay(BuildContext context) {
    final page = Theme.of(context).scaffoldBackgroundColor;
    final image = _image;
    return LayoutBuilder(
      builder: (context, box) {
        final half = box.maxWidth / 2;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The live right half stays hidden (and takes no taps) until the flap lies flat.
            Positioned(
              left: half,
              top: 0,
              right: 0,
              bottom: 0,
              child: AbsorbPointer(child: ColoredBox(key: FoldFlap.coverKey, color: page)),
            ),
            if (image != null)
              Positioned(
                left: half,
                top: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _open,
                    builder: (context, _) {
                      // 90 degrees (edge on) to flat.
                      final turn = (1 - Curves.easeOutCubic.transform(_open.value)) * math.pi / 2;
                      return Transform(
                        key: FoldFlap.flapKey,
                        alignment: Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(-turn),
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: kFoldFlapShadow,
                              top: kFoldFlapShadow,
                              right: -kFoldFlapShadow,
                              bottom: -kFoldFlapShadow,
                              child: ColoredBox(color: DL.ink.withValues(alpha: math.sin(turn))),
                            ),
                            CustomPaint(painter: _RightHalf(image, half / box.maxWidth)),
                            ColoredBox(color: Colors.black.withValues(alpha: 0.45 * math.sin(turn))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Paints the part of [image] right of [from] (a fraction of its width) to fill the size.
class _RightHalf extends CustomPainter {
  const _RightHalf(this.image, this.from);
  final ui.Image image;
  final double from;

  @override
  void paint(Canvas canvas, Size size) {
    final left = image.width * from;
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(left, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_RightHalf old) => old.image != image || old.from != from;
}

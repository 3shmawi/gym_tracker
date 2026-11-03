import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/router/link_guard.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The pictures at the top of the exercise screen (design board 1.1–2.1).
///
/// Source order: the gym's pictures ([gymPictures], cover first), then the
/// bundled drawing, then the library placeholder ([ExerciseIllustration]).
/// A gym picture that fails (404, offline with no cached copy) is dropped
/// silently; when all fail, the bundled drawing shows. Never an error.
///
/// One gym picture: shown like the bundled one. Several: a swipeable
/// carousel (dots, mirrored in RTL, "Picture 2 of 4" for screen readers).
/// When the two pictures are the start and end of one move ([movePair]) it
/// auto-advances: [stepEvery] per picture, a [transition] slide, at most
/// [maxLoops] loops, then rests on the last picture. A touch pauses it and
/// it resumes after [resumeAfter] with no touch; the pause button stops it
/// until play. It never runs with Reduce Motion, a screen reader, another
/// route on top or the app in the background.
class ExercisePicturesView extends StatefulWidget {
  const new({
    required this.exercise,
    this.gymPictures = const [],
    this.movePair = false,
    this.offline = false,
    this.onOpenCredits,
    super.key,
  });

  static const stepEvery = Duration(seconds: 3);
  static const transition = Duration(milliseconds: 250);
  static const resumeAfter = Duration(seconds: 6);
  static const maxLoops = 3;

  final LibraryExercise exercise;
  final List<ImageProvider> gymPictures;
  final bool movePair;

  /// The device is offline: when every gym picture failed, says they show
  /// once back online.
  final bool offline;

  /// Opens the licenses page (the credit line); null hides the link.
  final VoidCallback? onOpenCredits;

  @override
  State<ExercisePicturesView> createState() => _ExercisePicturesViewState();
}

class _ExercisePicturesViewState extends State<ExercisePicturesView>
    with WidgetsBindingObserver, IgnoresLinks {
  final PageController _pages = PageController();
  final Set<int> _failed = {};
  int _page = 0;
  Timer? _advance;
  Timer? _resume;
  bool _pausedByButton = false;
  bool _pausedByTouch = false;
  bool _finished = false;
  int _loops = 0;
  bool _appActive = true;
  bool _routeCurrent = true;

  List<int> get _shown => [
    for (var i = 0; i < widget.gymPictures.length; i++)
      if (!_failed.contains(i)) i,
  ];

  /// Motion is allowed here at all (the button shows).
  bool get _autoAdvance {
    final media = MediaQuery.of(context);
    return widget.movePair &&
        _shown.length == 2 &&
        !media.disableAnimations &&
        !media.accessibleNavigation;
  }

  bool get _running =>
      _autoAdvance &&
      !_pausedByButton &&
      !_pausedByTouch &&
      !_finished &&
      _appActive &&
      _routeCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _schedule();
  }

  @override
  void didUpdateWidget(ExercisePicturesView old) {
    super.didUpdateWidget(old);
    if (old.gymPictures.length != widget.gymPictures.length ||
        old.exercise.id != widget.exercise.id) {
      _failed.clear();
      _page = 0;
      _loops = 0;
      _finished = false;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advance?.cancel();
    _resume?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// (Re)starts the step timer when the carousel may move, stops it if not.
  void _schedule() {
    _advance?.cancel();
    _advance = null;
    if (!mounted || !_running) return;
    _advance = Timer(ExercisePicturesView.stepEvery, _step);
  }

  void _step() {
    if (!mounted || !_running || !_pages.hasClients) return;
    final next = _page == 0 ? 1 : 0;
    // Arriving at the end of the move completes a loop.
    if (next == 1) _loops++;
    setState(() => _finished = _loops >= ExercisePicturesView.maxLoops);
    unawaited(_slideTo(next));
    // The next step is timed from now (the slide, then the picture's time),
    // not from when the slide reports it ended.
    _advance?.cancel();
    _advance = _running
        ? Timer(
            ExercisePicturesView.stepEvery + ExercisePicturesView.transition,
            _step,
          )
        : null;
  }

  Future<void> _slideTo(int page) => _pages.animateToPage(
    page,
    duration: ExercisePicturesView.transition,
    curve: Curves.easeOutCubic,
  );

  void _touched() {
    if (!_autoAdvance) return;
    _resume?.cancel();
    _pausedByTouch = true;
    _schedule();
    _resume = Timer(ExercisePicturesView.resumeAfter, () {
      if (!mounted) return;
      setState(() => _pausedByTouch = false);
      _schedule();
    });
  }

  void _toggle() {
    setState(() {
      if (_pausedByButton || _finished) {
        _pausedByButton = false;
        _pausedByTouch = false;
        _resume?.cancel();
        if (_finished) {
          _finished = false;
          _loops = 0;
          if (_pages.hasClients) _pages.jumpToPage(0);
        }
      } else {
        _pausedByButton = true;
      }
    });
    _schedule();
  }

  void _failedAt(int index) {
    if (_failed.contains(index)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failed.contains(index)) return;
      setState(() {
        _failed.add(index);
        final count = _shown.length;
        if (_page >= count) _page = count == 0 ? 0 : count - 1;
      });
      if (_pages.hasClients && _shown.isNotEmpty) _pages.jumpToPage(_page);
      _schedule();
    });
  }

  void _turn(int delta) {
    final target = (_page + delta).clamp(0, _shown.length - 1);
    if (target == _page || !_pages.hasClients) return;
    _touched();
    unawaited(_slideTo(target));
  }

  /// The card the pictures sit in (design board 1.1): 210 high; inside it
  /// the picture inset 12 at the top, 48 at the sides and 28 at the bottom
  /// when there are dots (12 without).
  static double get _stageHeight => AppDimens.scaled(210);

  EdgeInsetsGeometry _pictureInset({required bool dots}) =>
      EdgeInsetsDirectional.fromSTEB(
        AppDimens.scaled(48),
        AppDimens.scaled(12),
        AppDimens.scaled(48),
        AppDimens.scaled(dots ? 28 : 12),
      );

  double _pictureHeight({required bool dots}) =>
      _stageHeight - AppDimens.scaled(dots ? 40 : 24);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = _shown;
    final hasBundled = ExerciseImages.has(widget.exercise.id);
    final allFailed = widget.gymPictures.isNotEmpty && shown.isEmpty;
    final Widget stage;
    if (shown.isEmpty && !hasBundled) {
      // The library placeholder fills the card (board 2.1-E).
      stage = _stage(
        ExerciseIllustration(
          exercise: widget.exercise,
          large: true,
          height: _stageHeight,
        ),
      );
    } else if (shown.isEmpty) {
      stage = _stage(
        Padding(
          padding: _pictureInset(dots: false),
          child: ExerciseIllustration(
            exercise: widget.exercise,
            large: true,
            height: _pictureHeight(dots: false),
          ),
        ),
      );
    } else if (shown.length == 1) {
      stage = _stage(_single(shown.first, hasBundled));
    } else {
      stage = _carousel(shown, hasBundled);
    }
    final String? hint;
    if (allFailed && widget.offline) {
      hint = l10n.exercisePicturesOfflineHint;
    } else if (shown.length > 1 && !_autoAdvance) {
      hint = l10n.exercisePicturesSwipeHint;
    } else {
      hint = null;
    }
    final credited = shown.isNotEmpty || hasBundled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stage,
        if (credited)
          _CreditLine(onOpen: widget.onOpenCredits, hint: hint)
        else
          SizedBox(height: AppDimens.sm),
      ],
    );
  }

  Widget _stage(Widget content, {List<Widget> over = const []}) => AppCard(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: SizedBox(
        height: _stageHeight,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: content),
            ...over,
          ],
        ),
      ),
    ),
  );

  Widget _image(int index, bool hasBundled, {required bool dots}) {
    final palette = context.palette;
    final height = _pictureHeight(dots: dots);
    return Padding(
      padding: _pictureInset(dots: dots),
      child: Image(
        key: Key('gym_picture_$index'),
        image: widget.gymPictures[index],
        fit: BoxFit.contain,
        width: double.infinity,
        height: height,
        // A transparent mask, drawn in the text colour like the bundled ones.
        color: palette.textPrimary,
        colorBlendMode: BlendMode.srcIn,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (frame != null || sync) return child;
          // Loading: the bundled drawing when there is one (board 2.1-A),
          // else a quiet box.
          return hasBundled
              ? ExcludeSemantics(
                  child: ExerciseIllustration(
                    exercise: widget.exercise,
                    large: true,
                    height: height,
                  ),
                )
              : _LoadingBox(height: height);
        },
        errorBuilder: (context, error, stack) {
          _failedAt(index);
          return SizedBox(height: height);
        },
      ),
    );
  }

  Widget _single(int index, bool hasBundled) {
    final lang = Localizations.localeOf(context).languageCode;
    return Semantics(
      container: true,
      image: true,
      label: context.l10n.exerciseIllustrationLabel(
        widget.exercise.name.of(lang),
      ),
      excludeSemantics: true,
      child: _image(index, hasBundled, dots: false),
    );
  }

  Widget _carousel(List<int> shown, bool hasBundled) {
    final l10n = context.l10n;
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    final lang = Localizations.localeOf(context).languageCode;
    final name = widget.exercise.name.of(lang);
    final page = _page.clamp(0, shown.length - 1);
    final showButton = _autoAdvance;
    final playing = !(_pausedByButton || _finished);
    return _stage(
      Semantics(
        container: true,
        label: l10n.exercisePicturePosition(page + 1, shown.length, name),
        onIncrease: page < shown.length - 1 ? () => _turn(1) : null,
        onDecrease: page > 0 ? () => _turn(-1) : null,
        child: ExcludeSemantics(
          child: Listener(
            onPointerDown: (_) => _touched(),
            onPointerUp: (_) => _touched(),
            child: PageView.builder(
              key: const Key('gym_pictures_pages'),
              controller: _pages,
              itemCount: shown.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) =>
                  _image(shown[i], hasBundled, dots: true),
            ),
          ),
        ),
      ),
      over: [
        // The time left on this picture, while it moves (board 1.4-A).
        if (_running)
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('progress-$page-$_loops'),
                tween: Tween(begin: 0, end: 1),
                duration: ExercisePicturesView.stepEvery,
                builder: (context, value, _) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      height: AppDimens.scaled(3),
                      color: primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        PositionedDirectional(
          top: AppDimens.scaled(10),
          start: AppDimens.scaled(12),
          child: ExcludeSemantics(
            child: AppBadge(
              // An LTR isolate: in Arabic "1 / 2" must not read "2 / 1".
              label: '\u2066${page + 1} / ${shown.length}\u2069',
              tone: AppTone.neutral,
            ),
          ),
        ),
        PositionedDirectional(
          bottom: AppDimens.sm,
          start: 0,
          end: 0,
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: AppDimens.scaled(6),
              children: [
                for (var i = 0; i < shown.length; i++)
                  AnimatedContainer(
                    duration: ExercisePicturesView.transition,
                    width: AppDimens.scaled(i == page ? 18 : 6),
                    height: AppDimens.scaled(6),
                    decoration: BoxDecoration(
                      color: i == page ? primary : palette.textTertiary,
                      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (showButton)
          PositionedDirectional(
            bottom: AppDimens.scaled(2),
            end: AppDimens.scaled(4),
            child: AppIconButton(
              key: const Key('gym_pictures_toggle'),
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tooltip: playing
                  ? l10n.exercisePicturesPause
                  : l10n.exercisePicturesPlay,
              onPressed: _toggle,
            ),
          ),
      ],
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const new({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: context.palette.fillSubtle,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
      ),
    ),
  );
}

/// "Everkinetic · CC BY-SA 4.0" under the picture; opens the licenses page
/// where the author, the licence and what we changed are listed.
class _CreditLine extends StatelessWidget {
  const new({required this.onOpen, this.hint});

  final VoidCallback? onOpen;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final style = AppTextStyles.caption.copyWith(color: palette.textSecondary);
    final credit = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppDimens.xs,
      children: [
        Icon(
          Icons.info_outline,
          size: AppDimens.scaled(14),
          color: palette.textSecondary,
        ),
        Flexible(
          child: Text(
            l10n.exercisePicturesCredit,
            style: style,
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );
    final link = onOpen == null
        ? credit
        : Semantics(
            container: true,
            button: true,
            label: l10n.exercisePicturesCreditLabel,
            excludeSemantics: true,
            child: InkWell(
              key: const Key('gym_pictures_credit'),
              onTap: onOpen,
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppDimens.minTouchTarget,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  child: credit,
                ),
              ),
            ),
          );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppDimens.sm,
      children: [
        link,
        if (hint != null)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: AppDimens.xs),
            child: Text(
              '· ${hint!}',
              key: const Key('gym_pictures_hint'),
              style: AppTextStyles.caption.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

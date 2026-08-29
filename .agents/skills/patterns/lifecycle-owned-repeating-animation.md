# Lifecycle-Owned Repeating Animation

## Rationale

A repeating animation controller is a long-lived resource even when it only
updates a small visual indicator. Keep the controller with the `StatefulWidget`
that owns the visual lifetime, start it only while the semantic state requires
animation, stop or reset it when that state ends, and dispose it with the
widget. This prevents ticker leaks and keeps animation state from outliving
the indicator it drives.

## When to use

Use for a repeating pulse, blink, or other continuously animated widget:

1. Make the smallest visual owner stateful and mix in
   `SingleTickerProviderStateMixin`.
2. Create the controller with `vsync: this` and start it only for the active
   semantic state.
3. Stop and reset it when the state no longer needs animation, especially
   when `didUpdateWidget` changes the inputs.
4. Dispose the controller in the owner's `dispose` method.
5. Animate paint properties such as opacity or scale without changing layout
   when the indicator's size must remain stable.

## When not to use

Do not create a repeating controller for a one-shot transition, a static
indicator, or an animation whose lifetime belongs to a parent service rather
than the widget. Do not leave an always-running ticker active when the
semantic state is inactive.

## Examples

### Example 1: Streaming response owns and disposes its blinking cursor

**File**: `app/lib/ui/chat/widgets/streaming_bubble.dart:18-34`

```dart
class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }
}
```

The cursor's ticker is scoped to the streaming bubble rather than a global
animation service.

### Example 2: Recording feedback repeats while its strip is mounted

**File**: `app/lib/ui/chat/voice/widgets/recording_strip.dart:43-77`

```dart
class _RecordingStripState extends State<RecordingStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}
```

The recording strip owns the pulsing red-dot ticker and closes it when the
recording surface leaves the tree.

### Example 3: Room status starts and stops a pulse at semantic edges

**File**: `app/lib/ui/home/widgets/session_tile.dart:134-170`

```dart
class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  bool get _isPulsing => _isOrchestrating(widget) && !widget.isWorking;

  @override
  void didUpdateWidget(covariant _PresenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPulsing == (_isOrchestrating(oldWidget) && !oldWidget.isWorking)) {
      return;
    }
    if (_isPulsing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}
```

The home tile does not keep animating for working, reconnecting, offline, or
stale rooms; it changes ticker activity with the same precedence as the dot's
semantic projection.

## Common violations

- Starting a repeating controller from a stateless widget or a global singleton
  with no matching teardown owner.
- Starting a new ticker on every rebuild instead of reusing the state-owned
  controller.
- Stopping the visual pulse but leaving the controller repeating after the
  semantic state becomes inactive.
- Forgetting to dispose the controller, causing ticker leaks when list rows or
  screens are removed.
- Animating size or layout for a fixed-size status dot when opacity or scale
  can preserve the surrounding layout.

## Related

- `lifecycle-boundary-state-convergence.md` — closes or converges lifecycle-owned
  activity at replacement and shutdown boundaries.
- `edge-triggered-convergence.md` — changes animation activity only when the
  semantic projection changes.

import 'package:app/protocol/protocol.dart';

/// User-visible state of the debug-capture quick action.
sealed class CaptureDeliveryState {
  const CaptureDeliveryState();
}

final class CaptureDeliveryIdle extends CaptureDeliveryState {
  const CaptureDeliveryIdle();
}

final class CaptureDeliveryReading extends CaptureDeliveryState {
  const CaptureDeliveryReading();
}

final class CaptureDeliverySending extends CaptureDeliveryState {
  const CaptureDeliverySending(this.progress);
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is CaptureDeliverySending && other.progress == progress;

  @override
  int get hashCode => progress.hashCode;
}

final class CaptureDeliveryDelivered extends CaptureDeliveryState {
  const CaptureDeliveryDelivered(this.path);
  final String path;

  @override
  bool operator ==(Object other) =>
      other is CaptureDeliveryDelivered && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class CaptureDeliveryFailed extends CaptureDeliveryState {
  const CaptureDeliveryFailed(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is CaptureDeliveryFailed && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// State for the Quick Actions sheet and its model/capture sub-actions.
sealed class QuickActionsState {
  final ThinkingLevel? currentThinking;
  final WireModel? currentModel;
  final String? currentModelName;
  final CaptureDeliveryState captureDelivery;

  const QuickActionsState({
    this.currentThinking,
    this.currentModel,
    this.currentModelName,
    this.captureDelivery = const CaptureDeliveryIdle(),
  });
}

class QuickActionsIdle extends QuickActionsState {
  const QuickActionsIdle({
    super.currentThinking,
    super.currentModel,
    super.currentModelName,
    super.captureDelivery,
  });

  @override
  bool operator ==(Object other) =>
      other is QuickActionsIdle &&
      other.currentThinking == currentThinking &&
      other.currentModel == currentModel &&
      other.currentModelName == currentModelName &&
      other.captureDelivery == captureDelivery;

  @override
  int get hashCode => Object.hash(
    currentThinking,
    currentModel,
    currentModelName,
    captureDelivery,
  );
}

class QuickActionsBusy extends QuickActionsState {
  final ActionName action;
  const QuickActionsBusy({
    required this.action,
    super.currentThinking,
    super.currentModel,
    super.currentModelName,
    super.captureDelivery,
  });

  @override
  bool operator ==(Object other) =>
      other is QuickActionsBusy &&
      other.action == action &&
      other.currentThinking == currentThinking &&
      other.currentModel == currentModel &&
      other.currentModelName == currentModelName &&
      other.captureDelivery == captureDelivery;

  @override
  int get hashCode => Object.hash(
    action,
    currentThinking,
    currentModel,
    currentModelName,
    captureDelivery,
  );
}

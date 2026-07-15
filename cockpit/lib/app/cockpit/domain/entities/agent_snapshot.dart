import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';

/// Snapshot of live agent state from `get_state`.
///
/// Cockpit uses it to initialize the model and effort selectors at startup and
/// to hydrate the turn projection.
class AgentSnapshot {
  const AgentSnapshot({
    required this.model,
    required this.thinkingLevel,
    required this.turn,
  });

  final PiModel? model;
  final ThinkingLevel thinkingLevel;
  final AgentTurnProjection turn;
}

/// Represent an LLM available to the agent.
///
/// This is the domain form of the RPC `Model` returned or consumed by
/// `get_available_models`, `set_model`, and `get_state`.
class PiModel {
  const PiModel({
    required this.provider,
    required this.id,
    required this.name,
    required this.reasoning,
    this.supportsImages = false,
    this.contextWindow,
    this.thinkingLevelMap = const <String, String?>{},
  });

  final String provider;
  final String id;
  final String name;

  /// Whether the model supports reasoning and enables the effort selector.
  final bool reasoning;

  /// Whether `input` includes `image` support and enables vision attachments.
  ///
  /// `false` denotes a text-only model that cannot inspect images.
  final bool supportsImages;

  /// Context-window size in tokens when reported by the provider.
  final int? contextWindow;

  /// Effort levels accepted by the model from the RPC `thinkingLevelMap`.
  ///
  /// Maps canonical levels to provider-specific strings. A `null` value marks a
  /// level as unavailable, while an absent key remains available by default.
  final Map<String, String?> thinkingLevelMap;

  /// Use provider and id as the logical identity required by `set_model`.
  @override
  bool operator ==(Object other) =>
      other is PiModel && other.provider == provider && other.id == id;

  @override
  int get hashCode => Object.hash(provider, id);
}

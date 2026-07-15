// Binary split-tree model for the multiplexer.
//
// A LeafPane contains tabs, one per agent. A SplitPane divides space between two
// nodes, either side by side (SplitDir.vertical) or stacked
// (SplitDir.horizontal). Closing a pane expands its sibling; see removeLeaf.
// Operations are immutable and return a new tree.

/// Orient pane children within a split.
///
/// [vertical] places panes side by side; [horizontal] stacks them.
enum SplitDir { vertical, horizontal }

/// Provide stable identity for nodes in the immutable pane split tree.
sealed class PaneNode {
  const PaneNode(this.id);
  final String id;
}

/// Hold agent-session tabs at a leaf, with [active] selecting the visible tab.
final class LeafPane extends PaneNode {
  const LeafPane({required String id, required this.tabs, required this.active})
    : super(id);

  final List<String> tabs;
  final String active;

  LeafPane copyWith({List<String>? tabs, String? active}) =>
      LeafPane(id: id, tabs: tabs ?? this.tabs, active: active ?? this.active);
}

/// Divide [a] and [b] according to [frac] (0..1) along [dir].
final class SplitPane extends PaneNode {
  const SplitPane({
    required String id,
    required this.dir,
    required this.a,
    required this.b,
    required this.frac,
  }) : super(id);

  final SplitDir dir;
  final PaneNode a;
  final PaneNode b;
  final double frac;

  SplitPane copyWith({PaneNode? a, PaneNode? b, double? frac}) => SplitPane(
    id: id,
    dir: dir,
    a: a ?? this.a,
    b: b ?? this.b,
    frac: frac ?? this.frac,
  );
}

// ---- serialization (layout persistence) ------------------------------------

/// Serialize the tree to a JSON-compatible map of primitives, lists, and maps.
Map<String, dynamic> paneNodeToJson(PaneNode node) {
  return switch (node) {
    LeafPane() => <String, dynamic>{
      'k': 'leaf',
      'id': node.id,
      'tabs': node.tabs,
      'active': node.active,
    },
    SplitPane() => <String, dynamic>{
      'k': 'split',
      'id': node.id,
      'dir': node.dir.name,
      'frac': node.frac,
      'a': paneNodeToJson(node.a),
      'b': paneNodeToJson(node.b),
    },
  };
}

/// Reconstruct a tree from a map produced by [paneNodeToJson].
PaneNode paneNodeFromJson(Map<String, dynamic> json) {
  if (json['k'] == 'split') {
    return SplitPane(
      id: json['id'] as String,
      dir: SplitDir.values.byName(json['dir'] as String),
      frac: (json['frac'] as num).toDouble(),
      a: paneNodeFromJson((json['a'] as Map).cast<String, dynamic>()),
      b: paneNodeFromJson((json['b'] as Map).cast<String, dynamic>()),
    );
  }
  return LeafPane(
    id: json['id'] as String,
    tabs: (json['tabs'] as List).cast<String>(),
    active: json['active'] as String,
  );
}

// ---- pure helpers (mirror the design) ---------------------------------------

/// Collect leaves in depth-first `a`-then-`b` display order.
///
/// When [acc] is supplied, appends to and returns that same accumulator; otherwise
/// creates a new list.
List<LeafPane> leaves(PaneNode node, [List<LeafPane>? acc]) {
  final out = acc ?? <LeafPane>[];
  switch (node) {
    case LeafPane():
      out.add(node);
    case SplitPane(:final a, :final b):
      leaves(a, out);
      leaves(b, out);
  }
  return out;
}

/// Find the first leaf with [id] in display order, or return `null` if absent.
LeafPane? findLeaf(PaneNode node, String id) {
  for (final leaf in leaves(node)) {
    if (leaf.id == id) return leaf;
  }
  return null;
}

/// Replace one split fraction through an immutable recursive tree update.
///
/// Preserves [frac] verbatim and leaves the tree structurally unchanged when
/// [splitId] is absent.
PaneNode setFrac(PaneNode node, String splitId, double frac) {
  return switch (node) {
    LeafPane() => node,
    SplitPane() =>
      node.id == splitId
          ? node.copyWith(frac: frac)
          : node.copyWith(
              a: setFrac(node.a, splitId, frac),
              b: setFrac(node.b, splitId, frac),
            ),
  };
}

/// Apply [update] to the leaf with [id] through an immutable tree replacement.
///
/// Leaves the tree structurally unchanged and never invokes [update] when the
/// target leaf is absent.
PaneNode updateLeaf(
  PaneNode node,
  String id,
  LeafPane Function(LeafPane) update,
) {
  return switch (node) {
    LeafPane() => node.id == id ? update(node) : node,
    SplitPane() => node.copyWith(
      a: updateLeaf(node.a, id, update),
      b: updateLeaf(node.b, id, update),
    ),
  };
}

/// Split leaf [id] along [dir] and place [newLeaf] beside it.
///
/// By default, the new pane appears **after** the original (right or below);
/// [before] places it **before** (left or above). [splitId] supplies a unique id
/// to avoid collisions when splitting the same leaf repeatedly; when omitted,
/// the id is derived from `id` and `dir`.
PaneNode splitLeaf(
  PaneNode node,
  String id,
  SplitDir dir,
  LeafPane newLeaf, {
  String? splitId,
  bool before = false,
}) {
  return switch (node) {
    LeafPane() =>
      node.id == id
          ? SplitPane(
              id: splitId ?? 'sp_${id}_$dir',
              dir: dir,
              a: before ? newLeaf : node,
              b: before ? node : newLeaf,
              frac: 0.5,
            )
          : node,
    SplitPane() => node.copyWith(
      a: splitLeaf(node.a, id, dir, newLeaf, splitId: splitId, before: before),
      b: splitLeaf(node.b, id, dir, newLeaf, splitId: splitId, before: before),
    ),
  };
}

/// Move [tabId] within [tabs] to slot [index] (0..length) and return a new list.
///
/// [index] denotes the target slot **before** removal, matching "drop into slot
/// i" semantics; this function adjusts the destination after removal. When
/// [tabId] is absent, the returned copy preserves the original order.
List<String> reorderTabs(List<String> tabs, String tabId, int index) {
  final out = [...tabs];
  final from = out.indexOf(tabId);
  if (from < 0) return out;
  out.removeAt(from);
  var to = index;
  if (to > from) to -= 1; // Removal before the target shifts it by one slot.
  to = to.clamp(0, out.length);
  out.insert(to, tabId);
  return out;
}

/// Remove leaf [id], promoting its sibling when it is a direct split child.
PaneNode removeLeaf(PaneNode node, String id) {
  switch (node) {
    case LeafPane():
      return node;
    case SplitPane(:final a, :final b):
      if (a is LeafPane && a.id == id) return b;
      if (b is LeafPane && b.id == id) return a;
      return node.copyWith(a: removeLeaf(a, id), b: removeLeaf(b, id));
  }
}

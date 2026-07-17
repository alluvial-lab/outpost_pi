import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/rpc_json_object.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_entry.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_markdown.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
// Material's SelectionArea wraps scrolling to auto-scroll text selection when
// dragging to an edge. It works under ShadcnApp.
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Keep chat content comfortably left-aligned instead of spanning wide panes.
const double _kChatMaxWidth = 920;

/// Respond to an interactive extension card as `(id, response, label)`.
///
/// Connect this callback to `AgentSession.respondUi`.
typedef UiResponder =
    void Function(String id, RpcUiResponse response, String label);

/// Project an agent event stream into a selectable, scrollable conversation.
///
/// Groups user messages and their responses into turns, optionally pins turn
/// headers, and routes interactive extension cards through [onUiResponse].
class AgentTranscript extends StatelessWidget {
  const AgentTranscript({
    super.key,
    required this.entries,
    required this.controller,
    this.onUiResponse,
    this.bottomPadding = 8,
  });

  final List<Object> entries;
  final ScrollController controller;

  /// Respond to interactive `extension_ui_request` cards.
  final UiResponder? onUiResponse;

  /// Reserve trailing space so conversation content clears the floating composer.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Send a prompt to get the agent started.',
          style: context.typo.body.copyWith(color: context.colors.text3),
        ),
      );
    }
    // Pinned question headers are optional under Settings → Appearance.
    final pin = context.watch<SettingsController>().settings.pinUserMessage;
    // Let the scrollbar and list span the pane while calculated horizontal
    // padding caps and centers content. With [pin], each question/response turn
    // becomes a section whose question stays at the top while its response
    // scrolls; otherwise questions remain bubbles in a flat list.
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = (constraints.maxWidth - _kChatMaxWidth) / 2;
        final hpad = extra > 26 ? extra : 26.0;
        final hPadding = EdgeInsets.symmetric(horizontal: hpad);

        final slivers = <Widget>[
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
        ];
        if (pin) {
          for (final turn in _groupIntoTurns(entries)) {
            if (turn.header == null) {
              slivers.add(
                SliverPadding(
                  padding: hPadding,
                  sliver: _bodySliver(turn.body),
                ),
              );
            } else {
              slivers.add(
                SliverStickyHeader.builder(
                  builder: (context, state) => Padding(
                    padding: hPadding,
                    child: _PinnedUserHeader(
                      entry: turn.header!,
                      pinned: state.isPinned,
                    ),
                  ),
                  sliver: SliverPadding(
                    padding: hPadding,
                    sliver: _bodySliver(turn.body),
                  ),
                ),
              );
            }
          }
        } else {
          slivers.add(
            SliverPadding(padding: hPadding, sliver: _bodySliver(entries)),
          );
        }
        slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottomPadding)));

        return SelectionArea(
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: ScrollConfiguration(
              // Prevent the automatic scrollbar from duplicating ours.
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: CustomScrollView(controller: controller, slivers: slivers),
            ),
          ),
        );
      },
    );
  }

  /// Group entries into turns opened by each [ProjectedUserMessage].
  ///
  /// Following entries form the body until the next user message. Entries before
  /// the first user message form a headerless turn.
  List<({ProjectedUserMessage? header, List<Object> body})> _groupIntoTurns(
    List<Object> entries,
  ) {
    final turns = <({ProjectedUserMessage? header, List<Object> body})>[];
    ProjectedUserMessage? header;
    var body = <Object>[];
    for (final entry in entries) {
      if (entry is ProjectedUserMessage) {
        if (header != null || body.isNotEmpty) {
          turns.add((header: header, body: body));
        }
        header = entry;
        body = <Object>[];
      } else {
        body.add(entry);
      }
    }
    turns.add((header: header, body: body));
    return turns;
  }

  Widget _bodySliver(List<Object> body) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _EntryView(
          key: ValueKey(body[i]),
          entry: body[i],
          onUiResponse: onUiResponse,
        ),
        childCount: body.length,
      ),
    );
  }
}

/// Render a user message as a sticky turn header when pinned.
///
/// Pinned headers gain an opaque background and bottom border to mask scrolling
/// content. Unpinned headers remain ordinary bubbles at the same size.
class _PinnedUserHeader extends StatelessWidget {
  const _PinnedUserHeader({required this.entry, required this.pinned});
  final ProjectedUserMessage entry;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = _UserMessage(
      text: entry.text,
      images: entry.images,
      compact: true,
    );
    if (!pinned) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: child,
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({super.key, required this.entry, this.onUiResponse});
  final Object entry;
  final UiResponder? onUiResponse;

  @override
  Widget build(BuildContext context) {
    return switch (entry) {
      ProjectedUserMessage(:final text, :final images) => _UserMessage(
        text: text,
        images: images,
      ),
      ProjectedAssistantTextMessage(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: text.isEmpty
            ? Text(
                '…',
                style: context.typo.body.copyWith(color: context.colors.text3),
              )
            : _CachedMarkdown(text),
      ),
      ProjectedThinkingMessage(:final text) => _ThinkingBlock(text: text),
      ProjectedToolMessage(
        :final name,
        :final args,
        :final status,
        :final resultText,
      ) =>
        _ToolCard(
          name: name,
          args: args,
          status: status,
          resultText: resultText,
        ),
      InfoEntry(:final text, :final isError) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: context.typo.label.copyWith(
            color: isError ? context.colors.error : context.colors.text3,
          ),
        ),
      ),
      WorkedEntry(:final duration) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: context.colors.text3),
            const SizedBox(width: 7),
            Text(
              'Worked for ${_formatWorked(duration)}',
              style: context.typo.label.copyWith(color: context.colors.text3),
            ),
          ],
        ),
      ),
      NoticeEntry(:final message, :final level) => _NoticeLine(
        message: message,
        level: level,
      ),
      UiRequestEntry() => _UiRequestCard(
        entry: entry as UiRequestEntry,
        onRespond: onUiResponse,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Cache [AgentMarkdown] widgets by text to avoid repeated parsing and layout.
///
/// Streaming notifications and tab changes rebuild the transcript frequently.
/// Reusing the identical widget instance lets Flutter skip its subtree when text
/// is unchanged. Theme changes still rebuild [AgentMarkdown] directly through
/// its own inherited color dependency.
class _CachedMarkdown extends StatefulWidget {
  const _CachedMarkdown(this.text);
  final String text;

  @override
  State<_CachedMarkdown> createState() => _CachedMarkdownState();
}

class _CachedMarkdownState extends State<_CachedMarkdown> {
  late Widget _markdown = AgentMarkdown(widget.text);

  @override
  void didUpdateWidget(_CachedMarkdown old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _markdown = AgentMarkdown(widget.text);
  }

  @override
  Widget build(BuildContext context) => _markdown;
}

/// Format a turn duration as `12s`, `3m 05s`, or `1h 02m`.
String _formatWorked(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final m = d.inMinutes;
  if (m < 60) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${d.inHours}h ${(m % 60).toString().padLeft(2, '0')}m';
}

class _UserMessage extends StatefulWidget {
  const _UserMessage({
    required this.text,
    this.images = const <Uint8List>[],
    this.compact = false,
  });
  final String text;
  final List<Uint8List> images;

  /// Reduce vertical padding when this bubble serves as a sticky header.
  final bool compact;

  @override
  State<_UserMessage> createState() => _UserMessageState();
}

class _UserMessageState extends State<_UserMessage> {
  bool _expanded = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = widget.text.trim().isNotEmpty;
    final vpad = widget.compact
        ? const EdgeInsets.only(top: 6, bottom: 6)
        : const EdgeInsets.only(top: 12, bottom: 16);
    return Padding(
      padding: vpad,
      child: Align(
        alignment: Alignment.centerRight,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.panel2,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.images.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: (i < widget.images.length - 1 || hasText)
                            ? 8
                            : 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: Image.memory(
                            widget.images[i],
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  if (hasText)
                    LayoutBuilder(
                      builder: (ctx, inner) =>
                          _buildText(ctx, inner.maxWidth, colors),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, double maxWidth, AppColors colors) {
    final style = context.typo.body.copyWith(
      fontSize: 13.5,
      color: context.colors.text,
    );
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final overflows = tp.didExceedMaxLines;

    if (!overflows) return _MessageText(text: widget.text);

    if (_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _MessageText(text: widget.text),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => setState(() => _expanded = false),
            child: Icon(
              Icons.expand_less,
              size: 15,
              color: context.colors.text3,
            ),
          ),
        ],
      );
    }

    // Float the collapsed chevron over text on hover without consuming a row.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => setState(() {
          _expanded = true;
          _hovered = false;
        }),
        child: Stack(
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (_hovered)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.panel2.withValues(alpha: 0),
                        colors.panel2,
                      ],
                    ),
                  ),
                ),
              ),
            if (_hovered)
              Positioned(
                bottom: 2,
                right: 0,
                child: Icon(Icons.expand_more, size: 15, color: colors.text3),
              ),
          ],
        ),
      ),
    );
  }
}

/// Render `@<path>` mentions in a user bubble as file-type badges.
class _MessageText extends StatelessWidget {
  const _MessageText({required this.text});
  final String text;

  // Match `@` only at the start or after a space to avoid email addresses.
  static final RegExp _mention = RegExp(r'(?<![^\s])@(\S+)');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = context.typo.body.copyWith(fontSize: 13.5, color: colors.text);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _mention.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _FileBadge(name: _basename(m.group(1)!)),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }

  String _basename(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}

/// Render an inline mentioned-file badge with its type icon and name.
class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FileTypeIcon.file(name, size: 13),
          const SizedBox(width: 5),
          Text(
            name,
            style: context.typo.label.copyWith(
              fontSize: 12,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cap expanded reasoning or tool results and scroll overflow internally.
const double _kExpandMaxHeight = 240;

/// Toggle a collapsible body from a chevron header.
///
/// Open content respects [_kExpandMaxHeight] and scrolls when it exceeds the cap.
class _Expandable extends StatefulWidget {
  const _Expandable({
    required this.header,
    required this.body,
    required this.canExpand,
    required this.decoration,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
  });

  final Widget header;
  final Widget body;
  final bool canExpand;
  final BoxDecoration decoration;
  final EdgeInsets bodyPadding;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canExpand = widget.canExpand;
    return Container(
      width: double.infinity,
      decoration: widget.decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoverTap(
            onTap: canExpand
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Expanded(child: widget.header),
                if (canExpand)
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: colors.text3,
                    ),
                  ),
              ],
            ),
          ),
          if (_expanded && canExpand)
            Padding(
              padding: widget.bodyPadding,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kExpandMaxHeight),
                child: SingleChildScrollView(child: widget.body),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Expandable(
        canExpand: text.trim().isNotEmpty,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(7),
        ),
        bodyPadding: const EdgeInsets.fromLTRB(34, 0, 14, 12),
        header: Row(
          children: [
            Icon(Icons.psychology_outlined, size: 14, color: colors.text3),
            const SizedBox(width: 8),
            Text(
              'reasoning',
              style: context.typo.label.copyWith(
                color: colors.text3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        body: SelectableText(
          text,
          style: context.typo.body.copyWith(
            fontSize: 13,
            color: colors.text3,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.name,
    required this.args,
    required this.status,
    required this.resultText,
  });

  final String name;
  final RpcJsonObject args;
  final ToolProjectionStatus status;
  final String resultText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final done = status != ToolProjectionStatus.running;
    final isError = status == ToolProjectionStatus.error;
    final accent = isError ? colors.error : colors.ok;
    final argsText = args.values.isEmpty ? '' : jsonEncode(args.values);
    final hasResult = done && resultText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Expandable(
        canExpand: hasResult,
        decoration: BoxDecoration(
          color: colors.panel2,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(7),
        ),
        header: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? accent.withValues(alpha: 0.10)
                    : colors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: done
                  ? Icon(
                      isError ? Icons.close : Icons.check,
                      size: 14,
                      color: accent,
                    )
                  : CircularProgressIndicator(
                      size: 12,
                      strokeWidth: 1.6,
                      color: colors.accent,
                    ),
            ),
            const SizedBox(width: 10),
            Text(
              name,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                argsText,
                overflow: TextOverflow.ellipsis,
                style: context.typo.mono.copyWith(
                  fontSize: 12,
                  color: colors.text2,
                ),
              ),
            ),
          ],
        ),
        body: SelectableText(
          _clip(resultText, 20000),
          style: context.typo.mono.copyWith(
            fontSize: 11.5,
            color: colors.text3,
          ),
        ),
      ),
    );
  }

  String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}\n… (truncated)';
}

/// Render an extension `notify` event inline with severity color.
///
/// Maps 0 to info, 1 to warning, and 2 to error while preserving line breaks.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.message, required this.level});
  final String message;
  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (IconData icon, Color color) = switch (level) {
      2 => (Icons.error_outline, colors.error),
      1 => (Icons.warning_amber_rounded, colors.warn),
      _ => (Icons.info_outline, colors.text3),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.typo.label.copyWith(color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Render an interactive extension request for select, confirm, input, or editor.
///
/// Responds through [onRespond], then displays the chosen value.
class _UiRequestCard extends StatefulWidget {
  const _UiRequestCard({required this.entry, required this.onRespond});
  final UiRequestEntry entry;
  final UiResponder? onRespond;

  @override
  State<_UiRequestCard> createState() => _UiRequestCardState();
}

class _UiRequestCardState extends State<_UiRequestCard> {
  late final TextEditingController _input = TextEditingController(
    text: widget.entry.defaultValue ?? '',
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _respond(RpcUiResponse response, String label) =>
      widget.onRespond?.call(widget.entry.id, response, label);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    if (entry.resolved) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.check_circle_outline,
                size: 14,
                color: colors.text3,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.answerLabel == null
                    ? '${entry.title ?? "Request"} — answered'
                    : '${entry.title ?? "You chose"}: ${entry.answerLabel}',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.title != null && entry.title!.isNotEmpty)
            Text(
              entry.title!,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (entry.message != null && entry.message!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.message!,
              style: context.typo.label.copyWith(color: colors.text2),
            ),
          ],
          const SizedBox(height: 10),
          _controls(context),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              onPressed: () =>
                  _respond(const RpcUiCancelledResponse(), 'cancelled'),
              child: Text(
                'Cancel',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final entry = widget.entry;
    switch (entry.method) {
      case 'confirm':
        return Row(
          children: [
            _ChoiceButton(
              label: 'No',
              filled: false,
              onTap: () =>
                  _respond(const RpcUiConfirmationResponse(false), 'No'),
            ),
            const SizedBox(width: 8),
            _ChoiceButton(
              label: 'Yes',
              filled: true,
              onTap: () =>
                  _respond(const RpcUiConfirmationResponse(true), 'Yes'),
            ),
          ],
        );
      case 'input':
      case 'editor':
        return _InputRow(
          controller: _input,
          hint: entry.placeholder ?? 'Type your answer',
          onSubmit: () {
            final v = _input.text.trim();
            if (v.isEmpty) return;
            _respond(RpcUiValueResponse(v), v);
          },
        );
      case 'select':
      default:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in entry.options)
              _ChoiceButton(
                label: option,
                filled: false,
                onTap: () => _respond(RpcUiValueResponse(option), option),
              ),
          ],
        );
    }
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: filled ? colors.accent : colors.panel3,
      // Keep the accent fill on hover instead of fading it to panel3.
      hoverColor: filled ? colors.accent : colors.border2,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        label,
        style: context.typo.body.copyWith(
          fontSize: 13,
          color: filled ? colors.bg : colors.text,
          fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.hint,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (_) => onSubmit(),
            style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
            placeholder: Text(hint),
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(width: 8),
        _ChoiceButton(label: 'Send', filled: true, onTap: onSubmit),
      ],
    );
  }
}

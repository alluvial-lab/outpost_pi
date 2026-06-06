import 'dart:convert';

import 'package:cockpit/ui/cockpit/session/agent_entry.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_markdown.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Teto de largura do conteúdo do chat — em panes largas a conversa não estica
/// de ponta a ponta (folgado; alinhado à esquerda).
const double _kChatMaxWidth = 920;

/// Corpo do pane: o stream do agente (texto, raciocínio, tool calls, infos),
/// estilizado conforme o design (rp-p / rp-think / rp-tool / rp-usermsg).
class AgentTranscript extends StatelessWidget {
  const AgentTranscript({
    super.key,
    required this.entries,
    required this.controller,
    this.bottomPadding = 8,
  });

  final List<AgentEntry> entries;
  final ScrollController controller;

  /// Espaço extra no fim da lista para a conversa não ficar atrás do composer
  /// flutuante.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Mande um prompt para o agente começar.',
          style: context.typo.body.copyWith(color: context.colors.text3),
        ),
      );
    }
    // A scrollbar e a lista ocupam a largura inteira (scrollbar na borda do
    // pane); o **conteúdo** é centralizado com teto de largura via padding
    // horizontal calculado. Cada entrada preenche a coluna → alinhada à esquerda.
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = (constraints.maxWidth - _kChatMaxWidth) / 2;
        final hpad = extra > 26 ? extra : 26.0;
        return Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ScrollConfiguration(
            // Evita a scrollbar automática duplicar a nossa (sempre visível).
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: controller,
              padding: EdgeInsets.fromLTRB(hpad, 26, hpad, bottomPadding),
              itemCount: entries.length,
              itemBuilder: (context, index) => _EntryView(
                key: ValueKey(entries[index]),
                entry: entries[index],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({super.key, required this.entry});
  final AgentEntry entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry) {
      UserEntry(:final text) => _UserMessage(text: text),
      AssistantTextEntry(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: text.isEmpty
            ? Text(
                '…',
                style: context.typo.body.copyWith(
                  color: const Color(0xFFC9C9CF),
                ),
              )
            : AgentMarkdown(text),
      ),
      ThinkingEntry(:final text) => _ThinkingBlock(text: text),
      ToolEntry() => _ToolCard(tool: entry as ToolEntry),
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
              'Trabalhou por ${_formatWorked(duration)}',
              style: context.typo.label.copyWith(color: context.colors.text3),
            ),
          ],
        ),
      ),
    };
  }
}

/// Formata a duração de um turno: `12s` → `3m 05s` → `1h 02m`.
String _formatWorked(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final m = d.inMinutes;
  if (m < 60) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${d.inHours}h ${(m % 60).toString().padLeft(2, '0')}m';
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Balão flexível (encolhe pro conteúdo), alinhado à direita e limitado a
    // 75% da largura da coluna do chat.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
              child: SelectableText(
                text,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Limite de altura do conteúdo expandido (raciocínio / resultado de tool);
/// passou disso, rola por dentro.
const double _kExpandMaxHeight = 240;

/// Caixa expansível: header clicável (com chevron) + corpo colapsável que,
/// quando aberto, respeita [_kExpandMaxHeight] e rola se ultrapassar.
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
          InkWell(
            onTap: canExpand
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(7),
            child: Padding(
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
          color: const Color(0xFF131316),
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(7),
        ),
        bodyPadding: const EdgeInsets.fromLTRB(34, 0, 14, 12),
        header: Row(
          children: [
            Icon(Icons.psychology_outlined, size: 14, color: colors.text3),
            const SizedBox(width: 8),
            Text(
              'raciocínio',
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
  const _ToolCard({required this.tool});
  final ToolEntry tool;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tool.isError ? colors.error : colors.ok;
    final argsText = tool.args.isEmpty ? '' : jsonEncode(tool.args);
    final hasResult = tool.done && tool.resultText.isNotEmpty;

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
                color: tool.done
                    ? accent.withValues(alpha: 0.10)
                    : colors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: tool.done
                  ? Icon(
                      tool.isError ? Icons.close : Icons.check,
                      size: 14,
                      color: accent,
                    )
                  : SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: colors.accent,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Text(
              tool.toolName,
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
          _clip(tool.resultText, 20000),
          style: context.typo.mono.copyWith(
            fontSize: 11.5,
            color: colors.text3,
          ),
        ),
      ),
    );
  }

  String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}\n… (truncado)';
}

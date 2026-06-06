import 'dart:async';
import 'dart:math' as math;

import 'package:cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/ui/cockpit/session/agent_session.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/cockpit/widgets/model_picker.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Composer do design: input + toolbar (modelo · effort · aprovação · enviar).
/// Modelo e effort são reais (set_model / set_thinking_level); aprovação é
/// preferência da UI por enquanto.
class AgentComposer extends StatefulWidget {
  const AgentComposer({super.key, required this.session});
  final AgentSession session;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _focused = false;
  bool _hasText = false;

  // --- slash commands (/) — input inteiro começa com '/' ---
  String? _cmdQuery; // texto após '/', null = fora do modo comando
  bool _cmdSuppress = false;

  // --- menções de arquivo (@) — '@token' colado no cursor ---
  ({int start, String query})? _mention;
  List<String> _fileMatches = const <String>[];
  bool _fileSuppress = false;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  /// Índice destacado no overlay ativo (comando OU arquivo).
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  int get _cursor {
    final sel = _controller.selection;
    return sel.isValid ? sel.end : _controller.text.length;
  }

  bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t';

  void _onChanged() {
    final text = _controller.text;
    _hasText = text.trim().isNotEmpty;

    // 1) Comando tem precedência: input inteiro começa com '/'.
    if (text.startsWith('/')) {
      _mention = null;
      _fileMatches = const <String>[];
      if (_cmdSuppress) {
        _cmdQuery = null;
      } else {
        if (_cmdQuery != text.substring(1)) _index = 0;
        _cmdQuery = text.substring(1);
      }
      setState(() {});
      return;
    }
    _cmdSuppress = false;
    _cmdQuery = null;

    // 2) Menção de arquivo: '@token' antes do cursor.
    final mention = _activeMention(text, _cursor);
    if (mention == null) {
      _fileSuppress = false;
      _mention = null;
      _fileMatches = const <String>[];
    } else if (_fileSuppress) {
      _mention = null;
    } else {
      if (_mention?.query != mention.query) _index = 0;
      _mention = mention;
      _searchFiles(mention.query);
    }
    setState(() {});
  }

  /// Acha o `@token` imediatamente antes do cursor (precedido por início ou
  /// espaço, sem espaço até o cursor). `null` = não há menção ativa.
  ({int start, String query})? _activeMention(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    var i = cursor - 1;
    while (i >= 0) {
      final c = text[i];
      if (c == '@') {
        final prevOk = i == 0 || _isSpace(text[i - 1]);
        if (!prevOk) return null;
        final query = text.substring(i + 1, cursor);
        if (query.contains(RegExp(r'\s'))) return null;
        return (start: i, query: query);
      }
      if (_isSpace(c)) return null;
      i--;
    }
    return null;
  }

  void _searchFiles(String query) {
    _searchDebounce?.cancel();
    final vm = context.read<CockpitViewModel>();
    final cwd = widget.session.workingDirectory;
    final seq = ++_searchSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 120), () async {
      final results = await vm.searchFiles(cwd, query);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _fileMatches = results);
    });
  }

  // --- slash command data ---
  static const List<PiCommand> _builtins = <PiCommand>[
    PiCommand(name: 'new', description: 'Nova sessão — limpa a conversa'),
    PiCommand(name: 'compact', description: 'Compacta o contexto do agente'),
  ];

  /// Embutidos + comandos das extensions, **suprimindo os `/remote-pi`**.
  List<PiCommand> get _allCommands => <PiCommand>[
    ..._builtins,
    ...widget.session.commands.where(
      (c) => c.name != 'remote-pi' && !c.name.startsWith('remote-pi '),
    ),
  ];

  List<PiCommand> get _cmdMatches {
    final query = _cmdQuery;
    if (query == null) return const <PiCommand>[];
    final q = query.toLowerCase();
    return _allCommands
        .where((c) => c.name.toLowerCase().startsWith(q))
        .toList(growable: false);
  }

  bool _runBuiltin(String name) {
    switch (name) {
      case 'new':
        widget.session.startNewSession();
        return true;
      case 'compact':
        widget.session.compact();
        return true;
      default:
        return false;
    }
  }

  // --- overlays (comando OU arquivo; nunca os dois) ---
  bool get _cmdOpen => _cmdQuery != null && _cmdMatches.isNotEmpty;
  bool get _fileOpen => _mention != null && _fileMatches.isNotEmpty;
  bool get _overlayOpen => _cmdOpen || _fileOpen;
  int get _activeCount =>
      _cmdOpen ? _cmdMatches.length : (_fileOpen ? _fileMatches.length : 0);

  /// Itens do overlay ativo, já no formato do palette.
  List<_Suggest> get _suggestions {
    if (_cmdOpen) {
      return [
        for (final c in _cmdMatches)
          _Suggest(
            primary: '/${c.name}',
            secondary: c.description.isEmpty ? null : c.description,
          ),
      ];
    }
    if (_fileOpen) {
      return [
        for (final p in _fileMatches)
          _Suggest(
            primary: _basename(p),
            secondary: _dirname(p),
            icon: Icons.insert_drive_file_outlined,
          ),
      ];
    }
    return const <_Suggest>[];
  }

  String _basename(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? p : p.substring(i + 1);
  }

  String? _dirname(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? null : p.substring(0, i);
  }

  // --- teclado / aceitação ---
  void _onEnter() {
    if (_cmdOpen) {
      _acceptCommand(_index);
    } else if (_fileOpen) {
      _acceptFile(_index);
    } else {
      _submit();
    }
  }

  void _onSelectIndex(int i) {
    if (_cmdOpen) {
      _acceptCommand(i);
    } else if (_fileOpen) {
      _acceptFile(i);
    }
  }

  void _moveIndex(int delta) {
    final n = _activeCount;
    if (n == 0) return;
    setState(() => _index = (_index + delta + n) % n);
  }

  void _accept() => _onSelectIndex(_index);

  void _dismissOverlay() {
    setState(() {
      if (_cmdOpen) {
        _cmdSuppress = true;
        _cmdQuery = null;
      } else if (_fileOpen) {
        _fileSuppress = true;
        _mention = null;
        _fileMatches = const <String>[];
      }
    });
  }

  void _acceptCommand(int index) {
    final matches = _cmdMatches;
    if (matches.isEmpty) return;
    final cmd = matches[index.clamp(0, matches.length - 1)];
    _cmdSuppress = true; // setado antes de mexer no texto (o listener lê isso)
    final value = '/${cmd.name} ';
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _acceptFile(int index) {
    final mention = _mention;
    final matches = _fileMatches;
    if (mention == null || matches.isEmpty) return;
    final rel = matches[index.clamp(0, matches.length - 1)];
    final text = _controller.text;
    final before = text.substring(0, mention.start);
    final after = text.substring(_cursor);
    final inserted = '@$rel ';
    _fileSuppress = true;
    final newText = before + inserted + after;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (before + inserted).length),
    );
  }

  /// Insere `@<rel>` no cursor — drag-drop de um arquivo do painel Files.
  void _insertFileMention(String absolutePath) {
    final rel = _relativeTo(widget.session.workingDirectory, absolutePath);
    final text = _controller.text;
    final sel = _controller.selection;
    final offset = sel.isValid ? sel.end : text.length;
    final needsSpace = offset > 0 && !_isSpace(text[offset - 1]);
    final insert = '${needsSpace ? ' ' : ''}@$rel ';
    _fileSuppress = true;
    final newText = text.substring(0, offset) + insert + text.substring(offset);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
    _inputFocus.requestFocus();
  }

  /// Caminho de [toPath] relativo a [fromDir] (com `../` quando necessário).
  String _relativeTo(String fromDir, String toPath) {
    final from = fromDir.split('/').where((s) => s.isNotEmpty).toList();
    final to = toPath.split('/').where((s) => s.isNotEmpty).toList();
    var i = 0;
    while (i < from.length && i < to.length && from[i] == to[i]) {
      i++;
    }
    final parts = <String>[
      ...List<String>.filled(from.length - i, '..'),
      ...to.sublist(i),
    ];
    return parts.isEmpty ? '.' : parts.join('/');
  }

  void _submit() {
    final session = widget.session;
    if (session.isStreaming) {
      session.stop();
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _cmdSuppress = false;
    _cmdQuery = null;
    _fileSuppress = false;
    _mention = null;
    _fileMatches = const <String>[];
    // Embutido (/new, /compact) → RPC dedicado; senão vai como prompt (texto
    // normal ou comando de extension, ex.: /remote-pi setup).
    if (text.startsWith('/') && _runBuiltin(text.substring(1).split(' ').first)) {
      return;
    }
    session.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final streaming = session.isStreaming;
    final controlsEnabled = session.isAlive && !streaming;

    // Alvo de drop — arrastar um arquivo do painel Files vira `@<rel>` no input.
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _insertFileMention(d.data),
      builder: (context, candidate, rejected) {
        final dragging = candidate.isNotEmpty;
        final borderColor = (_focused || dragging)
            ? colors.accent
            : (controlsEnabled ? colors.border2 : colors.border);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            boxShadow: [
              // Elevação — o composer paira sobre o transcript.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              if (_focused || dragging)
                BoxShadow(
                  color: colors.accentSoft,
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Overlay de sugestões (comandos `/` ou arquivos `@`) — acima do
              // input (a caixa cresce pra cima).
              if (_overlayOpen)
                _SuggestPalette(
                  items: _suggestions,
                  selected: _index,
                  onSelect: _onSelectIndex,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Focus(
                  onFocusChange: (f) => setState(() => _focused = f),
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.enter): _onEnter,
                      if (_overlayOpen) ...{
                        const SingleActivator(LogicalKeyboardKey.arrowDown):
                            () => _moveIndex(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                            _moveIndex(-1),
                        const SingleActivator(LogicalKeyboardKey.tab): _accept,
                        const SingleActivator(LogicalKeyboardKey.escape):
                            _dismissOverlay,
                      },
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocus,
                      minLines: 2,
                      maxLines: 6,
                      style: context.typo.body.copyWith(
                        fontSize: 13.5,
                        color: colors.text,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText:
                            'Mensagem pro agente, use @arquivos ou /comandos',
                        hintStyle: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
            child: Row(
              children: [
                _BarIcon(icon: Icons.add, tooltip: 'Anexar', onTap: () {}),
                _ModelChip(session: session, enabled: controlsEnabled),
                // Effort só pra modelos com raciocínio (senão o pi não usa).
                if (session.model?.reasoning ?? false)
                  _EffortChip(session: session, enabled: controlsEnabled),
                // Bolinha de uso do contexto (enche conforme a janela enche).
                _ContextGauge(session: session),
                const Spacer(),
                // Spinner + cronômetro do turno (só enquanto trabalha).
                _TurnIndicator(session: session),
                _SendButton(
                  streaming: streaming,
                  ready: _hasText,
                  onTap: _submit,
                ),
              ],
            ),
          ),
            ],
          ),
        );
      },
    );
  }
}

/// Item de uma sugestão do overlay (comando ou arquivo).
class _Suggest {
  const _Suggest({required this.primary, this.secondary, this.icon});
  final String primary; // mono
  final String? secondary; // dim, à direita
  final IconData? icon;
}

/// Lista de sugestões sobre o input (comandos `/` ou arquivos `@`). Realça o
/// item selecionado (setas) e aceita por clique. Rola se passar da altura máxima.
class _SuggestPalette extends StatelessWidget {
  const _SuggestPalette({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<_Suggest> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 5),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final active = i == selected;
          return InkWell(
            onTap: () => onSelect(i),
            canRequestFocus: false, // não rouba o foco do input
            child: Container(
              color: active ? colors.panel3 : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(
                      item.icon,
                      size: 13,
                      color: active ? colors.accentText : colors.text3,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      item.primary,
                      overflow: TextOverflow.ellipsis,
                      style: typo.mono.copyWith(
                        fontSize: 12.5,
                        color: active ? colors.accentText : colors.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (item.secondary != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.secondary!,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: typo.label.copyWith(color: colors.text3),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: iconColor ?? colors.text3),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: context.typo.label.copyWith(
                    fontSize: 12.5,
                    color: colors.text2,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 13, color: colors.text4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.session, required this.enabled});
  final AgentSession session;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final model = session.model;
    return _Chip(
      icon: Icons.auto_awesome,
      iconColor: context.colors.accentText,
      label: model?.name ?? 'modelo',
      enabled: enabled && session.models.isNotEmpty,
      onTap: () async {
        final picked = await showModelPicker(
          context,
          models: session.models,
          current: model,
        );
        if (picked != null) session.changeModel(picked);
      },
    );
  }
}

class _EffortChip extends StatelessWidget {
  const _EffortChip({required this.session, required this.enabled});
  final AgentSession session;
  final bool enabled;

  Future<void> _show(BuildContext context) async {
    // Níveis que ESTE modelo aceita (derivados do thinkingLevelMap dele).
    final levels = ThinkingLevel.availableFor(
      session.model?.thinkingLevelMap ?? const <String, String?>{},
    );
    final current = session.thinking;
    final level = await showAppMenu<ThinkingLevel>(
      context,
      minWidth: 170,
      items: [
        for (final l in levels)
          AppMenuItem(
            value: l,
            label: l.label,
            icon: Icons.psychology_alt_outlined,
            selected: l == current,
          ),
      ],
    );
    if (level != null) session.changeThinking(level);
  }

  @override
  Widget build(BuildContext context) {
    return _Chip(
      icon: Icons.psychology_alt_outlined,
      label: session.thinking.label,
      enabled: enabled,
      onTap: () => _show(context),
    );
  }
}

/// Spinner + cronômetro do turno enquanto o agente trabalha (streaming). Conta
/// em segundos e passa pra minutos/horas. Some quando o turno termina.
class _TurnIndicator extends StatefulWidget {
  const _TurnIndicator({required this.session});
  final AgentSession session;

  @override
  State<_TurnIndicator> createState() => _TurnIndicatorState();
}

class _TurnIndicatorState extends State<_TurnIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _sync();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _ticker?.cancel();
    super.dispose();
  }

  void _onSession() {
    _sync();
    if (mounted) setState(() {});
  }

  /// Liga/desliga o tick de 1s conforme o turno está rodando.
  void _sync() {
    final active =
        widget.session.isStreaming && widget.session.turnStartedAt != null;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _format(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = d.inMinutes;
    if (m < 60) {
      return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inHours}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final start = session.turnStartedAt;
    if (!session.isStreaming || start == null) return const SizedBox.shrink();
    final colors = context.colors;
    final elapsed = DateTime.now().difference(start);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _format(elapsed),
            style: context.typo.mono.copyWith(
              fontSize: 11.5,
              color: colors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bolinha de uso do contexto: um disco que enche conforme a janela de contexto
/// se aproxima do limite (verde→âmbar→vermelho). Tooltip mostra a porcentagem.
/// `percent` vem na escala 0–100 (ver [ContextUsage]).
class _ContextGauge extends StatelessWidget {
  const _ContextGauge({required this.session});
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final percent = session.contextUsage?.percent;
    if (percent == null) return const SizedBox.shrink();
    final colors = context.colors;
    final fraction = (percent / 100).clamp(0.0, 1.0);
    final fill = fraction >= 0.9
        ? colors.error
        : (fraction >= 0.75 ? colors.warn : colors.accentText);
    final pct = percent.toStringAsFixed(percent < 10 ? 1 : 0);
    return Tooltip(
      message: 'Contexto: $pct% da janela',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              fill: fill,
              track: colors.border2,
              ring: colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.ring,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Fundo (vazio).
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.fill,
    );

    // Preenchimento: fatia de pizza crescendo do topo no sentido horário.
    if (fraction > 0) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          fraction * 2 * math.pi,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }

    // Contorno (mais visível).
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.fill != fill;
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.ready,
    required this.onTap,
  });

  final bool streaming;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color bg;
    final Color fg;
    final IconData icon;
    if (streaming) {
      bg = colors.text;
      fg = colors.bg;
      icon = Icons.stop;
    } else if (ready) {
      bg = colors.accent;
      fg = Colors.white;
      icon = Icons.arrow_upward;
    } else {
      bg = Colors.transparent;
      fg = colors.text3;
      icon = Icons.arrow_upward;
    }
    return Tooltip(
      message: streaming ? 'Parar' : 'Enviar',
      child: Material(
        color: bg,
        shape: CircleBorder(
          side: ready || streaming
              ? BorderSide.none
              : BorderSide(color: colors.border2, width: 1.5),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 15, color: fg),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/workspace_projection.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'realizes file viewers, owns watcher debounce, and disposes it',
    () async {
      final reader = _FileReader(<String, FileView>{
        '/workspace/lib/main.dart': const FileViewText('one', language: 'dart'),
      });
      var changes = 0;
      final projection = _projection(
        reader: reader,
        onChanged: () => changes++,
      );
      final project = _project();

      final realized = await projection.realize(
        const WorkspaceTab.viewer(
          id: 'v1',
          filePath: '/workspace/lib/main.dart',
        ),
        project,
      );

      expect(realized, isTrue);
      final viewer = projection.item('v1') as FileViewerSession;
      expect((viewer.view as FileViewText).text, 'one');

      reader.views['/workspace/lib/main.dart'] = const FileViewText(
        'two',
        language: 'dart',
      );
      reader.emit('/workspace/lib/main.dart');
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect((viewer.view as FileViewText).text, 'two');
      expect(changes, greaterThan(0));

      final closing = projection.disposeTab('v1');
      expect(projection.item('v1'), isNull);
      await closing;
      reader.views['/workspace/lib/main.dart'] = const FileViewText(
        'three',
        language: 'dart',
      );
      reader.emit('/workspace/lib/main.dart');
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(projection.item('v1'), isNull);
      expect((viewer.view as FileViewText).text, 'two');
      await projection.dispose();
    },
  );

  test(
    'surfaces watcher and reload failures to the projection owner',
    () async {
      final path = '/workspace/lib/main.dart';
      final reader = _FileReader(<String, FileView>{
        path: const FileViewText('one', language: 'dart'),
      });
      final failures = <(String, Object)>[];
      final projection = _projection(
        reader: reader,
        onFileWatchError: (path, error, _) => failures.add((path, error)),
      );

      await projection.createViewer(id: 'v1', projectId: 'p1', path: path);
      reader.emitError(path, const FileSystemException('watch failed'));
      await pumpEventQueue();

      expect(failures, hasLength(1));
      expect(failures.single.$1, path);
      expect(failures.single.$2, isA<FileSystemException>());

      reader.readFailures[path] = const FileSystemException('reload failed');
      reader.emit(path);
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(failures, hasLength(2));
      expect(failures.last.$2, isA<FileSystemException>());
      await projection.dispose();
    },
  );

  test('projects live pane items back to workspace tab descriptors', () async {
    final projection = _projection();
    final project = _project();

    final terminal = projection.createTerminal(
      id: 't1',
      projectId: project.id,
      workingDirectory: '/workspace/tools',
      title: 'tools',
    );
    final empty = projection.createEmpty(id: 'a1', projectId: project.id);
    final viewer = await projection.createViewer(
      id: 'v1',
      projectId: project.id,
      path: '/workspace/README.md',
    );

    expect(
      projection.descriptorFor(terminal, project),
      isA<WorkspaceTab>()
          .having((tab) => tab.kind, 'kind', WorkspaceTabKind.terminal)
          .having((tab) => tab.relativeSubpath, 'relativeSubpath', 'tools')
          .having((tab) => tab.title, 'title', 'tools'),
    );
    expect(
      projection.descriptorFor(empty, project),
      isA<WorkspaceTab>().having(
        (tab) => tab.kind,
        'kind',
        WorkspaceTabKind.empty,
      ),
    );
    expect(
      projection.descriptorFor(viewer!, project),
      isA<WorkspaceTab>()
          .having((tab) => tab.kind, 'kind', WorkspaceTabKind.viewer)
          .having((tab) => tab.filePath, 'filePath', '/workspace/README.md'),
    );

    await projection.dispose();
  });

  test('realizes agent descriptors and projects them back unchanged', () async {
    final rpcFactory = _RpcFactory();
    final projection = _projection(rpcFactory: rpcFactory);
    final project = _project();
    const tab = WorkspaceTab.agent(
      id: 'a1',
      relativeSubpath: 'packages/app',
      title: 'Agent',
      sessionPath: '/sessions/a1.jsonl',
      autoStartRelay: true,
      preferredModelId: 'gpt-test',
      preferredThinking: ThinkingLevel.high,
    );

    final realized = await projection.realizeAgent(tab, project);

    expect(realized, isTrue);
    final agent = projection.item('a1');
    expect(agent, isA<AgentSession>());
    final session = agent! as AgentSession;
    expect(session.workingDirectory, '/workspace/packages/app');
    expect(session.sessionPath, '/sessions/a1.jsonl');
    expect(session.autoStartRelay, isTrue);
    expect(session.preferredModelId, 'gpt-test');
    expect(session.preferredThinking, ThinkingLevel.high);
    expect(
      rpcFactory.lastGateway?.spawnWorkingDirectory,
      session.workingDirectory,
    );
    expect(rpcFactory.lastGateway?.spawnSessionId, '/sessions/a1.jsonl');
    expect(
      rpcFactory.lastGateway?.spawnEnvironment?['OUTPOST_PI_DIRECT_CONFIG'],
      contains('"auto_start_relay":true'),
    );
    expect(
      projection.descriptorForAgent(session, project).kind,
      WorkspaceTabKind.agent,
    );
    expect(
      projection.descriptorForAgent(session, project).sessionPath,
      '/sessions/a1.jsonl',
    );
    expect(
      projection.descriptorForAgent(session, project).preferredModelId,
      'gpt-test',
    );
    expect(
      projection.descriptorForAgent(session, project).preferredThinking,
      ThinkingLevel.high,
    );
    await projection.dispose();
  });

  test('keeps placeholders distinct from unbooted agent descriptors', () async {
    final projection = _projection();
    final project = _project();

    final empty = projection.createEmpty(id: 'a-empty', projectId: project.id);
    final agent = projection.createAgent(
      id: 'a-real',
      project: project,
      workingDirectory: project.path,
      title: 'Real',
      preferredModelId: 'gpt-test',
    );

    expect(
      projection.descriptorFor(empty, project).kind,
      WorkspaceTabKind.empty,
    );
    expect(
      projection.descriptorFor(agent, project).kind,
      WorkspaceTabKind.agent,
    );
    expect(
      projection.descriptorFor(agent, project).preferredModelId,
      'gpt-test',
    );
    await projection.dispose();
  });

  test('captures session path through descriptor-change callback', () async {
    final changedProjects = <String>[];
    final projection = _projection(
      history: _History(<SessionInfo>[
        SessionInfo(
          path: '/sessions/new.jsonl',
          id: 'new',
          modifiedAt: DateTime(2026, 2),
        ),
      ]),
      onDescriptorChanged: changedProjects.add,
    );
    final project = _project();
    final agent = AgentSession(
      id: 'a1',
      projectId: project.id,
      workingDirectory: project.path,
      factory: _RpcFactory(),
      title: 'Agent',
    )..sessionBaseline = <String>{'/sessions/old.jsonl'};

    await projection.captureSessionPath(agent);

    expect(agent.sessionPath, '/sessions/new.jsonl');
    expect(changedProjects, <String>[project.id]);
    expect(
      projection.descriptorForAgent(agent, project).sessionPath,
      '/sessions/new.jsonl',
    );
    await agent.close();
    await projection.dispose();
  });

  test(
    'refreshes document descriptors without mutating the document',
    () async {
      final projection = _projection();
      final project = _project();
      await projection.createViewer(
        id: 'v1',
        projectId: project.id,
        path: '/workspace/current.md',
      );
      final document = WorkspaceDocument(
        projectId: project.id,
        focusedPaneId: 'main',
        root: const LeafPane(id: 'main', tabs: <String>['v1'], active: 'v1'),
        tabs: const <String, WorkspaceTab>{
          'v1': WorkspaceTab.viewer(id: 'v1', filePath: '/workspace/stale.md'),
        },
      );

      final refreshed = projection.documentWithLiveTabs(project, document);

      expect(document.tabs['v1']!.filePath, '/workspace/stale.md');
      expect(refreshed.tabs['v1']!.filePath, '/workspace/current.md');
      await projection.dispose();
    },
  );

  test('disposeTab removes immediately and awaits agent teardown', () async {
    final rpcFactory = _RpcFactory();
    final projection = _projection(rpcFactory: rpcFactory);
    final project = _project();
    await projection.realizeAgent(
      const WorkspaceTab.agent(id: 'a1', relativeSubpath: '', title: 'Agent'),
      project,
    );
    final gateway = rpcFactory.lastGateway!;
    final releaseKill = Completer<void>();
    gateway.killGate = releaseKill;
    var completed = false;

    final closing = projection.disposeTab('a1')..then((_) => completed = true);

    expect(projection.item('a1'), isNull);
    await pumpEventQueue();
    expect(gateway.killCalls, 1);
    expect(gateway.disposeCalls, 0);
    expect(completed, isFalse);

    releaseKill.complete();
    await closing;

    expect(gateway.disposeCalls, 1);
    expect(completed, isTrue);
    await projection.dispose();
  });

  test(
    'disposeTab invalidates agent boot blocked on session history',
    () async {
      final historyGate = Completer<List<SessionInfo>>();
      final history = _History(const <SessionInfo>[], historyGate);
      final rpcFactory = _RpcFactory();
      final asyncErrors = <Object>[];

      await runZonedGuarded(() async {
        final projection = _projection(
          rpcFactory: rpcFactory,
          history: history,
        );
        final agent = projection.createAgent(
          id: 'a1',
          project: _project(),
          workingDirectory: '/workspace',
        );
        var notifications = 0;
        agent.addListener(() => notifications++);
        var completed = false;

        final closing = projection.disposeTab('a1')
          ..then((_) => completed = true);

        expect(history.calls, 1);
        expect(projection.item('a1'), isNull);
        await closing;
        expect(completed, isTrue);
        final notificationsAtClose = notifications;

        historyGate.complete(const <SessionInfo>[]);
        await pumpEventQueue();

        expect(notifications, notificationsAtClose);
        expect(rpcFactory.lastGateway, isNull);
        await projection.dispose();
      }, (error, _) => asyncErrors.add(error));

      expect(asyncErrors, isEmpty);
    },
  );

  test(
    'project and projection disposal await every terminal in order',
    () async {
      final terminalFactory = _TerminalFactory();
      final projection = _projection(terminalFactory: terminalFactory);
      final project = _project();
      projection
        ..createTerminal(
          id: 't1',
          projectId: project.id,
          workingDirectory: project.path,
        )
        ..createTerminal(
          id: 't2',
          projectId: project.id,
          workingDirectory: project.path,
        );
      final projectGates = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
      ];
      for (var i = 0; i < projectGates.length; i++) {
        terminalFactory.gateways[i].killGate = projectGates[i];
      }
      final document = WorkspaceDocument(
        projectId: project.id,
        focusedPaneId: 'main',
        root: const LeafPane(
          id: 'main',
          tabs: <String>['t1', 't2'],
          active: 't1',
        ),
        tabs: const <String, WorkspaceTab>{
          't1': WorkspaceTab.terminal(
            id: 't1',
            relativeSubpath: '',
            title: 'Terminal 1',
          ),
          't2': WorkspaceTab.terminal(
            id: 't2',
            relativeSubpath: '',
            title: 'Terminal 2',
          ),
        },
      );
      var projectDisposed = false;

      final projectClosing = projection.disposeProject(document)
        ..then((_) => projectDisposed = true);

      expect(projection.item('t1'), isNull);
      expect(projection.item('t2'), isNull);
      await pumpEventQueue();
      for (final gateway in terminalFactory.gateways) {
        expect(gateway.lifecycle, <String>['cancel-output', 'kill']);
      }
      expect(projectDisposed, isFalse);
      projectGates.first.complete();
      await pumpEventQueue();
      expect(projectDisposed, isFalse);
      projectGates.last.complete();
      await projectClosing;
      expect(projectDisposed, isTrue);

      projection
        ..createTerminal(
          id: 't3',
          projectId: project.id,
          workingDirectory: project.path,
        )
        ..createTerminal(
          id: 't4',
          projectId: project.id,
          workingDirectory: project.path,
        );
      final projectionGates = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
      ];
      for (var i = 0; i < projectionGates.length; i++) {
        terminalFactory.gateways[i + 2].killGate = projectionGates[i];
      }
      var projectionDisposed = false;

      final allClosing = projection.dispose()
        ..then((_) => projectionDisposed = true);

      expect(projection.item('t3'), isNull);
      expect(projection.item('t4'), isNull);
      await pumpEventQueue();
      expect(projectionDisposed, isFalse);
      projectionGates.first.complete();
      await pumpEventQueue();
      expect(projectionDisposed, isFalse);
      projectionGates.last.complete();
      await allClosing;
      expect(projectionDisposed, isTrue);
    },
  );
}

WorkspaceProjection _projection({
  _RpcFactory? rpcFactory,
  _TerminalFactory? terminalFactory,
  _FileReader? reader,
  _History? history,
  void Function()? onChanged,
  void Function(String projectId)? onDescriptorChanged,
  WorkspaceProjectionFileWatchError? onFileWatchError,
}) {
  return WorkspaceProjection(
    rpcFactory: rpcFactory ?? _RpcFactory(),
    terminalFactory: terminalFactory ?? _TerminalFactory(),
    fileReader: reader ?? _FileReader(),
    history: history ?? _History(),
    notifier: _Notifier(),
    lsp: LspServerPool(_LspFactory()),
    onFileWatchError: onFileWatchError ?? (_, _, _) {},
    onChanged: onChanged,
    onDescriptorChanged: onDescriptorChanged,
  );
}

Project _project() => Project(
  id: 'p1',
  name: 'Workspace',
  path: '/workspace',
  colorValue: 0xFF000000,
  createdAt: DateTime(2026),
);

final class _FileReader implements FileReader {
  _FileReader([Map<String, FileView>? initial])
    : views = initial ?? <String, FileView>{};

  final Map<String, FileView> views;
  final Map<String, StreamController<void>> _controllers =
      <String, StreamController<void>>{};

  @override
  Future<FileView> read(String path) async {
    final failure = readFailures[path];
    if (failure != null) throw failure;
    return views[path] ?? FileViewText('content for $path');
  }

  @override
  Future<bool> write(String path, String content) async {
    views[path] = FileViewText(content);
    return true;
  }

  @override
  Stream<void> watch(String path) =>
      _controllers.putIfAbsent(path, StreamController<void>.broadcast).stream;

  final Map<String, Object> readFailures = <String, Object>{};

  void emit(String path) => _controllers[path]?.add(null);

  void emitError(String path, Object error) =>
      _controllers[path]?.addError(error, StackTrace.current);
}

final class _Notifier implements Notifier {
  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {}

  @override
  Future<void> init() async {}
}

final class _History implements SessionHistory {
  _History([this.sessions = const <SessionInfo>[], this.gate]);

  final List<SessionInfo> sessions;
  final Completer<List<SessionInfo>>? gate;
  var calls = 0;

  @override
  Future<List<SessionInfo>> sessionsFor(
    String cwd, {
    bool withTitle = false,
  }) async {
    calls++;
    return gate == null ? sessions : await gate!.future;
  }
}

final class _TerminalFactory implements TerminalGatewayFactory {
  final gateways = <_TerminalGateway>[];

  @override
  TerminalGateway create() {
    final gateway = _TerminalGateway();
    gateways.add(gateway);
    return gateway;
  }
}

final class _TerminalGateway implements TerminalGateway {
  _TerminalGateway() {
    _output = StreamController<List<int>>.broadcast(
      onCancel: () => lifecycle.add('cancel-output'),
    );
  }

  late final StreamController<List<int>> _output;
  final lifecycle = <String>[];
  Completer<void>? killGate;

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  Future<void> kill() async {
    lifecycle.add('kill');
    await killGate?.future;
    await _output.close();
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  }) {}

  @override
  void write(List<int> data) {}
}

final class _RpcFactory implements RpcGatewayFactory {
  _RpcGateway? lastGateway;

  @override
  RpcProcessGateway create() => lastGateway = _RpcGateway();
}

final class _RpcGateway implements RpcProcessGateway {
  final _events = StreamController<RpcEvent>.broadcast();
  String? spawnWorkingDirectory;
  Map<String, String>? spawnEnvironment;
  String? spawnSessionId;
  Completer<void>? killGate;
  var killCalls = 0;
  var disposeCalls = 0;

  @override
  Stream<RpcEvent> get events => _events.stream;

  @override
  bool get isRunning => false;

  @override
  String? get workingDirectory => null;

  @override
  Future<Result<void, RpcError>> abort() async => const Success(null);

  @override
  Future<Result<List<PiModel>, RpcError>> availableModels() async =>
      const Success([]);

  @override
  Future<Result<void, RpcError>> compact() async => const Success(null);

  @override
  Future<Result<List<PiCommand>, RpcError>> commands() async =>
      const Success([]);

  @override
  void dispose() {
    disposeCalls++;
    unawaited(_events.close());
  }

  @override
  Future<Result<List<CockpitTranscriptEvent>, RpcError>> getMessages({
    required String sessionId,
  }) async => const Success([]);

  @override
  Future<Result<ContextUsage?, RpcError>> sessionStats() async =>
      const Success(null);

  @override
  Future<Result<AgentSnapshot, RpcError>> state() async => const Success(
    AgentSnapshot(
      model: null,
      thinkingLevel: ThinkingLevel.off,
      turn: AgentTurnProjection.idle,
    ),
  );

  @override
  Future<void> kill() async {
    killCalls++;
    await killGate?.future;
  }

  @override
  Future<Result<void, RpcError>> newSession() async => const Success(null);

  @override
  Future<Result<void, RpcError>> respondUi(
    String id,
    RpcUiResponse response,
  ) async => const Success(null);

  @override
  Future<Result<void, RpcError>> sendControl(PiControlCommand command) async =>
      const Success(null);

  @override
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  }) async => const Success(null);

  @override
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level) async =>
      const Success(null);

  @override
  Future<Result<PiModel, RpcError>> setModel(PiModel model) async =>
      Success(model);

  @override
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  }) async {
    spawnWorkingDirectory = workingDirectory;
    spawnEnvironment = environment;
    spawnSessionId = sessionId;
    return const Success(null);
  }

  @override
  Future<Result<void, RpcError>> switchSession(String sessionPath) async =>
      const Success(null);
}

final class _LspFactory implements LspClientFactory {
  @override
  LspClient create({required LspServerSpec spec, required String rootPath}) =>
      _LspClient(rootPath);
}

final class _LspClient implements LspClient {
  _LspClient(this.rootPath);
  final _diagnostics = StreamController<LspDiagnosticsBatch>.broadcast();

  @override
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  @override
  bool get isRunning => false;

  @override
  final String rootPath;

  @override
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  }) async {}

  @override
  Future<void> didClose({required String path}) async {}

  @override
  Future<void> didOpen({required String path, required String text}) async {}

  @override
  void dispose() => unawaited(_diagnostics.close());

  @override
  Future<void> kill() async {}

  @override
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  ) async => const Success(null);

  @override
  Future<Result<void, LspError>> start() async => const Success(null);
}

import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/app_launcher_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_searcher_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_system_mutator_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_system_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/folder_lister_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_status_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/session_history_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/worktree_manager_impl.dart';
import 'package:cockpit/app/core/data/hive_box_opener.dart';
import 'package:cockpit/app/cockpit/data/notifications/local_notifier.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_project_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process_factory.dart';
import 'package:cockpit/app/cockpit/data/setup/environment_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/terminal/pty_terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/data/update/auto_updater_self_updater.dart';
import 'package:cockpit/app/cockpit/data/update/noop_self_updater.dart';
import 'package:cockpit/app/cockpit/data/update/update_checker_impl.dart';
import 'package:cockpit/app/cockpit/data/update/url_opener_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/update_target.dart';
import 'package:cockpit/app/cockpit/ui/cockpit_page.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Feature **Cockpit** — the shell (home, `path: '/'`). Registers the shell's
/// infra binds (filesystem, RPC, terminal, repos, setup, update) and declares
/// the `/` route with the 3 page-scoped ViewModels.
///
/// **Async bootstrap (flutter_modular idiom):** the builder is a `Future` and
/// opens its OWN async dependencies — Hive boxes, app version, notifier —
/// capturing them in the closure (private box → `addInstance(HiveX(box))`).
/// So `main` doesn't thread these values: call ONCE and compose the returned
/// module (dedup is by identity).
///
/// **Cross-module resolution (flutter_modular >= 7.1.0):** binds that depend
/// on `PiSpawnConfig` use `.new` and resolve the config **upward** from core
/// (root-owned) — which is why the builder no longer takes `config`. The Hive
/// boxes, however, still require the async bootstrap above (there is no async
/// bind).
///
/// Since the shell lives at `/` and Settings is **stacked** on top (not
/// replacing), the `/` route never leaves the stack during normal navigation →
/// these feature-scoped binds effectively live for the whole app lifetime.
Future<Module> buildCockpitModule() async {
  // Async bootstrap: opens its own boxes (private in the closure), resolves the
  // version, and starts the notifier. `Hive.initFlutter` already ran in `main`.
  final projectBox = await openHiveBoxWithRetry<dynamic>(
    HiveProjectRepository.boxName,
  );
  final layoutBox = await openHiveBoxWithRetry<dynamic>(
    HiveWorkspaceLayoutStore.boxName,
  );
  // Dismissed updates live in the settings box (same as SettingsController);
  // `openBox` is idempotent → returns the instance already opened by `main`.
  final settingsBox = await openHiveBoxWithRetry<dynamic>(
    HiveSettingsStore.boxName,
  );
  final appVersion = (await PackageInfo.fromPlatform()).version;

  // OS notifications — init asks for permission; failure must not crash the boot.
  final notifier = LocalNotifier();
  try {
    await notifier.init();
  } catch (error) {
    debugPrint('Failed to start notifications: $error');
  }

  return createModule(
    path: '/',
    register: (c) {
      c
        ..addInstance<ProjectRepository>(HiveProjectRepository(projectBox))
        ..addInstance<WorkspaceLayoutStore>(HiveWorkspaceLayoutStore(layoutBox))
        ..addInstance<DismissedUpdateStore>(
          HiveDismissedUpdateStore(settingsBox),
        )
        // Depend on PiSpawnConfig → `.new` resolves upward from core (>= 7.1.0).
        ..addLazySingleton<RpcGatewayFactory>(PiRpcProcessFactory.new)
        ..addLazySingleton<EnvironmentInstaller>(EnvironmentInstallerImpl.new)
        ..addInstance<FolderLister>(const FolderListerImpl())
        ..addInstance<FileSystemReader>(const FileSystemReaderImpl())
        ..addInstance<FileSystemMutator>(const FileSystemMutatorImpl())
        ..addInstance<FileReader>(const FileReaderImpl())
        ..addInstance<FileSearcher>(FileSearcherImpl())
        ..addInstance<GitStatusReader>(GitStatusReaderImpl())
        ..addInstance<WorktreeManager>(WorktreeManagerImpl())
        ..addInstance<SessionHistory>(const SessionHistoryImpl())
        ..addInstance<TerminalGatewayFactory>(const PtyTerminalGatewayFactory())
        ..addInstance<AppLauncherGateway>(const AppLauncherImpl())
        ..addInstance<Notifier>(notifier)
        ..addInstance<UpdateChecker>(const UpdateCheckerImpl())
        ..addInstance<UrlOpener>(const UrlOpenerImpl())
        ..addInstance<UpdateTarget>(_updateTarget(appVersion))
        // Native self-update remains disabled until appcasts are published
        // and deployed; the updater is Noop on all platforms.
        ..addInstance<SelfUpdater>(_buildSelfUpdater(_updateTarget(appVersion)))
        ..route(
          '/',
          // Page-scoped ViewModels via tear-off `.new` → auto_injector resolves
          // the constructor from the binds above. The `init()`/`check()` (which
          // used to chain in the factory) now run in `CockpitPage.initState`.
          provide: (s) => s
            ..addChangeNotifier<CockpitViewModel>(CockpitViewModel.new)
            ..addChangeNotifier<SetupViewModel>(SetupViewModel.new)
            ..addChangeNotifier<UpdateViewModel>(UpdateViewModel.new),
          child: (context, state) => const CockpitPage(),
        );
    },
  );
}

/// The current machine's [UpdateTarget]: app version + platform/format/arch of
/// the manifest. Native appcasts are not configured until those feeds are
/// published/deployed.
/// macOS → dmg/universal; Windows → exe/x64; Linux → deb/(arm64|x64).
UpdateTarget _updateTarget(String version) {
  if (Platform.isMacOS) {
    return UpdateTarget(
      version: version,
      platform: 'macos',
      format: 'dmg',
      arch: 'universal',
    );
  }
  if (Platform.isWindows) {
    return UpdateTarget(
      version: version,
      platform: 'windows',
      format: 'exe',
      arch: 'x64',
    );
  }
  final arch = Platform.version.toLowerCase().contains('arm') ? 'arm64' : 'x64';
  return UpdateTarget(
    version: version,
    platform: 'linux',
    format: 'deb',
    arch: arch,
  );
}

/// Builds the [SelfUpdater]. With no appcast configured, [NoopSelfUpdater]
/// leaves the `UpdateViewModel` on the manual notify + download path.
SelfUpdater _buildSelfUpdater(UpdateTarget target) {
  final feed = target.selfUpdateFeedUrl;
  if (feed == null) return const NoopSelfUpdater();
  return AutoUpdaterSelfUpdater(feedUrl: feed);
}

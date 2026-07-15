import 'package:cockpit/app/cockpit/cockpit_module.dart';
import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/settings/settings_module.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Root module — **composition only**. It is the app's coupling map: which
/// modules exist and how they connect. Each submodule declares its own `path`
/// (or the absence of one, in core's case), so here it's just `module(...)`.
///
/// `Future` because `cockpit` does async bootstrap (opens its own Hive boxes).
/// The only threaded value is [PiSpawnConfig]: it lives in core (root-owned) and
/// the features resolve it **upward**; the other async bits (boxes/version/
/// notifier) each builder resolves on its own. Built **once** in `main` — dedup
/// by identity is preserved.
Future<Module> buildAppModule({required PiSpawnConfig config}) async {
  final core = buildCoreModule(config: config);
  final cockpit = await buildCockpitModule();
  final settings = buildSettingsModule();
  return createModule(
    register: (c) => c
      ..module(core)
      ..module(cockpit)
      ..module(settings),
  );
}

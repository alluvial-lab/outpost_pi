import 'package:cockpit/app/cockpit/cockpit_module.dart';
import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/settings/settings_module.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Compose the root module from core and vertical feature modules.
///
/// [stateStores] is the single lifecycle-owned persistence boundary opened by
/// `main`; feature composition receives it without learning filesystem paths or
/// legacy migration details.
Future<Module> buildAppModule({
  required PiSpawnConfig config,
  required StateStoreFactory stateStores,
}) async {
  final core = buildCoreModule(config: config);
  final cockpit = await buildCockpitModule(stateStores);
  final settings = buildSettingsModule();
  return createModule(
    register: (c) => c
      ..module(core)
      ..module(cockpit)
      ..module(settings),
  );
}

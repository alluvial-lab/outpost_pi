import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verify the flutter_modular maintainer's root-scope resolution contract.
///
/// A root-owned `add<T>(Impl.new)` binding resolves another root-owned
/// dependency registered with `addInstance`. By contrast, placing the same
/// factory in a pathful feature module cannot resolve `PiSpawnConfig`, so these
/// factories remain in core rather than settings.
void main() {
  test('core add<T>(Impl.new) resolves PiSpawnConfig and create()', () {
    const config = PiSpawnConfig(executable: 'pi');
    final boot = bootstrapModule(buildCoreModule(config: config));

    final pairing = boot.injector.get<PairingGatewayFactory>();
    final revoke = boot.injector.get<RevokeGatewayFactory>();

    expect(pairing, isA<PairingGatewayFactory>());
    expect(revoke, isA<RevokeGatewayFactory>());

    // create() builds each gateway from the injected config. If construction
    // had not resolved PiSpawnConfig, the lookups above would already fail.
    expect(pairing.create(), isA<PairingGateway>());
    expect(revoke.create(), isA<RevokeGateway>());
  });
}

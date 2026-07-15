// Widget-adjacent smoke tests for file icons and setup gate behavior.

import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icon.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icon_map.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('file icons', () {
    test('simple extension resolves from the final segment', () {
      expect(fileIconName('main.dart'), 'dart');
      expect(fileIconName('styles.scss'), 'sass');
      expect(fileIconName('script.sh'), 'console');
    });

    test('extension matching is case-insensitive', () {
      expect(fileIconName('PHOTO.PNG'), 'image');
    });

    test('compound extension wins over a simple extension', () {
      expect(fileIconName('app.module.ts'), 'angular');
      expect(fileIconName('foo.test.tsx'), 'test-jsx');
    });

    test('exact name takes priority over extension', () {
      expect(fileIconName('package.json'), 'nodejs');
      expect(fileIconName('.gitignore'), 'git');
      expect(fileIconName('Dockerfile'), 'docker');
    });

    test('unknown file falls back to the default icon', () {
      expect(fileIconName('weird'), kDefaultFileIcon);
      expect(fileIconName('no.such.ext'), kDefaultFileIcon);
    });

    test('folder lookup normalizes dotted, dashed, and wrapped variants', () {
      expect(folderIconName('src'), folderIconName('.src'));
      expect(folderIconName('test'), folderIconName('__tests__'));
      expect(folderIconName('node_modules'), isNot(kDefaultFolderIcon));
    });

    test('open folder uses the open icon', () {
      final closed = folderIconName('src');
      final open = folderIconName('src', open: true);
      expect(open, isNot(closed));
      expect(folderIconName('xyz-unknown'), kDefaultFolderIcon);
      expect(folderIconName('xyz-unknown', open: true), kDefaultFolderOpenIcon);
    });
  });

  group('agent setup gate', () {
    test('all three prerequisites satisfied makes the agent ready', () async {
      final vm = SetupViewModel(_FakeEnv(), _FakeInstaller());
      await vm.recheckAll();
      expect(vm.pi, CheckStatus.ok);
      expect(vm.extension, CheckStatus.ok);
      expect(vm.supervisor, CheckStatus.ok);
      expect(vm.agentReady, isTrue);
    });

    test('one missing prerequisite blocks readiness', () async {
      final vm = SetupViewModel(_FakeEnv(ext: false), _FakeInstaller());
      await vm.recheckAll();
      expect(vm.extension, CheckStatus.missing);
      expect(vm.agentReady, isFalse);
    });

    test('missing Pi or supervisor also blocks readiness', () async {
      final a = SetupViewModel(_FakeEnv(pi: false), _FakeInstaller());
      await a.recheckAll();
      expect(a.pi, CheckStatus.missing);
      expect(a.agentReady, isFalse);

      final b = SetupViewModel(_FakeEnv(sup: false), _FakeInstaller());
      await b.recheckAll();
      expect(b.supervisor, CheckStatus.missing);
      expect(b.agentReady, isFalse);
    });
  });
}

class _FakeEnv implements EnvironmentProbe {
  _FakeEnv({this.pi = true, this.ext = true, this.sup = true});
  final bool pi;
  final bool ext;
  final bool sup;
  @override
  Future<bool> piInstalled() async => pi;
  @override
  Future<bool> extensionInstalled() async => ext;
  @override
  Future<bool> supervisorInstalled() async => sup;
}

class _FakeInstaller implements EnvironmentInstaller {
  @override
  Future<InstallResult> installExtension() async =>
      const InstallResult.success();
  @override
  Future<InstallResult> installSupervisor() async =>
      const InstallResult.success();
}

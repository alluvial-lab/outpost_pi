import 'dart:convert';
import 'dart:io';

/// Read content-free security state from the isolated Pi-host container.
final class PiHostInspector {
  PiHostInspector.fromEnvironment()
    : _composeProject = const String.fromEnvironment('E2E_COMPOSE_PROJECT'),
      _composeFile = const String.fromEnvironment('E2E_COMPOSE_FILE') {
    if (_composeProject.isEmpty || _composeFile.isEmpty) {
      throw StateError('compose inspection settings were not provided');
    }
  }

  final String _composeProject;
  final String _composeFile;

  Future<int> peerCount() async {
    final value = await _runNode('''
const fs = require('node:fs');
const path = '/tmp/outpost-pi-e2e-home/.pi/remote/peers.json';
let count = 0;
try { count = JSON.parse(fs.readFileSync(path, 'utf8')).peers?.length ?? 0; } catch {}
process.stdout.write(JSON.stringify({count}));
''');
    return (value['count'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> ownerChannelAudit() async {
    final value = await _runNode('''
const fs = require('node:fs');
const path = '/tmp/outpost-pi-e2e-home/.pi/remote/owner-channel-audit.jsonl';
let events = [];
try {
  events = fs.readFileSync(path, 'utf8').split('\\n').filter(Boolean).map(JSON.parse);
} catch {}
process.stdout.write(JSON.stringify({events}));
''');
    return (value['events'] as List<dynamic>)
        .map((event) => (event as Map).cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> _runNode(String script) async {
    final result = await Process.run('docker', <String>[
      'compose',
      '-p',
      _composeProject,
      '-f',
      _composeFile,
      'exec',
      '-T',
      'pi-host',
      'node',
      '-e',
      script,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'docker',
        const <String>['compose', 'exec', 'pi-host'],
        'Pi-host inspection failed with exit ${result.exitCode}',
        result.exitCode,
      );
    }
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }
}

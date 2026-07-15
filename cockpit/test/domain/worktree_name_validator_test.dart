import 'package:cockpit/app/cockpit/domain/validators/worktree_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = WorktreeNameValidator();

  WorktreeNameCheck check(
    String name, {
    Set<String> branches = const <String>{},
    Set<String> worktrees = const <String>{},
  }) => validator.validate(
    name,
    existingBranches: branches,
    existingWorktreeNames: worktrees,
  );

  group('format', () {
    test('rejects an empty name', () {
      expect(check('').error, WorktreeNameError.empty);
    });

    test('rejects whitespace according to product policy', () {
      expect(check('feat sso').error, WorktreeNameError.whitespace);
      expect(check('trailing ').error, WorktreeNameError.whitespace);
    });

    test('permits slashes', () {
      expect(check('feat/sso').isValid, isTrue);
      expect(check('fix/prorate').isValid, isTrue);
    });

    test('rejects characters forbidden by Git', () {
      for (final n in <String>[
        'a~b',
        'a^b',
        'a:b',
        'a?b',
        'a*b',
        'a[b',
        r'a\b',
      ]) {
        expect(check(n).error, WorktreeNameError.invalidChar, reason: n);
      }
    });

    test('rejects invalid sequences', () {
      expect(check('foo..bar').error, WorktreeNameError.invalidSequence);
      expect(check('foo//bar').error, WorktreeNameError.invalidSequence);
      expect(check('foo@{bar').error, WorktreeNameError.invalidSequence);
      expect(check('@').error, WorktreeNameError.invalidSequence);
      expect(check('/foo').error, WorktreeNameError.invalidSequence);
      expect(check('foo/').error, WorktreeNameError.invalidSequence);
    });

    test('rejects reserved positions', () {
      expect(check('-foo').error, WorktreeNameError.reserved);
      expect(check('.foo').error, WorktreeNameError.reserved);
      expect(check('foo.').error, WorktreeNameError.reserved);
      expect(check('foo.lock').error, WorktreeNameError.reserved);
      expect(check('feat/.hidden').error, WorktreeNameError.reserved);
      expect(check('feat/x.lock').error, WorktreeNameError.reserved);
    });

    test('accepts a valid simple name', () {
      expect(check('login').isValid, isTrue);
      expect(check('experiment/cache').isValid, isTrue);
    });
  });

  group('uniqueness (decision 11)', () {
    test('rejects a local branch collision', () {
      expect(
        check('main', branches: {'main', 'dev'}).error,
        WorktreeNameError.duplicateBranch,
      );
    });

    test('rejects an existing worktree collision', () {
      expect(
        check('feat/sso', worktrees: {'sso', 'feat/sso'}).error,
        WorktreeNameError.duplicateWorktree,
      );
    });

    test('accepts a unique name', () {
      expect(
        check('feat/new', branches: {'main'}, worktrees: {'old'}).isValid,
        isTrue,
      );
    });

    test('checks format before uniqueness', () {
      // The trailing space makes `main ` fail as whitespace, not as a duplicate.
      expect(
        check('main ', branches: {'main'}).error,
        WorktreeNameError.whitespace,
      );
    });
  });
}

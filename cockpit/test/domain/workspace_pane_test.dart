import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('split tree', () {
    test('leaves enumerates every leaf', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      expect(leaves(tree).map((l) => l.id), ['p1', 'p2']);
    });

    test('splitLeaf transforms a leaf into a split', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out = splitLeaf(
        tree,
        'p1',
        SplitDir.vertical,
        const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
      );
      expect(out, isA<SplitPane>());
      expect(leaves(out).length, 2);
    });

    test('removeLeaf expands the sibling', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final out = removeLeaf(tree, 'p1');
      expect(out, isA<LeafPane>());
      expect((out as LeafPane).id, 'p2');
    });

    test('updateLeaf changes only the target leaf', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out = updateLeaf(
        tree,
        'p1',
        (p) => p.copyWith(tabs: ['a', 'b'], active: 'b'),
      );
      expect((out as LeafPane).tabs, ['a', 'b']);
      expect(out.active, 'b');
    });

    test('setFrac adjusts the target split proportion', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.horizontal,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final out = setFrac(tree, 's1', 0.3) as SplitPane;
      expect(out.frac, 0.3);
    });

    test('splitLeaf before:true places the new pane first', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out =
          splitLeaf(
                tree,
                'p1',
                SplitDir.vertical,
                const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
                splitId: 'sx',
                before: true,
              )
              as SplitPane;
      expect(out.id, 'sx');
      expect((out.a as LeafPane).id, 'p2');
      expect((out.b as LeafPane).id, 'p1');
    });

    test(
      'splitLeaf uses a custom splitId and appends the new pane by default',
      () {
        const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
        final out =
            splitLeaf(
                  tree,
                  'p1',
                  SplitDir.vertical,
                  const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
                  splitId: 'unique-1',
                )
                as SplitPane;
        expect(out.id, 'unique-1');
        expect((out.b as LeafPane).id, 'p2');
      },
    );

    test('reorderTabs moves forward and adjusts for removal', () {
      expect(reorderTabs(['a', 'b', 'c', 'd'], 'a', 3), ['b', 'c', 'a', 'd']);
    });

    test('reorderTabs moves backward', () {
      expect(reorderTabs(['a', 'b', 'c', 'd'], 'd', 1), ['a', 'd', 'b', 'c']);
    });

    test("reorderTabs is a no-op at the tab's current position", () {
      expect(reorderTabs(['a', 'b', 'c'], 'b', 1), ['a', 'b', 'c']);
      expect(reorderTabs(['a', 'b', 'c'], 'b', 2), ['a', 'b', 'c']);
    });

    test('reorderTabs moves to the end', () {
      expect(reorderTabs(['a', 'b', 'c'], 'a', 3), ['b', 'c', 'a']);
    });

    test('reorderTabs returns an unchanged list when the id is absent', () {
      expect(reorderTabs(['a', 'b'], 'z', 0), ['a', 'b']);
    });

    test('paneNodeToJson and paneNodeFromJson round-trip the tree', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.horizontal,
        a: const LeafPane(id: 'p1', tabs: ['a', 'b'], active: 'b'),
        b: SplitPane(
          id: 's2',
          dir: SplitDir.vertical,
          a: const LeafPane(id: 'p2', tabs: ['c'], active: 'c'),
          b: const LeafPane(id: 'p3', tabs: ['d', 'e'], active: 'd'),
          frac: 0.4,
        ),
        frac: 0.6,
      );
      final back = paneNodeFromJson(paneNodeToJson(tree));
      expect(back, isA<SplitPane>());
      final s = back as SplitPane;
      expect(s.dir, SplitDir.horizontal);
      expect(s.frac, 0.6);
      expect((s.a as LeafPane).tabs, ['a', 'b']);
      expect((s.a as LeafPane).active, 'b');
      final s2 = s.b as SplitPane;
      expect(s2.id, 's2');
      expect(s2.dir, SplitDir.vertical);
      expect(s2.frac, 0.4);
      expect((s2.b as LeafPane).tabs, ['d', 'e']);
      expect(leaves(back).map((l) => l.id), ['p1', 'p2', 'p3']);
    });

    test('paneNodeFromJson reconstructs a simple leaf', () {
      final json = paneNodeToJson(
        const LeafPane(id: 'p1', tabs: ['x'], active: 'x'),
      );
      final back = paneNodeFromJson(json);
      expect(back, isA<LeafPane>());
      expect((back as LeafPane).id, 'p1');
      expect(back.tabs, ['x']);
    });

    test('moving the last tab empties its leaf and expands the sibling', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final docked = updateLeaf(
        tree,
        'p2',
        (p) => p.copyWith(tabs: [...p.tabs, 'a'], active: 'a'),
      );
      final out = removeLeaf(docked, 'p1');
      expect(out, isA<LeafPane>());
      expect((out as LeafPane).tabs, ['b', 'a']);
      expect(out.active, 'a');
    });
  });
}

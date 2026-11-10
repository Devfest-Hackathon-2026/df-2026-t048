import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:postcheck/presentation/venue_page.dart';
import 'package:postcheck/presentation/app_theme.dart';

void main() {
  testWidgets('no-key list → rule detail → apply works on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PublishedVenue? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPostCheckTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.push<PublishedVenue>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const VenuePage(repository: DemoVenueRepository()),
                  ),
                );
              },
              child: const Text('場所を選ぶ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('場所を選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('地図は未接続です。登録施設の一覧から選べます。'), findsOneWidget);
    final name = (await const DemoVenueRepository().list()).first.policy.name;
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.text('デモ・架空のルール'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('この施設のルールを使う'), 200);
    await tester.tap(find.text('この施設のルールを使う'));
    await tester.pumpAndSettle();
    expect(selected?.policy.name, name);
    expect(tester.takeException(), isNull);
  });
}

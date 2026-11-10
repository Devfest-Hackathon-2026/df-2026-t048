import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postcheck/adapters/local_storage.dart';
import 'package:postcheck/application/check_draft.dart';
import 'package:postcheck/domain/input.dart';
import 'package:postcheck/presentation/home_page.dart';
import 'package:postcheck/presentation/postcheck_controller.dart';

import 'controller_test.dart'
    show TestPerception, TestContext, TestImages, TestExport;

class EmptyLibrary implements PhotoLibraryPort {
  @override
  Future<Uint8List?> pick() async => null;
  @override
  Future<Uint8List?> sample() async => null;
}

void main() {
  testWidgets('起動時にカメラを開き、閉じた後は自動で開き直さない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = PostCheckController(
      check: CheckDraft(perception: TestPerception(), context: TestContext()),
      images: TestImages(),
      exporter: TestExport(),
    );
    addTearDown(c.dispose);
    var launches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          controller: c,
          settings: LocalSettings(await SharedPreferences.getInstance()),
          library: EmptyLibrary(),
          startWithCamera: true,
          openCamera: (context) {
            launches++;
            return Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('カメラを閉じる'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(find.text('カメラを閉じる'), findsOneWidget);
    await tester.tap(find.text('カメラを閉じる'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-button')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(find.byKey(const ValueKey('library-button')), findsOneWidget);
  });
}

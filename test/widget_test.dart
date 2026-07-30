import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:songloft_flutter/core/router/app_router.dart';
import 'package:songloft_flutter/main.dart';

void main() {
  testWidgets('Songloft app smoke test', (WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => const Scaffold(
                body: Center(child: Text('Songloft app test')),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routerProvider.overrideWithValue(router)],
        child: const SongloftApp(),
      ),
    );

    // Verify that our app shell can render with the test router.
    expect(find.text('Songloft app test'), findsOneWidget);
  });
}

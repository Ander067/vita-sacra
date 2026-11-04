import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vita_sacra_app/main.dart';

void main() {
  testWidgets('Verificar inicio de Vita Sacra', (WidgetTester tester) async {
    // Construir la aplicación principal.
    await tester.pumpWidget(const VitaSacraApp());

    // Comprobar que existe un widget MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

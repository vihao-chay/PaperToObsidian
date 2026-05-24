import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_convert/main.dart';

void main() {
  testWidgets('shows the PDF selection screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PaperToObsidianApp());

    expect(find.text('PDF to Obsidian Knowledge Nodes'), findsOneWidget);
    expect(find.text('Select PDF'), findsWidgets);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
    expect(find.text('Analyze'), findsNothing);
  });
}

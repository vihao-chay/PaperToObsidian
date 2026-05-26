import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('shows simplified PDF to Obsidian flow', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());

    expect(find.text('Chọn PDF'), findsWidgets);
    expect(find.text('Chọn Vault'), findsWidgets);
    expect(find.text('Chọn số trang'), findsOneWidget);
    expect(find.text('Trang bắt đầu'), findsOneWidget);
    expect(find.text('Trang kết thúc'), findsOneWidget);
    expect(find.text('Analyze'), findsWidgets);
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('Trang'), findsOneWidget);
    expect(find.text('Export'), findsWidgets);
    expect(find.text('Đã khóa'), findsOneWidget);
    expect(find.text('Select Folder'), findsNothing);
    expect(find.text('Save Folder'), findsNothing);
  });
}

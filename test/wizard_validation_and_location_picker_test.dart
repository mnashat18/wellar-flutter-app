import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/data/locations_data.dart';
import 'package:waller_app/utils/business_profile_validators.dart';
import 'package:waller_app/widgets/searchable_picker_field.dart';

void main() {
  group('Business profile phone validation', () {
    test('rejects alphabetic characters and short numbers', () {
      expect(
        BusinessProfileValidators.phone('abc1234567'),
        contains('Use only digits'),
      );
      expect(BusinessProfileValidators.phone('99'), isNotNull);
    });

    test('accepts a formatted international number', () {
      expect(BusinessProfileValidators.phone('+20 100 123 4567'), isNull);
    });
  });

  test('location selection clears dependent values when parent changes', () {
    final selection = CascadingLocationSelection();
    final egypt = LocationsData.countryNamed('Egypt')!;
    final uae = LocationsData.countryNamed('United Arab Emirates')!;
    final cairo = LocationsData.childNamed(egypt.children, 'Cairo')!;
    final alexandria = LocationsData.childNamed(egypt.children, 'Alexandria')!;
    final newCairo = LocationsData.childNamed(cairo.children, 'New Cairo')!;
    expect(egypt.children, hasLength(27));

    selection.selectCountry(egypt);
    selection.selectRegion(cairo);
    selection.selectCity(newCairo);
    expect(selection.city, same(newCairo));

    selection.selectRegion(alexandria);
    expect(selection.city, isNull);

    selection.selectRegion(cairo);
    selection.selectCity(newCairo);
    selection.selectCountry(uae);
    expect(selection.region, isNull);
    expect(selection.city, isNull);
  });

  testWidgets('searchable picker returns the chosen localized location', (
    tester,
  ) async {
    LocationOption? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePickerField(
            label: 'Country',
            searchHint: 'Search countries',
            value: null,
            options: LocationsData.countries,
            enabled: true,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('picker-field-Country')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egypt').last);
    await tester.pumpAndSettle();

    expect(selected?.nameEnglish, 'Egypt');
    expect(find.text('Egypt'), findsOneWidget);
  });
}

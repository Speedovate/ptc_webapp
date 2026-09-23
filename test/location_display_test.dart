import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/location_display.dart';

void main() {
  test('shortens only a trailing Puerto Princesa component', () {
    expect(locationDisplayLabel('Sicsican, Puerto Princesa'), 'Sicsican');
    expect(locationDisplayLabel('Sicsican, Puerto Princesa City'), 'Sicsican');
    expect(
      locationDisplayLabel(' Bagong Pag-asa, puerto princesa city '),
      'Bagong Pag-asa',
    );
    expect(
      locationDisplayLabel('Puerto Princesa City'),
      'Puerto Princesa City',
    );
    expect(locationDisplayLabel('Garage'), 'Garage');
    expect(locationDisplayLabel('Roxas'), 'Roxas');
    expect(locationDisplayLabel('Depot, Roxas'), 'Depot, Roxas');
    const url = 'https://maps.google.com/?q=Sicsican, Puerto Princesa';
    expect(locationDisplayLabel(url), url);
  });
}

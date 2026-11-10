import 'package:flutter_test/flutter_test.dart';
import 'package:ords_ba/Model/models.dart';

void main() {
  test('Sku parses sample item and trims names', () {
    final s = Sku.fromJson({
      'sku_id': 1010772601,
      'item_code': '101077',
      'item_name': 'BOX 150GM 60 PCS CTN',
      'blend_name': ' AWAZ',
      'sku_group': 'AWAZ',
      'con_blend_name': ' AWAZ',
      'active': 'Y',
    });
    expect(s.skuId, 1010772601);
    expect(s.blendName, 'AWAZ');
    expect(s.group, 'AWAZ');
  });

  test('MartLocation parses the API response', () {
    final l = MartLocation.fromJson({
      'location_id': '7',
      'mart_name': 'Test Mart',
      'area_name': 'Clifton',
      'city': 'Karachi',
      'latitude': 24.8607,
      'longitude': 67,
    });
    expect(l.id, 7);
    expect(l.name, 'Test Mart');
    expect(l.hasCoordinates, isTrue);
    expect(l.radiusMeters, 100);
  });

  test('Inactive SKUs are detected', () {
    expect(Sku.isActive({'active': 'N'}), isFalse);
    expect(Sku.isActive({'active': 'Y'}), isTrue);
  });
}

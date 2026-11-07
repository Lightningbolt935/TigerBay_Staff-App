import 'package:flutter_test/flutter_test.dart';
import 'package:tigerbay_staff_app/core/constants/app_constants.dart';

void main() {
  test('TigerBay Staff App constants verification', () {
    expect(AppConstants.appName, isNotEmpty);
    expect(AppConstants.supabaseUrl, isNotEmpty);
    expect(AppConstants.supabaseAnonKey, isNotEmpty);
  });
}

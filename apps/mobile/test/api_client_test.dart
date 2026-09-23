import 'package:flutter_test/flutter_test.dart';
import 'package:sababisha_pms_mobile/src/services/api_client.dart';

void main() {
  test('uses the Android emulator API address by default', () {
    expect(apiBaseUrl, 'http://10.0.2.2:5141/api/v1');
  });

  test('API errors retain status and message', () {
    const error = ApiException('Forbidden', statusCode: 403);
    expect(error.statusCode, 403);
    expect(error.toString(), 'Forbidden');
  });
}

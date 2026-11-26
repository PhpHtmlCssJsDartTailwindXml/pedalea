import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/subscription_service.dart';

void main() {
  group('SubscriptionService.isoPeriodDays', () {
    test('lee los periodos de prueba de Google Play', () {
      expect(SubscriptionService.isoPeriodDays('P7D'), 7);
      expect(SubscriptionService.isoPeriodDays('P1W'), 7);
      expect(SubscriptionService.isoPeriodDays('P2W'), 14);
      expect(SubscriptionService.isoPeriodDays('P1M'), 30);
      expect(SubscriptionService.isoPeriodDays('P1Y'), 365);
    });

    test('un periodo desconocido no se interpreta como prueba', () {
      expect(SubscriptionService.isoPeriodDays(''), isNull);
      expect(SubscriptionService.isoPeriodDays('7D'), isNull);
      expect(SubscriptionService.isoPeriodDays('P1H'), isNull);
    });
  });
}

// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps/nativ_maps.dart';
import 'package:test/test.dart';

import '../support/fake_service.dart';

void main() {
  group('Budget', () {
    /// Un reloj que se mueve a mano: el tiempo real haría la prueba lenta y
    /// escamosa.
    late DateTime ahora;
    DateTime reloj() => ahora;

    setUp(() => ahora = DateTime.utc(2026, 8, 22, 12));

    test('deja pasar hasta el tope y luego lanza', () {
      final presupuesto = Budget(maxUnits: 3, clock: reloj);
      presupuesto.charge('op', 1);
      presupuesto.charge('op', 1);
      presupuesto.charge('op', 1);
      expect(presupuesto.usedUnits, 3);
      expect(presupuesto.remainingUnits, 0);
      expect(
        () => presupuesto.charge('op', 1),
        throwsA(isA<BudgetExhaustedException>()),
      );
    });

    test('la ventana es deslizante, no un contador que se reinicia', () {
      // Con un contador que se reinicia, gastar el tope justo antes del corte
      // y otra vez justo después deja pasar el doble — que es exactamente
      // cuando un bucle desbocado está en su peor momento.
      final presupuesto = Budget(
        maxUnits: 2,
        window: const Duration(minutes: 1),
        clock: reloj,
      );
      presupuesto.charge('op', 2);
      ahora = ahora.add(const Duration(seconds: 59));
      expect(() => presupuesto.charge('op', 1), throwsA(isA<Exception>()));

      ahora = ahora.add(const Duration(seconds: 2));
      expect(presupuesto.usedUnits, 0);
      expect(() => presupuesto.charge('op', 2), returnsNormally);
    });

    test('el modo aviso deja pasar y notifica', () {
      final avisos = <BudgetExhaustedException>[];
      final presupuesto = Budget(
        maxUnits: 1,
        policy: BudgetPolicy.warn,
        onExceeded: avisos.add,
        clock: reloj,
      );
      presupuesto.charge('op', 1);
      expect(() => presupuesto.charge('op', 1), returnsNormally);
      expect(avisos, hasLength(1));
      expect(avisos.first.operation, 'op');
    });

    test('el aviso también se dispara en el modo que lanza', () {
      final avisos = <BudgetExhaustedException>[];
      final presupuesto = Budget(
        maxUnits: 1,
        onExceeded: avisos.add,
        clock: reloj,
      );
      presupuesto.charge('op', 1);
      expect(() => presupuesto.charge('op', 1), throwsA(isA<Exception>()));
      expect(avisos, hasLength(1));
    });

    test('el cargo no se devuelve si la petición falla', () async {
      // AWS cobra la mayoría de los errores de servicio igual. Un presupuesto
      // que se recupera al fallar algo es justo el que se vacía cuando el
      // servicio está teniendo un mal día.
      final servicio = FakeAlsService()
        ..stub('/v2/search-text', <String, dynamic>{
          'message': 'no',
        }, status: 400);
      final presupuesto = Budget(maxUnits: 10);
      final maps = fakeNativMaps(servicio, budget: presupuesto);
      addTearDown(maps.close);

      await expectLater(
        maps.places.searchText(queryText: 'x'),
        throwsA(isA<AlsApiException>()),
      );
      expect(presupuesto.usedUnits, 1);
    });

    test('reset devuelve todo el presupuesto', () {
      final presupuesto = Budget(maxUnits: 5, clock: reloj)..charge('op', 5);
      expect(presupuesto.remainingUnits, 0);
      presupuesto.reset();
      expect(presupuesto.remainingUnits, 5);
    });

    test('rechaza un tope o una ventana no positivos', () {
      expect(() => Budget(maxUnits: 0), throwsArgumentError);
      expect(
        () => Budget(maxUnits: 1, window: Duration.zero),
        throwsArgumentError,
      );
    });

    test('la excepción dice cuánto falta y cuándo vuelve', () {
      final presupuesto = Budget(maxUnits: 2, clock: reloj)..charge('op', 2);
      try {
        presupuesto.charge('CalculateRouteMatrix', 25);
        fail('debería haber lanzado');
      } on BudgetExhaustedException catch (e) {
        expect(e.requestedUnits, 25);
        expect(e.usedUnits, 2);
        expect(e.maxUnits, 2);
        expect(e.toString(), contains('CalculateRouteMatrix'));
        expect(e.resetsAt.isAfter(ahora), isTrue);
      }
    });
  });

  group('BillingUnits', () {
    test('lo normal cuesta una unidad', () {
      expect(BillingUnits.single, 1);
    });

    test('la isócrona cuesta por umbral', () {
      expect(BillingUnits.isolines(3), 3);
      expect(BillingUnits.isolines(0), 1);
    });

    test('la matriz cuesta por par', () {
      // Es la operación donde más se separan lo que parece y lo que cuesta.
      expect(BillingUnits.routeMatrix(10, 10), 100);
      expect(BillingUnits.routeMatrix(1, 1), 1);
    });

    test('snapToRoads cuesta por trozo enviado', () {
      expect(BillingUnits.snapToRoads(3), 3);
    });
  });
}

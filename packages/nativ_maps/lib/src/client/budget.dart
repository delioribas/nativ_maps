// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/exceptions.dart';

/// Qué hacer cuando se agota el presupuesto.
enum BudgetPolicy {
  /// Lanzar [BudgetExhaustedException] y no enviar la petición.
  ///
  /// Es el valor por defecto, y a propósito: el modo silencioso convierte un
  /// tope en una sugerencia.
  throwException,

  /// Dejar pasar la petición y avisar por [Budget.onExceeded].
  ///
  /// Para cuando cortar el servicio es peor que la factura — un rastreo en
  /// curso, por ejemplo. La llamada sí se cobra.
  warn,
}

/// Tope de gasto por ventana de tiempo, comprobado antes de enviar.
///
/// ## Por qué esto vive en el cliente y no en la disciplina de quien lo usa
///
/// Amazon Location se factura **por petición**, y algunas cobran más de una:
/// las isócronas cobran por umbral (hasta cinco), la matriz cobra **por par**
/// —una matriz de 10×10 son cien cálculos—.
///
/// Un bucle sobre la flota, un `initState` que pide una ruta en cada
/// reconstrucción, una pantalla que se refresca sola: ninguna de las tres se
/// ve como un error al leer el código, y las tres aparecen en la factura. La
/// revisión de código no las caza porque no parecen errores. Un tope que
/// cuenta unidades reales, sí.
///
/// ```dart
/// final maps = NativMaps(
///   region: 'us-east-1',
///   credentials: ApiKeyCredentials(clave),
///   budget: Budget(
///     maxUnits: 500,
///     window: const Duration(minutes: 1),
///     onExceeded: (e) => registro.alerta('$e'),
///   ),
/// );
/// ```
///
/// El presupuesto protege de **tus propios bucles**. No protege de un tercero
/// que extrajo la clave del APK: para eso está AWS Budgets, en la consola.
class Budget {
  /// Crea un presupuesto de [maxUnits] unidades facturables por [window].
  Budget({
    required this.maxUnits,
    this.window = const Duration(minutes: 1),
    this.policy = BudgetPolicy.throwException,
    this.onExceeded,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // Sin `assert`: Dart lo elimina al compilar en release, así que un
    // presupuesto inválido avisaría en depuración y pasaría callado en
    // producción. Es el mismo fallo que tenía `LatLngBounds.fromPoints`, y
    // aquí caería justo en el control de gasto.
    if (maxUnits <= 0) {
      throw ArgumentError.value(maxUnits, 'maxUnits', 'debe ser positivo');
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'debe ser positiva');
    }
  }

  /// Un presupuesto que no limita nada. Útil para pruebas y para el modo de
  /// desarrollo, donde el tope estorba más de lo que ayuda.
  factory Budget.unlimited() => Budget(
    maxUnits: 1 << 30,
    window: const Duration(days: 365),
    policy: BudgetPolicy.warn,
  );

  /// Unidades facturables permitidas dentro de una ventana.
  final int maxUnits;

  /// La longitud de la ventana deslizante.
  final Duration window;

  /// Qué hacer al superar el tope.
  final BudgetPolicy policy;

  /// Se llama cada vez que se supera el tope, sea cual sea la política.
  ///
  /// Es el sitio para enganchar el registro de la app: sin esto, un tope en
  /// modo [BudgetPolicy.warn] no deja rastro de que se cruzó.
  final void Function(BudgetExhaustedException event)? onExceeded;

  final DateTime Function() _clock;

  /// Ventana deslizante real: cada entrada es (instante, unidades).
  ///
  /// Una cola y no un contador con reinicio, porque el contador deja pasar el
  /// doble del tope justo en el cambio de ventana — que es exactamente cuando
  /// un bucle desbocado está en su peor momento.
  final Queue<(DateTime, int)> _spent = Queue<(DateTime, int)>();

  /// Unidades gastadas en la ventana que acaba ahora.
  int get usedUnits {
    _evictExpired();
    return _spent.fold(0, (sum, entry) => sum + entry.$2);
  }

  /// Unidades que quedan disponibles ahora mismo.
  int get remainingUnits => (maxUnits - usedUnits).clamp(0, maxUnits);

  /// Cuándo caduca la entrada más antigua, es decir, cuándo vuelve a haber
  /// presupuesto. Es [DateTime.now] si no hay nada gastado.
  DateTime get resetsAt {
    _evictExpired();
    if (_spent.isEmpty) return _clock();
    return _spent.first.$1.add(window);
  }

  /// Reserva [units] para [operation].
  ///
  /// Lanza [BudgetExhaustedException] si no caben y la política es
  /// [BudgetPolicy.throwException]. En [BudgetPolicy.warn] avisa y deja pasar.
  ///
  /// El cargo se apunta **antes** de enviar y no se devuelve si la petición
  /// falla: AWS cobra la mayoría de los errores de servicio igual, y un
  /// presupuesto que se recupera cuando algo falla es justo el que se vacía
  /// cuando el servicio está teniendo un mal día.
  void charge(String operation, int units) {
    if (units <= 0) return;
    _evictExpired();

    final used = _spent.fold(0, (int sum, entry) => sum + entry.$2);
    if (used + units > maxUnits) {
      final event = BudgetExhaustedException(
        operation: operation,
        requestedUnits: units,
        usedUnits: used,
        maxUnits: maxUnits,
        window: window,
        resetsAt: resetsAt,
      );
      onExceeded?.call(event);
      if (policy == BudgetPolicy.throwException) throw event;
    }
    _spent.add((_clock(), units));
  }

  /// Vacía el histórico. Después de esto queda todo el presupuesto.
  void reset() => _spent.clear();

  void _evictExpired() {
    final cutoff = _clock().subtract(window);
    while (_spent.isNotEmpty && _spent.first.$1.isBefore(cutoff)) {
      _spent.removeFirst();
    }
  }

  @override
  String toString() =>
      'Budget($usedUnits/$maxUnits por ${window.inSeconds}s, ${policy.name})';
}

/// Cuántas unidades facturables cuesta cada operación.
///
/// La mayoría cuesta una. Las tres que no son justamente las que aparecen en
/// una factura sorpresa, así que están aquí con nombre y explicación en vez de
/// escondidas en el sitio de la llamada.
@immutable
abstract final class BillingUnits {
  /// El caso normal: una petición, una unidad.
  static const int single = 1;

  /// Una isócrona cobra **por umbral**, no por petición.
  ///
  /// Pedir cinco umbrales en una llamada es más cómodo que cinco llamadas,
  /// pero cuesta exactamente lo mismo.
  static int isolines(int thresholdCount) =>
      thresholdCount <= 0 ? 1 : thresholdCount;

  /// Una matriz cobra **por par origen-destino**.
  ///
  /// Diez orígenes y diez destinos son cien cálculos de ruta. Es la operación
  /// donde la diferencia entre lo que parece y lo que cuesta es mayor.
  static int routeMatrix(int origins, int destinations) {
    final cells = origins * destinations;
    return cells <= 0 ? 1 : cells;
  }

  /// `SnapToRoads` cobra por petición enviada.
  ///
  /// Importa porque un histórico largo se trocea: 12 000 puntos son tres
  /// peticiones, y por tanto tres unidades, aunque quien llama solo escribió
  /// una línea.
  static int snapToRoads(int chunkCount) => chunkCount <= 0 ? 1 : chunkCount;
}

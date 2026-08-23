// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';
import 'package:nativ_maps/src/core/lat_lng.dart';
import 'package:nativ_maps/src/routes/routes_client.dart';

/// Dónde está un conductor.
@immutable
class DriverLocation {
  /// Crea una posición de conductor.
  const DriverLocation({
    required this.driverId,
    required this.position,
    this.updatedAt,
    this.available = true,
    this.headingDegrees,
  });

  /// Quién es.
  final String driverId;

  /// Dónde está.
  final LatLng position;

  /// Cuándo se supo por última vez.
  final DateTime? updatedAt;

  /// ¿Está libre?
  final bool available;

  /// Hacia dónde mira, en grados desde el norte.
  final double? headingDegrees;

  @override
  String toString() => 'DriverLocation($driverId, $position)';
}

/// Un conductor candidato para una recogida.
@immutable
class DriverCandidate {
  /// Crea un candidato.
  const DriverCandidate({
    required this.driver,
    required this.straightLineMeters,
    this.drivingMeters,
    this.drivingDuration,
  });

  /// El conductor.
  final DriverLocation driver;

  /// La distancia en línea recta hasta la recogida, en metros.
  ///
  /// Es gratis de calcular y sirve para preseleccionar, **no para elegir**.
  final double straightLineMeters;

  /// Los metros de conducción reales, si se refinó con la matriz.
  final double? drivingMeters;

  /// El tiempo de conducción real, si se refinó con la matriz.
  final Duration? drivingDuration;

  /// ¿Se refinó con una llamada al servicio?
  bool get refined => drivingDuration != null;

  /// Cuánto se aleja el trayecto real de la línea recta.
  ///
  /// Un valor de 1,4 es lo normal en una ciudad con trama regular. Por encima
  /// de 2,5 casi siempre hay un río, una vía de tren o una autopista de por
  /// medio, y es justo el caso en el que ordenar por línea recta se equivoca.
  double? get detourFactor {
    final meters = drivingMeters;
    if (meters == null || straightLineMeters <= 0) return null;
    return meters / straightLineMeters;
  }

  @override
  String toString() => refined
      ? 'DriverCandidate(${driver.driverId}, '
            '${drivingDuration!.inMinutes} min)'
      : 'DriverCandidate(${driver.driverId}, '
            '${straightLineMeters.round()} m straight line)';
}

/// Elige a qué conductores ofrecerles una carrera.
///
/// ## Las dos fases, y por qué son dos
///
/// **Ordenar por distancia en línea recta está mal.** El conductor que está a
/// 300 m al otro lado del río tarda quince minutos; el que está a 1,2 km por
/// la avenida tarda cuatro. Con la línea recta le ofreces la carrera al
/// primero.
///
/// **Pedir la matriz para toda la flota también está mal**, pero por dinero:
/// cada celda se factura, y una flota de 800 coches son 800 celdas por cada
/// petición de carrera.
///
/// Por eso hay dos fases:
///
/// 1. [shortlist] filtra por línea recta. Es local, instantáneo y **gratis**.
/// 2. [rank] refina solo esos con una llamada a la matriz.
///
/// Con 12 candidatos, una carrera cuesta 12 celdas en vez de 800.
@immutable
class DispatchPlanner {
  /// Crea un planificador.
  const DispatchPlanner({
    required this.routes,
    this.shortlistSize = 12,
    this.maxRadiusMeters = 8000,
  });

  /// El cliente con el que se refina.
  final RoutesClient routes;

  /// Cuántos candidatos se llevan a la fase de refinado.
  ///
  /// El máximo de orígenes de una matriz sin acotar es 15. Por encima de eso
  /// [rank] trocea en varias llamadas, y cada una se factura aparte.
  final int shortlistSize;

  /// Radio máximo en línea recta, en metros.
  ///
  /// Un conductor a 30 km no va a ir, y meterlo en la matriz es tirar dinero.
  final double maxRadiusMeters;

  /// Preselecciona por distancia en línea recta. **No gasta peticiones.**
  ///
  /// Descarta a los no disponibles y a los que se hayan quedado sin actualizar
  /// más de [staleAfter], si se indica: un coche cuya última posición es de
  /// hace diez minutos ya no está donde dice.
  List<DriverCandidate> shortlist(
    List<DriverLocation> drivers,
    LatLng pickup, {
    Duration? staleAfter,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();

    // Rechazo por caja envolvente antes de calcular ninguna distancia. Con
    // flotas grandes esto quita el 99 % de los candidatos con dos restas, sin
    // trigonometría.
    final latDegrees = maxRadiusMeters / 111320.0;
    final cosLat = math.cos(pickup.latitude * math.pi / 180).abs();
    final lonDegrees = cosLat < 1e-6
        ? 180.0
        : maxRadiusMeters / (111320.0 * cosLat);

    final candidates = <DriverCandidate>[];
    for (final driver in drivers) {
      if (!driver.available) continue;

      if (staleAfter != null) {
        final seen = driver.updatedAt;
        if (seen == null || moment.difference(seen).abs() > staleAfter) {
          continue;
        }
      }

      if ((driver.position.latitude - pickup.latitude).abs() > latDegrees) {
        continue;
      }
      if ((driver.position.longitude - pickup.longitude).abs() > lonDegrees) {
        continue;
      }

      final meters = driver.position.distanceTo(pickup);
      if (meters > maxRadiusMeters) continue;
      candidates.add(
        DriverCandidate(driver: driver, straightLineMeters: meters),
      );
    }

    candidates.sort(
      (a, b) => a.straightLineMeters.compareTo(b.straightLineMeters),
    );
    return candidates.take(shortlistSize).toList();
  }

  /// Refina la preselección con tiempos de conducción reales.
  ///
  /// Manda a los conductores como **orígenes** y la recogida como único
  /// destino, así que cuesta una celda por candidato. Si hay más de 15 se
  /// trocea, porque ese es el máximo de orígenes de una matriz sin acotar.
  ///
  /// El resultado va ordenado por tiempo de conducción. Los candidatos para
  /// los que el servicio no supo calcular ruta —una isla, una zona sin
  /// cartografía— se quedan al final con sus datos sin refinar, en vez de
  /// desaparecer sin explicación.
  Future<List<DriverCandidate>> rank(
    List<DriverCandidate> candidates,
    LatLng pickup, {
    TravelMode travelMode = TravelMode.car,
    DateTime? departureTime,
  }) async {
    if (candidates.isEmpty) return const <DriverCandidate>[];

    const perBatch = 15;
    final refinedList = <DriverCandidate>[];
    final unroutable = <DriverCandidate>[];

    for (var i = 0; i < candidates.length; i += perBatch) {
      final batch = candidates.skip(i).take(perBatch).toList();
      final matrix = await routes.calculateRouteMatrix(
        origins: <LatLng>[for (final c in batch) c.driver.position],
        destinations: <LatLng>[pickup],
        travelMode: travelMode,
        departureTime: departureTime,
      );

      for (var j = 0; j < batch.length; j++) {
        final cell = matrix.cells[j][0];
        if (!cell.isValid) {
          unroutable.add(batch[j]);
          continue;
        }
        refinedList.add(
          DriverCandidate(
            driver: batch[j].driver,
            straightLineMeters: batch[j].straightLineMeters,
            drivingMeters: cell.distanceMeters,
            drivingDuration: cell.duration,
          ),
        );
      }
    }

    refinedList.sort(
      (a, b) => a.drivingDuration!.compareTo(b.drivingDuration!),
    );
    return <DriverCandidate>[...refinedList, ...unroutable];
  }

  /// Preselecciona y refina de una vez.
  ///
  /// Es lo que se llama al recibir una petición de carrera.
  Future<List<DriverCandidate>> findNearest(
    List<DriverLocation> drivers,
    LatLng pickup, {
    Duration? staleAfter,
    TravelMode travelMode = TravelMode.car,
    DateTime? now,
  }) async {
    final shortlisted = shortlist(
      drivers,
      pickup,
      staleAfter: staleAfter,
      now: now,
    );
    if (shortlisted.isEmpty) return const <DriverCandidate>[];
    return rank(shortlisted, pickup, travelMode: travelMode);
  }
}

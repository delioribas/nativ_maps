// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/core/enums.dart';
import 'package:meta/meta.dart';

/// Raíz de todo lo que este paquete lanza a propósito.
///
/// Capturar este tipo atrapa cualquier fallo del framework sin atrapar los
/// errores de programación de la app que lo usa, que es justo la distinción
/// que un `catch (e)` genérico borra.
@immutable
sealed class CompassMapsException implements Exception {
  /// Crea la excepción con el mensaje legible que la describe.
  const CompassMapsException(this.message);

  /// Descripción en lenguaje llano de lo que ocurrió.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// El servicio respondió, pero con un error.
///
/// Nunca lleva la URL dentro. En el camino de clave de API la clave viaja en
/// la cadena de consulta, y una URL en un mensaje de error acaba, tarde o
/// temprano, en un informe de fallos, en un log de servidor o en una captura
/// de pantalla pegada en un chat.
@immutable
final class AlsApiException extends CompassMapsException {
  /// Crea la excepción a partir de la respuesta del servicio.
  const AlsApiException({
    required this.operation,
    required this.service,
    required this.statusCode,
    required String message,
    this.awsErrorCode,
    this.requestId,
  }) : super(message);

  /// La operación que falló, p. ej. `SearchText`.
  final String operation;

  /// El servicio al que iba dirigida.
  final AlsService service;

  /// Código HTTP de la respuesta.
  final int statusCode;

  /// El código de error de AWS, si la respuesta lo traía
  /// (p. ej. `ValidationException`, `ThrottlingException`).
  final String? awsErrorCode;

  /// El `x-amzn-RequestId` de la respuesta. Es lo primero que pide el soporte
  /// de AWS, y sin guardarlo aquí se pierde.
  final String? requestId;

  /// ¿Es un problema de configuración y no de red?
  ///
  /// Distinguirlo importa porque cambia qué hacer: un 429 o un 503 se arreglan
  /// reintentando, y un 400 o un 403 no — reintentar un parámetro mal escrito
  /// es gastar cuota para obtener el mismo error tres veces.
  bool get isConfigurationError => statusCode == 400 || statusCode == 403;

  /// ¿Nos está limitando el servicio?
  bool get isThrottled => statusCode == 429;

  /// ¿Merece la pena reintentar?
  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  /// Pista concreta cuando el error es de configuración.
  ///
  /// El `403` de una clave inválida y el de firmar con el nombre de servicio
  /// equivocado son **idénticos**, y esa ambigüedad es la que hace perder una
  /// tarde. Aquí queda escrita.
  String? get hint => switch (statusCode) {
    403 =>
      'Un 403 aquí significa una de tres cosas, y las tres dan la '
          'misma respuesta: (1) la clave de API no es válida o caducó; '
          '(2) la política de IAM no permite esta operación; (3) se firmó '
          'con el nombre de servicio equivocado — este es "'
          '${service.signingName}", no "geo" ni el nombre del host.',
    400 =>
      'Un 400 suele ser un parámetro que este servicio no conoce. '
          'Los tres más repetidos: enviar `DistanceUnit` (no existe en v2), '
          'combinar dos sesgos excluyentes en la misma petición, o pasar un '
          '`MaxResults` fuera del rango que admite la operación.',
    404 =>
      'La ruta del endpoint no existe. Suele ser una URL de la '
          'generación v0 —con `/maps/v0/` o un nombre de recurso dentro— '
          'contra el host de v2.',
    _ => null,
  };

  @override
  String toString() {
    final buffer = StringBuffer('AlsApiException($operation, $statusCode')
      ..write(awsErrorCode == null ? '' : ', $awsErrorCode')
      ..write('): $message');
    if (requestId != null) buffer.write('\n  RequestId: $requestId');
    if (hint != null) buffer.write('\n  Pista: $hint');
    return buffer.toString();
  }
}

/// No se pudo hablar con el servicio: sin red, DNS caído, TLS rechazado o se
/// agotó el tiempo en todos los intentos.
///
/// Es distinto de [AlsApiException] a propósito: aquí el servicio no llegó a
/// contestar, así que **no se ha facturado nada** y reintentar más tarde es
/// razonable.
@immutable
final class AlsTransportException extends CompassMapsException {
  /// Crea la excepción indicando cuántos intentos se hicieron.
  const AlsTransportException({
    required this.operation,
    required String message,
    required this.attempts,
    this.cause,
  }) : super(message);

  /// La operación que no llegó a completarse.
  final String operation;

  /// Cuántos intentos se hicieron antes de rendirse.
  final int attempts;

  /// El error original de la capa de red, si lo hubo.
  final Object? cause;

  @override
  String toString() =>
      'AlsTransportException($operation, $attempts intento(s)): $message'
      '${cause == null ? '' : '\n  Causa: $cause'}';
}

/// La respuesta llegó con un 200 pero no se pudo interpretar.
///
/// Casi siempre significa que el servicio cambió una forma bajo los pies. Se
/// distingue de [AlsApiException] porque la acción es otra: aquí no hay nada
/// que reintentar, hay que mirar el cuerpo real.
@immutable
final class AlsParseException extends CompassMapsException {
  /// Crea la excepción indicando qué campo no se pudo leer.
  const AlsParseException({
    required this.operation,
    required String message,
    this.field,
  }) : super(message);

  /// La operación cuya respuesta no se pudo leer.
  final String operation;

  /// El campo concreto que falló, si se sabe.
  final String? field;

  @override
  String toString() =>
      'AlsParseException($operation'
      '${field == null ? '' : ', campo "$field"'}): $message';
}

/// Falta configuración para poder llamar al servicio.
///
/// Se lanza **antes** de enviar nada, para que el fallo salga en el sitio
/// donde se puede corregir.
@immutable
final class CompassMapsConfigurationException extends CompassMapsException {
  /// Crea la excepción con la explicación de qué falta.
  const CompassMapsConfigurationException(super.message);
}

/// Se alcanzó el tope de gasto configurado en `Budget`.
///
/// El nombre de la excepción es literal: no es un error del servicio, es el
/// framework negándose a seguir gastando. Que exista un tipo propio permite
/// distinguir «se acabó el presupuesto» de «falló la red» en la pantalla, que
/// son dos mensajes muy distintos para el usuario.
@immutable
final class BudgetExhaustedException extends CompassMapsException {
  /// Crea la excepción con el estado del presupuesto en el momento del corte.
  const BudgetExhaustedException({
    required this.operation,
    required this.requestedUnits,
    required this.usedUnits,
    required this.maxUnits,
    required this.window,
    required this.resetsAt,
  }) : super('presupuesto agotado');

  /// La operación que se rechazó.
  final String operation;

  /// Cuántas unidades facturables pedía esa operación.
  ///
  /// No siempre es 1: una isócrona con tres umbrales pide 3, y una matriz de
  /// 10×10 pide 100.
  final int requestedUnits;

  /// Cuántas se llevan gastadas en la ventana actual.
  final int usedUnits;

  /// El tope configurado.
  final int maxUnits;

  /// La duración de la ventana.
  final Duration window;

  /// Cuándo vuelve a haber presupuesto.
  final DateTime resetsAt;

  @override
  String toString() =>
      'BudgetExhaustedException($operation): pedía $requestedUnits unidad(es), '
      'quedan ${maxUnits - usedUnits} de $maxUnits en una ventana de '
      '${window.inMinutes} min. Se restablece a las '
      '${resetsAt.toIso8601String()}.';
}

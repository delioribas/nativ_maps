// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// Root of everything this package throws on purpose.
///
/// Catching this type catches any framework failure without catching the
/// programming errors of the app using it, which is exactly the distinction a
/// generic `catch (e)` erases.
@immutable
sealed class NativMapsException implements Exception {
  /// Creates the exception with the readable message that describes it.
  const NativMapsException(this.message);

  /// Plain-language description of what happened.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The service responded, but with an error.
///
/// It never carries the URL inside. On the API key path the key travels in
/// the query string, and a URL in an error message ends up, sooner or later,
/// in a crash report, in a server log or in a screenshot pasted into a chat.
@immutable
final class AlsApiException extends NativMapsException {
  /// Creates the exception from the service response.
  const AlsApiException({
    required this.operation,
    required this.service,
    required this.statusCode,
    required String message,
    this.awsErrorCode,
    this.requestId,
  }) : super(message);

  /// The operation that failed, e.g. `SearchText`.
  final String operation;

  /// The service it was addressed to.
  final AlsService service;

  /// HTTP status code of the response.
  final int statusCode;

  /// The AWS error code, if the response included one
  /// (e.g. `ValidationException`, `ThrottlingException`).
  final String? awsErrorCode;

  /// The response's `x-amzn-RequestId`. It is the first thing AWS support
  /// asks for, and without keeping it here it gets lost.
  final String? requestId;

  /// Is it a configuration problem and not a network one?
  ///
  /// Telling them apart matters because it changes what to do: a 429 or a 503
  /// is fixed by retrying, and a 400 or a 403 is not — retrying a misspelled
  /// parameter is spending quota to get the same error three times.
  bool get isConfigurationError => statusCode == 400 || statusCode == 403;

  /// Is the service throttling us?
  bool get isThrottled => statusCode == 429;

  /// Is it worth retrying?
  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  /// A specific hint when the error is a configuration one.
  ///
  /// The `403` from an invalid key and the one from signing with the wrong
  /// service name are **identical**, and that ambiguity is what costs you an
  /// afternoon. Here it is written down.
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

/// The service could not be reached: no network, DNS down, TLS rejected or
/// every attempt timed out.
///
/// It is different from [AlsApiException] on purpose: here the service never
/// got to answer, so **nothing has been billed** and retrying later is
/// reasonable.
@immutable
final class AlsTransportException extends NativMapsException {
  /// Creates the exception stating how many attempts were made.
  const AlsTransportException({
    required this.operation,
    required String message,
    required this.attempts,
    this.cause,
  }) : super(message);

  /// The operation that never completed.
  final String operation;

  /// How many attempts were made before giving up.
  final int attempts;

  /// The original error from the network layer, if there was one.
  final Object? cause;

  @override
  String toString() =>
      'AlsTransportException($operation, $attempts intento(s)): $message'
      '${cause == null ? '' : '\n  Causa: $cause'}';
}

/// The response arrived with a 200 but could not be interpreted.
///
/// It almost always means the service changed a shape under your feet. It is
/// kept apart from [AlsApiException] because the action is different: here
/// there is nothing to retry, you have to look at the actual body.
@immutable
final class AlsParseException extends NativMapsException {
  /// Creates the exception stating which field could not be read.
  const AlsParseException({
    required this.operation,
    required String message,
    this.field,
  }) : super(message);

  /// The operation whose response could not be read.
  final String operation;

  /// The specific field that failed, if known.
  final String? field;

  @override
  String toString() =>
      'AlsParseException($operation'
      '${field == null ? '' : ', campo "$field"'}): $message';
}

/// Configuration is missing to be able to call the service.
///
/// It is thrown **before** sending anything, so the failure surfaces in the
/// place where it can be fixed.
@immutable
final class NativMapsConfigurationException extends NativMapsException {
  /// Creates the exception with the explanation of what is missing.
  const NativMapsConfigurationException(super.message);
}

/// The spending cap configured in `Budget` was reached.
///
/// The exception's name is literal: it is not a service error, it is the
/// framework refusing to keep spending. Having its own type lets the screen
/// tell "the budget ran out" apart from "the network failed", which are two
/// very different messages for the user.
@immutable
final class BudgetExhaustedException extends NativMapsException {
  /// Creates the exception with the budget state at the moment of the cutoff.
  const BudgetExhaustedException({
    required this.operation,
    required this.requestedUnits,
    required this.usedUnits,
    required this.maxUnits,
    required this.window,
    required this.resetsAt,
  }) : super('presupuesto agotado');

  /// The operation that was rejected.
  final String operation;

  /// How many billing units that operation requested.
  ///
  /// It is not always 1: an isoline with three thresholds requests 3, and a
  /// 10×10 matrix requests 100.
  final int requestedUnits;

  /// How many have been spent in the current window.
  final int usedUnits;

  /// The configured cap.
  final int maxUnits;

  /// The window duration.
  final Duration window;

  /// When budget becomes available again.
  final DateTime resetsAt;

  @override
  String toString() =>
      'BudgetExhaustedException($operation): pedía $requestedUnits unidad(es), '
      'quedan ${maxUnits - usedUnits} de $maxUnits en una ventana de '
      '${window.inMinutes} min. Se restablece a las '
      '${resetsAt.toIso8601String()}.';
}

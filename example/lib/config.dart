// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';

/// Configuración de la app de ejemplo.
///
/// ## Cómo ejecutarla
///
/// ```sh
/// flutter run --dart-define=ALS_API_KEY=tu-clave --dart-define=ALS_REGION=us-east-1
/// ```
///
/// Se usa `--dart-define` y no un fichero `.env` a propósito: un `.env` acaba
/// en el repositorio antes o después, y una clave de Amazon Location en un
/// repositorio público se gasta sola en cuestión de horas.
///
/// Sin clave, la app arranca igual y enseña una pantalla explicando qué falta,
/// en vez de un mapa gris sin explicación.
abstract final class Config {
  /// La clave de API, si se pasó por `--dart-define`.
  static const String apiKey = String.fromEnvironment('ALS_API_KEY');

  /// La región de AWS.
  static const String region = String.fromEnvironment(
    'ALS_REGION',
    defaultValue: 'us-east-1',
  );

  /// El idioma de los resultados.
  static const String language = String.fromEnvironment(
    'ALS_LANGUAGE',
    defaultValue: 'es',
  );

  /// La URL de un proxy que firma (`ProxyCredentials`), si se usa uno.
  ///
  /// ```sh
  /// flutter run --dart-define=ALS_PROXY_URL=http://10.0.2.2:8080/geo \
  ///   --dart-define=ALS_PROXY_TOKEN=token-de-prueba
  /// ```
  ///
  /// Con ella, la app no lleva ninguna clave: el proxy la guarda. Los
  /// servidores de referencia están en `proxies/` y la guía en
  /// `doc/PROXY.md`. Desde el emulador de Android, el `localhost` del
  /// ordenador es `10.0.2.2`.
  static const String proxyUrl = String.fromEnvironment('ALS_PROXY_URL');

  /// El token con el que la app se identifica ante el proxy.
  static const String proxyToken = String.fromEnvironment('ALS_PROXY_TOKEN');

  /// ¿Va por un proxy?
  static bool get usesProxy => proxyUrl.isNotEmpty;

  /// ¿Hay clave o proxy?
  static bool get isConfigured => apiKey.isNotEmpty || usesProxy;

  /// Las cabeceras que el mapa manda con el estilo y las teselas: el token
  /// del proxy, si lo hay. Con clave de API no hace falta ninguna.
  static Map<String, String>? get mapHeaders => usesProxy
      ? <String, String>{'Authorization': 'Bearer $proxyToken'}
      : null;

  /// Quito, que es donde se centra el mapa al arrancar.
  static final LatLng defaultCenter = LatLng(-0.1807, -78.4678);

  /// El cliente compartido por toda la app.
  ///
  /// Se construye una vez y se reutiliza: cada instancia trae sus propias
  /// cachés, y crear una por pantalla significa pagar dos veces la misma
  /// búsqueda.
  ///
  /// El presupuesto está deliberadamente apretado —200 unidades por minuto—
  /// porque esta app existe para probar, y una pantalla de pruebas con un
  /// bucle es exactamente el caso que el tope tiene que atrapar.
  static final NativMaps maps = NativMaps(
    region: region,
    credentials: usesProxy
        ? ProxyCredentials(
            baseUrl: Uri.parse(proxyUrl),
            headers: <String, String>{'Authorization': 'Bearer $proxyToken'},
          )
        : const ApiKeyCredentials(apiKey),
    language: language,
    budget: Budget(
      maxUnits: 200,
      onExceeded: (event) {
        // En una app real, aquí va el registro. Sin este enganche, un tope en
        // modo aviso no deja rastro de que se cruzó.
        // ignore: avoid_print
        print('⚠️  Presupuesto: $event');
      },
    ),
  );
}

// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:compass_maps/src/auth/credentials.dart';
import 'package:compass_maps/src/client/budget.dart';
import 'package:compass_maps/src/client/transport.dart';
import 'package:compass_maps/src/core/enums.dart';
import 'package:compass_maps/src/geofencing/geofencing_client.dart';
import 'package:compass_maps/src/maps/maps_client.dart';
import 'package:compass_maps/src/places/places_client.dart';
import 'package:compass_maps/src/routes/routes_client.dart';
import 'package:compass_maps/src/tracking/tracking_client.dart';
import 'package:http/http.dart' as http;

/// La puerta de entrada a las **44 operaciones** de Amazon Location.
///
/// ```dart
/// final maps = CompassMaps(
///   region: 'us-east-1',
///   credentials: const ApiKeyCredentials('...'),
///   language: 'es',
///   budget: Budget(maxUnits: 500, window: const Duration(minutes: 1)),
/// );
///
/// final lugares = await maps.places.searchText(queryText: 'gasolinera');
/// final ruta = await maps.routes.calculateRoutes(
///   origin: aqui,
///   destination: lugares.places.first.position!,
/// );
/// final estilo = maps.maps.styleDescriptorUrl(MapStyle.standard);
///
/// maps.close(); // cierra el cliente HTTP
/// ```
///
/// ## Por qué tres clientes y no diecisiete métodos aquí
///
/// Porque son servicios distintos: **firman con nombres distintos**
/// —`geo-places`, `geo-routes`, `geo-maps` en la generación v2, y `geo` a
/// secas en geovallas y rastreo—, tienen hosts distintos y se facturan por
/// separado. Aplanarlos en una sola clase escondería precisamente la
/// distinción que hay que tener presente al mirar una factura o al depurar un
/// `403`.
///
/// | Cliente | Operaciones | Generación |
/// |---|---|---|
/// | [places] | 7 | v2, sin recursos |
/// | [routes] | 5 | v2, sin recursos |
/// | [maps] | 5 | v2, sin recursos |
/// | [geofencing] | 12 | anterior, **exige SigV4** |
/// | [tracking] | 15 | anterior, **exige SigV4** |
///
/// ## Esto no depende de Flutter
///
/// A propósito. `compass_maps` se prueba sin emulador, corre en una
/// herramienta de línea de órdenes y sirve en un servidor Dart. El widget del
/// mapa vive en `compass_maps_flutter`, que reexporta todo esto: instalando
/// solo ese paquete ya se tienen las cuarenta y cuatro operaciones.
class CompassMaps {
  /// Crea el cliente.
  ///
  /// [region] es la región de AWS, p. ej. `us-east-1`. **Tiene que ser una
  /// donde Amazon Location esté disponible**; en una que no lo esté, el DNS
  /// resuelve igual y el error llega como un fallo de conexión genérico.
  ///
  /// [budget] es el tope de gasto. Su valor por defecto —600 unidades por
  /// minuto— no pretende ser el correcto para ninguna app concreta: pretende
  /// que un bucle desbocado se detenga en el primer minuto en vez de en la
  /// factura del mes. Ajústalo o pásale [Budget.unlimited] a conciencia.
  ///
  /// [httpClient] permite inyectar un `MockClient` en las pruebas. Si se pasa,
  /// [close] **no** lo cierra: lo cierra quien lo creó.
  CompassMaps({
    required this.region,
    required this.credentials,
    this.language,
    this.politicalView,
    this.intendedUse = IntendedUse.singleUse,
    Budget? budget,
    TransportOptions transportOptions = const TransportOptions(),
    http.Client? httpClient,
  }) : budget = budget ?? Budget(maxUnits: 600),
       _transport = AlsTransport(
         region: region,
         credentials: credentials,
         budget: budget ?? Budget(maxUnits: 600),
         options: transportOptions,
         httpClient: httpClient,
       ) {
    if (region.isEmpty) {
      throw ArgumentError.value(region, 'region', 'no puede estar vacía');
    }
    places = PlacesClient(
      transport: _transport,
      intendedUse: intendedUse,
      language: language,
      politicalView: politicalView,
    );
    routes = RoutesClient(transport: _transport, language: language);
    maps = MapsClient(
      transport: _transport,
      region: region,
      politicalView: politicalView,
    );
    geofencing = GeofencingClient(transport: _transport);
    tracking = TrackingClient(transport: _transport);
  }

  /// La región de AWS.
  final String region;

  /// Cómo se autentica cada petición.
  final Credentials credentials;

  /// Idioma de los resultados, en BCP 47.
  final String? language;

  /// Punto de vista político para las fronteras en disputa, en ISO 3166.
  final String? politicalView;

  /// Si los resultados se van a guardar. Ver [IntendedUse].
  final IntendedUse intendedUse;

  /// El tope de gasto, compartido por los tres clientes.
  ///
  /// Es uno solo a propósito: el gasto es de la cuenta de AWS, no de cada
  /// servicio. Tres presupuestos separados dejarían pasar el triple.
  final Budget budget;

  final AlsTransport _transport;

  /// Las siete operaciones de Places.
  late final PlacesClient places;

  /// Las cinco operaciones de Routes.
  late final RoutesClient routes;

  /// Las operaciones de Maps.
  late final MapsClient maps;

  /// Las doce operaciones de geovallas.
  ///
  /// ⚠️ Son de la **generación anterior**: hay que crear una colección y
  /// **no admiten clave de API**. Con `ApiKeyCredentials`, la primera llamada
  /// lanza `CompassMapsConfigurationException` explicando que hacen falta
  /// credenciales SigV4.
  late final GeofencingClient geofencing;

  /// Las quince operaciones de rastreo de dispositivos.
  ///
  /// ⚠️ Mismas condiciones que [geofencing]. Y antes de usarlo, la pregunta
  /// que ahorra dinero: **si ya guardas el histórico en tu propia base de
  /// datos, esto es infraestructura duplicada.** Lo que sí justifica usarlo
  /// está en la documentación de `TrackingClient`.
  late final TrackingClient tracking;

  /// ¿Hay credenciales suficientes para llamar al servicio?
  ///
  /// Conviene comprobarlo al arrancar: sin esto, la primera pantalla de mapa
  /// falla con un error de red que no dice que falta la clave.
  bool get isConfigured => credentials.isConfigured;

  /// Vacía todas las cachés.
  ///
  /// Hay que llamarlo al cambiar de idioma o de sesión.
  void clearCaches() {
    places.clearCache();
    routes.clearCache();
  }

  /// Cierra el cliente HTTP y las credenciales.
  ///
  /// Después de esto, cualquier operación lanza [StateError]. Es idempotente.
  void close() => _transport.close();
}

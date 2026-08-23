// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:nativ_maps/src/core/enums.dart';

/// Cómo se autentica una petición a Amazon Location.
///
/// Los tres caminos del mundo real caben detrás de esta interfaz, y la app que
/// los usa no tiene que enterarse de cuál está puesto:
///
/// | Camino | Implementación | Coste |
/// |---|---|---|
/// | Clave de API | `ApiKeyCredentials` | se extrae de un APK |
/// | Proxy que firma | `ProxyCredentials` | un endpoint nuevo |
/// | SigV4 en el móvil | `nativ_maps_sigv4` | configurar Cognito |
///
/// Cambiar de camino es cambiar el objeto que se pasa al construir el cliente.
/// Nada más arriba se entera.
///
/// ## Por qué [sign] recibe el servicio
///
/// Porque **los tres servicios firman con nombres distintos**: `geo-places`,
/// `geo-routes` y `geo-maps`. Firmar con el equivocado da un `403` idéntico al
/// de una clave mala. Pasar [AlsService] en vez de una cadena hace que ese
/// error no se pueda cometer.
abstract interface class Credentials {
  /// Devuelve la petición lista para enviar: firmada, con la clave puesta o
  /// redirigida al proxy, según el camino.
  ///
  /// Puede devolver una petición distinta de la recibida. No debe modificar
  /// [request] si devuelve otra.
  Future<http.BaseRequest> sign(
    http.BaseRequest request,
    AlsService service,
    String region,
  );

  /// La base a la que se dirigen las peticiones de [service] en [region].
  ///
  /// El camino directo devuelve el host de AWS; el de proxy, el del backend.
  /// Que lo decida la credencial y no el cliente es lo que permite cambiar de
  /// camino sin tocar ninguna de las diecisiete operaciones.
  Uri baseUri(AlsService service, String region);

  /// ¿Hay configuración suficiente para llamar al servicio?
  ///
  /// Se consulta antes de enviar, para que una clave vacía dé un error claro
  /// en lugar de un `403` del servidor cinco capas más abajo.
  bool get isConfigured;

  /// La clave que hay que poner en la cadena de consulta de una URL que se le
  /// entrega a MapLibre, o `null` si este camino no usa clave.
  ///
  /// Existe porque hay una frontera que [sign] no puede cubrir: el descriptor
  /// de estilo y las teselas **no los pide este paquete**, los pide MapLibre a
  /// partir de una URL que le damos. Ahí no hay `http.BaseRequest` que firmar.
  ///
  /// El camino de proxy y el de SigV4 devuelven `null` a propósito: los dos
  /// autentican con cabeceras, y el widget del mapa las instala con
  /// `setCustomHeaders`. Solo el de clave de API necesita ponerla en la URL, y
  /// por eso ese es el único camino en el que la clave sale en texto.
  String? get apiKeyForUrl;

  /// Libera lo que haya que liberar (clientes HTTP internos, temporizadores de
  /// renovación de credenciales temporales). Es idempotente.
  void close();
}

/// Base cómoda para escribir una [Credentials] propia.
///
/// Da por hecho el camino directo a AWS —el host de [AlsService.hostFor]— y
/// deja solo [sign] por implementar. Quien necesite otro destino, que
/// implemente [Credentials] entera.
@immutable
abstract base class DirectCredentials implements Credentials {
  /// Constructor constante para las subclases.
  const DirectCredentials();

  @override
  Uri baseUri(AlsService service, String region) =>
      Uri.https(service.hostFor(region));

  @override
  bool get isConfigured => true;

  @override
  String? get apiKeyForUrl => null;

  @override
  void close() {}
}

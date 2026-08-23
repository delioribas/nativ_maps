// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:async';

import 'package:compass_maps_example/config.dart';
import 'package:compass_maps_example/widgets/demo_scaffold.dart';
import 'package:compass_maps_flutter/compass_maps_flutter.dart';
import 'package:flutter/material.dart';

/// **Las 7 operaciones de Places**, cada una con su patrón de uso correcto.
///
/// ## El patrón barato de una barra de búsqueda
///
/// Es la parte que más dinero ahorra y la que más se hace mal:
///
/// 1. Al teclear → `autocomplete`, que es la operación más barata. Con
///    antirrebote de 300 ms: sin él, «gasolinera» son diez peticiones.
/// 2. `autocomplete` **no devuelve coordenadas**. Y está bien: el usuario
///    todavía no ha elegido.
/// 3. Al tocar una sugerencia → `getPlace` con su `placeId`. Una petición
///    más, y solo por la que eligió, no por las veinte que vio.
///
/// Hacerlo con `searchText` en cada tecla cuesta lo mismo por petición y
/// devuelve mucho más de lo que hace falta para pintar una lista.
class BusquedaDemo extends StatefulWidget {
  /// Crea la demostración.
  const BusquedaDemo({super.key});

  @override
  State<BusquedaDemo> createState() => _BusquedaDemoState();
}

class _BusquedaDemoState extends State<BusquedaDemo> {
  CompassMapController? _mapa;
  final _texto = TextEditingController();

  /// El antirrebote vive AQUÍ y no en el cliente a propósito: depende del
  /// ritmo de escritura y del hilo de la interfaz, y meterlo en el núcleo
  /// obligaría a que supiera de temporizadores de interfaz.
  Timer? _antirrebote;

  List<AutocompleteSuggestion> _sugerencias = <AutocompleteSuggestion>[];
  final List<Widget> _resultado = <Widget>[];
  bool _cargando = false;
  Object? _error;

  @override
  void dispose() {
    _antirrebote?.cancel();
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoScaffold(
    titulo: 'Búsqueda de lugares',
    cargando: _cargando,
    error: _error,
    panel: _panel(),
    child: Column(
      children: <Widget>[
        _barraDeBusqueda(),
        if (_sugerencias.isNotEmpty) _listaDeSugerencias(),
        Expanded(
          child: CompassMap(
            styleUrl: Config.maps.maps.styleDescriptorUrl(MapStyle.standard)!,
            initialCameraPosition: CameraPosition(
              target: Config.defaultCenter,
              zoom: 13,
            ),
            onMapCreated: (controller) => _mapa = controller,
            // Mantener pulsado geocodifica al revés: de coordenada a
            // dirección. Es lo que hay que enseñar cuando salta una alarma
            // — nadie despacha una unidad a un par de decimales.
            onLongPress: _geocodificarAlReves,
            padding: const EdgeInsets.only(bottom: 260),
          ),
        ),
      ],
    ),
  );

  Widget _barraDeBusqueda() => Padding(
    padding: const EdgeInsets.all(12),
    child: TextField(
      controller: _texto,
      decoration: InputDecoration(
        hintText: 'Escribe una dirección o un negocio…',
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _texto.clear();
            setState(() => _sugerencias = <AutocompleteSuggestion>[]);
          },
        ),
      ),
      onChanged: _alEscribir,
      onSubmitted: (texto) => unawaited(_buscarTexto(texto)),
    ),
  );

  /// Paso 1: autocompletar con antirrebote.
  void _alEscribir(String texto) {
    _antirrebote?.cancel();
    if (texto.trim().length < 3) {
      setState(() => _sugerencias = <AutocompleteSuggestion>[]);
      return;
    }
    // 300 ms: por debajo se disparan peticiones a media palabra; por encima
    // se nota el retraso al escribir.
    _antirrebote = Timer(const Duration(milliseconds: 300), () async {
      await _ejecutar(() async {
        final sugerencias = await Config.maps.places.autocomplete(
          query: texto,
          // El sesgo ORDENA por cercanía; el filtro DESCARTA lo de fuera. No
          // son lo mismo y no son excluyentes.
          biasPosition: Config.defaultCenter,
          filter: const SearchFilter(includeCountries: <String>['ECU']),
          maxResults: 6,
        );
        setState(() => _sugerencias = sugerencias);
      });
    });
  }

  Widget _listaDeSugerencias() => Container(
    constraints: const BoxConstraints(maxHeight: 180),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListView.builder(
      shrinkWrap: true,
      itemCount: _sugerencias.length,
      itemBuilder: (context, index) {
        final sugerencia = _sugerencias[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.place_outlined, size: 18),
          title: Text(sugerencia.title),
          subtitle: sugerencia.address == null
              ? null
              : Text(
                  sugerencia.address!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          // Paso 2: solo AQUÍ se paga la segunda petición.
          onTap: () => unawaited(_abrirSugerencia(sugerencia)),
        );
      },
    ),
  );

  /// Paso 2: la ficha completa, solo de la que el usuario eligió.
  Future<void> _abrirSugerencia(AutocompleteSuggestion sugerencia) async {
    final placeId = sugerencia.placeId;
    if (placeId == null) return;

    await _ejecutar(() async {
      final lugar = await Config.maps.places.getPlace(
        placeId,
        // Estos tres datos SOLO los da `getPlace`. Es lo que justifica su
        // precio frente a `searchText`.
        additionalFeatures: const <PlaceFeature>[
          PlaceFeature.contact,
          PlaceFeature.timeZone,
          PlaceFeature.access,
        ],
      );
      await _mostrarLugar(lugar, 'GetPlace');
      setState(() => _sugerencias = <AutocompleteSuggestion>[]);
    });
  }

  /// Búsqueda por texto libre: devuelve lugares CON coordenada.
  Future<void> _buscarTexto(String texto) async {
    if (texto.trim().isEmpty) return;
    await _ejecutar(() async {
      final respuesta = await Config.maps.places.searchText(
        queryText: texto,
        biasPosition: Config.defaultCenter,
        maxResults: 10,
      );
      if (respuesta.isEmpty) {
        setState(
          () => _resultado
            ..clear()
            ..add(const Dato('SearchText', 'sin resultados')),
        );
        return;
      }

      await _mapa?.setMarkers(<Marker>[
        for (final (indice, lugar) in respuesta.places.indexed)
          if (lugar.position != null)
            Marker(
              markerId: MarkerId('r-$indice'),
              position: lugar.position!,
              infoWindow: InfoWindow(
                title: lugar.title,
                snippet: lugar.formattedAddress,
              ),
            ),
      ]);

      final puntos = <LatLng>[
        for (final lugar in respuesta.places)
          if (lugar.position != null) lugar.position!,
      ];
      if (puntos.isNotEmpty) {
        await _mapa?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds.fromPoints(puntos).padded(500),
            48,
          ),
        );
      }

      setState(() {
        _resultado
          ..clear()
          ..add(Dato('SearchText', '${respuesta.places.length} resultados'))
          ..add(Dato('Hay más páginas', '${respuesta.hasMore}'))
          ..add(Dato('Tramo de precio', respuesta.pricingBucket ?? '—'));
      });
    });
  }

  /// De coordenada a dirección, con el radio acotado.
  ///
  /// Sin `radiusMeters`, una posición en una zona sin direcciones devuelve la
  /// localidad más próxima **aunque esté a kilómetros**, y eso se enseña igual
  /// que una dirección exacta. Comprobar `placeType.isPrecise` distingue los
  /// dos casos.
  Future<void> _geocodificarAlReves(LatLng posicion) async {
    await _ejecutar(() async {
      final lugares = await Config.maps.places.reverseGeocode(
        posicion,
        radiusMeters: 200,
        maxResults: 2,
      );
      if (lugares.isEmpty) {
        setState(
          () => _resultado
            ..clear()
            ..add(const Dato('ReverseGeocode', 'nada en 200 m')),
        );
        return;
      }
      await _mostrarLugar(lugares.first, 'ReverseGeocode');
    });
  }

  Future<void> _mostrarLugar(Place lugar, String operacion) async {
    await _mapa?.setMarkers(<Marker>[
      if (lugar.position != null)
        Marker(
          markerId: const MarkerId('elegido'),
          position: lugar.position!,
          infoWindow: InfoWindow(
            title: lugar.title,
            snippet: lugar.formattedAddress,
          ),
        ),
    ]);
    if (lugar.position != null) {
      await _mapa?.animateCamera(
        CameraUpdate.newLatLngZoom(lugar.position!, 16),
      );
    }

    setState(() {
      _resultado
        ..clear()
        ..add(Dato('Operación', operacion))
        ..add(Dato('Título', lugar.title))
        ..add(Dato('Tipo', lugar.placeType?.wireName ?? '—'))
        ..add(
          Dato(
            'Precisión',
            lugar.placeType?.isPrecise ?? false
                ? 'exacta'
                : 'aproximada — no es un portal',
          ),
        )
        ..add(Dato('Dirección', lugar.formattedAddress ?? '—'))
        ..add(Dato('Corta', lugar.address?.shortLabel ?? '—'))
        ..add(Dato('País', lugar.address?.country?.code3 ?? '—'))
        ..add(Dato('Posición', _fmt(lugar.position)))
        ..add(Dato('Para navegar', _fmt(lugar.navigationPosition)))
        ..add(Dato('Zona horaria', lugar.timeZone?.name ?? '—'))
        ..add(
          Dato('Teléfono', lugar.contacts?.phones.firstOrNull?.value ?? '—'),
        )
        ..add(
          Dato(
            'Coincidencia',
            lugar.matchScore == null
                ? '—'
                : '${(lugar.matchScore! * 100).round()} %',
          ),
        );
    });
  }

  Widget _panel() => PanelDeResultados(
    titulo: 'Las 7 operaciones de Places',
    altura: 260,
    children: <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _Chip('Geocode', _geocodificar),
          _Chip('SearchNearby', _cerca),
          _Chip('Suggest', _sugerir),
          _Chip('Limpiar', () async {
            await _mapa?.clearMarkers();
            setState(_resultado.clear);
          }),
        ],
      ),
      const SizedBox(height: 8),
      ..._resultado,
      if (_resultado.isEmpty)
        const Text(
          'Escribe arriba para autocompletar, o mantén pulsado el mapa '
          'para geocodificar al revés.',
          style: TextStyle(fontSize: 12),
        ),
    ],
  );

  /// Geocodificar: de dirección a coordenada, **con puntuación**.
  ///
  /// `matchScore` es lo que permite automatizar: por encima de 0,9 y con
  /// `PlaceType.pointAddress` se puede aceptar la dirección sola; por debajo
  /// hay que preguntar. Sin ella, la única opción honesta es preguntar
  /// siempre.
  Future<void> _geocodificar() => _ejecutar(() async {
    final lugares = await Config.maps.places.geocode(
      queryComponents: const AddressComponents(
        country: 'ECU',
        locality: 'Quito',
        street: 'Av. Amazonas',
        addressNumber: '1234',
      ),
      maxResults: 3,
    );
    if (lugares.isEmpty) return;
    await _mostrarLugar(lugares.first, 'Geocode (por componentes)');
  });

  /// Qué hay cerca, sin que el usuario escriba nada.
  Future<void> _cerca() => _ejecutar(() async {
    final centro = await _mapa?.getCameraPosition();
    final posicion = centro?.target ?? Config.defaultCenter;

    final respuesta = await Config.maps.places.searchNearby(
      position: posicion,
      radiusMeters: 1000,
      maxResults: 15,
    );

    await _mapa?.setMarkers(<Marker>[
      for (final (indice, lugar) in respuesta.places.indexed)
        if (lugar.position != null)
          Marker(
            markerId: MarkerId('cerca-$indice'),
            position: lugar.position!,
            icon: BitmapDescriptor.defaultMarkerWithHue(MarkerHue.hueGreen),
            infoWindow: InfoWindow(
              title: lugar.title,
              snippet: lugar.distanceMeters == null
                  ? null
                  : '${lugar.distanceMeters!.round()} m en línea recta',
            ),
          ),
    ]);

    setState(() {
      _resultado
        ..clear()
        ..add(Dato('SearchNearby', '${respuesta.places.length} en 1 km'))
        ..add(const Dato('Ojo', 'ordena por línea recta, no por carretera'));
      for (final lugar in respuesta.places.take(6)) {
        _resultado.add(
          Dato(lugar.title, '${lugar.distanceMeters?.round() ?? '?'} m'),
        );
      }
    });
  });

  /// Sugerencias mezcladas: sitios y consultas para refinar.
  Future<void> _sugerir() => _ejecutar(() async {
    final respuesta = await Config.maps.places.suggest(
      query: 'restau',
      biasPosition: Config.defaultCenter,
      // Sin `core`, las sugerencias de sitio llegan solo con el título.
      // Eso es lo que las hace baratas.
      additionalFeatures: const <PlaceFeature>[PlaceFeature.core],
    );

    setState(() {
      _resultado
        ..clear()
        ..add(Dato('Suggest', '${respuesta.results.length} sugerencias'));
      for (final resultado in respuesta.results) {
        _resultado.add(
          Dato(
            resultado.type == SuggestResultType.query
                ? '🔎 consulta'
                : '📍 lugar',
            resultado.title,
          ),
        );
      }
      for (final refinamiento in respuesta.queryRefinements) {
        _resultado.add(Dato('Refinar a', refinamiento.refinedTerm ?? '—'));
      }
    });
  });

  /// Envuelve una llamada con el indicador de carga y la captura de errores.
  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on CompassMapsException catch (error) {
      // Se captura el tipo raíz del paquete y no `Object`: así los errores de
      // programación de la app siguen llegando arriba, que es donde se ven.
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static String _fmt(LatLng? p) => p == null
      ? '—'
      : '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto, this.onTap);

  final String texto;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(texto, style: const TextStyle(fontSize: 12)),
    onPressed: () => unawaited(onTap()),
  );
}

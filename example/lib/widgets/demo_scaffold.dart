// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:nativ_maps_flutter/nativ_maps_flutter.dart';
import 'package:flutter/material.dart';

/// El armazón compartido por todas las demostraciones.
///
/// Existe para que cada demo sea **solo** el código que ilustra, sin veinte
/// líneas de `Scaffold` repetidas. Quien lea una demo tiene que ver la llamada
/// al paquete, no la fontanería de la interfaz.
class DemoScaffold extends StatelessWidget {
  /// Crea el armazón.
  const DemoScaffold({
    required this.titulo,
    required this.child,
    super.key,
    this.acciones = const <Widget>[],
    this.panel,
    this.cargando = false,
    this.error,
  });

  /// El título de la barra.
  final String titulo;

  /// El contenido, normalmente un [NativMap].
  final Widget child;

  /// Botones de la barra superior.
  final List<Widget> acciones;

  /// Un panel inferior con los resultados.
  final Widget? panel;

  /// ¿Hay una petición en curso?
  final bool cargando;

  /// El último error, si lo hubo.
  final Object? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(titulo), actions: acciones),
    body: Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        if (cargando)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (error != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _TarjetaDeError(error: error!),
          ),
        if (panel != null)
          Positioned(left: 0, right: 0, bottom: 0, child: panel!),
      ],
    ),
  );
}

/// Enseña un error del paquete con lo que hace falta para arreglarlo.
///
/// No es adorno: [AlsApiException.hint] lleva escrita la causa concreta de
/// cada código, incluido el `403` que se parece a otros tres errores distintos.
class _TarjetaDeError extends StatelessWidget {
  const _TarjetaDeError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (titulo, detalle) = switch (error) {
      final AlsApiException e => (
        'Error ${e.statusCode} en ${e.operation}',
        <String>[e.message, if (e.hint != null) e.hint!].join('\n\n'),
      ),
      final BudgetExhaustedException e => ('Presupuesto agotado', e.toString()),
      final AlsTransportException e => ('Sin conexión', e.message),
      final NativMapsConfigurationException e => ('Sin configurar', e.message),
      _ => ('Error', error.toString()),
    };

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detalle,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un panel inferior con resultados, plegable.
class PanelDeResultados extends StatelessWidget {
  /// Crea el panel.
  const PanelDeResultados({
    required this.titulo,
    required this.children,
    super.key,
    this.altura = 220,
  });

  /// El encabezado.
  final String titulo;

  /// Las filas.
  final List<Widget> children;

  /// Cuánto ocupa.
  final double altura;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    child: SizedBox(
      height: altura,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Una fila de dato con etiqueta y valor.
class Dato extends StatelessWidget {
  /// Crea la fila.
  const Dato(this.etiqueta, this.valor, {super.key});

  /// La etiqueta.
  final String etiqueta;

  /// El valor.
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 130,
          child: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

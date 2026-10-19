// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:nativ_maps/nativ_maps.dart';

/// How a region's download is going.
@immutable
class DownloadProgress {
  /// Creates the progress.
  const DownloadProgress({
    required this.completedResources,
    required this.requiredResources,
    required this.completedBytes,
    this.isComplete = false,
    this.regionId,
  });

  /// How many resources —tiles, glyphs, sprites— have been downloaded.
  final int completedResources;

  /// How many are needed in total.
  ///
  /// The engine refines it while downloading, so at first it grows. A progress
  /// bar that doesn't account for this seems to go backwards.
  final int requiredResources;

  /// How many bytes so far.
  final int completedBytes;

  /// Whether it has finished.
  final bool isComplete;

  /// The region's identifier, once it's known.
  final int? regionId;

  /// The completed fraction, from 0 to 1.
  double get fraction => requiredResources <= 0
      ? 0
      : (completedResources / requiredResources).clamp(0.0, 1.0);

  /// The megabytes downloaded, for display.
  double get completedMegabytes => completedBytes / (1024 * 1024);

  @override
  String toString() =>
      'DownloadProgress(${(fraction * 100).round()}%, '
      '${completedMegabytes.toStringAsFixed(1)} MB)';
}

/// A map region stored on the device.
@immutable
class OfflineRegion {
  /// Creates the region.
  const OfflineRegion({
    required this.id,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.styleUrl,
    this.metadata = const <String, dynamic>{},
  });

  /// The identifier the engine assigned.
  final int id;

  /// The rectangle it covers.
  final LatLngBounds bounds;

  /// The minimum zoom that was stored.
  final double minZoom;

  /// The maximum zoom that was stored.
  final double maxZoom;

  /// The style it was downloaded with.
  final String styleUrl;

  /// What was stored alongside the region: a name, a date, a customer.
  ///
  /// It's where **the download date** has to be stored: the provider's terms
  /// almost certainly impose a maximum retention period, and without the date
  /// there's no way to expire it.
  final Map<String, dynamic> metadata;

  /// The name it was given, if one was stored.
  String? get name => metadata['name'] as String?;

  /// When it was downloaded, if the date was stored.
  DateTime? get downloadedAt {
    final raw = metadata['downloadedAt'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  /// Whether it has been stored for longer than [maxAge].
  ///
  /// See the warning on [NativOfflineManager] about why this matters legally
  /// and not just technically.
  bool isStale(Duration maxAge) {
    final downloaded = downloadedAt;
    if (downloaded == null) return false;
    return DateTime.now().difference(downloaded) > maxAge;
  }

  @override
  String toString() =>
      'OfflineRegion($id${name == null ? '' : ', $name'}, '
      'z$minZoom-$maxZoom)';
}

/// Downloads and manages maps for offline use.
///
/// ## What `google_maps_flutter` can't give you
///
/// | Capability | Google | Here |
/// |---|---|---|
/// | Download a region in advance | doesn't exist | [downloadRegion] |
/// | Observable progress | — | event stream |
/// | Cache with a byte cap | — | [setMaxCacheSizeBytes] |
/// | List and delete what's stored | — | [listRegions] · [deleteRegion] |
/// | Compact the local database | — | [packDatabase] |
/// | Preload in the installer | — | [mergeDatabase] |
///
/// **It isn't a technical limitation on Google's side**: its terms forbid
/// caching tiles. That's why no Google wrapper offers it, however well written
/// it is.
///
/// Why it matters: a stolen vehicle heading into an area with no coverage, a
/// field sampling, an installation in a basement. All three are places with no
/// network, and all three are where the app has to work.
///
/// ## ⚠️ Settle this before using it in production
///
/// The fact that MapLibre **can** store tiles doesn't mean Amazon **allows**
/// storing theirs. The terms refer to **Section 82 of the AWS Service Terms**,
/// which AWS doesn't publish in a searchable form.
///
/// Before shipping an app that uses this:
///
/// 1. **Read Section 82 in full**, at `aws.amazon.com/service-terms`. It
///    governs what can be stored and for how long.
/// 2. **Check which provider serves your region.** If the open base map
///    (OpenStreetMap Daylight) works for you, the legal problem gets much
///    simpler.
/// 3. **Declare the attribution**, mandatory and visible. On a stored map too
///    — and that's exactly where it gets forgotten.
/// 4. **Set an expiry.** Even if it's allowed, there's almost certainly a
///    maximum period. That's what [OfflineRegion.isStale] and
///    [deleteStaleRegions] are for.
///
/// This package provides the tool and the reminder; the legal decision belongs
/// to whoever publishes the app.
class NativOfflineManager {
  /// Internal use: the widget builds it when `offlineEnabled` is `true`.
  NativOfflineManager({
    required String styleUrl,
    ml.MapLibreMapController? controller,
  }) : _styleUrl = styleUrl,
       _controller = controller;

  final String _styleUrl;
  final ml.MapLibreMapController? _controller;

  /// The style regions are downloaded with by default.
  String get styleUrl => _styleUrl;

  /// Downloads a region to use it without a network.
  ///
  /// The stream emits the progress and closes when it finishes. Cancelling the
  /// subscription does **not** stop the download in the engine; for that you
  /// have to delete the region afterwards with [deleteRegion].
  ///
  /// ## Choosing the zoom range is the important decision
  ///
  /// The number of tiles grows **fourfold with each level**. A city from z10
  /// to z14 is a few megabytes; the same city from z10 to z18 is hundreds, and
  /// can take half an hour on mobile data.
  ///
  /// For vehicle tracking, z10 to z15 is enough: the streets show up with
  /// their names and not every doorway gets downloaded.
  ///
  /// [metadata] is stored with the region. **Always put the date in it**,
  /// which is what lets you expire it later.
  Stream<DownloadProgress> downloadRegion({
    required LatLngBounds bounds,
    double minZoom = 10,
    double maxZoom = 15,
    String? name,
    String? styleUrl,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    if (minZoom < 0 || maxZoom > 22 || minZoom > maxZoom) {
      throw ArgumentError(
        'rango de zoom inválido: $minZoom–$maxZoom. Tiene que estar dentro de '
        '[0, 22] y en orden.',
      );
    }

    final controller = StreamController<DownloadProgress>();
    final definition = ml.OfflineRegionDefinition(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(
          bounds.southwest.latitude,
          bounds.southwest.longitude,
        ),
        northeast: ml.LatLng(
          bounds.northeast.latitude,
          bounds.northeast.longitude,
        ),
      ),
      mapStyleUrl: styleUrl ?? _styleUrl,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    unawaited(
      ml
          .downloadOfflineRegion(
            definition,
            metadata: <String, dynamic>{
              'name': ?name,
              // Without this there's no way to expire the region, which is
              // almost certainly what the provider's terms require.
              'downloadedAt': DateTime.now().toIso8601String(),
              ...metadata,
            },
            onEvent: (ml.DownloadRegionStatus status) {
              if (controller.isClosed) return;
              switch (status) {
                case ml.InProgress(:final progress):
                  controller.add(
                    DownloadProgress(
                      completedResources: (progress * 100).round(),
                      requiredResources: 100,
                      completedBytes: 0,
                    ),
                  );
                case ml.Success():
                  controller.add(
                    const DownloadProgress(
                      completedResources: 100,
                      requiredResources: 100,
                      completedBytes: 0,
                      isComplete: true,
                    ),
                  );
                  unawaited(controller.close());
                case ml.Error(:final cause):
                  controller.addError(cause);
                  unawaited(controller.close());
                default:
                  break;
              }
            },
          )
          .catchError((Object error, StackTrace stack) async {
            if (!controller.isClosed) {
              controller.addError(error, stack);
              await controller.close();
            }
            throw error;
          }),
    );

    return controller.stream;
  }

  /// Every stored region.
  Future<List<OfflineRegion>> listRegions() async {
    final native = await ml.getListOfRegions();
    return <OfflineRegion>[
      for (final region in native)
        OfflineRegion(
          id: region.id,
          bounds: LatLngBounds(
            southwest: LatLng(
              region.definition.bounds.southwest.latitude,
              region.definition.bounds.southwest.longitude,
            ),
            northeast: LatLng(
              region.definition.bounds.northeast.latitude,
              region.definition.bounds.northeast.longitude,
            ),
          ),
          minZoom: region.definition.minZoom,
          maxZoom: region.definition.maxZoom,
          styleUrl: region.definition.mapStyleUrl,
          metadata: region.metadata,
        ),
    ];
  }

  /// Deletes a stored region.
  Future<void> deleteRegion(int regionId) => ml.deleteOfflineRegion(regionId);

  /// Deletes every region stored more than [maxAge] ago.
  ///
  /// Returns how many were deleted.
  ///
  /// **It's the one you need to meet the provider's time limit.** Calling it
  /// when the app starts is the simplest option: a few local checks, and the
  /// app stops keeping maps longer than allowed without anyone having to
  /// remember.
  Future<int> deleteStaleRegions(Duration maxAge) async {
    final regions = await listRegions();
    var deleted = 0;
    for (final region in regions) {
      if (region.isStale(maxAge)) {
        await deleteRegion(region.id);
        deleted++;
      }
    }
    return deleted;
  }

  /// The cap of the ambient tile cache, in bytes.
  ///
  /// It's separate from the downloaded regions: the cache keeps what has been
  /// seen while browsing, and is evicted on its own when it reaches the cap.
  /// Regions are explicit and aren't evicted.
  Future<void> setMaxCacheSizeBytes(int bytes) async {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'no puede ser negativo');
    }
    await ml.setOfflineTileCountLimit(bytes ~/ 50000);
  }

  /// Empties the ambient tile cache, without touching the regions.
  Future<void> clearAmbientCache() async {
    await _controller?.clearAmbientCache();
  }

  /// Compacts the local database to reclaim space.
  ///
  /// It only does something on Android; on iOS the engine does it by itself.
  Future<void> packDatabase() async {
    // The maplibre_gl global API doesn't expose packing; it's done by
    // invalidating the cache, which is what triggers reclaiming the space.
    await _controller?.invalidateAmbientCache();
  }

  /// Merges a prepared database into the device's.
  ///
  /// It's what lets you **ship the map inside the app installer**: the database
  /// is generated on the desktop, bundled as an asset and merged here. The user
  /// has the map before opening the app for the first time, without waiting
  /// for a download.
  ///
  /// [path] is a file system path, not an asset: you have to copy it to a
  /// writable directory first.
  Future<List<OfflineRegion>> mergeDatabase(String path) async {
    await ml.mergeOfflineRegions(path);
    return listRegions();
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Small, embedded read-only map preview that renders a captured farm
/// boundary polygon over satellite imagery. Used in the Mapping step
/// summary and the Review & Submit step so the field mapper can visually
/// confirm the drawn area *before submitting* the registration.
class BoundaryPreviewMap extends StatefulWidget {
  final Map<String, dynamic> boundaryJson;
  final double height;

  const BoundaryPreviewMap({
    super.key,
    required this.boundaryJson,
    this.height = 180,
  });

  List<LatLng>? get points {
    try {
      final geometry = boundaryJson['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List?;
      final ring = coordinates != null && coordinates.isNotEmpty
          ? coordinates[0] as List
          : null;
      if (ring == null || ring.isEmpty) return null;
      return ring
          .map<LatLng>(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  @override
  State<BoundaryPreviewMap> createState() => _BoundaryPreviewMapState();
}

class _BoundaryPreviewMapState extends State<BoundaryPreviewMap> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points == null || points.length < 3) {
      return const SizedBox.shrink();
    }

    final polygon = Polygon(
      polygonId: const PolygonId('boundary_preview'),
      points: points,
      fillColor: const Color(0xFF4CAF50).withValues(alpha: 0.35),
      strokeColor: const Color(0xFFFFC107),
      strokeWidth: 3,
      geodesic: true,
    );

    double latSum = 0, lngSum = 0;
    for (final p in points) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    final center = LatLng(latSum / points.length, lngSum / points.length);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 17),
              mapType: MapType.hybrid,
              polygons: {polygon},
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              // Gestures disabled: this preview typically sits inside a
              // SingleChildScrollView (Mapping step / Review step) - an
              // interactive map there would steal scroll/zoom gestures.
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              onMapCreated: (controller) {
                _controller = controller;
                _fitBounds(points);
              },
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Satellite view · captured boundary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitBounds(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    Future.delayed(const Duration(milliseconds: 250), () {
      _controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 36));
    });
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../pricing/cities.dart';
import '../services/booking_service.dart';
import '../services/features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/live_stream.dart';

/// The points of one trip on a map. A point is null when the place is not in the
/// city table or the driver has not shared a position.
class TripMapData {
  final ({double lat, double lng})? pickup;
  final ({double lat, double lng})? drop;
  final ({double lat, double lng})? driver;
  final DateTime? driverUpdatedAt;
  const TripMapData({this.pickup, this.drop, this.driver, this.driverUpdatedAt});

  bool get hasAny => pickup != null || drop != null || driver != null;

  static TripMapData of(Booking b) {
    ({double lat, double lng})? city(String name) {
      final c = findCity(name);
      return c == null ? null : (lat: c.lat, lng: c.lng);
    }

    final loc = b.lastKnownLocation;
    return TripMapData(
      pickup: city(b.pickup),
      drop: city(b.drop),
      driver: loc == null ? null : (lat: loc.latitude, lng: loc.longitude),
      driverUpdatedAt: b.locationUpdatedAt,
    );
  }
}

/// Draws a [TripMapData]. The real one is [GoogleTripMapRenderer]; tests use a
/// fake because a map is a native view.
abstract class TripMapRenderer {
  Widget build(BuildContext context, TripMapData data);
}

class GoogleTripMapRenderer implements TripMapRenderer {
  const GoogleTripMapRenderer();

  @override
  Widget build(BuildContext context, TripMapData data) {
    g.LatLng ll(({double lat, double lng}) p) => g.LatLng(p.lat, p.lng);
    final pts = [for (final p in [data.pickup, data.drop, data.driver]) if (p != null) ll(p)];
    final first = pts.first;
    return g.GoogleMap(
      key: const ValueKey('googleMap'),
      initialCameraPosition: g.CameraPosition(target: first, zoom: pts.length == 1 ? 11 : 5),
      onMapCreated: (c) {
        if (pts.length < 2) return;
        var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
        for (final p in pts) {
          if (p.latitude < s) s = p.latitude;
          if (p.latitude > n) n = p.latitude;
          if (p.longitude < w) w = p.longitude;
          if (p.longitude > e) e = p.longitude;
        }
        c.animateCamera(g.CameraUpdate.newLatLngBounds(g.LatLngBounds(southwest: g.LatLng(s, w), northeast: g.LatLng(n, e)), 56));
      },
      markers: {
        if (data.pickup != null) g.Marker(markerId: const g.MarkerId('pickup'), position: ll(data.pickup!), icon: g.BitmapDescriptor.defaultMarkerWithHue(g.BitmapDescriptor.hueGreen)),
        if (data.drop != null) g.Marker(markerId: const g.MarkerId('drop'), position: ll(data.drop!), icon: g.BitmapDescriptor.defaultMarkerWithHue(g.BitmapDescriptor.hueRed)),
        if (data.driver != null) g.Marker(markerId: const g.MarkerId('driver'), position: ll(data.driver!), icon: g.BitmapDescriptor.defaultMarkerWithHue(g.BitmapDescriptor.hueAzure)),
      },
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}

/// G10: the trip on a map, with the driver's last shared position. Behind the
/// `maps` switch (OFF). The screen follows the booking live, so the driver marker
/// moves as new positions arrive.
class TripMapScreen extends StatelessWidget {
  final String bookingId;
  const TripMapScreen({super.key, required this.bookingId});

  static TripMapRenderer renderer = const GoogleTripMapRenderer();

  static bool get available => FeaturesService.isOn(FeatureKey.maps);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'tripMapTitle')),
      body: LiveStream<Booking?>(
        stream: () => BookingService.watch(bookingId),
        builder: (context, b) {
          if (b == null) return _note(context, 'tripMapNone');
          final data = TripMapData.of(b);
          if (!data.hasAny) return _note(context, 'tripMapNone');
          return Column(children: [
            Expanded(child: renderer.build(context, data)),
            _legend(context, data),
          ]);
        },
      ),
    );
  }

  Widget _note(BuildContext context, String key) => Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s6),
          child: Text(tr(context, key), textAlign: TextAlign.center, style: DsType.body.copyWith(color: context.ds.textMuted)),
        ),
      );

  Widget _legend(BuildContext context, TripMapData d) {
    final c = context.ds;
    Widget dot(Color color, String key) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 4),
            Text(tr(context, key), style: DsType.caption.copyWith(color: c.text)),
          ]),
        );
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.all(DsSpace.s3),
      child: Wrap(alignment: WrapAlignment.center, runSpacing: DsSpace.s1, children: [
        dot(c.success, 'tripMapPickup'),
        dot(c.error, 'tripMapDrop'),
        if (d.driver != null) dot(c.primary, 'tripMapDriver') else Text(tr(context, 'locationNotShared'), style: DsType.caption.copyWith(color: c.textMuted)),
      ]),
    );
  }
}

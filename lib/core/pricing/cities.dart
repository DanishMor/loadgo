import 'dart:math' as math;

/// A city in the offline distance table.
class City {
  final String name;
  final String state;
  final double lat;
  final double lng;
  final List<String> aliases;

  const City(this.name, this.state, this.lat, this.lng, [this.aliases = const []]);
}

/// ~60 large Indian cities and freight hubs. Used for offline distance
/// estimates only. LATER(paid): Google Distance Matrix / Directions for real
/// road distance.
const List<City> indianCities = [
  City('Delhi', 'Delhi', 28.6139, 77.2090, ['new delhi', 'dilli']),
  City('Mumbai', 'Maharashtra', 19.0760, 72.8777, ['bombay', 'navi mumbai']),
  City('Kolkata', 'West Bengal', 22.5726, 88.3639, ['calcutta', 'howrah']),
  City('Chennai', 'Tamil Nadu', 13.0827, 80.2707, ['madras']),
  City('Bengaluru', 'Karnataka', 12.9716, 77.5946, ['bangalore']),
  City('Hyderabad', 'Telangana', 17.3850, 78.4867, ['secunderabad']),
  City('Ahmedabad', 'Gujarat', 23.0225, 72.5714, ['amdavad']),
  City('Pune', 'Maharashtra', 18.5204, 73.8567, ['poona']),
  City('Surat', 'Gujarat', 21.1702, 72.8311),
  City('Jaipur', 'Rajasthan', 26.9124, 75.7873),
  City('Lucknow', 'Uttar Pradesh', 26.8467, 80.9462),
  City('Kanpur', 'Uttar Pradesh', 26.4499, 80.3319),
  City('Nagpur', 'Maharashtra', 21.1458, 79.0882),
  City('Indore', 'Madhya Pradesh', 22.7196, 75.8577),
  City('Bhopal', 'Madhya Pradesh', 23.2599, 77.4126),
  City('Visakhapatnam', 'Andhra Pradesh', 17.6868, 83.2185, ['vizag']),
  City('Patna', 'Bihar', 25.5941, 85.1376),
  City('Vadodara', 'Gujarat', 22.3072, 73.1812, ['baroda']),
  City('Ludhiana', 'Punjab', 30.9010, 75.8573),
  City('Agra', 'Uttar Pradesh', 27.1767, 78.0081),
  City('Nashik', 'Maharashtra', 19.9975, 73.7898),
  City('Faridabad', 'Haryana', 28.4089, 77.3178),
  City('Meerut', 'Uttar Pradesh', 28.9845, 77.7064),
  City('Rajkot', 'Gujarat', 22.3039, 70.8022),
  City('Varanasi', 'Uttar Pradesh', 25.3176, 82.9739, ['banaras', 'kashi']),
  City('Srinagar', 'Jammu and Kashmir', 34.0837, 74.7973),
  City('Jammu', 'Jammu and Kashmir', 32.7266, 74.8570),
  City('Aurangabad', 'Maharashtra', 19.8762, 75.3433, ['chhatrapati sambhajinagar']),
  City('Amritsar', 'Punjab', 31.6340, 74.8723),
  City('Prayagraj', 'Uttar Pradesh', 25.4358, 81.8463, ['allahabad']),
  City('Ranchi', 'Jharkhand', 23.3441, 85.3096),
  City('Jabalpur', 'Madhya Pradesh', 23.1815, 79.9864),
  City('Gwalior', 'Madhya Pradesh', 26.2183, 78.1828),
  City('Coimbatore', 'Tamil Nadu', 11.0168, 76.9558),
  City('Vijayawada', 'Andhra Pradesh', 16.5062, 80.6480),
  City('Jodhpur', 'Rajasthan', 26.2389, 73.0243),
  City('Madurai', 'Tamil Nadu', 9.9252, 78.1198),
  City('Raipur', 'Chhattisgarh', 21.2514, 81.6296),
  City('Kota', 'Rajasthan', 25.2138, 75.8648),
  City('Guwahati', 'Assam', 26.1445, 91.7362),
  City('Chandigarh', 'Chandigarh', 30.7333, 76.7794, ['mohali', 'panchkula']),
  City('Mysuru', 'Karnataka', 12.2958, 76.6394, ['mysore']),
  City('Bhubaneswar', 'Odisha', 20.2961, 85.8245),
  City('Kochi', 'Kerala', 9.9312, 76.2673, ['cochin', 'ernakulam']),
  City('Thiruvananthapuram', 'Kerala', 8.5241, 76.9366, ['trivandrum']),
  City('Dehradun', 'Uttarakhand', 30.3165, 78.0322),
  City('Gurugram', 'Haryana', 28.4595, 77.0266, ['gurgaon']),
  City('Noida', 'Uttar Pradesh', 28.5355, 77.3910, ['greater noida']),
  City('Ghaziabad', 'Uttar Pradesh', 28.6692, 77.4538),
  City('Mangaluru', 'Karnataka', 12.9141, 74.8560, ['mangalore']),
  City('Hubballi', 'Karnataka', 15.3647, 75.1240, ['hubli', 'dharwad']),
  City('Belagavi', 'Karnataka', 15.8497, 74.4977, ['belgaum']),
  City('Tiruchirappalli', 'Tamil Nadu', 10.7905, 78.7047, ['trichy']),
  City('Salem', 'Tamil Nadu', 11.6643, 78.1460),
  City('Goa', 'Goa', 15.4909, 73.8278, ['panaji', 'panjim', 'vasco']),
  City('Udaipur', 'Rajasthan', 24.5854, 73.7125),
  City('Ajmer', 'Rajasthan', 26.4499, 74.6399),
  City('Siliguri', 'West Bengal', 26.7271, 88.3953),
  City('Dhanbad', 'Jharkhand', 23.7957, 86.4304),
  City('Jamshedpur', 'Jharkhand', 22.8046, 86.2029, ['tatanagar']),
  City('Bhiwandi', 'Maharashtra', 19.2813, 73.0483),
  City('Kandla', 'Gujarat', 23.0333, 70.2167, ['gandhidham']),
  City('Mundra', 'Gujarat', 22.8390, 69.7210),
  City('Tuticorin', 'Tamil Nadu', 8.7642, 78.1348, ['thoothukudi']),
];

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Finds the city mentioned in a free-text place ("Andheri, Mumbai",
/// "bangalore"). The longest matching name or alias wins; null if none.
City? findCity(String text) {
  final t = ' ${_norm(text)} ';
  City? best;
  var bestLen = 0;
  for (final c in indianCities) {
    for (final n in [c.name, ...c.aliases]) {
      final key = _norm(n);
      if (key.length > bestLen && t.contains(' $key ')) {
        best = c;
        bestLen = key.length;
      }
    }
  }
  return best;
}

/// Great-circle distance in km.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Estimated road km between two cities: straight line x [roadFactor],
/// rounded up to a whole km. Same city counts as [sameCityKm].
int roadKmBetween(City a, City b, {double roadFactor = 1.25, int sameCityKm = 15}) {
  if (a.name == b.name) return sameCityKm;
  return (haversineKm(a.lat, a.lng, b.lat, b.lng) * roadFactor).ceil();
}

/// Cities whose name or alias starts with / contains [query], prefix matches
/// first (for the typeahead on place fields). Empty query gives nothing.
List<City> suggestCities(String query, {int limit = 6}) {
  final q = _norm(query);
  if (q.isEmpty) return const [];
  final starts = <City>[];
  final contains = <City>[];
  for (final c in indianCities) {
    final names = [c.name, ...c.aliases].map(_norm);
    if (names.any((n) => n.startsWith(q))) {
      starts.add(c);
    } else if (q.length >= 2 && names.any((n) => n.contains(q))) {
      contains.add(c);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}

/// The city of the table closest to a position, or null when none lies
/// within [maxKm] (a position far outside the table is not "in" any city).
City? nearestCity(double lat, double lng, {double maxKm = 80}) {
  City? best;
  var bestKm = double.infinity;
  for (final c in indianCities) {
    final km = haversineKm(lat, lng, c.lat, c.lng);
    if (km < bestKm) {
      bestKm = km;
      best = c;
    }
  }
  return bestKm <= maxKm ? best : null;
}

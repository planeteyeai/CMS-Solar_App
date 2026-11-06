import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherInfo {
  final double tempC;
  final IconData icon;
  final String label;
  const WeatherInfo(this.tempC, this.icon, this.label);
}

/// Current weather from Open-Meteo (free, no key). Uses the phone's last known
/// position and never asks for location permission by itself.
class WeatherService {
  WeatherService._();

  static WeatherInfo? _cache;
  static DateTime? _at;

  static Future<WeatherInfo?> current() async {
    if (_cache != null &&
        _at != null &&
        DateTime.now().difference(_at!) < const Duration(minutes: 15)) {
      return _cache;
    }
    try {
      Position? p = await Geolocator.getLastKnownPosition();
      if (p == null) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          p = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          );
        }
      }
      if (p == null) return _cache;
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast'
          '?latitude=${p.latitude}&longitude=${p.longitude}'
          '&current=temperature_2m,weather_code');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return _cache;
      final cur = (jsonDecode(res.body) as Map)['current'] as Map;
      final code = (cur['weather_code'] as num).toInt();
      final (icon, label) = _describe(code);
      _cache = WeatherInfo((cur['temperature_2m'] as num).toDouble(), icon, label);
      _at = DateTime.now();
      return _cache;
    } catch (_) {
      return _cache;
    }
  }

  static (IconData, String) _describe(int c) {
    if (c == 0) return (Icons.wb_sunny_rounded, 'Clear');
    if (c <= 2) return (Icons.wb_cloudy_rounded, 'Partly cloudy');
    if (c == 3) return (Icons.cloud_rounded, 'Overcast');
    if (c == 45 || c == 48) return (Icons.foggy, 'Fog');
    if (c >= 51 && c <= 67) return (Icons.water_drop_rounded, 'Rain');
    if (c >= 71 && c <= 77) return (Icons.ac_unit_rounded, 'Snow');
    if (c >= 80 && c <= 82) return (Icons.grain_rounded, 'Showers');
    if (c >= 95) return (Icons.thunderstorm_rounded, 'Thunderstorm');
    return (Icons.cloud_rounded, 'Cloudy');
  }
}

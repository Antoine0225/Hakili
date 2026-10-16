import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Météo en direct de l'endroit où se trouve le PC (comme obtenir_meteo_locale de Python) :
/// la ville est trouvée par l'adresse IP, puis la température est lue sur Open-Meteo.
/// Tout se passe en arrière-plan : un réseau lent ne gèle jamais l'écran.
class Meteo {
  Meteo._();

  static final ValueNotifier<double> temperature = ValueNotifier(30.0);
  static String ville = 'Bamako';

  /// Températures maximales prévues : aujourd'hui, demain, après-demain, J+3 (vide tant que rien n'a été reçu).
  static final ValueNotifier<List<double>> maxPrevus = ValueNotifier(const []);
  static Timer? _minuteur;

  static void demarrer() {
    _minuteur?.cancel();
    _actualiser();
    _minuteur = Timer.periodic(const Duration(minutes: 20), (_) => _actualiser());
  }

  static Future<void> _actualiser() async {
    var lat = 12.6392, lon = -8.0029, nom = 'Bamako'; // repli si la localisation échoue
    try {
      final r = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map;
        if (d['latitude'] != null && d['longitude'] != null) {
          lat = (d['latitude'] as num).toDouble();
          lon = (d['longitude'] as num).toDouble();
          final v = '${d['city'] ?? ''}';
          if (v.isNotEmpty) nom = v;
        }
      }
    } catch (_) {}
    try {
      final horodatage = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final r = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
              '&current_weather=true&daily=temperature_2m_max&forecast_days=4&timezone=auto&_=$horodatage'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final corps = jsonDecode(r.body) as Map;
        final t = (corps['current_weather'] as Map)['temperature'];
        if (t is num) {
          temperature.value = t.toDouble();
          ville = nom;
        }
        try {
          final m = ((corps['daily'] as Map)['temperature_2m_max'] as List).whereType<num>().map((e) => e.toDouble()).toList();
          if (m.isNotEmpty) maxPrevus.value = m;
        } catch (_) {} // pas de prévision : l'alerte se base alors sur la température actuelle
      }
    } catch (_) {} // pas d'Internet : l'ancienne valeur reste affichée
  }
}

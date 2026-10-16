import 'dart:convert';

/// Le « badge » signé délivré par le serveur de licences (licence-gateway).
/// Il prouve au Cloud (Supabase) que ce logiciel a une licence valide.
/// Gardé en mémoire seulement : jamais écrit sur le disque (comme dans la version Python).
class JetonCloud {
  JetonCloud._();

  static String _jeton = '';
  static double _exp = 0; // secondes Unix
  static String _licence = '';

  static double _maintenant() => DateTime.now().millisecondsSinceEpoch / 1000.0;

  static Map<String, dynamic> _lireCharge(String jeton) {
    try {
      var charge = jeton.split('.')[1];
      charge += '=' * ((4 - charge.length % 4) % 4);
      final d = jsonDecode(utf8.decode(base64Url.decode(charge)));
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  /// Garde le badge reçu (ignoré s'il est mal formé ou presque expiré).
  static void memoriser(Object? jeton) {
    if (jeton is! String || '.'.allMatches(jeton).length != 2) return;
    final charge = _lireCharge(jeton);
    final exp = double.tryParse('${charge['exp']}');
    final licence = '${charge['licence'] ?? ''}'.trim().toLowerCase();
    if (exp == null || licence.isEmpty || exp <= _maintenant() + 60) return;
    _jeton = jeton;
    _exp = exp;
    _licence = licence;
  }

  /// Le badge encore valide (marge de 60 s) et qui correspond à cette licence, sinon ''.
  static String lire([String licence = '']) {
    if (_jeton.isEmpty || _exp <= _maintenant() + 60) return '';
    if (licence.isNotEmpty && _licence != licence.trim().toLowerCase()) return '';
    return _jeton;
  }

  static void oublier() {
    _jeton = '';
    _exp = 0;
    _licence = '';
  }
}

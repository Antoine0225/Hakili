import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../config/constantes.dart';
import '../data/parametres.dart';

/// Codes PIN Patron / Ouvrier.
/// Même méthode que securite.py (PBKDF2-HMAC-SHA256, 200 000 tours, sel de 16 octets,
/// format « sel$empreinte » en hexadécimal) : les PIN déjà enregistrés restent valables.
/// Le code en clair n'est jamais conservé : seule l'empreinte est écrite en base.
class Pin {
  Pin._();

  static const int _tailleSel = 16;

  static String _enHex(List<int> octets) =>
      octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();

  static String _selAleatoire() {
    final r = Random.secure();
    return _enHex(List<int>.generate(_tailleSel, (_) => r.nextInt(256)));
  }

  // Le calcul est lourd (200 000 tours) : on le fait « à côté » (isolate) pour que l'écran
  // reste fluide et ne se fige jamais pendant la vérification.
  static Future<String> _empreinte(String code, String selHex) =>
      Isolate.run(() => _calculerEmpreinte(code, selHex));

  /// Transforme un PIN en « sel$empreinte » (à stocker).
  static Future<String> hacher(String code, {String? selHex}) async {
    final sel = selHex ?? _selAleatoire();
    return '$sel\$${await _empreinte(code, sel)}';
  }

  /// Compare un PIN saisi à l'empreinte stockée. Ne plante jamais : en cas de doute, refuse.
  static Future<bool> verifier(String code, String empreinteStockee) async {
    if (code.isEmpty || !empreinteStockee.contains('\$')) return false;
    try {
      final i = empreinteStockee.indexOf('\$');
      final sel = empreinteStockee.substring(0, i);
      final attendue = empreinteStockee.substring(i + 1);
      final calculee = await _empreinte(code, sel);
      if (calculee.length != attendue.length) return false;
      var diff = 0; // comparaison en temps constant
      for (var k = 0; k < calculee.length; k++) {
        diff |= calculee.codeUnitAt(k) ^ attendue.codeUnitAt(k);
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  static String _cle(String role) => role == rolePatron ? 'pin_patron' : 'pin_ouvrier';

  /// Enregistre (ou change) le PIN d'un rôle. Renvoie false si le rôle ou le code est invalide.
  static Future<bool> definir(String role, String nouveauCode) async {
    if (nouveauCode.isEmpty) return false;
    if (role != rolePatron && role != roleOuvrier) return false;
    await Parametres.ecrire(_cle(role), await hacher(nouveauCode));
    return true;
  }

  /// Quel rôle correspond à ce PIN ? « Patron », « Ouvrier », ou null si aucun.
  static Future<String?> identifierRole(String code) async {
    if (code.isEmpty) return null;
    final stockes = await Future.wait([
      Parametres.lire('pin_patron'),
      Parametres.lire('pin_ouvrier'),
    ]);
    final r = await Future.wait([verifier(code, stockes[0]), verifier(code, stockes[1])]);
    if (r[0]) return rolePatron;
    if (r[1]) return roleOuvrier;
    return null;
  }

  /// La configuration initiale est faite quand les deux PIN existent (comme dans le logiciel actuel).
  static Future<bool> configurationTerminee() async {
    return await Parametres.lire('configuration_terminee') == '1' &&
        (await Parametres.lire('pin_patron')).contains('\$') &&
        (await Parametres.lire('pin_ouvrier')).contains('\$');
  }
}

/// Fonction autonome (nécessaire pour tourner dans l'isolate).
Future<String> _calculerEmpreinte(String code, String selHex) async {
  final algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256);
  final octetsSel = [
    for (var i = 0; i < selHex.length; i += 2) int.parse(selHex.substring(i, i + 2), radix: 16)
  ];
  final cle = await algo.deriveKeyFromPassword(password: code, nonce: octetsSel);
  final octets = await cle.extractBytes();
  return octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
}

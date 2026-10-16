import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constantes.dart';
import 'jeton_cloud.dart';

/// Réponse normalisée du serveur de licences.
/// reseau = false : pas d'Internet, délai dépassé ou panne serveur (≠ un refus).
class ReponseLicence {
  final bool reseau;
  final bool autorise;   // contrôle de démarrage / battement
  final bool succes;     // demande ou vérification du code OTP
  final String code;
  final String? expiration;
  final String message;
  final List<int>? occupation; // [PC inscrits, PC autorisés]

  const ReponseLicence({
    this.reseau = true,
    this.autorise = false,
    this.succes = false,
    this.code = '',
    this.expiration,
    this.message = '',
    this.occupation,
  });
}

class LicenceServeur {
  LicenceServeur._();

  static const _sansReseau = ReponseLicence(reseau: false, code: 'reseau');

  static List<int>? _lireOccupation(Object? o) {
    try {
      if (o is List && o.length >= 2) return [int.parse('${o[0]}'), int.parse('${o[1]}')];
    } catch (_) {}
    return null;
  }

  /// Envoie une requête. Renvoie (statut HTTP, contenu) ou null si le réseau est coupé.
  static Future<(int, Object?)?> _envoyer(Map<String, Object?> payload) async {
    try {
      final r = await http
          .post(
            Uri.parse(licenceEdgeFunctionUrl),
            headers: {
              'apikey': supabaseCle,
              'Authorization': 'Bearer $supabaseCle',
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: licenceDelaiReseauSec));
      Object? donnees;
      try {
        donnees = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        donnees = null;
      }
      return (r.statusCode, donnees);
    } catch (_) {
      return null;
    }
  }

  /// Opération de licence décidée ENTIÈREMENT par le serveur.
  /// mode : 'demarrage' | 'battement' | 'deconnexion'
  static Future<ReponseLicence> transaction(String email, String pcId,
      {String mode = 'demarrage'}) async {
    email = email.trim().toLowerCase();
    if (email.isEmpty) {
      return const ReponseLicence(code: 'inconnu', message: '⛔ Aucune adresse e-mail renseignée.');
    }
    final rep = await _envoyer({'email': email, 'pc_id': pcId, 'mode': mode});
    if (rep == null) return _sansReseau;
    final (statut, donnees) = rep;

    if (statut == 429) {
      return const ReponseLicence(
          code: 'conflit', message: '⚠️ Trop de tentatives. Réessayez dans quelques minutes.');
    }
    if (statut != 200) return _sansReseau; // 5xx, 4xx... : traité comme « pas de réseau »
    if (donnees is! Map || !donnees.containsKey('code')) return _sansReseau;

    final autorise = donnees['autorise'] == true;
    if (autorise && donnees['jeton'] != null) JetonCloud.memoriser(donnees['jeton']);

    return ReponseLicence(
      autorise: autorise,
      code: '${donnees['code'] ?? ''}',
      expiration: donnees['expiration']?.toString(),
      message: '${donnees['message'] ?? ''}',
      occupation: _lireOccupation(donnees['occupation']),
    );
  }

  /// Étape 1 : le serveur envoie un code à 6 chiffres par e-mail.
  static Future<ReponseLicence> demanderCode(String email) =>
      _otp({'email': email.trim().toLowerCase(), 'mode': 'demande_otp'}, 'demande_otp');

  /// Étape 2 : le serveur compare le code saisi (on ne connaît JAMAIS le code attendu).
  static Future<ReponseLicence> verifierCode(String email, String code, String pcId) => _otp({
        'email': email.trim().toLowerCase(),
        'otp_code': code,
        'mode': 'verification_otp',
        'pc_id': pcId,
      }, 'verification_otp');

  static Future<ReponseLicence> _otp(Map<String, Object?> payload, String mode) async {
    final rep = await _envoyer(payload);
    if (rep == null) return _sansReseau;
    final (statut, donnees) = rep;

    if (statut == 429) {
      return const ReponseLicence(
          code: 'conflit', message: '⚠️ Trop de tentatives. Réessayez dans quelques minutes.');
    }
    if (statut >= 500) return _sansReseau;

    if (statut != 200) {
      // 4xx : refus explicite (code faux, expiré, e-mail inconnu...)
      if (donnees is Map) {
        return ReponseLicence(code: '${donnees['code'] ?? ''}', message: '${donnees['message'] ?? ''}');
      }
      return const ReponseLicence();
    }
    if (donnees is! Map) return _sansReseau;

    final codeServeur = '${donnees['code'] ?? ''}';
    final expiration = donnees['expiration']?.toString();
    final bool succes;
    if (mode == 'demande_otp') {
      succes = donnees['otp_envoye'] == true ||
          donnees['autorise'] == true ||
          codeServeur == 'otp_envoye' ||
          codeServeur == 'otp_genere';
    } else {
      // sans date d'expiration, aucun cache ne peut être scellé : refus par prudence
      succes = donnees['autorise'] == true && expiration != null && expiration.isNotEmpty;
      if (succes && donnees['jeton'] != null) JetonCloud.memoriser(donnees['jeton']);
    }

    return ReponseLicence(
      succes: succes,
      code: codeServeur,
      expiration: expiration,
      message: '${donnees['message'] ?? ''}',
      occupation: _lireOccupation(donnees['occupation']),
    );
  }
}

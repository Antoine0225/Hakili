import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/base_locale.dart';

/// Journal de diagnostic (donnies_antoine_diagnostic.log, dans le dossier utilisateur) :
/// ouvertures, fermetures et erreurs inattendues. Utile au support en cas de problème.
class Diagnostic {
  Diagnostic._();

  static void ecrire(String message) {
    try {
      final f = File(p.join(BaseLocale.dossierUtilisateur(), 'donnies_antoine_diagnostic.log'));
      f.writeAsStringSync('[${DateTime.now().toIso8601String()}] $message\n', mode: FileMode.append);
    } catch (_) {}
  }

  static final Map<String, DateTime> _dernierePourContexte = {};

  /// Note une erreur qu'on choisit de ne pas montrer à l'écran, sans jamais faire planter le logiciel.
  /// Une même erreur n'est écrite qu'une fois toutes les 10 minutes (sinon le fichier grossirait pour rien).
  static void erreur(String contexte, Object e) {
    try {
      final maintenant = DateTime.now();
      final avant = _dernierePourContexte[contexte];
      if (avant != null && maintenant.difference(avant).inMinutes < 10) return;
      _dernierePourContexte[contexte] = maintenant;
      ecrire('ERREUR SILENCIEUSE [$contexte] : $e');
    } catch (_) {}
  }
}

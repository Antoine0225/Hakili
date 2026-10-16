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
}

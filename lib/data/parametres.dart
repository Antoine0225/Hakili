import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'base_locale.dart';

/// Les réglages du logiciel (nom de la ferme, PIN, thème...) : table « parametres », clé / valeur.
class Parametres {
  Parametres._();

  static Future<String> lire(String cle, {String defaut = ''}) async {
    try {
      final l = await BaseLocale.db
          .rawQuery('SELECT valeur FROM parametres WHERE cle = ?', [cle]);
      if (l.isEmpty || l.first['valeur'] == null) return defaut;
      return l.first['valeur'] as String;
    } catch (_) {
      return defaut;
    }
  }

  static Future<void> ecrire(String cle, String valeur) async {
    await BaseLocale.db.insert('parametres', {'cle': cle, 'valeur': valeur},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

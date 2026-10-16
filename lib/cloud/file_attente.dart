import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/constantes.dart';
import '../data/base_locale.dart';

class OperationCloud {
  final int id;
  final String table;
  final String operation; // 'upsert' | 'delete' | 'stock_delta' | 'stock_init'
  final Map<String, dynamic> payload;
  const OperationCloud(this.id, this.table, this.operation, this.payload);
}

/// Tout ce qui n'a pas encore été transmis au Cloud attend ici. Une coupure Internet ne bloque
/// donc jamais une vente : l'écran écrit dans SQLite, et l'envoi se fait ensuite, en arrière-plan.
class FileAttente {
  FileAttente._();

  /// Mis à true à chaque nouvel ajout : le prochain cycle part dans la seconde qui suit.
  static bool urgent = false;

  /// À appeler avec la même transaction que l'écriture locale (« ex ») pour que tout réussisse ou échoue ensemble.
  static Future<void> enfiler(DatabaseExecutor ex, String licence, String tableCible,
      String operation, Map<String, Object?> payload) async {
    await ex.rawInsert(
        'INSERT INTO file_attente_cloud (licence, table_cible, operation, payload, cree_le) '
        'VALUES (?, ?, ?, ?, ?)',
        [licence, tableCible, operation, jsonEncode(payload), _maintenant()]);
    urgent = true;
  }

  static String _maintenant() {
    final n = DateTime.now();
    String d(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${d(n.month)}-${d(n.day)} ${d(n.hour)}:${d(n.minute)}:${d(n.second)}';
  }

  static Future<int> compter() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT COUNT(*) AS n FROM file_attente_cloud WHERE tentatives < ?', [cloudMaxTentatives]);
      return (l.first['n'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Les opérations à envoyer, dans l'ordre. Une ligne illisible est mise de côté (jamais renvoyée).
  static Future<List<OperationCloud>> lire(String licence, {int limite = 2000}) async {
    final l = await BaseLocale.db.rawQuery(
        'SELECT id, table_cible, operation, payload FROM file_attente_cloud '
        'WHERE tentatives < ? ORDER BY id ASC LIMIT ?',
        [cloudMaxTentatives, limite]);
    final ops = <OperationCloud>[];
    for (final r in l) {
      final id = r['id'] as int;
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(r['payload'] as String) as Map);
      } catch (_) {
        await BaseLocale.db.rawUpdate(
            'UPDATE file_attente_cloud SET tentatives = ? WHERE id = ?', [cloudMaxTentatives, id]);
        continue;
      }
      // ligne saisie avant l'identification du client : on la rattache à la licence
      for (final champ in ['licence', 'p_licence']) {
        if (payload.containsKey(champ) && ('${payload[champ] ?? ''}').isEmpty) payload[champ] = licence;
      }
      ops.add(OperationCloud(id, r['table_cible'] as String, r['operation'] as String, payload));
    }
    return ops;
  }

  static Future<void> retirer(List<int> ids) async {
    if (ids.isEmpty) return;
    final b = BaseLocale.db.batch();
    for (final id in ids) {
      b.rawDelete('DELETE FROM file_attente_cloud WHERE id = ?', [id]);
    }
    await b.commit(noResult: true);
  }

  static Future<void> compterUnEchec(Iterable<int> ids) async {
    final b = BaseLocale.db.batch();
    for (final id in ids) {
      b.rawUpdate('UPDATE file_attente_cloud SET tentatives = tentatives + 1 WHERE id = ?', [id]);
    }
    await b.commit(noResult: true);
  }
}

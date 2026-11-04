import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../data/parametres.dart';

class OperationCloud {
  final int id;
  final String table;
  final String operation; // 'upsert' | 'delete' | 'stock_delta' | 'stock_init'
  final Map<String, dynamic> payload;
  const OperationCloud(this.id, this.table, this.operation, this.payload);
}

/// Une opération que le serveur a refusée 5 fois : elle n'est plus renvoyée toute seule
/// et attend la décision du Patron (réessayer ou abandonner).
class OperationBloquee {
  final int id;
  final String table, operation, creeLe, erreur;
  final Map<String, dynamic> payload;
  const OperationBloquee(this.id, this.table, this.operation, this.creeLe, this.erreur, this.payload);

  /// Ce que c'est, en mots simples : « Vente », « Arrivage de stock »...
  String get nature => switch (table) {
        'ventes' => 'Vente',
        'stocks_arrivages' => 'Arrivage de stock',
        'bandes_elevage' => "Bande d'élevage",
        'rappels_veterinaires' => 'Rappel vétérinaire',
        'journal_bande_evenements' => 'Journal de bande',
        'catalogue_produits' => 'Produit du catalogue',
        'stock_produits' => 'Quantité en stock',
        _ => table,
      };

  /// Ce qu'on tentait de faire.
  String get action {
    if (payload['supprime'] == true || operation == 'delete') return 'Suppression';
    return switch (operation) {
      'stock_delta' => 'Mouvement de stock',
      'stock_init' => 'Stock de départ',
      _ => 'Envoi',
    };
  }

  /// Une ligne qui permet de reconnaître l'opération (produit, date, montant...).
  String get resume {
    String s(String cle) => '${payload[cle] ?? ''}'.trim();
    final morceaux = <String>[];
    switch (table) {
      case 'ventes':
        morceaux.addAll([s('type'), s('date'), if (s('total').isNotEmpty) '${s('total')} F']);
      case 'stocks_arrivages':
        morceaux.addAll([s('produit'), s('date'), s('fournisseur')]);
      case 'bandes_elevage':
        morceaux.addAll([s('nom'), s('type_elevage')]);
      case 'rappels_veterinaires':
        morceaux.addAll([s('tache'), s('date_prevue')]);
      case 'journal_bande_evenements':
        morceaux.addAll([s('date'), s('note')]);
      case 'catalogue_produits':
        morceaux.add(s('nom'));
      case 'stock_produits':
        morceaux.add(s('p_nom'));
    }
    final texte = morceaux.where((m) => m.isNotEmpty).join(' — ');
    return texte.isEmpty ? '(aucun détail)' : texte;
  }

  /// Le refus du serveur, expliqué sans jargon.
  String get explication {
    final e = erreur.toLowerCase();
    if (e.isEmpty) return 'Le serveur a refusé cette ligne.';
    if (e.contains('42501') || e.contains('row-level security') || e.contains('policy')) {
      return 'Le serveur refuse cette ligne pour des raisons de sécurité (droits ou licence).';
    }
    if (e.contains('pgrst204') || e.contains('42703') || e.contains('column')) {
      return "Le Cloud ne connaît pas un des champs envoyés : la base en ligne doit être mise à jour.";
    }
    if (e.contains('23502') || e.contains('null value')) {
      return "Une information obligatoire est absente de cette ligne.";
    }
    if (e.contains('23505') || e.contains('duplicate')) {
      return 'Cette ligne existe déjà dans le Cloud avec un conflit.';
    }
    if (e.contains('22p02') || e.contains('invalid input')) {
      return "Une valeur n'a pas le bon format (date, nombre...).";
    }
    if (e.contains('données illisibles')) {
      return 'Les données de cette ligne sont abîmées : elle ne peut pas être envoyée.';
    }
    return 'Le serveur a refusé cette ligne.';
  }
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

  /// Lignes encore en cours d'envoi, y compris celles que le logiciel va retenter tout seul.
  /// (Les lignes « définitivement bloquées » sont comptées à part : voir [compterBloquees].)
  static Future<int> compter() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT COUNT(*) AS n FROM file_attente_cloud WHERE tentatives < ? OR IFNULL(reprises_auto, 0) < ?',
          [cloudMaxTentatives, cloudDelaisReprisesAuto.length]);
      return (l.first['n'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Lignes prêtes à partir maintenant (celles qui attendent leur prochaine reprise automatique n'en font pas partie).
  static Future<int> compterAEnvoyer() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT COUNT(*) AS n FROM file_attente_cloud WHERE tentatives < ?', [cloudMaxTentatives]);
      return (l.first['n'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Lignes que le serveur a refusées malgré toutes les reprises automatiques : elles attendent le Patron.
  static Future<int> compterBloquees() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT COUNT(*) AS n FROM file_attente_cloud WHERE tentatives >= ? AND IFNULL(reprises_auto, 0) >= ?',
          [cloudMaxTentatives, cloudDelaisReprisesAuto.length]);
      return (l.first['n'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _texteMaintenant() => _maintenant();

  /// Reprise automatique : une ligne refusée 5 fois est retentée toute seule (une fois) quand son délai est écoulé
  /// (30 min, puis 3 h, 12 h, 48 h). Si le serveur la refuse encore, elle repart en attente jusqu'au délai suivant.
  /// Renvoie le nombre de lignes remises dans la file.
  static Future<int> reprendreAutomatiquement() async {
    try {
      final nb = cloudDelaisReprisesAuto.length;
      final l = await BaseLocale.db.rawQuery(
          'SELECT id, IFNULL(reprises_auto, 0) AS r, dernier_echec FROM file_attente_cloud '
          'WHERE tentatives >= ? AND IFNULL(reprises_auto, 0) < ?',
          [cloudMaxTentatives, nb]);
      if (l.isEmpty) return 0;
      final maintenant = DateTime.now();
      final b = BaseLocale.db.batch();
      var n = 0;
      for (final r in l) {
        final rang = (r['r'] as int?) ?? 0;
        final dernier = DateTime.tryParse('${r['dernier_echec'] ?? ''}');
        final echu = dernier == null || maintenant.difference(dernier).inMinutes >= cloudDelaisReprisesAuto[rang];
        if (!echu) continue;
        b.rawUpdate('UPDATE file_attente_cloud SET tentatives = ?, reprises_auto = ? WHERE id = ?',
            [cloudMaxTentatives - 1, rang + 1, r['id']]);
        n++;
      }
      if (n > 0) {
        await b.commit(noResult: true);
        urgent = true;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Après une mise à jour du logiciel (qui a pu corriger le problème), les lignes bloquées repartent de zéro :
  /// les reprises automatiques recommencent. À appeler au démarrage de la synchro.
  static Future<void> reprendreApresMiseAJour(String versionActuelle) async {
    try {
      final vue = await Parametres.lire('cloud_version_reprises');
      if (vue == versionActuelle) return;
      await BaseLocale.db.rawUpdate(
          'UPDATE file_attente_cloud SET reprises_auto = 0, dernier_echec = NULL WHERE tentatives >= ?',
          [cloudMaxTentatives]);
      await Parametres.ecrire('cloud_version_reprises', versionActuelle);
    } catch (_) {}
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
            'UPDATE file_attente_cloud SET tentatives = ?, reprises_auto = ?, derniere_erreur = ? WHERE id = ?',
            [cloudMaxTentatives, cloudDelaisReprisesAuto.length, 'données illisibles', id]);
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

  /// Compte un échec de plus pour chaque ligne refusée et garde la raison du refus (pour la fenêtre « bloquées »).
  static Future<void> compterUnEchec(Map<int, String> echecs) async {
    if (echecs.isEmpty) return;
    final b = BaseLocale.db.batch();
    final quand = _texteMaintenant();
    echecs.forEach((id, raison) {
      final court = raison.length > 600 ? raison.substring(0, 600) : raison;
      b.rawUpdate(
          'UPDATE file_attente_cloud SET tentatives = tentatives + 1, derniere_erreur = ?, dernier_echec = ? WHERE id = ?',
          [court, quand, id]);
    });
    await b.commit(noResult: true);
  }

  // ------------------------------------------------------------------ opérations bloquées
  /// La liste des opérations bloquées, de la plus ancienne à la plus récente.
  static Future<List<OperationBloquee>> bloquees() async {
    final l = await BaseLocale.db.rawQuery(
        'SELECT id, table_cible, operation, payload, cree_le, derniere_erreur FROM file_attente_cloud '
        'WHERE tentatives >= ? AND IFNULL(reprises_auto, 0) >= ? ORDER BY id ASC',
        [cloudMaxTentatives, cloudDelaisReprisesAuto.length]);
    final out = <OperationBloquee>[];
    for (final r in l) {
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(r['payload'] as String) as Map);
      } catch (_) {
        payload = {};
      }
      out.add(OperationBloquee(r['id'] as int, '${r['table_cible']}', '${r['operation']}',
          '${r['cree_le'] ?? ''}', '${r['derniere_erreur'] ?? ''}', payload));
    }
    return out;
  }

  /// Reprise contrôlée : chaque ligne choisie reçoit UNE dernière tentative (pas cinq).
  /// Si le serveur la refuse encore, elle revient aussitôt dans la liste, avec la nouvelle raison.
  /// [ids] = null → toutes les lignes bloquées.
  static Future<void> relancer({List<int>? ids}) async {
    final b = BaseLocale.db.batch();
    if (ids == null) {
      b.rawUpdate('UPDATE file_attente_cloud SET tentatives = ? WHERE tentatives >= ?',
          [cloudMaxTentatives - 1, cloudMaxTentatives]);
    } else {
      for (final id in ids) {
        b.rawUpdate('UPDATE file_attente_cloud SET tentatives = ? WHERE id = ? AND tentatives >= ?',
            [cloudMaxTentatives - 1, id, cloudMaxTentatives]);
      }
    }
    await b.commit(noResult: true);
    urgent = true;
  }

  /// Abandonne ces opérations : elles sont retirées de la file (la donnée reste sur ce PC, mais ne partira plus).
  static Future<void> abandonner(List<int> ids) => retirer(ids);
}

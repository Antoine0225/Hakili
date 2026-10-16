import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../cloud/file_attente.dart';
import '../cloud/payloads.dart';
import '../data/base_locale.dart';
import '../securite/licence_locale.dart';
import '../utilitaires/formats.dart';

/// Une ligne du fil « Activités récentes » de l'accueil.
class Activite {
  final String titre, detail, quand;
  final String couleur; // 'or' | 'principal' | 'succes'
  const Activite(this.titre, this.detail, this.couleur, this.quand);
}

class StatsBandes {
  final int actives, activesPrec, proches;
  const StatsBandes(this.actives, this.activesPrec, this.proches);
}

class BandesRepo {
  BandesRepo._();

  /// Toutes les bandes non supprimées, la plus récente d'abord (comme _lire_toutes_les_bandes).
  static Future<List<Map<String, Object?>>> toutes() async {
    try {
      final l = await BaseLocale.db.rawQuery('SELECT * FROM bandes_elevage WHERE supprime = 0 ORDER BY id DESC');
      return l.map((r) => Map<String, Object?>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Filet de sécurité : efface rappels et journaux d'une bande qui n'existe plus.
  static Future<void> purgerOrphelins() async {
    try {
      await BaseLocale.db.rawDelete(
          'DELETE FROM rappels_veterinaires WHERE bande_uid NOT IN (SELECT uid FROM bandes_elevage)');
      await BaseLocale.db.rawDelete(
          'DELETE FROM journal_bande_evenements WHERE bande_uid NOT IN (SELECT uid FROM bandes_elevage)');
    } catch (_) {}
  }

  /// Rappels vétérinaires « À faire » dont la date est arrivée.
  static Future<int> compterRappelsDus() async {
    try {
      await purgerOrphelins();
      final l = await BaseLocale.db.rawQuery(
          "SELECT r.date_prevue FROM rappels_veterinaires r "
          "INNER JOIN bandes_elevage b ON b.uid = r.bande_uid WHERE r.statut = 'À faire'");
      final auj = aujourdhui();
      var total = 0;
      for (final r in l) {
        final d = lireJma(r['date_prevue']);
        if (d != null && !DateTime(d.year, d.month, d.day).isAfter(auj)) total++;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// (bandes actives, actives fin du mois dernier, bandes proches de la fin).
  static StatsBandes stats(List<Map<String, Object?>> bandes) {
    final auj = aujourdhui();
    final finMoisPrec = DateTime(auj.year, auj.month, 1).subtract(const Duration(days: 1));
    var actives = 0, activesPrec = 0, proches = 0;
    DateTime? jour(Object? t) {
      final d = lireJma(t);
      return d == null ? null : DateTime(d.year, d.month, d.day);
    }

    for (final b in bandes) {
      final epuisee = b['statut'] == 'Épuisée';
      if (!epuisee) {
        actives++;
        if (maturiteCommercialeJours.containsKey(b['type_elevage']) && b['statut'] == 'En élevage') {
          final dm = jour(b['date_maturite_commerciale']);
          if (dm != null && !dm.isAfter(auj.add(const Duration(days: 7)))) proches++;
        }
      }
      final arr = jour(b['date_arrivee']);
      final ep = jour(b['date_epuisement']);
      if (arr != null && !arr.isAfter(finMoisPrec) && (!epuisee || (ep != null && ep.isAfter(finMoisPrec)))) {
        activesPrec++;
      }
    }
    return StatsBandes(actives, activesPrec, proches);
  }

  static String _coupe(String t) {
    final d = t.trim();
    return d.length > 34 ? '${d.substring(0, 33).trimRight()}…' : d;
  }

  /// Dernières opérations réelles (ventes, entrées de stock, nouvelles bandes), plus récentes d'abord.
  static Future<List<Activite>> activites(List<dynamic> ventes, List<Map<String, Object?>> bandes,
      {int limite = 3, required bool Function(String) estHorsCA, required String Function(num) fcfa}) async {
    final ev = <(DateTime, int, Activite)>[];

    final recentes = ventes.length > 12 ? ventes.sublist(ventes.length - 12) : ventes;
    for (var i = 0; i < recentes.length; i++) {
      final v = recentes[i];
      final d = lireJma(v.date);
      if (d == null) continue;
      final typeTxt = '${v.type}';
      final Activite a;
      if (estHorsCA(typeTxt)) {
        a = Activite('Encaissement', _coupe(typeTxt), 'or', formaterJourRelatif(d));
      } else {
        a = Activite('Vente enregistrée', _coupe('${nombreCourt(v.qte)} $typeTxt – ${fcfa(v.total)} FCFA'), 'or',
            formaterJourRelatif(d));
      }
      ev.add((d, i, a));
    }

    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT date, produit, unite, quantite_saisie, id FROM stocks_arrivages ORDER BY id DESC LIMIT 6');
      for (final r in l) {
        final d = lireJma(r['date']);
        if (d == null) continue;
        final q = (r['quantite_saisie'] as num?)?.toDouble() ?? 0;
        final detail = '${nombreCourt(q)} ${r['unite'] ?? ''} – ${r['produit']}'.replaceAll('  ', ' ');
        ev.add((d, (r['id'] as int?) ?? 0, Activite('Entrée de stock', _coupe(detail), 'principal', formaterJourRelatif(d))));
      }
    } catch (_) {}

    for (final b in bandes.take(6)) {
      final d = lireJma(b['date_creation']);
      if (d == null) continue;
      final heure = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      final eff = (b['effectif_initial'] as num?)?.toInt() ?? 0;
      ev.add((d, (b['id'] as int?) ?? 0,
          Activite('Nouvelle bande créée', _coupe('${b['nom'] ?? ''} – $eff sujets'), 'succes', heure)));
    }

    ev.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : b.$2.compareTo(a.$2);
    });
    return ev.take(limite).map((e) => e.$3).toList();
  }

  // ------------------------------------------------------------------ ÉCRITURES (module Élevage)
  static const colonnes = [
    'uid', 'nom', 'batiment', 'type_elevage', 'stade_biologique', 'bascule_effectuee', 'date_creation',
    'date_arrivee', 'effectif_initial', 'effectif_actuel', 'morts_cumulees', 'oeufs_cumules', 'alveoles_cumulees',
    'cout_investissement_initial', 'cout_direct_cumule', 'cout_direct_cumule_ponte', 'cout_aliment',
    'cout_sante_cumule', 'cout_initial_poussins', 'statut', 'date_maturite_commerciale', 'date_mise_en_vente',
    'date_epuisement', 'cout_unitaire_fige', 'produit_stock_nom', 'date_derniere_imputation',
    'cout_amortissement_cumule', 'frais_annexes_en_attente', 'prix_kg_aliment', 'conso_aliment_kg_cumulee',
    'date_reforme', 'supprime',
  ];

  static Future<Map<String, Object?>?> parUid(String? uid) async {
    if (uid == null || uid.isEmpty) return null;
    try {
      final l = await BaseLocale.db.rawQuery('SELECT * FROM bandes_elevage WHERE uid = ?', [uid]);
      return l.isEmpty ? null : Map<String, Object?>.from(l.first);
    } catch (_) {
      return null;
    }
  }

  static const _defauts = <String, Object>{
    'supprime': 0, 'cout_aliment': 0.0, 'cout_sante_cumule': 0.0, 'cout_initial_poussins': 0.0,
    'date_derniere_imputation': '', 'cout_amortissement_cumule': 0.0, 'frais_annexes_en_attente': 0.0,
    'prix_kg_aliment': 0.0, 'conso_aliment_kg_cumulee': 0.0, 'date_reforme': '',
  };

  /// Enregistre une bande (création ou mise à jour) ET la place dans la file d'envoi, dans la même transaction.
  /// Si [ex] est fourni, l'écriture se joint à la transaction en cours.
  static Future<void> sauvegarder(Map<String, Object?> bande, {bool supprimeCloud = false, DatabaseExecutor? ex}) async {
    _defauts.forEach((k, v) => bande.putIfAbsent(k, () => v));
    Future<void> travail(DatabaseExecutor e) async {
      final existe = await e.rawQuery('SELECT id FROM bandes_elevage WHERE uid = ?', [bande['uid']]);
      final valeurs = [for (final c in colonnes) bande[c] is bool ? ((bande[c] as bool) ? 1 : 0) : bande[c]];
      if (existe.isNotEmpty) {
        await e.rawUpdate(
            'UPDATE bandes_elevage SET ${colonnes.map((c) => '$c = ?').join(', ')} WHERE uid = ?', [...valeurs, bande['uid']]);
      } else {
        await e.rawInsert(
            'INSERT INTO bandes_elevage (${colonnes.join(', ')}) VALUES (${colonnes.map((_) => '?').join(', ')})', valeurs);
      }
      final licence = await Licence.lireEmail();
      await FileAttente.enfiler(e, licence, 'bandes_elevage', 'upsert', PayloadsCloud.bande(bande, licence, supprime: supprimeCloud));
    }

    if (ex != null) {
      await travail(ex);
    } else {
      await BaseLocale.db.transaction(travail);
    }
  }

  /// Supprime la bande, son planning vétérinaire et son journal (répercuté sur les autres PC).
  static Future<void> supprimer(Map<String, Object?> bande) async {
    final uid = bande['uid'];
    await BaseLocale.db.transaction((txn) async {
      await txn.rawDelete('DELETE FROM rappels_veterinaires WHERE bande_uid = ?', [uid]);
      await txn.rawDelete('DELETE FROM journal_bande_evenements WHERE bande_uid = ?', [uid]);
      await txn.rawDelete('DELETE FROM journal_ponte_jour WHERE bande_uid = ?', [uid]);
      await txn.rawDelete('DELETE FROM bandes_elevage WHERE uid = ?', [uid]);
      final licence = await Licence.lireEmail();
      await FileAttente.enfiler(txn, licence, 'bandes_elevage', 'upsert', PayloadsCloud.bande(bande, licence, supprime: true));
    });
  }

  static Future<void> enfilerRappel(DatabaseExecutor ex, Map<String, Object?> rappel) async {
    if ('${rappel['uid'] ?? ''}'.isEmpty) return;
    final licence = await Licence.lireEmail();
    await FileAttente.enfiler(ex, licence, 'rappels_veterinaires', 'upsert', PayloadsCloud.rappel(rappel, licence));
  }

  static Future<void> enfilerJournal(DatabaseExecutor ex, Map<String, Object?> evt) async {
    if ('${evt['uid'] ?? ''}'.isEmpty) return;
    final licence = await Licence.lireEmail();
    await FileAttente.enfiler(ex, licence, 'journal_bande_evenements', 'upsert', PayloadsCloud.journalBande(evt, licence));
  }
}

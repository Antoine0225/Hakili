import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../cloud/file_attente.dart';
import '../cloud/payloads.dart';
import '../data/base_locale.dart';
import '../securite/licence_locale.dart';
import '../utilitaires/formats.dart';
import 'stock_repo.dart';

/// Préfixes des lignes « mouvement de trésorerie pur » du journal de caisse (config_systeme.py).
const prefixeReglementDetteClient = '💵 Règlement de dette';
const prefixeRemboursementFournisseur = '💸 Remboursement fournisseur';

/// Vrai si la ligne est un simple mouvement de trésorerie : elle ne doit pas gonfler le CA.
bool ligneEstHorsChiffreAffaires(String? type) {
  final t = type ?? '';
  return t.startsWith(prefixeReglementDetteClient) || t.startsWith(prefixeRemboursementFournisseur);
}

/// Une vente telle qu'elle est lue en base.
class Vente {
  final int id;
  final String? uid;
  final String date, type, reglement, client, statut;
  final double qte, pu, total, montantRegle, coutAchat;
  const Vente({
    required this.id, required this.uid, required this.date, required this.type,
    required this.qte, required this.pu, required this.total, required this.reglement,
    required this.client, required this.statut, required this.montantRegle, required this.coutAchat,
  });

  double get reste => total - montantRegle;
  bool get estCredit => reglement == 'À Crédit';

  static double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);

  factory Vente.depuisLigne(Map<String, Object?> r) => Vente(
        id: (r['id'] as int?) ?? 0,
        uid: r['uid'] as String?,
        date: '${r['date'] ?? ''}',
        type: '${r['type'] ?? ''}',
        qte: _d(r['qte']),
        pu: _d(r['pu']),
        total: _d(r['total']),
        reglement: '${r['reglement'] ?? ''}',
        client: '${r['client'] ?? ''}',
        statut: ((r['statut'] as String?) ?? '').isEmpty ? 'Actif' : r['statut'] as String,
        montantRegle: _d(r['montant_regle']),
        coutAchat: _d(r['cout_achat']),
      );
}

/// Totaux d'une période : encaissements et bénéfice par jour, + totaux.
class TotauxPeriode {
  final Map<DateTime, List<double>> parJour; // jour -> [encaissé, bénéfice]
  final double ca, benefice;
  final int nb;
  const TotauxPeriode(this.parJour, this.ca, this.benefice, this.nb);

  double get ticket => nb > 0 ? ca / nb : 0.0;
  double get margePct => ca > 0 ? benefice / ca * 100.0 : 0.0;
}

class ProduitRevenu {
  double qte = 0, ca = 0, caSansCout = 0, cout = 0, benefice = 0;
}

/// Revenus de la caisse sur une période (calculer_revenu_caisse_periode de Python).
class RevenuCaisse {
  double caBrut = 0, caSansCout = 0, coutAchat = 0, beneficePur = 0, beneficeEnAttente = 0;
  int nbVentes = 0, nbSansCout = 0;
  final Map<String, ProduitRevenu> parProduit = {};
}

class VentesRepo {
  VentesRepo._();

  // La liste de toutes les ventes est gardée en mémoire tant que rien n'a changé dans la base
  // (voir le compteur « compteurs_changements »). Ouvrir un écran ne relit donc plus des milliers de lignes pour rien.
  static List<Vente>? _cache;
  static int _cacheVersion = -1;
  static Object? _cacheBase;

  static Future<int?> _versionVentes() async {
    try {
      final l = await BaseLocale.db.rawQuery("SELECT n FROM compteurs_changements WHERE nom = 'ventes'");
      return l.isEmpty ? null : (l.first['n'] as int?);
    } catch (_) {
      return null; // pas de compteur : on lit toujours la base (plus lent, mais toujours juste)
    }
  }

  static Future<List<Vente>> toutes() async {
    final base = BaseLocale.db;
    final version = await _versionVentes(); // lue AVANT la lecture : en cas de doute on relira, jamais l'inverse
    final cache = _cache;
    if (version != null && cache != null && _cacheVersion == version && identical(_cacheBase, base)) {
      return List<Vente>.of(cache);
    }
    final l = await base.rawQuery(
        'SELECT id, uid, date, type, qte, pu, total, reglement, client, statut, montant_regle, cout_achat '
        'FROM ventes ORDER BY id ASC');
    final liste = l.map(Vente.depuisLigne).toList();
    if (version != null) {
      _cache = liste;
      _cacheVersion = version;
      _cacheBase = base;
    } else {
      _cache = null;
    }
    return List<Vente>.of(liste);
  }

  /// Seulement les ventes à crédit qui ne sont pas encore soldées (écran Crédits) : quelques lignes au lieu de tout l'historique.
  static Future<List<Vente>> creancesOuvertes() async {
    final l = await BaseLocale.db.rawQuery(
        'SELECT id, uid, date, type, qte, pu, total, reglement, client, statut, montant_regle, cout_achat '
        "FROM ventes WHERE reglement = 'À Crédit' AND (total - IFNULL(montant_regle, 0)) > 0.01 ORDER BY id ASC");
    return l.map(Vente.depuisLigne).toList();
  }

  /// Mêmes règles que le reste du logiciel : les mouvements de trésorerie purs ne comptent pas dans le CA ;
  /// une vente à crédit ne compte que pour la part déjà réglée ; le bénéfice ne compte que si le coût d'achat est connu.
  static TotauxPeriode totauxPeriode(List<Vente> ventes, DateTime debut, DateTime fin) {
    final parJour = <DateTime, List<double>>{};
    var nb = 0;
    for (final v in ventes) {
      if (ligneEstHorsChiffreAffaires(v.type)) continue;
      final dt = lireJma(v.date.trim().length >= 10 ? v.date.trim().substring(0, 10) : v.date);
      if (dt == null) continue;
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d.isBefore(debut) || d.isAfter(fin)) continue;
      final part = v.estCredit ? (v.total < v.montantRegle ? v.total : v.montantRegle) : v.total;
      final ratio = v.total > 0 ? part / v.total : 1.0;
      final marge = v.coutAchat > 0 ? (v.pu - v.coutAchat) * v.qte * ratio : 0.0;
      final j = parJour.putIfAbsent(d, () => [0.0, 0.0]);
      j[0] += part;
      j[1] += marge;
      nb++;
    }
    final ca = parJour.values.fold<double>(0, (s, j) => s + j[0]);
    final ben = parJour.values.fold<double>(0, (s, j) => s + j[1]);
    return TotauxPeriode(parJour, ca, ben, nb);
  }

  /// Dettes clients encore ouvertes (reste à payer > seuil).
  static List<Vente> dettesOuvertes(List<Vente> ventes, {double seuil = 0.01}) =>
      ventes.where((v) => v.estCredit && v.reste > seuil).toList();

  /// (bénéfice en poche, bénéfice en attente sur crédits) — mêmes règles que calculer_marges_depuis_ventes.
  static (double, double) margesEnPocheEtAttente(List<Vente> ventes) {
    var poche = 0.0, attente = 0.0;
    for (final v in ventes) {
      if (ligneEstHorsChiffreAffaires(v.type) || v.coutAchat <= 0) continue;
      final marge = (v.pu - v.coutAchat) * v.qte;
      if (v.estCredit) {
        final part = v.total > 0 ? (v.montantRegle / v.total).clamp(0.0, 1.0).toDouble() : 1.0;
        poche += marge * part;
        attente += marge * (1.0 - part);
      } else {
        poche += marge;
      }
    }
    return (poche, attente);
  }

  static RevenuCaisse revenuPeriode(List<Vente> ventes, DateTime debut, DateTime fin) {
    final r = RevenuCaisse();
    for (final v in ventes) {
      if (ligneEstHorsChiffreAffaires(v.type)) continue;
      final dt = lireJma(v.date.trim());
      if (dt == null || dt.isBefore(debut) || dt.isAfter(fin)) continue;
      final nom = v.type.isEmpty ? 'Produit inconnu' : v.type;
      final p = r.parProduit.putIfAbsent(nom, () => ProduitRevenu());
      r.nbVentes++;
      r.caBrut += v.total;
      p.qte += v.qte;
      p.ca += v.total;
      if (v.coutAchat > 0) {
        final coutLigne = v.coutAchat * v.qte;
        final marge = v.total - coutLigne;
        r.coutAchat += coutLigne;
        p.cout += coutLigne;
        p.benefice += marge;
        r.beneficePur += marge;
        if (v.estCredit && v.total > 0) {
          final part = (v.montantRegle / v.total).clamp(0.0, 1.0).toDouble();
          r.beneficeEnAttente += marge * (1.0 - part);
        }
      } else {
        r.nbSansCout++;
        r.caSansCout += v.total;
        p.caSansCout += v.total;
      }
    }
    return r;
  }

  static Future<int> _compter(DatabaseExecutor ex) async {
    final l = await ex.rawQuery('SELECT COUNT(*) AS n FROM ventes');
    return (l.first['n'] as int?) ?? 0;
  }

  // ------------------------------------------------------------------ ÉCRITURES
  // Chaque écriture locale est doublée, dans la MÊME transaction, d'une ligne « à envoyer » au Cloud :
  // rien ne peut se perdre, même si le PC s'éteint à la milliseconde suivante.

  static Map<String, Object?> _enMap(String date, String type, double qte, double pu, double total,
          String reglement, String client, String statut, double regle, double cout) =>
      {
        'date': date, 'type': type, 'qte': qte, 'pu': pu, 'total': total, 'reglement': reglement,
        'client': client, 'statut': statut, 'montant_regle': regle, 'cout_achat': cout,
      };

  static Future<void> _enfilerVente(DatabaseExecutor ex, Map<String, Object?> m, String uid,
      {bool supprime = false}) async {
    final licence = await Licence.lireEmail();
    await FileAttente.enfiler(ex, licence, 'ventes', 'upsert', PayloadsCloud.vente(m, uid, licence, supprime: supprime));
  }

  /// Nouvelle vente : écriture + sortie de stock. Renvoie l'uid créé.
  static Future<String> ajouter({
    required String date, required String type, required double qte, required double pu,
    required String reglement, required String client, required double coutAchat,
  }) async {
    final uid = nouvelUid();
    await BaseLocale.db.transaction((txn) async {
      final n = await _compter(txn);
      final total = qte * pu;
      await txn.rawInsert(
          'INSERT INTO ventes (uid, ligne, date, type, qte, pu, total, reglement, client, statut, montant_regle, cout_achat) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'Actif', 0, ?)",
          [uid, n, date, type, qte, pu, total, reglement, client, coutAchat]);
      await _enfilerVente(txn, _enMap(date, type, qte, pu, total, reglement, client, 'Actif', 0.0, coutAchat), uid);
      await StockRepo.mettreAJour(txn, type, -qte);
    });
    return uid;
  }

  /// Modification d'une vente : on rend l'ancien stock, on retire le nouveau (statut et règlement conservés).
  static Future<void> modifier(Vente ancienne, {
    required String date, required String type, required double qte, required double pu,
    required String reglement, required String client, required double coutAchat,
  }) async {
    await BaseLocale.db.transaction((txn) async {
      var uid = ancienne.uid;
      if (uid == null || uid.isEmpty) {
        final l = await txn.rawQuery('SELECT uid FROM ventes WHERE id = ?', [ancienne.id]);
        uid = (l.isNotEmpty && ('${l.first['uid'] ?? ''}').isNotEmpty) ? '${l.first['uid']}' : nouvelUid();
      }
      final total = qte * pu;
      await txn.rawUpdate(
          'UPDATE ventes SET uid=?, date=?, type=?, qte=?, pu=?, total=?, reglement=?, client=?, statut=?, '
          'montant_regle=?, cout_achat=? WHERE id=?',
          [uid, date, type, qte, pu, total, reglement, client, ancienne.statut, ancienne.montantRegle, coutAchat, ancienne.id]);
      await _enfilerVente(
          txn, _enMap(date, type, qte, pu, total, reglement, client, ancienne.statut, ancienne.montantRegle, coutAchat), uid);
      if (ancienne.type.isNotEmpty) await StockRepo.mettreAJour(txn, ancienne.type, ancienne.qte);
      await StockRepo.mettreAJour(txn, type, -qte);
    });
  }

  static Future<void> _reecrire(DatabaseExecutor ex, Vente v, {String? statut, double? regle}) async {
    var uid = v.uid;
    if (uid == null || uid.isEmpty) {
      final l = await ex.rawQuery('SELECT uid FROM ventes WHERE id = ?', [v.id]);
      uid = (l.isNotEmpty && ('${l.first['uid'] ?? ''}').isNotEmpty) ? '${l.first['uid']}' : nouvelUid();
    }
    final s = statut ?? v.statut;
    final r = regle ?? v.montantRegle;
    await ex.rawUpdate('UPDATE ventes SET uid=?, statut=?, montant_regle=? WHERE id=?', [uid, s, r, v.id]);
    await _enfilerVente(ex, _enMap(v.date, v.type, v.qte, v.pu, v.total, v.reglement, v.client, s, r, v.coutAchat), uid);
  }

  /// 🔒 « Figer Vente » : la facture ne peut plus être modifiée.
  static Future<void> cloturer(Vente v) =>
      BaseLocale.db.transaction((txn) => _reecrire(txn, v, statut: 'Clôturé'));

  /// Encaisse une partie (ou la totalité) d'une dette client, et inscrit l'entrée d'argent dans le journal.
  static Future<void> reglerCredit(Vente v, double montant, {String mode = 'Espèces'}) async {
    if (!v.estCredit) return;
    final reste = v.reste < 0 ? 0.0 : v.reste;
    montant = montant < 0 ? 0.0 : (montant > reste ? reste : montant);
    if (montant <= 0) return;
    await BaseLocale.db.transaction((txn) async {
      await _reecrire(txn, v, regle: v.montantRegle + montant);
      final nom = v.client.trim().isEmpty ? 'Débiteur' : v.client.trim();
      final uid = nouvelUid();
      final date = jourEnTexte(DateTime.now());
      final n = await _compter(txn);
      final type = '$prefixeReglementDetteClient — $nom';
      await txn.rawInsert(
          'INSERT INTO ventes (uid, ligne, date, type, qte, pu, total, reglement, client, statut, montant_regle, cout_achat) '
          "VALUES (?, ?, ?, ?, 1, ?, ?, ?, '', 'Actif', 0, 0)",
          [uid, n, date, type, montant, montant, mode]);
      await _enfilerVente(txn, _enMap(date, type, 1, montant, montant, mode, '', 'Actif', 0.0, 0.0), uid);
    });
  }

  /// Inscrit un mouvement de trésorerie pur dans le journal de caisse (montant > 0 : entrée, < 0 : sortie).
  static Future<void> ligneTresorerie(DatabaseExecutor txn, String type, double montant, {String mode = 'Espèces'}) async {
    final uid = nouvelUid();
    final date = jourEnTexte(DateTime.now());
    final n = await _compter(txn);
    await txn.rawInsert(
        'INSERT INTO ventes (uid, ligne, date, type, qte, pu, total, reglement, client, statut, montant_regle, cout_achat) '
        "VALUES (?, ?, ?, ?, 1, ?, ?, ?, '', 'Actif', 0, 0)",
        [uid, n, date, type, montant, montant, mode]);
    await _enfilerVente(txn, _enMap(date, type, 1, montant, montant, mode, '', 'Actif', 0.0, 0.0), uid);
  }

  /// Supprime une vente et rend la marchandise au stock (sauf pour un simple mouvement de trésorerie).
  static Future<void> supprimer(Vente v) async {
    await BaseLocale.db.transaction((txn) async {
      var uid = v.uid;
      if (uid == null || uid.isEmpty) {
        final l = await txn.rawQuery('SELECT uid FROM ventes WHERE id = ?', [v.id]);
        uid = l.isNotEmpty ? l.first['uid'] as String? : null;
      }
      await txn.rawDelete('DELETE FROM ventes WHERE id = ?', [v.id]);
      if (uid != null && uid.isNotEmpty) {
        await _enfilerVente(
            txn, _enMap(v.date, v.type, v.qte, v.pu, v.total, v.reglement, v.client, v.statut, v.montantRegle, v.coutAchat), uid,
            supprime: true);
      }
      if (v.type.isNotEmpty && !ligneEstHorsChiffreAffaires(v.type)) {
        await StockRepo.mettreAJour(txn, v.type, v.qte);
      }
    });
  }
}

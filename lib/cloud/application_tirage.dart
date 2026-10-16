import 'dart:convert';

import '../data/base_locale.dart';
import '../data/parametres.dart';
import 'moteur_cloud.dart';

/// Ce qui a changé après un rapatriement : les écrans s'en servent pour se rafraîchir.
class ResumeTirage {
  int ventesAjoutees = 0, ventesModifiees = 0, ventesSupprimees = 0, arrivagesAjoutes = 0;
  bool catalogueChange = false, stockChange = false, bandesChange = false, rappelsChange = false;

  bool get quelqueChoseAChange =>
      ventesAjoutees + ventesModifiees + ventesSupprimees + arrivagesAjoutes > 0 ||
      catalogueChange || stockChange || bandesChange || rappelsChange;
}

/// Intègre dans SQLite ce que l'autre PC a saisi. Règle d'or : une ligne locale qui attend encore
/// d'être envoyée n'est JAMAIS écrasée (« 🛡️ protégée »). Tout se fait dans UNE transaction :
/// si une erreur survient, rien n'est modifié (retour arrière complet).
class ApplicationTirage {
  ApplicationTirage._();

  static double _n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);
  static String _s(Object? v, [String defaut = '']) {
    final t = v?.toString() ?? '';
    return t.isEmpty ? defaut : t;
  }

  /// SQLite n'accepte pas les booléens : vrai/faux deviennent 1/0.
  static Object? _sql(Object? v) => v is bool ? (v ? 1 : 0) : v;

  static const _colonnesBande = [
    'nom', 'batiment', 'type_elevage', 'stade_biologique', 'bascule_effectuee', 'date_creation',
    'date_arrivee', 'effectif_initial', 'effectif_actuel', 'morts_cumulees', 'oeufs_cumules',
    'alveoles_cumulees', 'cout_investissement_initial', 'cout_initial_poussins', 'cout_direct_cumule',
    'cout_direct_cumule_ponte', 'cout_aliment', 'statut', 'date_maturite_commerciale',
    'date_mise_en_vente', 'date_epuisement', 'cout_unitaire_fige', 'produit_stock_nom',
    'date_derniere_imputation', 'cout_amortissement_cumule', 'frais_annexes_en_attente',
    'prix_kg_aliment', 'conso_aliment_kg_cumulee', 'date_reforme',
  ];

  static Future<ResumeTirage> appliquer(Tirage tirage,
      {required void Function(String etat, String detail) journaliser}) async {
    final resume = ResumeTirage();
    await BaseLocale.db.transaction((txn) async {
      // --- Ce qui attend encore d'être envoyé est protégé
      final protegesVentes = <String>{}, protegesArrivages = <String>{};
      final protegesCatalogue = <String>{}, protegesStock = <String>{};
      final protegesBandes = <String>{}, protegesRappels = <String>{};
      final file = await txn.rawQuery('SELECT table_cible, payload FROM file_attente_cloud');
      for (final l in file) {
        Map p;
        try {
          p = jsonDecode(l['payload'] as String) as Map;
        } catch (_) {
          continue;
        }
        final table = l['table_cible'];
        if (table == 'ventes' && p['uid'] != null) protegesVentes.add('${p['uid']}');
        if (table == 'stocks_arrivages' && p['uid'] != null) protegesArrivages.add('${p['uid']}');
        if (table == 'catalogue_produits' && p['nom'] != null) protegesCatalogue.add('${p['nom']}');
        if (table == 'stock_produits' && p['p_nom'] != null) protegesStock.add('${p['p_nom']}');
        if (table == 'bandes_elevage' && p['uid'] != null) protegesBandes.add('${p['uid']}');
        if (table == 'rappels_veterinaires' && p['uid'] != null) protegesRappels.add('${p['uid']}');
      }

      // --- VENTES
      const ordreVente = ['date', 'type', 'qte', 'pu', 'total', 'reglement', 'client', 'statut',
        'montant_regle', 'cout_achat'];
      for (final ligne in tirage.tables['ventes']!) {
        final uid = ligne['uid'];
        if (uid == null || '$uid'.isEmpty || protegesVentes.contains('$uid')) continue;
        final local = await txn.rawQuery('SELECT * FROM ventes WHERE uid = ?', [uid]);
        if (ligne['supprime'] == true) {
          if (local.isNotEmpty) {
            await txn.rawDelete('DELETE FROM ventes WHERE uid = ?', [uid]);
            resume.ventesSupprimees++;
          }
          continue;
        }
        final valeurs = <String, Object>{
          'date': _s(ligne['date']), 'type': _s(ligne['type']),
          'qte': _n(ligne['qte']), 'pu': _n(ligne['pu']), 'total': _n(ligne['total']),
          'reglement': _s(ligne['reglement'], 'Espèces'), 'client': _s(ligne['client']),
          'statut': _s(ligne['statut'], 'Actif'),
          'montant_regle': _n(ligne['montant_regle']), 'cout_achat': _n(ligne['cout_achat']),
        };
        final args = ordreVente.map((k) => valeurs[k]).toList();
        if (local.isNotEmpty) {
          final l = local.first;
          var identique = true;
          for (final k in ordreVente) {
            final a = l[k], b = valeurs[k];
            final egal = b is double ? (_n(a) == b) : (_s(a, k == 'statut' ? 'Actif' : '') == b);
            if (!egal) {
              identique = false;
              break;
            }
          }
          if (identique) continue; // déjà à jour
          await txn.rawUpdate(
              'UPDATE ventes SET date=?, type=?, qte=?, pu=?, total=?, reglement=?, client=?, statut=?, '
              'montant_regle=?, cout_achat=? WHERE uid=?',
              [...args, uid]);
          resume.ventesModifiees++;
        } else {
          await txn.rawInsert(
              'INSERT INTO ventes (uid, ligne, date, type, qte, pu, total, reglement, client, statut, '
              'montant_regle, cout_achat) VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [uid, ...args]);
          resume.ventesAjoutees++;
        }
      }

      // --- ARRIVAGES (jamais de « solde » imposé par le Cloud : le local garde la main sur les dettes)
      for (final ligne in tirage.tables['stocks_arrivages']!) {
        final uid = ligne['uid'];
        if (uid == null || '$uid'.isEmpty || protegesArrivages.contains('$uid')) continue;
        final local = await txn.rawQuery(
            'SELECT montant_regle, statut, prix_achat_total, fournisseur, produit '
            'FROM stocks_arrivages WHERE uid = ?',
            [uid]);
        final mrCloud = _n(ligne['montant_regle']);
        final statutCloud = _s(ligne['statut'], 'Actif');
        final prixCloud = _n(ligne['prix_achat_total']);
        if (local.isNotEmpty) {
          final l = local.first;
          final ancienMr = _n(l['montant_regle']);
          final ancienStatut = _s(l['statut'], 'Actif');
          final prixLocal = _n(l['prix_achat_total']) != 0 ? _n(l['prix_achat_total']) : prixCloud;
          var nouveauMr = ancienMr > mrCloud ? ancienMr : mrCloud;
          // Un « Soldé » venu du Cloud sans que le local l'ait décidé est ignoré
          if (prixLocal > 0 && nouveauMr >= prixLocal - 0.01 &&
              (prixLocal - ancienMr) > 0.01 && statutCloud != 'Soldé') {
            nouveauMr = ancienMr;
          }
          final nouveauStatut = (prixLocal > 0 && (prixLocal - nouveauMr) <= 0.01) ? 'Soldé' : 'Actif';
          if (nouveauMr != mrCloud) {
            journaliser('arrivage_solde_cloud_ignore',
                "arrivage $uid (${_s(l['fournisseur'], '?')} / ${_s(l['produit'], '?')}) : Cloud "
                "montant_regle=$mrCloud statut='$statutCloud' — local conservé =$nouveauMr");
          }
          if (ancienMr == nouveauMr && ancienStatut == nouveauStatut) continue; // déjà à jour
          // On signale à la « boîte noire » que cette écriture vient du Cloud
          await txn.rawInsert("INSERT OR REPLACE INTO parametres (cle, valeur) VALUES ('ctx_ecriture', 'pull_cloud')");
          await txn.rawUpdate('UPDATE stocks_arrivages SET montant_regle = ?, statut = ? WHERE uid = ?',
              [nouveauMr, nouveauStatut, uid]);
          await txn.rawDelete("DELETE FROM parametres WHERE cle = 'ctx_ecriture'");
        } else {
          await txn.rawInsert(
              'INSERT INTO stocks_arrivages (uid, date, produit, unite, quantite_saisie, poids_sac, '
              'prix_achat_total, cout_unitaire, quantite_ajoutee, reglement, fournisseur, alveoles_bonus, '
              'montant_regle, statut) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [uid, _s(ligne['date']), ligne['produit'], ligne['unite'], _n(ligne['quantite_saisie']),
               _n(ligne['poids_sac']), prixCloud, _n(ligne['cout_unitaire']), _n(ligne['quantite_ajoutee']),
               _s(ligne['reglement'], 'Espèces'), _s(ligne['fournisseur']), _n(ligne['alveoles_bonus']),
               mrCloud, statutCloud]);
        }
        resume.arrivagesAjoutes++;
      }

      // --- BANDES
      for (final ligne in tirage.tables['bandes_elevage']!) {
        final uid = ligne['uid'];
        if (uid == null || '$uid'.isEmpty || protegesBandes.contains('$uid')) continue;
        final existe = await txn.rawQuery('SELECT id FROM bandes_elevage WHERE uid = ?', [uid]);
        if (ligne['supprime'] == true) {
          if (existe.isNotEmpty) {
            await txn.rawDelete('DELETE FROM rappels_veterinaires WHERE bande_uid = ?', [uid]);
            await txn.rawDelete('DELETE FROM journal_bande_evenements WHERE bande_uid = ?', [uid]);
            await txn.rawDelete('DELETE FROM bandes_elevage WHERE uid = ?', [uid]);
            resume.bandesChange = true;
          }
          continue;
        }
        final valeurs = [for (final c in _colonnesBande) _sql(ligne[c])];
        if (existe.isNotEmpty) {
          await txn.rawUpdate(
              'UPDATE bandes_elevage SET ${_colonnesBande.map((c) => '$c = ?').join(', ')} WHERE uid = ?',
              [...valeurs, uid]);
        } else {
          await txn.rawInsert(
              'INSERT INTO bandes_elevage (uid, ${_colonnesBande.join(', ')}) '
              'VALUES (?, ${_colonnesBande.map((_) => '?').join(', ')})',
              [uid, ...valeurs]);
        }
        resume.bandesChange = true;
      }

      // --- RAPPELS VÉTÉRINAIRES
      for (final ligne in tirage.tables['rappels_veterinaires']!) {
        final uid = ligne['uid'];
        if (uid == null || '$uid'.isEmpty || protegesRappels.contains('$uid')) continue;
        final existe = await txn.rawQuery('SELECT id FROM rappels_veterinaires WHERE uid = ?', [uid]);
        if (existe.isEmpty) {
          // un rappel dont la bande n'existe pas ici est ignoré
          final bande = await txn.rawQuery(
              'SELECT 1 FROM bandes_elevage WHERE uid = ?', [_s(ligne['bande_uid'])]);
          if (bande.isEmpty) continue;
        }
        final v = [_s(ligne['bande_uid']), _s(ligne['date_prevue']), _s(ligne['tache']),
          _s(ligne['recurrent']), _s(ligne['statut'], 'À faire'), _s(ligne['fait_le']), _s(ligne['fait_par'])];
        if (existe.isNotEmpty) {
          await txn.rawUpdate(
              'UPDATE rappels_veterinaires SET bande_uid=?, date_prevue=?, tache=?, recurrent=?, '
              'statut=?, fait_le=?, fait_par=? WHERE uid=?',
              [...v, uid]);
        } else {
          await txn.rawInsert(
              'INSERT INTO rappels_veterinaires (uid, bande_uid, date_prevue, tache, recurrent, statut, '
              'fait_le, fait_par) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
              [uid, ...v]);
        }
        resume.rappelsChange = true;
      }

      // --- CATALOGUE (fusion : les ajouts/suppressions locaux en attente gagnent)
      final cataCloud = <String, String>{
        for (final l in tirage.tables['catalogue_produits']!) _s(l['nom']): _s(l['unite'], 'piece')
      };
      final cataLocalLignes = await txn.rawQuery('SELECT nom, unite FROM catalogue_produits ORDER BY id ASC');
      final cataLocal = <String, String>{for (final l in cataLocalLignes) '${l['nom']}': _s(l['unite'])};
      if (cataCloud.isNotEmpty) {
        final fusion = Map<String, String>.from(cataCloud);
        for (final nom in protegesCatalogue) {
          if (cataLocal.containsKey(nom)) {
            fusion[nom] = cataLocal[nom]!;
          } else {
            fusion.remove(nom);
          }
        }
        final memeContenu = fusion.length == cataLocal.length &&
            fusion.entries.every((e) => cataLocal[e.key] == e.value);
        if (!memeContenu) {
          await txn.rawDelete('DELETE FROM catalogue_produits');
          for (final e in fusion.entries) {
            await txn.rawInsert('INSERT INTO catalogue_produits (nom, unite) VALUES (?, ?)', [e.key, e.value]);
          }
          resume.catalogueChange = true;
        }
      }

      // --- STOCK (priorité absolue au local en attente)
      final stockCloud = <String, (double, double)>{
        for (final l in tirage.tables['stock_produits']!)
          _s(l['nom']): (_n(l['quantite_disponible']), _n(l['cout_achat_unitaire']))
      };
      final stockLocalLignes =
          await txn.rawQuery('SELECT nom, quantite_disponible, cout_achat_unitaire FROM stock_produits');
      final stockLocal = <String, (double, double)>{
        for (final l in stockLocalLignes)
          '${l['nom']}': (_n(l['quantite_disponible']), _n(l['cout_achat_unitaire']))
      };
      final fusionStock = Map<String, (double, double)>.from(stockCloud);
      for (final nom in protegesStock) {
        if (stockLocal.containsKey(nom)) fusionStock[nom] = stockLocal[nom]!;
      }
      stockLocal.forEach((nom, valeur) => fusionStock.putIfAbsent(nom, () => valeur));
      final stockIdentique = fusionStock.length == stockLocal.length &&
          fusionStock.entries.every((e) => stockLocal[e.key] == e.value);
      if (fusionStock.isNotEmpty && !stockIdentique) {
        await txn.rawDelete('DELETE FROM stock_produits');
        for (final e in fusionStock.entries) {
          await txn.rawInsert(
              'INSERT INTO stock_produits (nom, quantite_disponible, cout_achat_unitaire) VALUES (?, ?, ?)',
              [e.key, e.value.$1, e.value.$2]);
        }
        resume.stockChange = true;
      }

      // --- Curseurs : le prochain tirage reprendra à partir d'ici
      for (final e in tirage.curseurs.entries) {
        await txn.rawInsert('INSERT OR REPLACE INTO parametres (cle, valeur) VALUES (?, ?)',
            ['cloud_curseur_${e.key}', '${e.value}']);
      }
    });
    return resume;
  }

  /// Lit les curseurs mémorisés (dernière ligne « seq » rapatriée par table).
  static Future<Map<String, int>> lireCurseurs(Iterable<String> tables) async {
    final c = <String, int>{};
    for (final t in tables) {
      c[t] = int.tryParse(await Parametres.lire('cloud_curseur_$t', defaut: '0')) ?? 0;
    }
    return c;
  }
}

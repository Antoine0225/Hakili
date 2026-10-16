import '../cloud/file_attente.dart';
import '../cloud/payloads.dart';
import '../securite/licence_locale.dart';
import '../services/diagnostic.dart';
import '../utilitaires/formats.dart';
import 'base_locale.dart';
import 'stock_repo.dart';
import 'ventes_repo.dart';

class Arrivage {
  final int id;
  final String uid, date, produit, unite, reglement, fournisseur, statut;
  final double quantiteSaisie, poidsSac, prixAchatTotal, coutUnitaire, quantiteAjoutee, alveolesBonus, montantRegle;
  const Arrivage({
    required this.id, required this.uid, required this.date, required this.produit, required this.unite,
    required this.quantiteSaisie, required this.poidsSac, required this.prixAchatTotal, required this.coutUnitaire,
    required this.quantiteAjoutee, required this.reglement, required this.fournisseur, required this.alveolesBonus,
    required this.montantRegle, required this.statut,
  });

  static double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);

  factory Arrivage.depuisLigne(Map<String, Object?> r) => Arrivage(
        id: (r['id'] as int?) ?? 0,
        uid: '${r['uid'] ?? ''}',
        date: '${r['date'] ?? ''}'.trim(),
        produit: '${r['produit'] ?? ''}',
        unite: '${r['unite'] ?? 'piece'}',
        quantiteSaisie: _d(r['quantite_saisie']),
        poidsSac: _d(r['poids_sac']),
        prixAchatTotal: _d(r['prix_achat_total']),
        coutUnitaire: _d(r['cout_unitaire']),
        quantiteAjoutee: _d(r['quantite_ajoutee']),
        reglement: ('${r['reglement'] ?? ''}').isEmpty ? 'Espèces' : '${r['reglement']}',
        fournisseur: '${r['fournisseur'] ?? ''}',
        alveolesBonus: _d(r['alveoles_bonus']),
        montantRegle: _d(r['montant_regle']),
        statut: ('${r['statut'] ?? ''}').isEmpty ? 'Actif' : '${r['statut']}',
      );

  double get totalAchete => coutUnitaire * quantiteAjoutee;
}

class DetteFournisseur {
  final int id;
  final String date, produit, fournisseur;
  final double prixAchatTotal, montantRegle, resteDu;
  const DetteFournisseur(this.id, this.date, this.produit, this.fournisseur, this.prixAchatTotal, this.montantRegle, this.resteDu);
}

class ProduitFournisseur {
  int n = 0;
  double sommeCout = 0;
  double? coutMin;
  String unite;
  ProduitFournisseur(this.unite);
}

class StatFournisseur {
  int livraisons = 0;
  double totalDepense = 0;
  String derniereDate = '';
  final Map<String, ProduitFournisseur> produits = {};
}

class StatsFournisseurs {
  final Map<String, StatFournisseur> parFournisseur;
  final Map<String, (String, double, String)> meilleurPrix; // produit -> (fournisseur, coût, unité)
  const StatsFournisseurs(this.parFournisseur, this.meilleurPrix);
}

class ArrivagesRepo {
  ArrivagesRepo._();

  static Future<List<Arrivage>> du(String date) async {
    try {
      final l = await BaseLocale.db.rawQuery('SELECT * FROM stocks_arrivages WHERE date = ? ORDER BY id ASC', [date.trim()]);
      return l.map((r) => Arrivage.depuisLigne(r)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Arrivage>> periode(DateTime debut, DateTime fin) async {
    try {
      final l = await BaseLocale.db.rawQuery('SELECT * FROM stocks_arrivages ORDER BY id ASC');
      final out = <(DateTime, Arrivage)>[];
      for (final r in l) {
        final a = Arrivage.depuisLigne(r);
        final d = lireJma(a.date);
        if (d != null && !d.isBefore(debut) && !d.isAfter(fin)) out.add((d, a));
      }
      out.sort((x, y) => x.$1.compareTo(y.$1)); // tri stable : l'ordre de saisie est conservé le même jour
      return out.map((e) => e.$2).toList();
    } catch (_) {
      return [];
    }
  }

  /// Enregistre un arrivage ET met à jour le stock, dans une seule transaction.
  /// Renvoie l'identifiant créé, ou null si l'écriture a échoué.
  static Future<int?> enregistrer({
    required String date, required String produit, required String unite, required double quantiteSaisie,
    required double poidsSac, required double prixAchatTotal, required double coutUnitaire,
    required double quantiteAjoutee, required String reglement, required String fournisseur,
    required double alveolesBonus,
  }) async {
    try {
      return await BaseLocale.db.transaction((txn) async {
        await StockRepo.mettreAJour(txn, produit, quantiteAjoutee, nouveauCout: coutUnitaire);
        if (alveolesBonus > 0) await StockRepo.mettreAJour(txn, produit, alveolesBonus);
        final uid = nouvelUid();
        final id = await txn.rawInsert(
            'INSERT INTO stocks_arrivages (uid, date, produit, unite, quantite_saisie, poids_sac, prix_achat_total, '
            "cout_unitaire, quantite_ajoutee, reglement, fournisseur, alveoles_bonus, montant_regle, statut) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'Actif')",
            [uid, date, produit, unite, quantiteSaisie, poidsSac, prixAchatTotal, coutUnitaire, quantiteAjoutee,
             reglement, fournisseur, alveolesBonus]);
        final licence = await Licence.lireEmail();
        await FileAttente.enfiler(txn, licence, 'stocks_arrivages', 'upsert', PayloadsCloud.arrivage({
          'uid': uid, 'date': date, 'produit': produit, 'unite': unite, 'quantite_saisie': quantiteSaisie,
          'poids_sac': poidsSac, 'prix_achat_total': prixAchatTotal, 'cout_unitaire': coutUnitaire,
          'quantite_ajoutee': quantiteAjoutee, 'reglement': reglement, 'fournisseur': fournisseur,
          'alveoles_bonus': alveolesBonus, 'montant_regle': 0.0, 'statut': 'Actif',
        }, licence));
        return id;
      });
    } catch (e) {
      Diagnostic.ecrire('Arrivage non enregistré : $e');
      return null;
    }
  }

  /// Répertoire fournisseurs : livraisons, dépenses, meilleur prix par produit.
  static Future<StatsFournisseurs?> statistiquesFournisseurs() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          "SELECT fournisseur, produit, cout_unitaire, prix_achat_total, date, unite FROM stocks_arrivages "
          "WHERE fournisseur IS NOT NULL AND TRIM(fournisseur) != '' ORDER BY id ASC");
      final par = <String, StatFournisseur>{};
      final meilleur = <String, (String, double, String)>{};
      for (final r in l) {
        final nom = ('${r['fournisseur']}').trim();
        if (nom.isEmpty) continue;
        final cout = Arrivage._d(r['cout_unitaire']);
        final prix = Arrivage._d(r['prix_achat_total']);
        final produit = '${r['produit']}';
        final unite = '${r['unite'] ?? 'piece'}';
        final f = par.putIfAbsent(nom, () => StatFournisseur());
        f.livraisons++;
        f.totalDepense += prix;
        final d = lireJma(r['date']);
        final derniere = lireJma(f.derniereDate);
        if (d != null && (derniere == null || d.isAfter(derniere))) f.derniereDate = '${r['date']}'.trim();
        final p = f.produits.putIfAbsent(produit, () => ProduitFournisseur(unite));
        p.n++;
        p.sommeCout += cout;
        if (p.coutMin == null || cout < p.coutMin!) p.coutMin = cout;
        final m = meilleur[produit];
        if (cout > 0 && (m == null || cout < m.$2)) meilleur[produit] = (nom, cout, unite);
      }
      return StatsFournisseurs(par, meilleur);
    } catch (_) {
      return null;
    }
  }

  /// Dettes fournisseurs encore ouvertes. Renvoie null si la lecture échoue (on ne dit jamais « tout est réglé » à tort).
  static Future<List<DetteFournisseur>?> dettesActives() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          "SELECT id, date, produit, fournisseur, prix_achat_total, montant_regle FROM stocks_arrivages "
          "WHERE reglement = 'À Crédit' ORDER BY id ASC");
      final out = <DetteFournisseur>[];
      for (final r in l) {
        final prix = Arrivage._d(r['prix_achat_total']);
        final regle = Arrivage._d(r['montant_regle']);
        final reste = prix - regle;
        if (reste > 0.01) {
          final f = ('${r['fournisseur'] ?? ''}').isEmpty ? 'Fournisseur' : '${r['fournisseur']}';
          out.add(DetteFournisseur(r['id'] as int, '${r['date']}', '${r['produit']}', f, prix, regle, reste));
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Règle une dette fournisseur (acompte ou solde) et inscrit la SORTIE d'argent dans le journal de caisse.
  static Future<void> reglerDette(int idArrivage, double montant, {String mode = 'Espèces'}) async {
    try {
      await BaseLocale.db.transaction((txn) async {
        final l = await txn.rawQuery('SELECT * FROM stocks_arrivages WHERE id = ?', [idArrivage]);
        if (l.isEmpty) return;
        final a = Arrivage.depuisLigne(l.first);
        final reste = (a.prixAchatTotal - a.montantRegle) < 0 ? 0.0 : a.prixAchatTotal - a.montantRegle;
        montant = montant < 0 ? 0.0 : (montant > reste ? reste : montant);
        if (montant <= 0) return;
        final nouveau = a.montantRegle + montant;
        final statut = (a.prixAchatTotal - nouveau) <= 0.01 ? 'Soldé' : 'Actif';
        await txn.rawUpdate('UPDATE stocks_arrivages SET montant_regle = ?, statut = ? WHERE id = ?', [nouveau, statut, idArrivage]);
        final licence = await Licence.lireEmail();
        await FileAttente.enfiler(txn, licence, 'stocks_arrivages', 'upsert', PayloadsCloud.arrivage({
          'uid': a.uid, 'date': a.date, 'produit': a.produit, 'unite': a.unite, 'quantite_saisie': a.quantiteSaisie,
          'poids_sac': a.poidsSac, 'prix_achat_total': a.prixAchatTotal, 'cout_unitaire': a.coutUnitaire,
          'quantite_ajoutee': a.quantiteAjoutee, 'reglement': a.reglement, 'fournisseur': a.fournisseur,
          'alveoles_bonus': a.alveolesBonus, 'montant_regle': nouveau, 'statut': statut,
        }, licence));
        final nom = a.fournisseur.trim().isEmpty ? 'Fournisseur' : a.fournisseur.trim();
        await VentesRepo.ligneTresorerie(txn, '$prefixeRemboursementFournisseur — $nom', -montant, mode: mode);
      });
    } catch (_) {}
  }
}

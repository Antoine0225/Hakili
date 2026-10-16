import '../data/base_locale.dart';
import '../data/bandes_repo.dart';
import '../data/stock_repo.dart';
import '../utilitaires/formats.dart';
import 'compta_ponte.dart' as cp;

const typesElevageBande = ['Poulet de chair', 'RLA / Pintade', 'Poules Pondeuses'];

const protocoleVetoChair = [
  (1, '💉 Vitamines (arrivée)'),
  (7, '💉 Gumboro'),
  (14, '💉 Newcastle + Rappel Gumboro'),
  (28, '💉 Rappel Newcastle'),
];
const protocoleVetoRla = [
  (1, '💉 Vitamines (arrivée)'),
  (7, '💉 Gumboro'),
  (14, '💉 Newcastle'),
  (30, '💉 Rappel Newcastle + Déparasitage'),
  (60, '💉 Rappel Newcastle fort'),
];
const protocoleVetoPondeuseDemarrage = [
  (1, '💉 Vitamines (arrivée)'),
  (7, '💉 Gumboro'),
  (14, '💉 Newcastle + Rappel Gumboro'),
  (28, '💉 Rappel Newcastle'),
];

const seuilBasculeAdulteJours = 18 * 7; // 18 semaines = 126 jours
const periodeVermifugeTrimestrielJours = 90;
const periodeRappelNewcastlePondeuseJours = 60;
const seuilTauxPonteAlerte = 60.0; // % — en dessous : avertissement discret
const nbOeufsParAlveole = 30;
const poidsSacAlimentKg = 100;
const stadePoussins = 'Poussins (Démarrage à J0)';

DateTime _jourDe(DateTime d) => DateTime(d.year, d.month, d.day);

/// Les opérations de l'Élevage : création de bande, planning vétérinaire, arrivages d'aliment, frais de santé…
class ElevageService {
  ElevageService._();

  static String _maintenantTexte() {
    final n = DateTime.now();
    return '${jourEnTexte(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------------ planning vétérinaire
  static Map<String, Object?> _rappel(String bandeUid, DateTime date, String tache, String recurrent) => {
        'uid': nouvelUid(), 'bande_uid': bandeUid, 'date_prevue': jourEnTexte(date), 'tache': tache,
        'recurrent': recurrent, 'statut': 'À faire', 'fait_le': '', 'fait_par': '',
      };

  static Future<void> _insererRappel(dynamic ex, String bandeUid, DateTime date, String tache, {String recurrent = ''}) async {
    final r = _rappel(bandeUid, date, tache, recurrent);
    await ex.rawInsert(
        "INSERT INTO rappels_veterinaires (uid, bande_uid, date_prevue, tache, recurrent, statut) VALUES (?, ?, ?, ?, ?, 'À faire')",
        [r['uid'], bandeUid, r['date_prevue'], tache, recurrent]);
    await BandesRepo.enfilerRappel(ex, r);
  }

  /// Premier lundi du mois, à partir de la date de référence (ce mois-ci s'il n'est pas passé, sinon le suivant).
  static DateTime prochainPremierLundi(DateTime ref) {
    DateTime premier(int annee, int mois) {
      final d = DateTime(annee, mois, 1);
      return d.add(Duration(days: (8 - d.weekday) % 7)); // lundi = 1 en Dart
    }

    final c = premier(ref.year, ref.month);
    if (!_jourDe(c).isBefore(_jourDe(ref))) return c;
    return ref.month == 12 ? premier(ref.year + 1, 1) : premier(ref.year, ref.month + 1);
  }

  static Future<void> genererTachesPeriodiquesPondeuse(dynamic ex, String bandeUid, DateTime depart) async {
    await _insererRappel(ex, bandeUid, depart, '💊 Calcium & Vitamines de ponte (injection immédiate)');
    await _insererRappel(ex, bandeUid, prochainPremierLundi(depart), '💊 Calcium & Vitamines de ponte', recurrent: 'mensuel_premier_lundi');
    await _insererRappel(ex, bandeUid, depart.add(const Duration(days: periodeVermifugeTrimestrielJours)),
        '🪱 Vermifuge trimestriel', recurrent: 'trimestriel');
    await _insererRappel(ex, bandeUid, depart.add(const Duration(days: periodeRappelNewcastlePondeuseJours)),
        '💉 Rappel Newcastle périodique', recurrent: 'newcastle_periodique');
  }

  static Future<void> genererCalendrierVeterinaire(dynamic ex, Map<String, Object?> bande) async {
    final arrivee = lireJma(bande['date_arrivee']);
    if (arrivee == null) return;
    final uid = '${bande['uid']}';
    Future<void> protocole(List<(int, String)> liste) async {
      for (final (jour, tache) in liste) {
        await _insererRappel(ex, uid, arrivee.add(Duration(days: jour)), tache);
      }
    }

    switch (bande['type_elevage']) {
      case 'Poulet de chair':
        await protocole(protocoleVetoChair);
      case 'RLA / Pintade':
        await protocole(protocoleVetoRla);
      case 'Poules Pondeuses':
        if (bande['stade_biologique'] == stadePoussins) {
          await protocole(protocoleVetoPondeuseDemarrage);
          await _insererRappel(ex, uid, arrivee.add(const Duration(days: seuilBasculeAdulteJours)),
              '🔁 Bascule automatique : fin de croissance, passage au Stade Adulte (ponte)');
        } else {
          await genererTachesPeriodiquesPondeuse(ex, uid, DateTime.now());
        }
    }
  }

  /// Les poussins pondeuses deviennent adultes à 18 semaines : la bande bascule et reçoit son planning de ponte.
  static Future<void> verifierBasculeStadePondeuses() async {
    await BandesRepo.purgerOrphelins();
    for (final b in await BandesRepo.toutes()) {
      if (b['type_elevage'] == 'Poules Pondeuses' && b['stade_biologique'] == stadePoussins && (b['bascule_effectuee'] ?? 0) == 0) {
        final arrivee = lireJma(b['date_arrivee']);
        if (arrivee == null) continue;
        if (DateTime.now().difference(arrivee).inDays >= seuilBasculeAdulteJours) {
          b['stade_biologique'] = cp.stadeAdulte;
          b['bascule_effectuee'] = 1;
          await BaseLocale.db.transaction((txn) async {
            await BandesRepo.sauvegarder(b, ex: txn);
            await genererTachesPeriodiquesPondeuse(txn, '${b['uid']}', DateTime.now());
          });
        }
      }
    }
  }

  // ------------------------------------------------------------------ création d'une bande
  /// Crée la bande et son planning vétérinaire. Renvoie null si tout va bien, sinon le message d'erreur à afficher.
  static Future<(String?, String?)> creerBande({
    required String nom, required String batiment, required String effectifTexte, required DateTime dateArrivee,
    required String type, required String stade, required String coutInvestissementTexte,
    required String prixKgTexte, required String prixPoussinsTexte,
  }) async {
    if (nom.trim().isEmpty) return ('⚠️ Le nom de la bande est obligatoire.', null);
    if (batiment.trim().isEmpty) return ('⚠️ Le bâtiment est obligatoire.', null);
    String propre(String t) => t.trim().replaceAll(' ', '').replaceAll(',', '.');
    final eff = double.tryParse(effectifTexte.trim().replaceAll(',', '.'));
    if (eff == null || eff.toInt() <= 0) return ("⚠️ L'effectif initial doit être un nombre entier positif.", null);
    final effectif = eff.toInt();

    final stadeBio = type == 'Poules Pondeuses' ? stade : '';
    final adulte = type == 'Poules Pondeuses' && stadeBio == cp.stadeAdulte;
    var cout = 0.0, prixKg = 0.0, prixPoussins = 0.0;
    if (adulte) {
      final cb = propre(coutInvestissementTexte);
      if (cb.isNotEmpty) {
        final v = double.tryParse(cb);
        if (v == null) return ("⚠️ Coût d'investissement invalide.", null);
        cout = v;
      }
      if (cout <= 0) return ("⚠️ Indiquez le coût d'investissement de la bande adulte.", null);
      final kb = propre(prixKgTexte);
      if (kb.isNotEmpty) {
        final v = double.tryParse(kb);
        if (v == null) return ("⚠️ Prix du kilo d'aliment invalide.", null);
        prixKg = v;
      }
      if (prixKg <= 0) return ('⚠️ Indiquez le prix du kilo de votre aliment de ponte.', null);
    } else {
      final pb = propre(prixPoussinsTexte);
      if (pb.isNotEmpty) {
        final v = double.tryParse(pb);
        if (v == null) return ("⚠️ Le prix d'achat des poussins doit être un nombre.", null);
        prixPoussins = v;
      }
      if (prixPoussins <= 0) return ("⚠️ Le prix d'achat total des poussins est obligatoire.", null);
    }

    var dateMaturite = '';
    if (maturiteCommercialeJours.containsKey(type)) {
      dateMaturite = jourEnTexte(dateArrivee.add(Duration(days: maturiteCommercialeJours[type]!)));
    }
    final champs = adulte
        ? cp.champsInitiauxBandeLissee(DateTime.now(), prixKg)
        : {
            'date_derniere_imputation': '', 'cout_amortissement_cumule': 0.0, 'frais_annexes_en_attente': 0.0,
            'prix_kg_aliment': 0.0, 'conso_aliment_kg_cumulee': 0.0, 'date_reforme': '',
          };
    final pondeuse = type == 'Poules Pondeuses';
    final bande = <String, Object?>{
      'uid': nouvelUid(), 'nom': nom.trim(), 'batiment': batiment.trim(), 'type_elevage': type,
      'stade_biologique': stadeBio, 'bascule_effectuee': 0, 'date_creation': _maintenantTexte(),
      'date_arrivee': jourEnTexte(dateArrivee), 'effectif_initial': effectif, 'effectif_actuel': effectif,
      'morts_cumulees': 0, 'oeufs_cumules': 0, 'alveoles_cumulees': 0.0,
      'cout_investissement_initial': cout, 'cout_initial_poussins': prixPoussins,
      'cout_direct_cumule': pondeuse ? 0.0 : prixPoussins,
      'cout_direct_cumule_ponte': pondeuse ? (adulte ? 0.0 : prixPoussins) : 0.0,
      'cout_aliment': 0.0, 'statut': 'En élevage', 'date_maturite_commerciale': dateMaturite,
      'date_mise_en_vente': '', 'date_epuisement': '', 'cout_unitaire_fige': 0.0, 'produit_stock_nom': '',
      ...champs,
    };
    await BaseLocale.db.transaction((txn) async {
      await BandesRepo.sauvegarder(bande, ex: txn);
      await genererCalendrierVeterinaire(txn, bande);
    });
    return (null, '${bande['uid']}');
  }

  // ------------------------------------------------------------------ journal
  static Future<void> noterJournal(dynamic ex, String bandeUid, String note,
      {int morts = 0, int oeufs = 0, double alveoles = 0, double taux = 0, String? date}) async {
    final evt = <String, Object?>{
      'uid': nouvelUid(), 'bande_uid': bandeUid, 'date': date ?? _maintenantTexte(),
      'morts': morts, 'oeufs': oeufs, 'alveoles': alveoles, 'taux_ponte': taux, 'note': note,
    };
    await ex.rawInsert(
        'INSERT INTO journal_bande_evenements (uid, bande_uid, date, morts, oeufs, alveoles, taux_ponte, note) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [evt['uid'], bandeUid, evt['date'], morts, oeufs, alveoles, taux, note]);
    await BandesRepo.enfilerJournal(ex, evt);
  }

  static String _espaces(String t) => t.replaceAll(',', ' ');

  // ------------------------------------------------------------------ arrivage d'aliment pour une bande
  /// Renvoie le message de confirmation à afficher.
  static Future<String?> enregistrerArrivageAliment(String bandeUid, String typeAliment, double nbSacs, double prixTotal) async {
    final bande = await BandesRepo.parUid(bandeUid);
    if (bande == null) return null;
    final lissee = cp.estBandeLissee(bande);
    var prixKgMisAJour = false;
    if (lissee && typeAliment == 'Ponte' && nbSacs > 0 && prixTotal > 0) {
      bande['prix_kg_aliment'] = prixTotal / (nbSacs * poidsSacAlimentKg);
      prixKgMisAJour = true;
    }
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    if (!lissee) {
      bande['cout_aliment'] = d(bande['cout_aliment']) + prixTotal;
      if (bande['type_elevage'] == 'Poules Pondeuses') {
        bande['cout_direct_cumule_ponte'] = d(bande['cout_direct_cumule_ponte']) + prixTotal;
      } else {
        bande['cout_direct_cumule'] = d(bande['cout_direct_cumule']) + prixTotal;
      }
    }
    final poidsTotal = nbSacs * poidsSacAlimentKg;
    final coutKg = poidsTotal > 0 ? prixTotal / poidsTotal : 0.0;
    var note = _espaces('🌾 Arrivage aliment $typeAliment : ${nombreCourt(nbSacs)} sac(s) × $poidsSacAlimentKg kg '
        '≈ ${milliersAnglais(poidsTotal)} kg — ${milliersAnglais(prixTotal)} FCFA (${milliersAnglais(coutKg)} FCFA/kg)');
    if (lissee) note += " — (hors coût de l'alvéole : calculé sur la consommation réelle)";
    await BaseLocale.db.transaction((txn) async {
      await BandesRepo.sauvegarder(bande, ex: txn);
      await noterJournal(txn, bandeUid, note);
    });
    final montant = milliersAnglais(prixTotal).replaceAll(',', ' ');
    if (lissee) {
      final suite = prixKgMisAJour
          ? "le prix du kilo d'aliment est mis à jour pour les jours à venir."
          : 'choisissez le type « Ponte » pour mettre à jour le prix du kilo.';
      return '🌾 Arrivage tracé pour « ${bande['nom']} » — $suite';
    }
    return '🌾 Arrivage aliment enregistré pour « ${bande['nom']} » — $montant FCFA ajoutés au coût de revient.';
  }

  // ------------------------------------------------------------------ frais de santé
  static Future<String?> enregistrerFraisSante(String bandeUid, String categorie, String description, double montant) async {
    final bande = await BandesRepo.parUid(bandeUid);
    if (bande == null) return null;
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    bande['cout_sante_cumule'] = d(bande['cout_sante_cumule']) + montant;
    if (bande['type_elevage'] == 'Poules Pondeuses') {
      bande['cout_direct_cumule_ponte'] = d(bande['cout_direct_cumule_ponte']) + montant;
      if (cp.estBandeLissee(bande)) bande['frais_annexes_en_attente'] = d(bande['frais_annexes_en_attente']) + montant;
    } else {
      bande['cout_direct_cumule'] = d(bande['cout_direct_cumule']) + montant;
    }
    final detail = description.isNotEmpty ? ' — $description' : '';
    final note = _espaces('🩺 Frais de santé [$categorie]$detail : ${milliersAnglais(montant)} FCFA');
    await BaseLocale.db.transaction((txn) async {
      await BandesRepo.sauvegarder(bande, ex: txn);
      await noterJournal(txn, bandeUid, note);
    });
    return '🩺 Frais de santé enregistré pour « ${bande['nom']} » — ${milliersAnglais(montant).replaceAll(',', ' ')} FCFA ajoutés au coût de revient.';
  }

  // ------------------------------------------------------------------ journal de production (pondeuses)
  static Future<void> _noterJournalPonte(dynamic ex, String bandeUid, DateTime jour, cp.Imputation imp, double alveolesSaisies) async {
    for (final d in imp.detailJours) {
      await ex.rawInsert(
          'INSERT OR IGNORE INTO journal_ponte_jour (bande_uid, jour, vivants, saisi, conso_kg, prix_kg, cout_aliment, amortissement, annexes, alveoles) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
          [bandeUid, jourEnTexte(d.jour), d.vivants, d.saisi ? 1 : 0, d.consoKg, d.prixKg, d.aliment, d.amortissement,
           d.saisi ? imp.annexes : 0.0]);
    }
    await ex.rawUpdate('UPDATE journal_ponte_jour SET alveoles = alveoles + ?, saisi = 1 WHERE bande_uid = ? AND jour = ?',
        [alveolesSaisies, bandeUid, jourEnTexte(jour)]);
  }

  // ------------------------------------------------------------------ rappels vétérinaires
  static Future<List<Map<String, Object?>>> rappelsDeBande(String bandeUid) async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT id, uid, date_prevue, tache, recurrent, statut, fait_le, fait_par FROM rappels_veterinaires '
          'WHERE bande_uid = ? ORDER BY id ASC', [bandeUid]);
      return l.map((r) => Map<String, Object?>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> marquerRappelFait(Map<String, Object?> rappel, String bandeUid, String role) async {
    final maintenant = DateTime.now();
    final faitLe = _maintenantTexte();
    final recurrent = '${rappel['recurrent'] ?? ''}';
    final tache = '${rappel['tache']}';
    await BaseLocale.db.transaction((txn) async {
      await txn.rawUpdate("UPDATE rappels_veterinaires SET statut = 'Fait', fait_le = ?, fait_par = ? WHERE id = ?",
          [faitLe, role, rappel['id']]);
      await BandesRepo.enfilerRappel(txn, {
        'uid': rappel['uid'], 'bande_uid': bandeUid, 'date_prevue': rappel['date_prevue'], 'tache': tache,
        'recurrent': recurrent, 'statut': 'Fait', 'fait_le': faitLe, 'fait_par': role,
      });
      if (recurrent == 'mensuel_premier_lundi') {
        await _insererRappel(txn, bandeUid, prochainPremierLundi(maintenant.add(const Duration(days: 1))), tache, recurrent: recurrent);
      } else if (recurrent == 'trimestriel') {
        await _insererRappel(txn, bandeUid, maintenant.add(const Duration(days: periodeVermifugeTrimestrielJours)), tache, recurrent: recurrent);
      } else if (recurrent == 'newcastle_periodique') {
        await _insererRappel(txn, bandeUid, maintenant.add(const Duration(days: periodeRappelNewcastlePondeuseJours)), tache, recurrent: recurrent);
      }
    });
  }

  // ------------------------------------------------------------------ saisie à l'incident
  /// Renvoie (message d'erreur, messages d'information). Si le premier n'est pas null, rien n'a été enregistré.
  static Future<(String?, List<(String, bool)>)> enregistrerEvenementQuotidien(
      String bandeUid, String mortsTexte, String oeufsTexte) async {
    final bande = await BandesRepo.parUid(bandeUid);
    if (bande == null) return (null, <(String, bool)>[]);
    if (cp.estReformee(bande)) return ('🏁 Cette bande est réformée : la saisie est clôturée.', <(String, bool)>[]);
    final lissee = cp.estBandeLissee(bande);
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    int i(Object? v) => v is num ? v.toInt() : 0;
    if (lissee && d(bande['prix_kg_aliment']) <= 0) {
      return ("⚠️ Prix du kilo d'aliment manquant : le Patron doit le renseigner (Rapport Flash) avant la saisie.", <(String, bool)>[]);
    }
    final mortsBrut = mortsTexte.trim().replaceAll(',', '.').isEmpty ? '0' : mortsTexte.trim().replaceAll(',', '.');
    final mortsF = double.tryParse(mortsBrut);
    if (mortsF == null || mortsF < 0) return ('⚠️ Le nombre de morts doit être un entier positif ou nul.', <(String, bool)>[]);
    final nbMorts = mortsF.toInt();
    if (nbMorts > i(bande['effectif_actuel'])) {
      return ('⛔ Impossible : il ne reste que ${i(bande['effectif_actuel'])} sujet(s) vivant(s) dans cette bande.', <(String, bool)>[]);
    }
    final enProduction = bande['type_elevage'] == 'Poules Pondeuses' && bande['stade_biologique'] == cp.stadeAdulte;
    var nbOeufs = 0;
    if (enProduction) {
      if (oeufsTexte.trim().isEmpty) {
        return ("⚠️ Le nombre d'œufs récoltés est obligatoire pour une bande de pondeuses en production.", <(String, bool)>[]);
      }
      final o = double.tryParse(oeufsTexte.trim().replaceAll(',', '.'));
      if (o == null || o < 0) return ("⚠️ Le nombre d'œufs doit être un entier positif ou nul.", <(String, bool)>[]);
      nbOeufs = o.toInt();
    }
    final effectifVeille = i(bande['effectif_actuel']);
    bande['morts_cumulees'] = i(bande['morts_cumulees']) + nbMorts;
    bande['effectif_actuel'] = i(bande['effectif_actuel']) - nbMorts;
    var taux = 0.0, alveoles = 0.0;
    if (enProduction && nbOeufs > 0) {
      alveoles = nbOeufs / nbOeufsParAlveole;
      final vivants = i(bande['effectif_actuel']) < 1 ? 1 : i(bande['effectif_actuel']);
      taux = (nbOeufs / vivants) * 100.0;
      bande['oeufs_cumules'] = i(bande['oeufs_cumules']) + nbOeufs;
      bande['alveoles_cumulees'] = d(bande['alveoles_cumulees']) + alveoles;
    }
    var joursSansSaisie = 0;
    await BaseLocale.db.transaction((txn) async {
      if (enProduction && lissee) {
        final auj = DateTime.now();
        final jour = DateTime(auj.year, auj.month, auj.day);
        final imp = cp.imputerCharges(bande, jour, effectifVeille, i(bande['effectif_actuel']), bande['prix_kg_aliment']);
        cp.appliquerImputation(bande, jour, imp);
        await _noterJournalPonte(txn, bandeUid, jour, imp, alveoles);
        joursSansSaisie = imp.joursSansSaisie;
      }
      await BandesRepo.sauvegarder(bande, ex: txn);
      await noterJournal(txn, bandeUid, '', morts: nbMorts, oeufs: nbOeufs, alveoles: alveoles, taux: taux);
      if (enProduction && alveoles > 0) await _transfererAlveoles(txn, bande, alveoles);
    });
    final infos = <(String, bool)>[]; // (message, alerte ?)
    if (joursSansSaisie > 0) infos.add(('⚠️ $joursSansSaisie jour(s) sans récolte saisie avant aujourd\'hui.', true));
    if (enProduction && nbOeufs > 0 && taux < seuilTauxPonteAlerte) {
      infos.add(('⚠️ Taux de ponte bas : ${taux.toStringAsFixed(1)} % (< ${seuilTauxPonteAlerte.toStringAsFixed(0)} %)', true));
    } else {
      infos.add(('💾 Événement du jour enregistré.', false));
    }
    return (null, infos);
  }

  static Future<void> _transfererAlveoles(dynamic txn, Map<String, Object?> bande, double alveoles) async {
    if (alveoles <= 0) return;
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    final nomProduit = "Alvéoles d'œufs — Bande ${bande['nom']}";
    await _ajouterProduitDansTransaction(txn, nomProduit);
    final total = d(bande['alveoles_cumulees']) > 0 ? d(bande['alveoles_cumulees']) : alveoles;
    final coutUnitaire = total > 0 ? d(bande['cout_direct_cumule_ponte']) / total : 0.0;
    await StockRepo.mettreAJour(txn, nomProduit, alveoles, nouveauCout: coutUnitaire);
    bande['produit_stock_nom'] = nomProduit;
    if (bande['statut'] == 'En élevage') {
      bande['statut'] = 'En vente';
      if (('${bande['date_mise_en_vente'] ?? ''}').isEmpty) bande['date_mise_en_vente'] = jourEnTexte(DateTime.now());
    }
    await BandesRepo.sauvegarder(bande, ex: txn);
  }

  static Future<void> _ajouterProduitDansTransaction(dynamic txn, String nom) async {
    final e = await txn.rawQuery('SELECT 1 FROM catalogue_produits WHERE nom = ?', [nom]);
    if ((e as List).isNotEmpty) return;
    await StockRepo.ajouterDansTransaction(txn, nom, 'piece');
  }

  // ------------------------------------------------------------------ mise en vente (chair / pintade) et réforme
  /// Renvoie le nom du produit créé, ou null.
  static Future<String?> mettreEnVente(String bandeUid) async {
    final bande = await BandesRepo.parUid(bandeUid);
    if (bande == null || bande['statut'] != 'En élevage') return null;
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    final eff = (bande['effectif_actuel'] as num?)?.toInt() ?? 0;
    final cout = eff > 0 ? d(bande['cout_direct_cumule']) / eff : 0.0;
    final nom = "${bande['type_elevage'] == 'Poulet de chair' ? 'Poulet' : 'Pintade'} — Bande ${bande['nom']}";
    await BaseLocale.db.transaction((txn) async {
      await _ajouterProduitDansTransaction(txn, nom);
      await StockRepo.mettreAJour(txn, nom, eff.toDouble(), nouveauCout: cout);
      bande['statut'] = 'En vente';
      bande['date_mise_en_vente'] = jourEnTexte(DateTime.now());
      bande['cout_unitaire_fige'] = cout;
      bande['produit_stock_nom'] = nom;
      await BandesRepo.sauvegarder(bande, ex: txn);
    });
    return nom;
  }

  static Future<String?> reformer(String bandeUid) async {
    final bande = await BandesRepo.parUid(bandeUid);
    final auj = DateTime.now();
    final jour = DateTime(auj.year, auj.month, auj.day);
    if (bande == null || !cp.reformePossible(bande, jour)) return null;
    final eff = (bande['effectif_actuel'] as num?)?.toInt() ?? 0;
    if (eff <= 0) return null;
    final imp = cp.imputerCharges(bande, jour, eff, eff, bande['prix_kg_aliment']);
    cp.appliquerImputation(bande, jour, imp);
    final cout = cp.valeurResiduelleCheptel(bande) / eff;
    final nom = 'Poules de réforme — Bande ${bande['nom']}';
    await BaseLocale.db.transaction((txn) async {
      await _noterJournalPonte(txn, bandeUid, jour, imp, 0.0);
      await _ajouterProduitDansTransaction(txn, nom);
      await StockRepo.mettreAJour(txn, nom, eff.toDouble(), nouveauCout: cout);
      bande['date_reforme'] = jourEnTexte(jour);
      await BandesRepo.sauvegarder(bande, ex: txn);
    });
    return nom;
  }

  static Future<void> modifierPrixKg(String bandeUid, double prix) async {
    final b = await BandesRepo.parUid(bandeUid);
    if (b == null) return;
    b['prix_kg_aliment'] = prix;
    await BandesRepo.sauvegarder(b);
  }

  /// Une bande « En vente » dont le produit n'a plus de stock passe à « Épuisée ».
  static Future<void> verifierEpuisementStocksBandes() async {
    for (final b in await BandesRepo.toutes()) {
      if (b['statut'] == 'En vente' && ('${b['produit_stock_nom'] ?? ''}').isNotEmpty && ('${b['date_epuisement'] ?? ''}').isEmpty) {
        final (qte, _) = await StockRepo.stockProduit('${b['produit_stock_nom']}');
        if (qte <= 0.0001) {
          b['statut'] = 'Épuisée';
          b['date_epuisement'] = jourEnTexte(DateTime.now());
          await BandesRepo.sauvegarder(b);
        }
      }
    }
  }

  /// Lignes du journal de production, plus récentes d'abord.
  static Future<List<Map<String, Object?>>> journalProduction(String bandeUid) async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT jour, vivants, saisi, conso_kg, cout_aliment, amortissement, annexes, alveoles FROM journal_ponte_jour '
          "WHERE bande_uid = ? ORDER BY substr(jour, 7, 4) || substr(jour, 4, 2) || substr(jour, 1, 2) DESC LIMIT 400",
          [bandeUid]);
      return l.map((r) => Map<String, Object?>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }
}

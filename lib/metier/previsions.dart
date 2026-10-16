import 'dart:convert';
import 'dart:math' as math;

import '../data/parametres.dart';
import '../data/ventes_repo.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

const dureesChair = {
  '45': (kg: (0.4, 1.4, 2.0), libelle: '30-45 jours', chip: 'Cycle 30-45 jours'),
  '90': (kg: (1.0, 2.0, 2.6), libelle: '3 mois', chip: 'Cycle 90 jours'),
};

class LigneFormule {
  final String nom;
  final double kg, cout;
  const LigneFormule(this.nom, this.kg, this.cout);
}

class DonneesFormule {
  final String titre, sous, eyebrow;
  final double intensite, totalKg, totalCout, coutKg;
  final List<LigneFormule> lignes;
  final bool perso; // true : formule saisie par l'utilisateur
  const DonneesFormule(this.titre, this.sous, this.eyebrow, this.intensite, this.lignes, this.totalKg, this.totalCout, this.coutKg,
      {this.perso = false});
}

/// Un ingrédient de la formule d'aliment écrite par l'utilisateur : nom, part (en % du mélange) et prix au kilo.
class IngredientPerso {
  final String nom;
  final double pct, prix;
  const IngredientPerso(this.nom, this.pct, this.prix);

  Map<String, Object> versJson() => {'n': nom, 'p': pct, 'c': prix};
}

/// Un bloc du rapport comptable.
class SectionRapport {
  final String type; // 'table' | 'lignes' | 'seuil'
  final String titre, sous;
  final List<String> colonnes;
  final List<List<Object>> lignes; // table : [nom, c2, c3, couleurCode]; lignes : [libellé, valeur, fort(bool)]
  final List<String>? total;
  final (String, double)? bilan;
  final int? nombre;
  final String texte, detail;
  const SectionRapport({
    required this.type, this.titre = '', this.sous = '', this.colonnes = const [], this.lignes = const [],
    this.total, this.bilan, this.nombre, this.texte = '', this.detail = '',
  });
}

class RapportComptable {
  final String titre;
  final List<String> chips;
  final List<SectionRapport> sections;
  const RapportComptable(this.titre, this.chips, this.sections);
}

class ResultatProjet {
  final RapportComptable rapport;
  final double cout, recette, benefice, coutKg, objectifKg, encaisse, objectifEncaisse;
  final int sujetsActifs, sujetsLances, pertes;
  final bool chair;
  const ResultatProjet(this.rapport, this.cout, this.recette, this.benefice, this.coutKg, this.objectifKg,
      this.sujetsActifs, this.sujetsLances, this.pertes, this.encaisse, this.objectifEncaisse, this.chair);
}

/// Les réglages de la page Prévisions (prix des intrants, bande, intensités). Ils survivent à la navigation entre pages.
class Previsions {
  Previsions._();

  static double mais = 150, soja = 500, son = 280, poisson = 500, coquille = 200, premix = 1400, sel = 200;
  static int nbSujets = 100, nbPertes = 0;
  static double fraisSante = 150, prixPoussin = 600;
  static double prixVenteChair = 3500, prixOeufFec = 250, prixPoussinUnJour = 650, tauxPonte = 70, tauxEclosion = 80;
  static double boost = 0, boostRepro = 0;
  static String dureeChair = '90';
  static String typeVenteRepro = 'oeuf';
  static String derniereEtape = 'demarrage';
  static bool _charge = false;

  static bool get chair => Session.typeElevage == 'chair';

  static Future<void> charger() async {
    if (_charge) return;
    double n(String v, double d) => double.tryParse(v) ?? d;
    Future<String> l(String k) => Parametres.lire(k);
    mais = n(await l('mais'), 150.0);
    soja = n(await l('soja'), 500.0);
    son = n(await l('son'), 280.0);
    poisson = n(await l('poisson'), 500.0);
    coquille = n(await l('coquille'), 200.0);
    premix = n(await l('premix'), 1400.0);
    sel = n(await l('sel'), 200.0);
    await _chargerPerso();
    nbSujets = n(await l('nb_sujets'), 100).toInt();
    nbPertes = n(await l('nb_pertes'), 0).toInt();
    fraisSante = n(await l('frais_sante'), 150.0);
    prixPoussin = n(await l('prix_poussin'), 600.0);
    _charge = true;
  }

  // ------------------------------------------------------------------ formules personnalisées
  // Une seule formule par étape (démarrage, croissance, finition, reproducteur). Elle est gardée dans les réglages
  // sous la clé « formule_perso_<étape> » ; absente ou vide = on utilise la formule d'origine.
  static final Map<String, List<IngredientPerso>> _perso = {};

  static Future<void> _chargerPerso() async {
    _perso.clear();
    for (final etape in const ['demarrage', 'croissance', 'finition', 'reproducteur']) {
      try {
        final texte = await Parametres.lire('formule_perso_$etape');
        if (texte.trim().isEmpty) continue;
        final liste = <IngredientPerso>[];
        for (final e in jsonDecode(texte) as List) {
          final m = e as Map;
          final nom = '${m['n'] ?? ''}'.trim();
          final pct = double.tryParse('${m['p']}') ?? 0.0;
          final prix = double.tryParse('${m['c']}') ?? 0.0;
          if (nom.isNotEmpty && pct > 0) liste.add(IngredientPerso(nom, pct, prix));
        }
        if (liste.isNotEmpty) _perso[etape] = liste;
      } catch (_) {
        // formule illisible : on retombe sur la formule d'origine, rien n'est perdu
      }
    }
  }

  static List<IngredientPerso>? persoDe(String etape) {
    final l = _perso[etape];
    return (l == null || l.isEmpty) ? null : l;
  }

  static bool aPerso(String etape) => persoDe(etape) != null;

  static Future<void> enregistrerPerso(String etape, List<IngredientPerso> lignes) async {
    _perso[etape] = List<IngredientPerso>.from(lignes);
    await Parametres.ecrire('formule_perso_$etape', jsonEncode([for (final l in lignes) l.versJson()]));
  }

  static Future<void> retirerPerso(String etape) async {
    _perso.remove(etape);
    await Parametres.ecrire('formule_perso_$etape', '');
  }

  /// Coût au kilo de la formule d'une étape SANS l'intensité (le curseur) : sert d'objectif de comparaison.
  static double _coutKgSansIntensite(String etape) {
    final b = boost, br = boostRepro;
    boost = 0;
    boostRepro = 0;
    try {
      return formule(etape).coutKg;
    } finally {
      boost = b;
      boostRepro = br;
    }
  }

  static Future<void> sauvegarder() async {
    final v = {
      'mais': mais, 'soja': soja, 'son': son, 'poisson': poisson, 'coquille': coquille, 'premix': premix, 'sel': sel,
      'nb_sujets': nbSujets, 'nb_pertes': nbPertes, 'frais_sante': fraisSante, 'prix_poussin': prixPoussin,
      'stock_aliment_sacs': Session.sacsAlimentEnStock,
    };
    for (final e in v.entries) {
      await Parametres.ecrire(e.key, '${e.value}');
    }
  }

  static ({double kg0, double kg1, double kg2}) get _kg => (kg0: dureesChair[dureeChair]!.kg.$1, kg1: dureesChair[dureeChair]!.kg.$2, kg2: dureesChair[dureeChair]!.kg.$3);
  static String get libelleDuree => dureesChair[dureeChair]!.libelle;
  static String get chipDuree => dureesChair[dureeChair]!.chip;

  // ------------------------------------------------------------------ recettes d'aliment
  static DonneesFormule formule(String etape) {
    final List<(String, double, double)> lignes;
    final String titre, sous, eyebrow;
    final double intensite;
    if (chair) {
      intensite = boost;
      final b = intensite / 100.0;
      sous = 'Poulet de chair';
      eyebrow = 'RECETTE CHAIR';
      if (etape == 'croissance') {
        titre = 'Aliment croissance';
        lignes = [('Maïs grain concassé moyen', 55.0 - 5.0 * b, mais), ('Tourteau de soja torréfié', 22.0 + 5.0 * b, soja),
          ('Son de blé volumateur', 10.0, son), ('Farine de poisson premium', 6.0, poisson),
          ('Prémix chair concentré', 4.0, premix), ('Coquilles broyées (calcium)', 2.5, coquille), ('Sel de cuisine affiné', 0.5, sel)];
      } else if (etape == 'finition') {
        titre = 'Aliment finition';
        lignes = [('Maïs grain énergétique', 60.0 - 4.0 * b, mais), ('Tourteau de soja torréfié', 16.0 + 4.0 * b, soja),
          ('Son de blé volumateur', 12.0, son), ('Farine de poisson premium', 5.0, poisson),
          ('Prémix chair concentré', 4.0, premix), ('Coquilles broyées (calcium)', 2.5, coquille), ('Sel de cuisine affiné', 0.5, sel)];
      } else {
        titre = 'Aliment démarrage';
        lignes = [('Maïs grain broyé fin', 50.0 - 6.0 * b, mais), ('Tourteau de soja torréfié', 28.0 + 6.0 * b, soja),
          ('Farine de poisson premium', 8.0, poisson), ('Son de blé volumateur', 7.0, son),
          ('Prémix chair concentré', 4.5, premix), ('Coquilles broyées (calcium)', 2.0, coquille), ('Sel de cuisine affiné', 0.5, sel)];
      }
    } else {
      intensite = boostRepro;
      final b = intensite / 100.0;
      titre = 'Aliment reproducteurs';
      sous = 'Ponte & reproduction';
      eyebrow = 'RECETTE EXCLUSIVE';
      lignes = [('Maïs grain énergétique', 58.0 - 6.0 * b, mais), ('Tourteau de soja protéiné', 18.0 + 4.0 * b, soja),
        ('Coquilles broyées (calcium fort)', 3.5 + 2.0 * b, coquille), ('Son de blé volumateur', 12.0, son),
        ('Farine de poisson premium', 5.0, poisson), ('Prémix repro concentré', 3.0, premix), ('Sel de cuisine affiné', 0.5, sel)];
    }
    final cle = chair ? (const ['demarrage', 'croissance', 'finition'].contains(etape) ? etape : 'demarrage') : 'reproducteur';
    final perso = persoDe(cle);
    final detail = perso != null
        ? [for (final i in perso) LigneFormule(i.nom, i.pct, i.pct * i.prix)]
        : [for (final (n, kg, prix) in lignes) LigneFormule(n, kg, kg * prix)];
    final totalCout = detail.fold<double>(0, (s, l) => s + l.cout);
    return DonneesFormule(titre, sous, eyebrow, perso != null ? 0.0 : intensite, detail,
        detail.fold<double>(0, (s, l) => s + l.kg), totalCout, totalCout / 100.0, perso: perso != null);
  }

  // ------------------------------------------------------------------ évaluation du projet
  static Future<ResultatProjet> calculer() async {
    final sujetsActifs = (nbSujets - nbPertes) < 0 ? 0 : nbSujets - nbPertes;
    final totalPoussins = nbSujets * prixPoussin;
    final totalSante = sujetsActifs * fraisSante;
    final ventes = await VentesRepo.toutes();
    final auj = aujourdhui();

    if (chair) {
      // le coût au kilo de chaque étape vient de la formule affichée (d'origine ou personnalisée) : un seul calcul pour tout
      final pxDem = formule('demarrage').coutKg;
      final pxCrois = formule('croissance').coutKg;
      final pxFin = formule('finition').coutKg;
      final kg = _kg;
      final totalDem = kg.kg0 * sujetsActifs, totalCrois = kg.kg1 * sujetsActifs, totalFin = kg.kg2 * sujetsActifs;
      final totalAliment = totalDem * pxDem + totalCrois * pxCrois + totalFin * pxFin;
      final coutTotal = totalPoussins + totalSante + totalAliment;
      final recette = sujetsActifs * prixVenteChair;
      final benefice = recette - coutTotal;
      final kgTotal = totalDem + totalCrois + totalFin;
      final pointMort = prixVenteChair > 0 ? math.max(1, (coutTotal / prixVenteChair).round()) : 1;
      String sacs(double x) => '~ ${(x / 50).round() < 1 ? 1 : (x / 50).round()} sacs';
      final rapport = RapportComptable('Bande chair · $libelleDuree', [
        '$sujetsActifs sujets actifs', 'Intensité ${boost.toStringAsFixed(0)} %', chipDuree
      ], [
        SectionRapport(
          type: 'table', titre: 'Planification logistique des stocks', sous: 'Sacs de 50 kg',
          colonnes: const ['PHASE', 'QUANTITÉ', 'SACS'],
          lignes: [
            ['Démarrage', '${totalDem.toStringAsFixed(0)} kg', sacs(totalDem), 'orange'],
            ['Croissance', '${totalCrois.toStringAsFixed(0)} kg', sacs(totalCrois), 'vert'],
            ['Finition', '${totalFin.toStringAsFixed(0)} kg', sacs(totalFin), 'bleu'],
          ],
          total: ['Total aliment de la bande', '${kgTotal.toStringAsFixed(0)} kg', '~ ${(kgTotal / 50).round()} sacs'],
        ),
        SectionRapport(
          type: 'lignes', titre: 'Audit des dépenses et rentabilité', sous: 'Prévisions sur $libelleDuree',
          lignes: [
            ['Facture alimentation globale', fmtF(totalAliment, unite: 'FCFA'), false],
            ['Facture acquisition & santé', fmtF(totalPoussins + totalSante, unite: 'FCFA'), false],
            ['Capital total investi', fmtF(coutTotal, unite: 'FCFA'), true],
            ["Chiffre d'affaires projeté", fmtF(recette, unite: 'FCFA'), true],
          ],
          bilan: ('Bénéfice net prévisionnel final', benefice),
        ),
        SectionRapport(
          type: 'seuil', nombre: pointMort, texte: 'poulets à vendre au minimum pour couvrir vos frais.',
          detail: 'Chaque sujet vendu à partir du ${pointMort + 1}e sera du bénéfice net pur.',
        ),
      ]);
      final objectifKg = kgTotal > 0
          ? (totalDem * _coutKgSansIntensite('demarrage') +
                  totalCrois * _coutKgSansIntensite('croissance') +
                  totalFin * _coutKgSansIntensite('finition')) / kgTotal
          : 0.0;
      final dRec = DateTime(Session.dateReceptionPoussins.year, Session.dateReceptionPoussins.month, Session.dateReceptionPoussins.day);
      final encaisse = VentesRepo.totauxPeriode(ventes, dRec, auj).ca;
      return ResultatProjet(rapport, coutTotal, recette, benefice, kgTotal > 0 ? totalAliment / kgTotal : 0.0, objectifKg,
          sujetsActifs, nbSujets, nbPertes, encaisse, recette, true);
    }

    final pxRepro = formule('reproducteur').coutKg;
    final consoMensuelle = sujetsActifs * 3.75;
    final coutAlimentMensuel = consoMensuelle * pxRepro;
    final oeufsParMois = sujetsActifs * (tauxPonte / 100) * 30;
    final String produit;
    final double prixU, recetteMensuelle;
    if (typeVenteRepro == 'oeuf') {
      produit = 'Œufs Fécondés';
      prixU = prixOeufFec;
      recetteMensuelle = oeufsParMois * prixU;
    } else {
      produit = 'Poussins 1 Jour';
      prixU = prixPoussinUnJour;
      recetteMensuelle = oeufsParMois * (tauxEclosion / 100) * prixU;
    }
    final beneficeMensuel = recetteMensuelle - coutAlimentMensuel;
    final rapport = RapportComptable('Filière reproducteurs · par mois', ['$sujetsActifs reproducteurs actifs', 'Intensité ${boostRepro.toStringAsFixed(0)} %'], [
      SectionRapport(
        type: 'lignes', titre: 'Flux et stocks mensuels', sous: 'Planification',
        lignes: [
          ['Coût dynamique de la ration', '${pxRepro.toStringAsFixed(1)} FCFA / kg', false],
          ['Consommation globale mensuelle', "${milliersAnglais(consoMensuelle).replaceAll(',', ' ')} kg d'aliment", false],
          ['Stock requis', '~ ${(consoMensuelle / 50).round() < 1 ? 1 : (consoMensuelle / 50).round()} sacs de 50 kg / mois', true],
        ],
      ),
      SectionRapport(
        type: 'lignes', titre: 'Rentabilité prévisionnelle', sous: 'Par mois',
        lignes: [
          ['Production estimée', '${milliersAnglais(oeufsParMois).replaceAll(',', ' ')} unités pondues / mois', false],
          ['Débouché commercial', '$produit (${milliersAnglais(prixU).replaceAll(',', ' ')} F / u)', false],
          ['Facture alimentation mensuelle', fmtF(coutAlimentMensuel, unite: 'FCFA'), false],
          ['Revenu brut mensuel projeté', fmtF(recetteMensuelle, unite: 'FCFA'), true],
        ],
        bilan: ('Bénéfice net mensuel', beneficeMensuel),
      ),
    ]);
    final objectifKg = _coutKgSansIntensite('reproducteur');
    final encaisse = VentesRepo.totauxPeriode(ventes, auj.subtract(const Duration(days: 29)), auj).ca;
    return ResultatProjet(rapport, coutAlimentMensuel, recetteMensuelle, beneficeMensuel, pxRepro, objectifKg,
        sujetsActifs, nbSujets, nbPertes, encaisse, recetteMensuelle, false);
  }
}

import 'dart:math' as math;
import '../utilitaires/formats.dart';
import 'conso_aliment.dart';
import 'financement.dart';
import 'formules_aliment.dart';

/// 🥚 Prévision « pondeuses d'œufs de table » : du poussin d'un jour jusqu'à la fin de la ponte.
/// Pure simulation : rien n'est lu dans les bandes, le stock ou les ventes. L'éleveur donne ses chiffres,
/// le logiciel calcule semaine par semaine (puis regroupe par mois).

const semainesDebutPonte = 19; // la ponte commence à 19 semaines d'âge
const _semainesParMois = 4.345;

/// Une race avec ses valeurs de départ. Tout est modifiable à l'écran : ce sont des ordres de grandeur
/// courants, à confirmer avec la fiche technique de votre fournisseur de poussins.
class RacePondeuse {
  final String nom;
  final double pic; // taux de ponte maximal (%)
  final double declin; // baisse du taux de ponte, en points par semaine, après le pic
  final double g1, g2, g3, gPonte; // aliment en grammes par poule et par jour (démarrage, croissance, développement, ponte)
  final double mortElevage; // % de pertes entre 0 et 19 semaines
  final double mortPonteMois; // % de pertes par mois pendant la ponte
  const RacePondeuse(this.nom, this.pic, this.declin, this.g1, this.g2, this.g3, this.gPonte, this.mortElevage, this.mortPonteMois);
}

const racesPondeuses = <RacePondeuse>[
  RacePondeuse('ISA Brown', 94, 0.35, 27, 55, 72, 115, 4, 0.8),
  RacePondeuse('Lohmann Brown', 94, 0.35, 27, 55, 72, 115, 4, 0.8),
  RacePondeuse('Hy-Line Brown', 94, 0.35, 26, 54, 70, 112, 4, 0.8),
  RacePondeuse('Bovans Brown', 93, 0.35, 27, 55, 72, 114, 4, 0.8),
  RacePondeuse('Pondeuse locale ou croisée', 70, 0.5, 22, 45, 60, 100, 8, 1.2),
];

/// Tous les chiffres que l'éleveur peut régler.
class ParamsPondeuses {
  double poussins = 1000, prixPoussin = 800;
  double prixSac1 = 20000, prixSac2 = 18000, prixSac3 = 17000, prixSacPonte = 16500; // FCFA le sac de 50 kg
  double pic = 94, declin = 0.35;
  double g1 = 27, g2 = 55, g3 = 72, gPonte = 115;
  double mortElevage = 4, mortPonteMois = 0.8, casse = 3;
  double prixPlateau = 2200, prixReforme = 3000;
  double dureePonteSem = 53;
  // coûts de l'élevage (par poussin)
  double vaccinPoussin = 450, chauffage = 150, litiere = 100, transport = 50;
  // coûts de la ponte
  double vaccinPouleMois = 40, eclairagePouleMois = 30, emballagePlateau = 40;
  double mainOeuvreMois = 0, imprevus = 3;
  // à cocher : matériel et bâtiment (amortis sur leur durée de vie)
  bool avecMateriel = false, avecBatiment = false;
  double materielPoule = 3000, dureeMaterielMois = 60, batimentPoule = 4000, dureeBatimentMois = 120;
  // date d'arrivée des poussins (facultative) et baisse de ponte en saison chaude (mars à juin)
  DateTime? arrivee;
  double baisseChaleur = 8;
  // fabrication de son propre aliment : prix des ingrédients au kilo
  bool alimentMaison = false;
  double mais = 150, soja = 500, son = 280, poisson = 500, coquille = 200, premix = 1400, sel = 200, fraisFabrication = 10;

  // ingrédients ajoutés à ceux de l'onglet Prévisions (prix au kilo)
  double huile = 1000, premixPonte = 1300, facteurIng = 1, boost = 0;

  // financement par un crédit (facultatif)
  bool avecCredit = false;
  double creditMontant = 0, creditTaux = 14, creditMois = 12, creditDiffere = 0, creditFrais = 1;

  double _prixIng(String cle) {
    switch (cle) {
      case 'mais':
        return mais;
      case 'soja':
        return soja;
      case 'son':
        return son;
      case 'poisson':
        return poisson;
      case 'coquille':
        return coquille;
      case 'premix':
        return premix;
      case 'sel':
        return sel;
      case 'huile':
        return huile;
      case 'premixPonte':
        return premixPonte;
    }
    return FormulesAliment.prixDe(cle) * facteurIng;
  }

  /// Coût d'un kilo d'aliment fabriqué pour un stade (0 à 3), d'après les formules de la bibliothèque, frais de fabrication compris.
  double coutKgMaison(int stade) {
    final nB = math.max(1, math.min(150, dureePonteSem.round()));
    final parts = switch (stade) {
      0 => [('pond_dem', 1.0)],
      1 => [('pond_cro', 1.0)],
      2 => [('pond_dev', 5.0), ('pond_pre', 2.0)],
      _ => [('pond_p1', math.min(nB, 27).toDouble()), ('pond_p2', math.max(0, nB - 27).toDouble())],
    };
    return FormulesAliment.coutKgMoyen(parts, _prixIng, boost: boost) + fraisFabrication;
  }

  /// Prix du sac de 50 kg utilisé dans le calcul : acheté tout fait, ou fabriqué.
  double prixSacStade(int stade) {
    if (alimentMaison) return coutKgMaison(stade) * 50;
    return [prixSac1, prixSac2, prixSac3, prixSacPonte][stade];
  }
}

class EtapeElevage {
  final String nom;
  final int semaines;
  final double kgParPoule, kgTotal, sacs, cout;
  const EtapeElevage(this.nom, this.semaines, this.kgParPoule, this.kgTotal, this.sacs, this.cout);
}

class FluxMois {
  final int mois;
  final double depenses, recettes, cumul;
  const FluxMois(this.mois, this.depenses, this.recettes, this.cumul);
}

class ResultatPondeuses {
  // phase A : du poussin à 19 semaines
  final List<EtapeElevage> etapes;
  final List<(String, double)> autresCoutsA;
  final double totalA, survivantes, coutParPoule;
  // phase B : la ponte
  final double oeufs, plateaux, kgAlimentB, sacsB;
  final List<(String, double)> coutsB;
  final double totalB, recettePlateaux, recetteReforme, pouleReforme;
  // global
  final double coutTotal, recetteTotale, benefice, coutPlateau, besoinFinancement, beneficeMensuelPonte;
  final int? moisPointMort;
  final int moisTotal;
  final List<FluxMois> mois;
  final List<ConsoPeriode> conso; // aliment mois par mois
  final EffetCredit? credit; // crédit éventuel : le bénéfice et le coût total en tiennent déjà compte
  final double beneficeAvantCredit;

  const ResultatPondeuses({
    required this.etapes, required this.autresCoutsA, required this.totalA, required this.survivantes, required this.coutParPoule,
    required this.oeufs, required this.plateaux, required this.kgAlimentB, required this.sacsB, required this.coutsB,
    required this.totalB, required this.recettePlateaux, required this.recetteReforme, required this.pouleReforme,
    required this.coutTotal, required this.recetteTotale, required this.benefice, required this.coutPlateau,
    required this.besoinFinancement, required this.beneficeMensuelPonte, required this.moisPointMort,
    required this.moisTotal, required this.mois, required this.conso, this.credit, this.beneficeAvantCredit = 0,
  });
}

class PrevisionPondeuses {
  PrevisionPondeuses._();

  /// Taux de ponte (%) à un âge donné en semaines : montée jusqu'au pic, plateau, puis baisse lente.
  static double tauxPonte(double age, double pic, double declin) {
    if (age < semainesDebutPonte) return 0;
    if (age < 28) return 5 + (pic - 5) * (age - semainesDebutPonte) / (28 - semainesDebutPonte);
    if (age <= 34) return pic;
    return math.max(40.0, pic - declin * (age - 34));
  }

  /// Saison chaude (mars à juin) : la ponte baisse un peu. Sans date d'arrivée, rien ne change.
  static double facteurChaleur(ParamsPondeuses p, double semaineDepuisArrivee) {
    final a = p.arrivee;
    if (a == null || p.baisseChaleur <= 0) return 1.0;
    final d = a.add(Duration(days: (semaineDepuisArrivee * 7).round()));
    return (d.month >= 3 && d.month <= 6) ? 1 - p.baisseChaleur / 100 : 1.0;
  }

  static ResultatPondeuses calculer(ParamsPondeuses p0) {
    // Le boost (aliment maison seulement) : taux de ponte maximal +2 points à 100 %.
    var p = p0;
    if (p0.alimentMaison && p0.boost > 0) {
      p = p0.copie();
      p.pic = math.min(99.0, p0.pic + 2 * (p0.boost / 100).clamp(0.0, 1.0));
    }
    final n = math.max(0.0, p.poussins);
    final mA = (p.mortElevage / 100).clamp(0.0, 0.95).toDouble();
    final mB = (p.mortPonteMois / 100).clamp(0.0, 0.5).toDouble();
    final nB = math.max(1, math.min(150, p.dureePonteSem.round()));
    final totalSem = semainesDebutPonte + nB;

    // ---------------------------------------------------------------- phase A : l'élevage jusqu'à 19 semaines
    // pertes réparties : la moitié pendant le démarrage, le quart en croissance, le quart en développement
    final debut = [n, n * (1 - mA * 0.5), n * (1 - mA * 0.75)];
    final fin = [n * (1 - mA * 0.5), n * (1 - mA * 0.75), n * (1 - mA)];
    final jours = [6, 6, 7]; // semaines par étape
    final grammes = [p.g1, p.g2, p.g3];
    final prixSac = [p.prixSacStade(0), p.prixSacStade(1), p.prixSacStade(2)];
    const noms = ['Démarrage (0 à 6 semaines)', 'Croissance (7 à 12 semaines)', 'Développement (13 à 19 semaines)'];
    final etapes = <EtapeElevage>[];
    for (var i = 0; i < 3; i++) {
      final kgPoule = jours[i] * 7 * grammes[i] / 1000;
      final kgTotal = kgPoule * (debut[i] + fin[i]) / 2;
      etapes.add(EtapeElevage(noms[i], jours[i], kgPoule, kgTotal, kgTotal / 50, kgTotal * prixSac[i] / 50));
    }
    final survivantes = n * (1 - mA);

    final matMensuel = p.avecMateriel && p.dureeMaterielMois > 0 ? p.materielPoule * n / p.dureeMaterielMois : 0.0;
    final batMensuel = p.avecBatiment && p.dureeBatimentMois > 0 ? p.batimentPoule * n / p.dureeBatimentMois : 0.0;
    final amortSem = (matMensuel + batMensuel) * 12 / 52;
    final mainSem = p.mainOeuvreMois * 12 / 52;
    final imp = p.imprevus / 100;

    final depSem = List<double>.filled(totalSem, 0.0);
    final recSem = List<double>.filled(totalSem, 0.0);

    final kgSem = List<double>.filled(totalSem, 0.0), coutAlimSem = List<double>.filled(totalSem, 0.0), oisSem = List<double>.filled(totalSem, 0.0);
    var aPoussins = 0.0, aAliment = 0.0, aVaccins = 0.0, aChauffage = 0.0, aLitiere = 0.0, aTransport = 0.0;
    var aMain = 0.0, aAmort = 0.0, aImprevus = 0.0;
    for (var w = 1; w <= semainesDebutPonte; w++) {
      final etape = w <= 6 ? 0 : (w <= 12 ? 1 : 2);
      final alim = etapes[etape].cout / jours[etape];
      kgSem[w - 1] = etapes[etape].kgTotal / jours[etape];
      coutAlimSem[w - 1] = alim;
      oisSem[w - 1] = (debut[etape] + fin[etape]) / 2;
      final poussinsSem = w == 1 ? n * p.prixPoussin : 0.0;
      final transportSem = w == 1 ? n * p.transport : 0.0;
      final vaccSem = n * p.vaccinPoussin / semainesDebutPonte;
      final chaufSem = w <= 4 ? n * p.chauffage / 4 : 0.0;
      final litSem = n * p.litiere / semainesDebutPonte;
      final base = poussinsSem + transportSem + alim + vaccSem + chaufSem + litSem + mainSem;
      final imprevuSem = base * imp;
      aPoussins += poussinsSem;
      aTransport += transportSem;
      aAliment += alim;
      aVaccins += vaccSem;
      aChauffage += chaufSem;
      aLitiere += litSem;
      aMain += mainSem;
      aAmort += amortSem;
      aImprevus += imprevuSem;
      depSem[w - 1] = base + imprevuSem + amortSem;
    }
    final autresA = <(String, double)>[
      ('Poussins', aPoussins),
      ('Transport des poussins', aTransport),
      ('Vaccins et médicaments', aVaccins),
      ('Chauffage et éclairage', aChauffage),
      ('Litière, eau, électricité', aLitiere),
      if (p.mainOeuvreMois > 0) ('Main-d\'œuvre', aMain),
      if (amortSem > 0) ('Matériel et bâtiment (part de la période)', aAmort),
      ('Imprévus', aImprevus),
    ];
    final totalA = aAliment + autresA.fold<double>(0, (s, e) => s + e.$2);

    // ---------------------------------------------------------------- phase B : la ponte
    var oeufs = 0.0, plateaux = 0.0, kgB = 0.0;
    var bAliment = 0.0, bVaccins = 0.0, bEclairage = 0.0, bEmballage = 0.0, bMain = 0.0, bAmort = 0.0, bImprevus = 0.0;
    var recettePlateaux = 0.0;
    for (var t = 1; t <= nB; t++) {
      final age = semainesDebutPonte + t - 0.5;
      final vivantes = survivantes * math.pow(1 - mB, (t - 0.5) / _semainesParMois);
      final taux = tauxPonte(age, p.pic, p.declin) * facteurChaleur(p, semainesDebutPonte + t - 0.5);
      final oeufsSem = vivantes * 7 * taux / 100 * (1 - p.casse / 100);
      final plSem = oeufsSem / 30;
      final kg = vivantes * 7 * p.gPonte / 1000;
      final alim = kg * p.prixSacStade(3) / 50;
      kgSem[semainesDebutPonte + t - 1] = kg;
      coutAlimSem[semainesDebutPonte + t - 1] = alim;
      oisSem[semainesDebutPonte + t - 1] = vivantes;
      final vacc = vivantes * p.vaccinPouleMois * 12 / 52;
      final ecl = vivantes * p.eclairagePouleMois * 12 / 52;
      final emb = plSem * p.emballagePlateau;
      final base = alim + vacc + ecl + emb + mainSem;
      final imprevuSem = base * imp;
      oeufs += oeufsSem;
      plateaux += plSem;
      kgB += kg;
      bAliment += alim;
      bVaccins += vacc;
      bEclairage += ecl;
      bEmballage += emb;
      bMain += mainSem;
      bAmort += amortSem;
      bImprevus += imprevuSem;
      final rec = plSem * p.prixPlateau;
      recettePlateaux += rec;
      final idx = semainesDebutPonte + t - 1;
      depSem[idx] = base + imprevuSem + amortSem;
      recSem[idx] = rec;
    }
    final vivantesFin = survivantes * math.pow(1 - mB, nB / _semainesParMois);
    final recetteReforme = vivantesFin * p.prixReforme;
    recSem[totalSem - 1] += recetteReforme;
    // financement : frais, argent emprunté et mensualités entrent dans la trésorerie ; les intérêts courus sont une dépense du projet
    final cred = injecterCredit({
      'avecCredit': p.avecCredit ? 1.0 : 0.0, 'creditMontant': p.creditMontant, 'creditTaux': p.creditTaux,
      'creditMois': p.creditMois, 'creditDiffere': p.creditDiffere, 'creditFrais': p.creditFrais,
    }, depSem, recSem);
    final cFin = cred?.coutProjet ?? 0.0;

    final coutsB = <(String, double)>[
      ('Aliment pondeuse', bAliment),
      ('Vaccins et médicaments', bVaccins),
      ('Éclairage, eau, électricité', bEclairage),
      ('Plateaux (emballage)', bEmballage),
      if (p.mainOeuvreMois > 0) ('Main-d\'œuvre', bMain),
      if (amortSem > 0) ('Matériel et bâtiment (part de la période)', bAmort),
      ('Imprévus', bImprevus),
    ];
    final totalB = coutsB.fold<double>(0, (s, e) => s + e.$2);

    // ---------------------------------------------------------------- résultats globaux
    final coutTotal = totalA + totalB + cFin;
    final recetteTotale = recettePlateaux + recetteReforme;
    final benefice = recetteTotale - coutTotal;
    final coutPlateau = plateaux > 0 ? (coutTotal - recetteReforme) / plateaux : 0.0;

    // trésorerie : cumul semaine par semaine, regroupé par mois
    final nbMois = (totalSem / _semainesParMois).ceil();
    final depMois = List<double>.filled(nbMois, 0.0);
    final recMois = List<double>.filled(nbMois, 0.0);
    var cumul = 0.0, plusBas = 0.0;
    int? semPointMort;
    var etaitNegatif = false;
    for (var i = 0; i < totalSem; i++) {
      final m = math.min(nbMois - 1, (i / _semainesParMois).floor());
      depMois[m] += depSem[i];
      recMois[m] += recSem[i];
      cumul += recSem[i] - depSem[i];
      if (cumul < plusBas) plusBas = cumul;
      if (cumul < 0) etaitNegatif = true;
      if (semPointMort == null && etaitNegatif && cumul >= 0) semPointMort = i + 1;
    }
    final mois = <FluxMois>[];
    var c = 0.0;
    for (var m = 0; m < nbMois; m++) {
      c += recMois[m] - depMois[m];
      mois.add(FluxMois(m + 1, depMois[m], recMois[m], c));
    }
    final moisPonte = nB / _semainesParMois;
    final beneficeMensuelPonte = moisPonte > 0 ? (recettePlateaux - totalB) / moisPonte : 0.0;

    return ResultatPondeuses(
      etapes: etapes, autresCoutsA: autresA, totalA: totalA, survivantes: survivantes,
      coutParPoule: survivantes > 0 ? totalA / survivantes : 0.0,
      oeufs: oeufs, plateaux: plateaux, kgAlimentB: kgB, sacsB: kgB / 50, coutsB: coutsB, totalB: totalB,
      recettePlateaux: recettePlateaux, recetteReforme: recetteReforme, pouleReforme: vivantesFin,
      coutTotal: coutTotal, recetteTotale: recetteTotale, benefice: benefice, coutPlateau: coutPlateau,
      besoinFinancement: -plusBas, beneficeMensuelPonte: beneficeMensuelPonte,
      moisPointMort: semPointMort == null ? null : (semPointMort / _semainesParMois).ceil(),
      moisTotal: nbMois, mois: mois, credit: cred, beneficeAvantCredit: benefice + cFin,
      conso: consoParPeriode(parJour(kgSem), parJour(coutAlimSem), parJour(oisSem), joursParPeriode: 30.4, label: (i) => libelleMoisConso(p.arrivee, i)),
    );
  }
}

// =====================================================================================================
// Scénarios, « et si… », verdict et profil de ponte
// =====================================================================================================

extension ParamsPondeusesOutils on ParamsPondeuses {
  ParamsPondeuses copie() {
    final c = ParamsPondeuses();
    c.poussins = poussins;
    c.prixPoussin = prixPoussin;
    c.prixSac1 = prixSac1;
    c.prixSac2 = prixSac2;
    c.prixSac3 = prixSac3;
    c.prixSacPonte = prixSacPonte;
    c.pic = pic;
    c.declin = declin;
    c.g1 = g1;
    c.g2 = g2;
    c.g3 = g3;
    c.gPonte = gPonte;
    c.mortElevage = mortElevage;
    c.mortPonteMois = mortPonteMois;
    c.casse = casse;
    c.prixPlateau = prixPlateau;
    c.prixReforme = prixReforme;
    c.dureePonteSem = dureePonteSem;
    c.vaccinPoussin = vaccinPoussin;
    c.chauffage = chauffage;
    c.litiere = litiere;
    c.transport = transport;
    c.vaccinPouleMois = vaccinPouleMois;
    c.eclairagePouleMois = eclairagePouleMois;
    c.emballagePlateau = emballagePlateau;
    c.mainOeuvreMois = mainOeuvreMois;
    c.imprevus = imprevus;
    c.avecMateriel = avecMateriel;
    c.avecBatiment = avecBatiment;
    c.materielPoule = materielPoule;
    c.dureeMaterielMois = dureeMaterielMois;
    c.batimentPoule = batimentPoule;
    c.dureeBatimentMois = dureeBatimentMois;
    c.arrivee = arrivee;
    c.baisseChaleur = baisseChaleur;
    c.alimentMaison = alimentMaison;
    c.mais = mais;
    c.soja = soja;
    c.son = son;
    c.poisson = poisson;
    c.coquille = coquille;
    c.premix = premix;
    c.sel = sel;
    c.fraisFabrication = fraisFabrication;
    c.huile = huile;
    c.premixPonte = premixPonte;
    c.facteurIng = facteurIng;
    c.avecCredit = avecCredit;
    c.creditMontant = creditMontant;
    c.creditTaux = creditTaux;
    c.creditMois = creditMois;
    c.creditDiffere = creditDiffere;
    c.creditFrais = creditFrais;
    c.boost = boost;
    return c;
  }

  /// Une copie où l'on change quelques éléments : « et si l'aliment augmentait de 10 % ? ».
  /// [alimentPct] : prix des sacs ; [prixPct] : prix du plateau ; [pertesPct] : pertes ; [picPoints] : taux de ponte maximal.
  ParamsPondeuses varie({double alimentPct = 0, double prixPct = 0, double pertesPct = 0, double picPoints = 0}) {
    final c = copie();
    final fa = 1 + alimentPct / 100;
    c.prixSac1 *= fa;
    c.prixSac2 *= fa;
    c.prixSac3 *= fa;
    c.prixSacPonte *= fa;
    c.mais *= fa;
    c.soja *= fa;
    c.son *= fa;
    c.poisson *= fa;
    c.coquille *= fa;
    c.premix *= fa;
    c.sel *= fa;
    c.huile *= fa;
    c.premixPonte *= fa;
    c.facteurIng *= fa;
    c.prixPlateau *= 1 + prixPct / 100;
    final fp = math.max(0.0, 1 + pertesPct / 100);
    c.mortElevage = math.min(90.0, c.mortElevage * fp);
    c.mortPonteMois = math.min(40.0, c.mortPonteMois * fp);
    c.pic = math.max(30.0, math.min(99.0, c.pic + picPoints));
    return c;
  }
}

const _moisCourts = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _moisLongs = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

String dateLongue(DateTime d) => '${d.day} ${_moisLongs[d.month - 1]} ${d.year}';

/// « Mois 3 » ou, si la date de départ est connue, « Mois 3 · janv. 2027 ». [decalageSemaines] : décalage depuis la date de départ.
String libelleMois(DateTime? debut, int rang, {int decalageSemaines = 0, String prefixe = 'Mois'}) {
  if (debut == null) return '$prefixe $rang';
  final d = debut.add(Duration(days: decalageSemaines * 7 + ((rang - 1) * 30.4).round()));
  return '$prefixe $rang · ${_moisCourts[d.month - 1]} ${d.year}';
}

/// Les limites à ne pas dépasser pour ne pas perdre d'argent (null = pas de limite atteinte dans les valeurs raisonnables).
class SeuilsPondeuses {
  final double prixPlateauMin, plateauxMinTotal, pctProduction, plateauxMinJour;
  final double? picMin, hausseAlimentMax, pertesElevageMax;
  const SeuilsPondeuses(this.prixPlateauMin, this.plateauxMinTotal, this.pctProduction, this.plateauxMinJour,
      this.picMin, this.hausseAlimentMax, this.pertesElevageMax);
}

class ScenarioPondeuses {
  final String nom, description;
  final ResultatPondeuses r;
  const ScenarioPondeuses(this.nom, this.description, this.r);
}

class MoisPonte {
  final int mois;
  final double taux, plateauxJour, poules, plateauxMois;
  const MoisPonte(this.mois, this.taux, this.plateauxJour, this.poules, this.plateauxMois);
}

class VerdictPondeuses {
  final int niveau; // 0 = à éviter, 1 = risqué ou mince, 2 = favorable
  final String titre, resume;
  final List<String> constats, attention;
  const VerdictPondeuses(this.niveau, this.titre, this.resume, this.constats, this.attention);
}

class AnalysePondeuses {
  AnalysePondeuses._();

  /// Trois situations : prudent (ça se passe mal), normal (vos chiffres), optimiste (ça se passe bien).
  static List<ScenarioPondeuses> scenarios(ParamsPondeuses p) {
    final prudent = p.varie(alimentPct: 10, prixPct: -10, pertesPct: 50, picPoints: -3);
    final optimiste = p.varie(alimentPct: -5, prixPct: 5, pertesPct: -30, picPoints: 1);
    return [
      ScenarioPondeuses('Prudent', 'Aliment +10 %, plateau -10 %, pertes +50 %, ponte -3 points', PrevisionPondeuses.calculer(prudent)),
      ScenarioPondeuses('Normal', 'Vos chiffres tels quels', PrevisionPondeuses.calculer(p)),
      ScenarioPondeuses('Optimiste', 'Aliment -5 %, plateau +5 %, pertes -30 %, ponte +1 point', PrevisionPondeuses.calculer(optimiste)),
    ];
  }

  /// Où en est l'élevage pendant ce mois (le mois 1 commence à l'arrivée des poussins).
  static String phaseMois(int m) {
    final debut = (m - 1) * _semainesParMois, fin = m * _semainesParMois;
    if (fin <= semainesDebutPonte) return 'Élevage';
    if (debut >= semainesDebutPonte) return 'Ponte';
    return 'Élevage puis ponte';
  }

  static double? _zero(double Function(double) f, double lo, double hi) {
    // f est supposée monotone ; on cherche l'endroit où elle passe par zéro
    final a = f(lo), b = f(hi);
    if (a == 0) return lo;
    if ((a > 0) == (b > 0)) return null;
    var x0 = lo, x1 = hi;
    for (var i = 0; i < 40; i++) {
      final m = (x0 + x1) / 2;
      if ((f(m) > 0) == (a > 0)) {
        x0 = m;
      } else {
        x1 = m;
      }
    }
    return (x0 + x1) / 2;
  }

  /// Seuils de rentabilité : prix minimum, ventes minimum, ponte minimum, hausse d'aliment et pertes maximum.
  static SeuilsPondeuses seuils(ParamsPondeuses p, ResultatPondeuses r) {
    final nB = math.max(1, math.min(150, p.dureePonteSem.round()));
    final aVendre = r.coutTotal - r.recetteReforme;
    final minTotal = p.prixPlateau > 0 ? math.max(0.0, aVendre / p.prixPlateau) : 0.0;
    final pct = r.plateaux > 0 ? minTotal / r.plateaux * 100 : 0.0;
    double b(ParamsPondeuses q) => PrevisionPondeuses.calculer(q).benefice;

    double? picMin;
    if (b(p.varie(picPoints: 99 - p.pic)) > 0) {
      picMin = b(p.varie(picPoints: 30 - p.pic)) >= 0 ? 30.0 : _zero((x) => b(p.varie(picPoints: x - p.pic)), 30, 99);
    }
    double? hausse;
    if (r.benefice > 0) hausse = _zero((x) => b(p.varie(alimentPct: x)), 0, 500);
    double? pertes;
    if (r.benefice > 0) {
      pertes = _zero((x) {
        final q = p.copie();
        q.mortElevage = x;
        return b(q);
      }, p.mortElevage, 90);
    }
    return SeuilsPondeuses(r.coutPlateau, minTotal, pct, minTotal / (nB * 7), picMin, hausse, pertes);
  }

  /// Production mois par mois pendant la ponte.
  static List<MoisPonte> profilPonte(ParamsPondeuses p, ResultatPondeuses r) {
    final nB = math.max(1, math.min(150, p.dureePonteSem.round()));
    final mB = (p.mortPonteMois / 100).clamp(0.0, 0.5).toDouble();
    final nbMois = (nB / _semainesParMois).ceil();
    final liste = <MoisPonte>[];
    for (var m = 1; m <= nbMois; m++) {
      final age = semainesDebutPonte + (m - 0.5) * _semainesParMois;
      final taux = PrevisionPondeuses.tauxPonte(age, p.pic, p.declin) * PrevisionPondeuses.facteurChaleur(p, age);
      final vivantes = r.survivantes * math.pow(1 - mB, m - 0.5);
      final pj = vivantes * taux / 100 * (1 - p.casse / 100) / 30;
      final sem = math.min(_semainesParMois, nB - (m - 1) * _semainesParMois);
      liste.add(MoisPonte(m, taux, pj, vivantes, pj * 7 * math.max(0.0, sem)));
    }
    return liste;
  }

  /// Le jugement final : peut-on se lancer ou pas ?
  static VerdictPondeuses verdict(ParamsPondeuses p, List<ScenarioPondeuses> sc) {
    final r = sc[1].r;
    final prud = sc[0].r;
    final alimTotal = r.etapes.fold<double>(0, (s, e) => s + e.cout) + (r.coutsB.isEmpty ? 0.0 : r.coutsB.first.$2);
    final marge = r.coutTotal > 0 ? r.benefice / r.coutTotal : 0.0;
    final imp = p.imprevus / 100;

    int niveau;
    String titre, resume;
    if (r.benefice <= 0) {
      niveau = 0;
      titre = 'À ÉVITER AVEC CES CHIFFRES';
      resume = 'Même si tout se passe comme prévu, vous ne gagnez rien sur ce cycle. Il faut soit un meilleur prix de vente, '
          'soit un aliment moins cher, soit moins de dépenses, avant de vous lancer.';
    } else if (prud.benefice < 0) {
      niveau = 1;
      titre = 'POSSIBLE, MAIS RISQUÉ';
      resume = 'Vous gagnez si tout se passe comme prévu, mais une mauvaise période (aliment plus cher, œufs moins bien payés, '
          'plus de pertes) vous ferait perdre de l\'argent. Lancez-vous seulement si vous pouvez supporter cette perte.';
    } else if (marge < 0.10) {
      niveau = 1;
      titre = 'RENTABLE, MAIS MARGE FAIBLE';
      resume = 'Vous gagnez, même dans le scénario prudent, mais la marge est mince (moins de 10 % de ce que vous dépensez). '
          'Un petit problème peut la faire disparaître : essayez de baisser vos coûts ou de mieux vendre.';
    } else {
      niveau = 2;
      titre = 'FAVORABLE';
      resume = 'Vous gagnez avec vos chiffres et vous gagnez encore dans le scénario prudent. Le projet tient bien, '
          'à condition que vos prix et vos consommations soient réalistes.';
    }

    final constats = <String>[];
    final arr = p.arrivee;
    if (arr != null) {
      final debutPonte = arr.add(const Duration(days: semainesDebutPonte * 7));
      final finPonte = debutPonte.add(Duration(days: p.dureePonteSem.round() * 7));
      constats.add('Si les poussins arrivent le ${dateLongue(arr)}, les premiers œufs arrivent vers le ${dateLongue(debutPonte)} '
          'et la ponte se termine vers le ${dateLongue(finPonte)}.');
      var chaud = 0;
      for (var w = 0; w < p.dureePonteSem.round(); w++) {
        if (PrevisionPondeuses.facteurChaleur(p, semainesDebutPonte + w + 0.5) < 1) chaud++;
      }
      if (chaud > 0 && p.baisseChaleur > 0) {
        constats.add('Environ $chaud semaines de ponte tombent en saison chaude (mars à juin) : la ponte y baisse de ${p.baisseChaleur.round()} %, '
            'c\'est déjà compté dans les chiffres.');
      }
    }
    if (p.alimentMaison) {
      final achete = [p.prixSac1, p.prixSac2, p.prixSac3, p.prixSacPonte];
      final eco = [for (var i = 0; i < 4; i++) achete[i] - p.coutKgMaison(i) * 50];
      constats.add('En fabriquant votre aliment, le sac de ponte vous revient à ${fmtF(p.coutKgMaison(3) * 50)} '
          '(contre ${fmtF(p.prixSacPonte)} acheté tout fait : ${eco[3] >= 0 ? 'vous économisez' : 'vous perdez'} ${fmtF(eco[3].abs())} par sac).');
    }
    constats.add('Pendant les ${(semainesDebutPonte / 4.345).toStringAsFixed(1).replaceAll('.', ',')} premiers mois (jusqu\'à 19 semaines), '
        'vous dépensez ${fmtF(r.totalA)} sans encaisser le moindre franc.');
    constats.add('Il faut avoir au moins ${fmtF(r.besoinFinancement)} de côté (ou emprunté) pour tenir jusqu\'à ce que la ponte rembourse vos dépenses.');
    if (r.credit != null) constats.addAll(constatsCredit(r.credit!, r.beneficeAvantCredit, r.benefice, r.besoinFinancement));
    if (r.moisPointMort != null) {
      constats.add('Vous récupérez tout l\'argent avancé au mois ${r.moisPointMort} (sur ${r.moisTotal} mois en tout).');
    } else {
      constats.add('Dans ce cycle, vous ne récupérez pas tout l\'argent avancé.');
    }
    final margePlateau = p.prixPlateau - r.coutPlateau;
    constats.add('Un plateau de 30 œufs vous coûte ${fmtF(r.coutPlateau)} et se vend ${fmtF(p.prixPlateau)} : '
        '${margePlateau >= 0 ? 'vous gagnez' : 'vous perdez'} ${fmtF(margePlateau.abs())} par plateau.');
    if (r.coutTotal > 0) {
      constats.add('L\'aliment représente ${(alimTotal / r.coutTotal * 100).round()} % de vos dépenses : c\'est lui qui décide de votre réussite.');
    }
    if (r.benefice > 0 && p.prixPlateau > 0 && r.coutPlateau > 0) {
      final baisse = (1 - r.coutPlateau / p.prixPlateau) * 100;
      constats.add('Votre prix de vente peut baisser d\'environ ${baisse.round()} % avant que vous ne gagniez plus rien.');
    }
    if (r.benefice > 0 && alimTotal > 0) {
      final hausse = r.benefice / (alimTotal * (1 + imp)) * 100;
      constats.add('L\'aliment peut augmenter d\'environ ${hausse.round()} % avant que vous ne gagniez plus rien.');
    }
    if (r.besoinFinancement > 0) {
      constats.add('Pour 100 F avancés au plus bas de votre trésorerie, ${r.benefice >= 0 ? 'vous gagnez' : 'vous perdez'} '
          '${fmtF((r.benefice / r.besoinFinancement * 100).abs())} sur le cycle.');
    }
    final profil = AnalysePondeuses.profilPonte(p, r);
    if (profil.isNotEmpty) {
      final pic = profil.map((e) => e.plateauxJour).fold<double>(0, math.max);
      constats.add('Au plus fort de la ponte, il faut vendre environ ${pic.round()} plateaux par jour. '
          'Assurez-vous d\'avoir ces clients avant d\'acheter les poussins.');
    }

    final attention = <String>[
      'La chaleur fait baisser la ponte et augmente les pertes : prévoyez de l\'ombre, de l\'eau fraîche et une bonne aération.',
      'Le prix des œufs change selon la saison et les fêtes : testez d\'autres prix de vente avec « Et si… ».',
      'Achetez des poussins vaccinés (Marek) chez un fournisseur sérieux, et respectez le calendrier de vaccination : c\'est ce qui limite les pertes.',
      'Les chiffres de ce logiciel sont des exemples : mettez vos vrais prix d\'aliment et de poussins pour avoir une prévision fiable.',
      if (!p.avecMateriel && !p.avecBatiment)
        'Le matériel (cages, mangeoires, abreuvoirs) et le bâtiment ne sont pas comptés : cochez-les si vous devez les acheter ou les construire.',
      'En fin de cycle, pensez déjà à la relève : une nouvelle bande doit arriver à temps pour que vos clients ne manquent pas d\'œufs.',
    ];
    return VerdictPondeuses(niveau, titre, resume, constats, attention);
  }
}

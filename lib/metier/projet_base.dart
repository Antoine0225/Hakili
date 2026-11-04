import 'dart:math' as math;

import '../utilitaires/formats.dart';
import 'conso_aliment.dart';
import 'formules_aliment.dart';
import 'previsions_pondeuses.dart' show dateLongue;

/// Socle commun des simulateurs de projet (poulet de chair, reproducteurs) :
/// chaque modèle décrit ses champs et son calcul ; l'écran, les scénarios, le verdict, les seuils et le PDF sont partagés.
typedef Valeurs = Map<String, double>;

const semainesParMois = 4.345;

/// Date d'arrivée enregistrée sous forme de nombre de jours (0 = pas de date).
DateTime? arriveeDe(Valeurs v) {
  final j = v['arrivee'] ?? 0;
  if (j <= 0) return null;
  return DateTime(1970, 1, 1 + j.round());
}

double jourDe(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays.toDouble();

DateTime? depuisJour(double j) => j <= 0 ? null : DateTime(1970, 1, 1 + j.round());

class ChampDef {
  final String cle, label, unite, aide;
  final double defaut;
  final bool simple; // affiché aussi en mode Simple
  final bool Function(Valeurs)? visible;
  ChampDef(this.cle, this.label, this.unite, this.aide, this.defaut, {this.simple = false, this.visible});
}

/// Un bloc de champs. [vraisPrix] : affiche le bouton « Utiliser mes vrais prix ». [note] : texte calculé affiché sous les champs.
class GroupeDef {
  final String titre;
  final List<ChampDef> champs;
  final bool Function(Valeurs)? visible;
  final bool detailSeulement;
  final bool vraisPrix;
  final String Function(Valeurs)? note;
  GroupeDef(this.titre, this.champs, {this.visible, this.detailSeulement = false, this.vraisPrix = false, this.note});
}

class CaseDef {
  final String cle, label, aide;
  final bool defaut, simple;
  final bool Function(Valeurs)? visible;
  CaseDef(this.cle, this.label, this.aide, {this.defaut = false, this.simple = true, this.visible});
}

class RaceDef {
  final String nom;
  final Valeurs valeurs;
  const RaceDef(this.nom, this.valeurs);
}

class CarteRes {
  final String cle, titre, valeur, aide;
  final String? detail;
  final int ton; // 0 neutre, 1 bon, 2 mauvais
  const CarteRes(this.cle, this.titre, this.valeur, this.aide, {this.detail, this.ton = 0});
}

class TableauRes {
  final String titre, note;
  final List<String> entetes;
  final List<int> flex;
  final List<List<String>> lignes;
  const TableauRes(this.titre, this.note, this.entetes, this.flex, this.lignes);
}

class SectionRes {
  final String titre;
  final List<(String, String)> lignes;
  final (String, String)? total;
  const SectionRes(this.titre, this.lignes, [this.total]);
}

class FluxPeriode {
  final String label;
  final double depenses, recettes, cumul;
  const FluxPeriode(this.label, this.depenses, this.recettes, this.cumul);
}

class ResultatSimu {
  final double benefice, coutTotal, recetteTotale, besoinFinancement, alimentTotal, coutUnitaire, prixUnitaire, unitesVendues, recettesAnnexes;
  final String unite; // « poulet », « poussin d'un jour »…
  final int? periodePointMort;
  final String periodeNom; // « Semaine » ou « Mois »
  final List<FluxPeriode> flux;
  final List<CarteRes> cartes;
  final List<SectionRes> sections;
  final List<TableauRes> tableaux;
  final List<String> constats;
  const ResultatSimu({
    required this.benefice, required this.coutTotal, required this.recetteTotale, required this.besoinFinancement,
    required this.alimentTotal, required this.coutUnitaire, required this.prixUnitaire, required this.unitesVendues,
    required this.recettesAnnexes, required this.unite, required this.periodePointMort, required this.periodeNom,
    required this.flux, required this.cartes, required this.sections, required this.tableaux, required this.constats,
  });
}

abstract class ModeleProjet {
  String get cle;
  String get titre;
  List<Object> get saisie; // GroupeDef ou CaseDef, dans l'ordre d'affichage
  List<RaceDef> get races;
  String get perfLabel;
  String get perfUnite;
  double get perfMin; // plus grande baisse testée (en valeur absolue de variation)
  double get perfMax;
  double get perfPas; // pas du curseur « Et si… »
  double get perfPrudent;
  double get perfOptimiste;
  bool get perfHausseBonne; // true : plus la performance monte, mieux c'est (taux de ponte) ; false : l'inverse (indice de consommation)
  double perfBase(Valeurs v);
  double pertesBase(Valeurs v);
  ResultatSimu calculer(Valeurs v);
  Valeurs varier(Valeurs v, {double alimentPct = 0, double prixPct = 0, double pertesPct = 0, double perfDelta = 0});
  List<String> attention(Valeurs v);

  Valeurs defauts() {
    final m = <String, double>{'arrivee': 0};
    for (final r in races) {
      for (final k in r.valeurs.keys) {
        m.putIfAbsent(k, () => 0);
      }
    }
    for (final e in saisie) {
      if (e is GroupeDef) {
        for (final c in e.champs) {
          m[c.cle] = c.defaut;
        }
      } else if (e is CaseDef) {
        m[e.cle] = e.defaut ? 1 : 0;
      }
    }
    return m;
  }
}

// ---------------------------------------------------------------------------------------------------
// Outils communs
// ---------------------------------------------------------------------------------------------------

/// Ingrédients de l'aliment fabriqué soi-même (mêmes prix pour tous les projets).
List<ChampDef> champsIngredients({bool ponte = true}) => [
      ChampDef('mais', 'Maïs', 'F/kg', 'Prix d\'un kilo de maïs.', 150, simple: true),
      ChampDef('soja', 'Tourteau de soja', 'F/kg', 'Prix d\'un kilo de soja torréfié (source de protéines).', 500, simple: true),
      ChampDef('son', 'Son de blé', 'F/kg', 'Prix d\'un kilo de son.', 280, simple: true),
      ChampDef('poisson', 'Farine de poisson', 'F/kg', 'Prix d\'un kilo de farine de poisson.', 500, simple: true),
      ChampDef('coquille', 'Coquilles broyées', 'F/kg', 'Prix d\'un kilo de coquilles (calcium).', 200, simple: true),
      ChampDef('premix', 'Prémix chair (concentré)', 'F/kg', 'Prix d\'un kilo de prémix chair : un concentré qui apporte vitamines, minéraux, phosphore, lysine et méthionine. Il est indispensable.', 1400, simple: true),
      if (ponte)
        ChampDef('premixPonte', 'Prémix ponte (concentré)', 'F/kg', 'Prix d\'un kilo de prémix ponte (pondeuses et reproducteurs pondeuse). Il est indispensable.', 1300, simple: true),
      ChampDef('sel', 'Sel', 'F/kg', 'Prix d\'un kilo de sel.', 200, simple: true),
      ChampDef('huile', 'Huile (palme ou soja)', 'F/kg', 'Prix d\'un kilo d\'huile : elle apporte l\'énergie dont le poulet de chair a besoin.', 1000),
      ChampDef('fraisFabrication', 'Frais de broyage et mélange', 'F/kg',
          'Ce que coûtent le broyage, le mélange, le courant ou la main-d\'œuvre pour chaque kilo d\'aliment fabriqué.', 10, simple: true),
    ];

/// Prix au kilo d'un ingrédient pris dans les valeurs du projet (les ingrédients ajoutés retombent sur le prix de la bibliothèque).
double prixIngredient(Valeurs v, String cle) {
  final x = v[cle];
  if (x != null) return x;
  return FormulesAliment.prixDe(cle) * (v['facteurIng'] ?? 1);
}

/// Coût d'un kilo d'aliment fabriqué pour une étape de simulation : une ou plusieurs formules de la bibliothèque
/// (poids = durées), plus les frais de broyage et de mélange.
double coutKgFormules(Valeurs v, List<(String, double)> parts) =>
    FormulesAliment.coutKgMoyen(parts, (k) => prixIngredient(v, k), boost: v['boost'] ?? 0) + (v['fraisFabrication'] ?? 0);

/// Ligne d'information sur le boost, pour les notes des simulateurs (vide si le boost est à 0).
String boostLigne(Valeurs v) {
  final b = v['boost'] ?? 0;
  return b > 0 ? '🔥 Boost de la ration : ${b.toStringAsFixed(0)} % (barre de boost de la page Prévisions)\n' : '';
}

/// Multiplie les prix de l'aliment (sacs et ingrédients) par (1 + pct/100).
void appliquerPrixAliment(Valeurs v, double pct) {
  final f = 1 + pct / 100;
  v['facteurIng'] = (v['facteurIng'] ?? 1) * f;
  for (final k in ['prixSac1', 'prixSac2', 'prixSac3', 'prixSacPonte', 'mais', 'soja', 'son', 'poisson', 'coquille', 'premix', 'sel', 'huile', 'premixPonte']) {
    if (v.containsKey(k)) v[k] = v[k]! * f;
  }
}

/// Saison chaude (mars à juin) à une date donnée.
bool estChaud(DateTime d) => d.month >= 3 && d.month <= 6;

/// Cherche l'endroit où [f] passe par zéro entre [lo] et [hi] (null si elle ne change pas de signe).
double? racine(double Function(double) f, double lo, double hi) {
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

/// Ajoute au flux les dépenses et recettes de chaque période et calcule le cumul.
List<FluxPeriode> construireFlux(List<double> dep, List<double> rec, String Function(int) label) {
  final r = <FluxPeriode>[];
  var c = 0.0;
  for (var i = 0; i < dep.length; i++) {
    c += rec[i] - dep[i];
    r.add(FluxPeriode(label(i + 1), dep[i], rec[i], c));
  }
  return r;
}

/// Le point le plus bas de la trésorerie (argent à avoir) et la première période où tout est récupéré.
(double, int?) besoinEtPointMort(List<double> dep, List<double> rec) {
  var cumul = 0.0, bas = 0.0;
  var neg = false;
  int? pm;
  for (var i = 0; i < dep.length; i++) {
    cumul += rec[i] - dep[i];
    if (cumul < bas) bas = cumul;
    if (cumul < 0) neg = true;
    if (pm == null && neg && cumul >= 0) pm = i + 1;
  }
  return (-bas, pm);
}

// ---------------------------------------------------------------------------------------------------
// Scénarios, verdict, seuils
// ---------------------------------------------------------------------------------------------------

class ScenarioProjet {
  final String nom, description;
  final ResultatSimu r;
  const ScenarioProjet(this.nom, this.description, this.r);
}

class VerdictProjet {
  final int niveau; // 0 = à éviter, 1 = risqué ou mince, 2 = favorable
  final String titre, resume;
  final List<String> constats, attention;
  const VerdictProjet(this.niveau, this.titre, this.resume, this.constats, this.attention);
}

class AnalyseProjet {
  AnalyseProjet._();

  static String _signe(double x) {
    final s = x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(2).replaceAll('.', ',');
    return x > 0 ? '+$s' : s;
  }

  static List<ScenarioProjet> scenarios(ModeleProjet m, Valeurs v) {
    final prudent = m.varier(v, alimentPct: 10, prixPct: -10, pertesPct: 50, perfDelta: m.perfPrudent);
    final optimiste = m.varier(v, alimentPct: -5, prixPct: 5, pertesPct: -30, perfDelta: m.perfOptimiste);
    return [
      ScenarioProjet('Prudent', 'Aliment +10 %, prix de vente -10 %, pertes +50 %, ${m.perfLabel.toLowerCase()} ${_signe(m.perfPrudent)} ${m.perfUnite}',
          m.calculer(prudent)),
      ScenarioProjet('Normal', 'Vos chiffres tels quels', m.calculer(v)),
      ScenarioProjet('Optimiste', 'Aliment -5 %, prix de vente +5 %, pertes -30 %, ${m.perfLabel.toLowerCase()} ${_signe(m.perfOptimiste)} ${m.perfUnite}',
          m.calculer(optimiste)),
    ];
  }

  static double? hausseAlimentMax(ModeleProjet m, Valeurs v, ResultatSimu r) {
    if (r.benefice <= 0) return null;
    return racine((x) => m.calculer(m.varier(v, alimentPct: x)).benefice, 0, 500);
  }

  static double? pertesMax(ModeleProjet m, Valeurs v, ResultatSimu r) {
    if (r.benefice <= 0) return null;
    final x = racine((x) => m.calculer(m.varier(v, pertesPct: x)).benefice, 0, 1000);
    return x == null ? null : math.min(95.0, m.pertesBase(v) * (1 + x / 100));
  }

  /// Valeur limite de la performance : (texte, valeur) — « taux de ponte minimum », « indice de consommation maximum »…
  static String limitePerf(ModeleProjet m, Valeurs v) {
    double b(double d) => m.calculer(m.varier(v, perfDelta: d)).benefice;
    final fl = b(m.perfMin), fh = b(m.perfMax);
    if (fl > 0 && fh > 0) return 'Aucune limite atteinte';
    if (fl < 0 && fh < 0) return 'Impossible, même au mieux';
    final x = racine(b, m.perfMin, m.perfMax);
    if (x == null) return 'Non calculable';
    final val = m.perfBase(v) + x;
    return '${val.toStringAsFixed(val.abs() >= 10 ? 0 : 2).replaceAll('.', ',')} ${m.perfUnite}';
  }

  static List<(String, String)> seuils(ModeleProjet m, Valeurs v, ResultatSimu r) {
    final minU = r.prixUnitaire > 0 ? math.max(0.0, (r.coutTotal - r.recettesAnnexes) / r.prixUnitaire) : 0.0;
    final pct = r.unitesVendues > 0 ? minU / r.unitesVendues * 100 : 0.0;
    final perdu = r.benefice <= 0;
    final hausse = hausseAlimentMax(m, v, r);
    final pertes = pertesMax(m, v, r);
    final u = r.unite;
    return [
      ('Prix minimum d\'un $u', fmtF(r.coutUnitaire)),
      ('Votre prix prévu', fmtF(r.prixUnitaire)),
      ('Quantité à vendre au minimum', '${fmtF(minU.ceilToDouble(), unite: '')} sur ${fmtF(r.unitesVendues.roundToDouble(), unite: '')} (${pct.round()} %)'),
      ('Hausse maximale du prix de l\'aliment', perdu ? 'Déjà dépassée' : (hausse == null ? 'Plus de 500 %' : '${hausse.round()} %')),
      ('Pertes maximales acceptables', perdu ? 'Déjà dépassées' : (pertes == null ? 'Plus de 95 %' : '${pertes.round()} %')),
      ('${m.perfLabel} ${m.perfHausseBonne ? 'minimum' : 'maximum'}', perdu ? 'Déjà dépassé' : limitePerf(m, v)),
    ];
  }

  static VerdictProjet verdict(ModeleProjet m, Valeurs v, List<ScenarioProjet> sc) {
    final r = sc[1].r;
    final prud = sc[0].r;
    final marge = r.coutTotal > 0 ? r.benefice / r.coutTotal : 0.0;
    int niveau;
    String titre, resume;
    if (r.benefice <= 0) {
      niveau = 0;
      titre = 'À ÉVITER AVEC CES CHIFFRES';
      resume = 'Même si tout se passe comme prévu, vous ne gagnez rien. Il faut un meilleur prix de vente, un aliment moins cher '
          'ou moins de dépenses avant de vous lancer.';
    } else if (prud.benefice < 0) {
      niveau = 1;
      titre = 'POSSIBLE, MAIS RISQUÉ';
      resume = 'Vous gagnez si tout se passe comme prévu, mais une mauvaise période (aliment plus cher, ventes moins bien payées, '
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

    final c = <String>[...r.constats];
    c.add('Il faut avoir au moins ${fmtF(r.besoinFinancement)} de côté (ou emprunté) pour tenir jusqu\'à ce que les ventes remboursent vos dépenses.');
    if (r.periodePointMort != null) {
      c.add('Vous récupérez tout l\'argent avancé ${r.periodeNom == 'Semaine' ? 'à la semaine' : 'au mois'} ${r.periodePointMort}.');
    } else {
      c.add('Dans ce cycle, vous ne récupérez pas tout l\'argent avancé.');
    }
    final ecart = r.prixUnitaire - r.coutUnitaire;
    c.add('Un ${r.unite} vous coûte ${fmtF(r.coutUnitaire)} et se vend ${fmtF(r.prixUnitaire)} : '
        '${ecart >= 0 ? 'vous gagnez' : 'vous perdez'} ${fmtF(ecart.abs())} par ${r.unite}.');
    if (r.coutTotal > 0) {
      c.add('L\'aliment représente ${(r.alimentTotal / r.coutTotal * 100).round()} % de vos dépenses : c\'est lui qui décide de votre réussite.');
    }
    if (r.benefice > 0 && r.prixUnitaire > 0 && r.coutUnitaire > 0) {
      c.add('Votre prix de vente peut baisser d\'environ ${((1 - r.coutUnitaire / r.prixUnitaire) * 100).round()} % avant que vous ne gagniez plus rien.');
    }
    final hausse = hausseAlimentMax(m, v, r);
    if (hausse != null) {
      c.add('L\'aliment peut augmenter d\'environ ${hausse.round()} % avant que vous ne gagniez plus rien.');
    }
    if (r.besoinFinancement > 0) {
      c.add('Pour 100 F avancés au plus bas de votre trésorerie, ${r.benefice >= 0 ? 'vous gagnez' : 'vous perdez'} '
          '${fmtF((r.benefice / r.besoinFinancement * 100).abs())} sur le cycle.');
    }
    final arr = arriveeDe(v);
    if (arr != null && r.constats.isEmpty) {
      c.insert(0, 'Date d\'arrivée des poussins : ${dateLongue(arr)}.');
    }
    return VerdictProjet(niveau, titre, resume, c, m.attention(v));
  }
}


/// Tableau de consommation d'aliment (par semaine ou par mois) prêt à afficher.
TableauRes tableauConso(String titre, String note, List<ConsoPeriode> lignes, {required String periode, int nbOiseauxDecimales = 0}) {
  String n(double x, [int d = 0]) => fmtF(double.parse(x.toStringAsFixed(d)), unite: '').replaceAll(',', ' ');
  String dec(double x, int d) => x.toStringAsFixed(d).replaceAll('.', ',');
  return TableauRes(titre, note, [periode, 'Kg par jour (troupeau)', 'Grammes par oiseau et par jour', 'Kg dans la période', 'Sacs de 50 kg', 'Coût'],
      [4, 3, 3, 3, 2, 3], [
    for (final c in lignes) [c.label, dec(c.kgJour, c.kgJour < 100 ? 1 : 0), dec(c.gOiseauJour, 0), n(c.kgPeriode), dec(c.sacs, 1), fmtF(c.cout)],
  ]);
}

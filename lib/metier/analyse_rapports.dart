import 'dart:math' as math;

import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../utilitaires/formats.dart';

/// Noms des mois (avec accents) pour les écrans et l'Excel. Les PDF passent par `sansAccents`.
const moisNomsRapport = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
  'Septembre', 'Octobre', 'Novembre', 'Décembre'
];

/// Résultat de la lecture d'un montant saisi : soit une valeur, soit un message d'erreur clair.
class MontantLu {
  final double? valeur;
  final String? erreur;
  const MontantLu.ok(double v)
      : valeur = v,
        erreur = null;
  const MontantLu.erreur(String message)
      : valeur = null,
        erreur = message;
  bool get valide => erreur == null;
}

/// Les chiffres du bilan. Règles IDENTIQUES à celles qui existaient dans l'écran :
///   net    = revenu retenu (bénéfice pur) − charges
///   marge  = net ÷ chiffre d'affaires facturé du mois (à défaut, ÷ revenu retenu), en %
class ResultatFinancier {
  final double caBrut, coutAchat, benefice, charges, net, base, margePct;
  const ResultatFinancier({
    required this.caBrut, required this.coutAchat, required this.benefice, required this.charges,
    required this.net, required this.base, required this.margePct,
  });

  factory ResultatFinancier.calculer({
    required double benefice,
    required double charges,
    required double caBrut,
    double coutAchat = 0,
  }) {
    final net = benefice - charges;
    final base = caBrut > 0 ? caBrut : benefice;
    final pct = base > 0 ? net / base * 100 : 0.0;
    return ResultatFinancier(
        caBrut: caBrut, coutAchat: coutAchat, benefice: benefice, charges: charges, net: net, base: base, margePct: pct);
  }
}

/// Un mois de la courbe de tendance (données réelles issues des ventes + éventuel bilan archivé).
class PointMensuel {
  final DateTime mois;
  final String etiquette;
  final double ca, coutAchat, benefice;
  final int nbVentes;
  final double? chargesArchivees, netArchive;
  const PointMensuel(this.mois, this.etiquette, this.ca, this.coutAchat, this.benefice, this.nbVentes,
      this.chargesArchivees, this.netArchive);
}

/// Une ligne du tableau de comparaison entre deux périodes.
class LigneComparaison {
  final String libelle;
  final double actuel;
  final double? precedent; // null = pas de donnée pour la période précédente
  final bool enPourcent; // la marge se compare en « points », pas en %
  final bool? hausseEstBonne; // null = neutre (ex. coût d'achat, lié au volume)
  const LigneComparaison(this.libelle, this.actuel, this.precedent,
      {this.enPourcent = false, this.hausseEstBonne = true});

  double? get ecart => precedent == null ? null : actuel - precedent!;

  /// Évolution en % (ou en points pour une marge). null si la période précédente vaut zéro / est inconnue.
  double? get evolution {
    final pr = precedent;
    if (pr == null) return null;
    if (enPourcent) return actuel - pr;
    if (pr.abs() < 0.005) return null;
    return (actuel - pr) / pr.abs() * 100;
  }

  /// true = évolution favorable, false = défavorable, null = neutre / inconnue.
  bool? get favorable {
    final e = ecart;
    if (e == null || hausseEstBonne == null || e.abs() < 0.005) return null;
    return hausseEstBonne! ? e > 0 : e < 0;
  }
}

/// Tout ce qui accompagne le bilan : comparaison + tendance. Calculé uniquement à partir des ventes
/// et des bilans archivés réels (aucune donnée inventée).
class SynthesePeriodes {
  final String libelleActuel, libellePrecedent;
  final RevenuCaisse detail; // période actuelle
  final RevenuCaisse precedent; // période précédente
  final BilanArchive? archivePrecedente;
  final List<PointMensuel> tendance;
  final List<LigneComparaison> comparaison;
  const SynthesePeriodes({
    required this.libelleActuel, required this.libellePrecedent, required this.detail, required this.precedent,
    required this.archivePrecedente, required this.tendance, required this.comparaison,
  });

  bool get precedentVide => precedent.nbVentes == 0;
}

class AnalyseRapports {
  AnalyseRapports._();

  // ------------------------------------------------------------------ lecture des montants
  /// Lit un montant tapé par la personne. Accepte « 150 000 », « 150000 », « 1,5 », « 1.250.000 », « 12 500 FCFA ».
  /// Un séparateur unique suivi d'exactement 3 chiffres (« 1,234 » / « 1.234 ») est lu comme séparateur de milliers.
  /// Les lettres et les montants mal écrits sont REFUSÉS (avant : ils étaient silencieusement comptés pour 0).
  static MontantLu lireMontant(String brut, {bool negatifPermis = false, bool videPermis = true}) {
    var t = brut.replaceAll(RegExp(r'[\s\u00A0\u202F\u2009]'), '');
    t = t.replaceAll(RegExp(r'fcfa|cfa', caseSensitive: false), '');
    if (t.isEmpty) {
      return videPermis
          ? const MontantLu.ok(0)
          : const MontantLu.erreur("Champ obligatoire : saisissez 0 s'il n'y a rien à compter.");
    }
    var negatif = false;
    if (t.startsWith('-') || t.startsWith('\u2212')) {
      negatif = true;
      t = t.substring(1);
    }
    if (!RegExp(r'^[0-9.,]+$').hasMatch(t)) {
      return const MontantLu.erreur('Utilisez uniquement des chiffres, par exemple 150 000.');
    }
    final nbVirgules = ','.allMatches(t).length;
    final nbPoints = '.'.allMatches(t).length;
    var entier = '';
    var decimale = '';
    if (nbVirgules > 0 && nbPoints > 0) {
      final i = math.max(t.lastIndexOf(','), t.lastIndexOf('.'));
      entier = t.substring(0, i).replaceAll(RegExp(r'[.,]'), '');
      decimale = t.substring(i + 1);
    } else if (nbVirgules + nbPoints >= 2) {
      final sep = nbVirgules > 0 ? ',' : '.';
      final groupes = t.split(sep);
      final ok = groupes.first.isNotEmpty &&
          groupes.first.length <= 3 &&
          groupes.skip(1).every((g) => g.length == 3);
      if (!ok) return const MontantLu.erreur('Montant mal écrit : vérifiez les séparateurs (ex. 1 250 000).');
      entier = groupes.join();
    } else if (nbVirgules + nbPoints == 1) {
      final sep = nbVirgules > 0 ? ',' : '.';
      final i = t.indexOf(sep);
      final avant = t.substring(0, i);
      final apres = t.substring(i + 1);
      if (apres.length == 3 && avant.isNotEmpty && avant.length <= 3 && avant != '0') {
        entier = avant + apres;
      } else {
        entier = avant;
        decimale = apres;
      }
    } else {
      entier = t;
    }
    if (entier.isEmpty) entier = '0';
    if (decimale.length > 2) return const MontantLu.erreur('Deux décimales au maximum.');
    final v = double.tryParse(decimale.isEmpty ? entier : '$entier.$decimale');
    if (v == null || !v.isFinite) return const MontantLu.erreur('Montant illisible.');
    if (v > 1e12) return const MontantLu.erreur('Montant trop grand : vérifiez le nombre de zéros.');
    if (negatif && v != 0) {
      if (!negatifPermis) return const MontantLu.erreur('Le montant ne peut pas être négatif.');
      return MontantLu.ok(-v);
    }
    return MontantLu.ok(v);
  }

  // ------------------------------------------------------------------ périodes
  static DateTime _finDeJour(int a, int m, int j) => DateTime(a, m, j, 23, 59, 59, 999);

  /// Période de comparaison :
  ///  - mois civil (complet) -> mois précédent complet ;
  ///  - mois civil en cours (1er -> aujourd'hui) -> mêmes jours du mois précédent (comparaison équitable) ;
  ///  - période libre -> période de même durée juste avant.
  static (DateTime, DateTime) periodePrecedente(DateTime debut, DateTime fin) {
    final d0 = DateTime(debut.year, debut.month, debut.day);
    final f0 = DateTime(fin.year, fin.month, fin.day);
    if (d0.day == 1 && d0.year == f0.year && d0.month == f0.month) {
      final pd = DateTime(d0.year, d0.month - 1, 1);
      final dernierPrec = DateTime(d0.year, d0.month, 0).day;
      final dernierCourant = DateTime(d0.year, d0.month + 1, 0).day;
      final jour = f0.day >= dernierCourant ? dernierPrec : math.min(f0.day, dernierPrec);
      return (pd, _finDeJour(pd.year, pd.month, jour));
    }
    final nbJours = DateTime.utc(f0.year, f0.month, f0.day).difference(DateTime.utc(d0.year, d0.month, d0.day)).inDays + 1;
    final veille = DateTime(d0.year, d0.month, d0.day - 1);
    final pd = DateTime(veille.year, veille.month, veille.day - (nbJours - 1));
    return (pd, _finDeJour(veille.year, veille.month, veille.day));
  }

  /// « Octobre 2026 » pour un mois entier, sinon « du 01/10/2026 au 15/10/2026 ».
  static String libellePeriode(DateTime debut, DateTime fin) {
    final dernier = DateTime(fin.year, fin.month + 1, 0).day;
    if (debut.year == fin.year && debut.month == fin.month && debut.day == 1 && fin.day == dernier) {
      return '${moisNomsRapport[debut.month - 1]} ${debut.year}';
    }
    if (debut.year == fin.year && debut.month == fin.month && debut.day == 1) {
      return '${moisNomsRapport[debut.month - 1]} ${debut.year} (du 1er au ${fin.day})';
    }
    return 'du ${jourEnTexte(debut)} au ${jourEnTexte(fin)}';
  }

  /// « 09/2026 » -> « Septembre 2026 » (texte inchangé s'il n'est pas lisible).
  static String libelleMois(String periode) {
    final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(periode.trim());
    if (m == null) return periode;
    final n = int.parse(m[1]!);
    if (n < 1 || n > 12) return periode;
    return '${moisNomsRapport[n - 1]} ${m[2]}';
  }

  /// Clé de tri chronologique d'une période « MM/AAAA » (null si illisible).
  static int? clePeriode(String periode) {
    final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(periode.trim());
    if (m == null) return null;
    return int.parse(m[2]!) * 100 + int.parse(m[1]!);
  }

  static String cleMois(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Bilan archivé d'un mois : le plus récent s'il y en a plusieurs (la liste est triée du plus récent au plus ancien).
  static BilanArchive? archiveDuMois(List<BilanArchive> archives, DateTime mois) {
    final cle = cleMois(mois);
    for (final a in archives) {
      if (a.periode.trim() == cle) return a;
    }
    return null;
  }

  /// Une archive par période (la plus récente), sans doublon.
  static List<BilanArchive> dernieresParPeriode(List<BilanArchive> archives) {
    final vues = <String>{};
    final sortie = <BilanArchive>[];
    for (final a in archives) {
      if (vues.add(a.periode.trim())) sortie.add(a);
    }
    return sortie;
  }

  // ------------------------------------------------------------------ tendance et comparaison
  static List<PointMensuel> tendance(List<Vente> ventes, List<BilanArchive> archives, DateTime finPeriode,
      {int nbMois = 6}) {
    final fin0 = _finDeJour(finPeriode.year, finPeriode.month, finPeriode.day);
    final points = <PointMensuel>[];
    for (var i = nbMois - 1; i >= 0; i--) {
      final m = DateTime(fin0.year, fin0.month - i, 1);
      final finMois = _finDeJour(m.year, m.month + 1, 0);
      final r = VentesRepo.revenuPeriode(ventes, m, (i == 0 && fin0.isBefore(finMois)) ? fin0 : finMois);
      final a = archiveDuMois(archives, m);
      final etiquette = '${moisAbr[m.month - 1]} ${(m.year % 100).toString().padLeft(2, '0')}';
      points.add(PointMensuel(m, etiquette, r.caBrut, r.coutAchat, r.beneficePur, r.nbVentes, a?.totalCharges, a?.net));
    }
    return points;
  }

  static SynthesePeriodes construire({
    required List<Vente> ventes,
    required List<BilanArchive> archives,
    required DateTime debut,
    required DateTime fin,
    required ResultatFinancier res,
  }) {
    final detail = VentesRepo.revenuPeriode(ventes, debut, fin);
    final (pd, pf) = periodePrecedente(debut, fin);
    final precedent = VentesRepo.revenuPeriode(ventes, pd, pf);
    // Les bilans archivés couvrent un mois entier : on ne les compare qu'à une période « mois civil ».
    final moisCivil = debut.day == 1 && debut.year == fin.year && debut.month == fin.month;
    final arch = moisCivil ? archiveDuMois(archives, pd) : null;
    final lignes = <LigneComparaison>[
      LigneComparaison("Chiffre d'affaires facturé", detail.caBrut, precedent.caBrut),
      LigneComparaison("Coût d'achat des marchandises", detail.coutAchat, precedent.coutAchat, hausseEstBonne: null),
      LigneComparaison('Bénéfice pur de la Caisse', res.benefice, precedent.beneficePur),
      LigneComparaison('Charges totales', res.charges, arch?.totalCharges, hausseEstBonne: false),
      LigneComparaison('Bénéfice net', res.net, arch?.net),
      LigneComparaison('Marge nette (%)', res.margePct, arch?.margePct, enPourcent: true),
    ];
    return SynthesePeriodes(
      libelleActuel: libellePeriode(debut, fin),
      libellePrecedent: libellePeriode(pd, pf),
      detail: detail,
      precedent: precedent,
      archivePrecedente: arch,
      tendance: tendance(ventes, archives, fin),
      comparaison: lignes,
    );
  }
}

import 'dart:convert';
import 'dart:math' as math;

import '../data/parametres.dart';
import '../utilitaires/formats.dart';
import 'calendrier_fetes.dart';
import 'elevage_service.dart' show protocoleVetoChair;
import 'previsions.dart';

/// Une étape du calendrier (acheter, vacciner, vendre…).
class EtapePlan {
  final DateTime date;
  final String icone, titre, detail;
  final bool achat;
  const EtapePlan(this.date, this.icone, this.titre, {this.detail = '', this.achat = false});
}

class ChiffresPlan {
  final int poussins, cible;
  final double kgDemarrage, kgCroissance, kgFinition;
  final int sacsDemarrage, sacsCroissance, sacsFinition;
  final double coutAliment, coutPoussins, coutSante, capital, recette, benefice;
  const ChiffresPlan({
    required this.poussins, required this.cible, required this.kgDemarrage, required this.kgCroissance,
    required this.kgFinition, required this.sacsDemarrage, required this.sacsCroissance, required this.sacsFinition,
    required this.coutAliment, required this.coutPoussins, required this.coutSante, required this.capital,
    required this.recette, required this.benefice,
  });

  double get kgTotal => kgDemarrage + kgCroissance + kgFinition;
  int get sacsTotal => sacsDemarrage + sacsCroissance + sacsFinition;
}

/// Planificateur « à l'envers » : l'éleveur donne la date de la fête et le nombre de poulets à vendre ;
/// le logiciel calcule quand recevoir les poussins, quoi acheter et quand, et ce que cela rapporte.
class PlanFete {
  final String occasion;
  final DateTime dateFete;
  final int joursAvant; // être prêt à vendre ce nombre de jours avant la fête
  final int cible; // poulets à vendre
  final String cycle; // '45' | '90'
  final double mortalitePct;

  const PlanFete({
    required this.occasion, required this.dateFete, this.joursAvant = 2, required this.cible,
    this.cycle = '45', this.mortalitePct = 5,
  });

  static const _cle = 'plan_fete';
  // Début de chaque phase d'aliment, en jours après l'arrivée des poussins (indicatif).
  static const jourCroissance = 15, jourFinition = 30;

  int get cycleJours => cycle == '45' ? 45 : 90;
  DateTime get dateVente => dateFete.subtract(Duration(days: joursAvant));
  DateTime get dateReception => dateVente.subtract(Duration(days: cycleJours));
  int get poussins {
    final m = math.max(0.0, math.min(60.0, mortalitePct));
    return (cible / (1 - m / 100)).ceil();
  }

  // ------------------------------------------------------------------ faisabilité
  /// false si les poussins auraient dû arriver avant aujourd'hui.
  bool get faisable => !dateReception.isBefore(aujourdhui());

  /// Date de fête la plus proche possible avec ce cycle si on commande aujourd'hui.
  DateTime get fetePossibleAuPlusTot =>
      aujourdhui().add(Duration(days: cycleJours + joursAvant));

  // ------------------------------------------------------------------ calendrier
  List<EtapePlan> etapes({ChiffresPlan? chiffres}) {
    final r = dateReception;
    DateTime j(int n) => r.add(Duration(days: n));
    String sacs(int? n) => n == null ? '' : '$n sac(s) de 50 kg';
    final liste = <EtapePlan>[
      EtapePlan(r.subtract(const Duration(days: 7)), '🧹', 'Préparer le bâtiment',
          detail: 'Nettoyer, désinfecter, mettre la litière, vérifier abreuvoirs et mangeoires.'),
      EtapePlan(r.subtract(const Duration(days: 5)), '📞', 'Commander les poussins',
          detail: '$poussins poussins à réserver chez votre fournisseur.', achat: true),
      EtapePlan(r.subtract(const Duration(days: 3)), '🛒', "Acheter l'aliment démarrage",
          detail: sacs(chiffres?.sacsDemarrage), achat: true),
      EtapePlan(r, '🐣', 'Arrivée des poussins', detail: '$poussins poussins attendus.'),
      for (final (jour, tache) in protocoleVetoChair)
        EtapePlan(j(jour), '💉', tache.replaceFirst(RegExp(r'^\S+\s*'), ''), detail: 'Selon le protocole vétérinaire de la bande.'),
      EtapePlan(j(jourCroissance - 2), '🛒', "Acheter l'aliment croissance",
          detail: sacs(chiffres?.sacsCroissance), achat: true),
      EtapePlan(j(jourCroissance), '🌱', 'Début de la phase croissance'),
      EtapePlan(j(jourFinition - 2), '🛒', "Acheter l'aliment finition",
          detail: sacs(chiffres?.sacsFinition), achat: true),
      EtapePlan(j(jourFinition), '🍗', 'Début de la phase finition'),
      EtapePlan(dateVente.subtract(const Duration(days: 5)), '📣', 'Annoncer la vente à vos clients',
          detail: 'Prévenez vos clients (WhatsApp) : $cible poulets disponibles.'),
      EtapePlan(dateVente, '💰', 'Début de la vente', detail: '$cible poulets prêts à vendre.'),
      EtapePlan(dateFete, '🎉', occasion),
    ];
    liste.sort((a, b) => a.date.compareTo(b.date));
    return liste;
  }

  // ------------------------------------------------------------------ chiffres (utilise vos prix de la page Prévisions)
  ChiffresPlan chiffres() {
    final kg = dureesChair[cycle]!.kg;
    final kgD = kg.$1 * cible, kgC = kg.$2 * cible, kgF = kg.$3 * cible;
    int sacs(double x) => x <= 0 ? 0 : (x / 50).ceil();
    final aliment = kgD * Previsions.formule('demarrage').coutKg +
        kgC * Previsions.formule('croissance').coutKg +
        kgF * Previsions.formule('finition').coutKg;
    final poussinsCout = poussins * Previsions.prixPoussin;
    final sante = cible * Previsions.fraisSante;
    final capital = aliment + poussinsCout + sante;
    final recette = cible * Previsions.prixVenteChair;
    return ChiffresPlan(
      poussins: poussins, cible: cible, kgDemarrage: kgD, kgCroissance: kgC, kgFinition: kgF,
      sacsDemarrage: sacs(kgD), sacsCroissance: sacs(kgC), sacsFinition: sacs(kgF),
      coutAliment: aliment, coutPoussins: poussinsCout, coutSante: sante, capital: capital,
      recette: recette, benefice: recette - capital,
    );
  }

  // ------------------------------------------------------------------ mémorisation (pour les rappels de l'accueil)
  Future<void> enregistrer() => Parametres.ecrire(
      _cle,
      jsonEncode({
        'o': occasion, 'd': _iso(dateFete), 'a': joursAvant, 'c': cible, 'y': cycle, 'm': mortalitePct,
      }));

  static Future<void> supprimer() => Parametres.ecrire(_cle, '');

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<PlanFete?> charger() async {
    try {
      final t = await Parametres.lire(_cle);
      if (t.trim().isEmpty) return null;
      final m = jsonDecode(t) as Map;
      final d = DateTime.tryParse('${m['d']}');
      final c = int.tryParse('${m['c']}');
      if (d == null || c == null || c <= 0) return null;
      final cycle = '${m['y']}' == '90' ? '90' : '45';
      return PlanFete(
        occasion: '${m['o'] ?? 'Fête'}', dateFete: DateTime(d.year, d.month, d.day),
        joursAvant: int.tryParse('${m['a']}') ?? 2, cible: c, cycle: cycle,
        mortalitePct: double.tryParse('${m['m']}') ?? 5,
      );
    } catch (_) {
      return null;
    }
  }

  /// La prochaine étape à moins de 7 jours (pour l'afficher sur la Vue d'ensemble), ou null.
  /// Un plan dont la fête est passée depuis plus de 3 jours est ignoré.
  static Future<({PlanFete plan, EtapePlan etape, int jours})?> prochaineEtape() async {
    final plan = await charger();
    if (plan == null) return null;
    final auj = aujourdhui();
    if (CalendrierFetes.jours(plan.dateFete, auj) > 3) return null;
    for (final e in plan.etapes()) {
      final n = CalendrierFetes.jours(auj, e.date);
      if (n >= 0 && n <= 7) return (plan: plan, etape: e, jours: n);
    }
    return null;
  }
}

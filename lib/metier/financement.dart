import 'dart:math' as math;

import '../utilitaires/formats.dart';
import 'projet_base.dart';

/// Un mois du crédit : ce qu'on paie, dont intérêts et capital, et ce qu'il reste à devoir.
class LigneCredit {
  final int mois;
  final double mensualite, interets, capital, reste;
  const LigneCredit(this.mois, this.mensualite, this.interets, this.capital, this.reste);
}

/// Un crédit à mensualités constantes, avec un différé possible (pendant lequel on ne paie que les intérêts).
class PlanCredit {
  final double montant, tauxAn, fraisPct;
  final int mois, differe;
  final List<LigneCredit> lignes;

  PlanCredit._(this.montant, this.tauxAn, this.fraisPct, this.mois, this.differe, this.lignes);

  factory PlanCredit(double montant, double tauxAn, int mois, int differe, double fraisPct) {
    final n = math.max(1, mois);
    final d = math.max(0, math.min(differe, n - 1));
    final rm = tauxAn / 100 / 12;
    final restant = n - d;
    final pmt = rm == 0 ? montant / restant : montant * rm / (1 - math.pow(1 + rm, -restant));
    final l = <LigneCredit>[];
    var reste = montant;
    for (var m = 1; m <= n; m++) {
      final inter = reste * rm;
      if (m <= d) {
        l.add(LigneCredit(m, inter, inter, 0, reste));
      } else {
        final cap = m == n ? reste : math.min(reste, pmt - inter);
        reste = math.max(0.0, reste - cap);
        l.add(LigneCredit(m, cap + inter, inter, cap, reste));
      }
    }
    return PlanCredit._(montant, tauxAn, fraisPct, n, d, l);
  }

  double get fraisDossier => montant * fraisPct / 100;

  /// La mensualité normale (après le différé).
  double get mensualite => lignes[math.min(differe, lignes.length - 1)].mensualite;

  double get totalInterets => lignes.fold<double>(0, (a, l) => a + l.interets);

  /// Tout ce qu'on rembourse : capital + intérêts + frais de dossier.
  double get totalRembourse => montant + totalInterets + fraisDossier;

  /// Les intérêts courus jusqu'à [moisFin] (mois entiers, puis un morceau du mois suivant).
  double interetsJusqua(double moisFin) {
    var t = 0.0;
    for (final l in lignes) {
      final part = (moisFin - (l.mois - 1)).clamp(0.0, 1.0);
      t += l.interets * part;
    }
    return t;
  }

  /// Ce qu'il reste à devoir après [m] mois.
  double resteApres(int m) => m <= 0 ? montant : (m >= mois ? 0.0 : lignes[m - 1].reste);
}

const semainesParMoisCredit = 4.345;

/// Ce que le crédit change dans un projet (calculé une fois, utilisé pour les chiffres, les tableaux et les constats).
class EffetCredit {
  final PlanCredit plan;
  final double besoinSansCredit, horizonMois;
  final double coutProjet; // intérêts courus pendant le projet + frais de dossier
  final double interetsProjet;
  EffetCredit(this.plan, this.besoinSansCredit, this.horizonMois, this.interetsProjet)
      : coutProjet = interetsProjet + plan.fraisDossier;

  int get moisPayes => math.min(plan.mois, horizonMois.floor());
  double get resteFin => plan.resteApres(moisPayes);
}

/// Si le projet est financé par un crédit : ajoute dans les dépenses et recettes (par semaine) les frais de dossier,
/// l'argent emprunté et les mensualités, puis renvoie ce que le crédit coûte au projet. Renvoie null sans crédit.
EffetCredit? injecterCredit(Valeurs v, List<double> dep, List<double> rec) {
  if ((v['avecCredit'] ?? 0) != 1) return null;
  final montant = v['creditMontant'] ?? 0;
  if (montant <= 0 || dep.isEmpty) return null;
  final besoin0 = besoinEtPointMort(dep, rec).$1;
  final plan = PlanCredit(montant, v['creditTaux'] ?? 0, (v['creditMois'] ?? 12).round(), (v['creditDiffere'] ?? 0).round(), v['creditFrais'] ?? 0);
  final horizon = dep.length / semainesParMoisCredit;
  rec[0] += montant;
  dep[0] += plan.fraisDossier;
  for (final l in plan.lignes) {
    final w = (l.mois * semainesParMoisCredit).ceil();
    if (w > dep.length) break;
    dep[w - 1] += l.mensualite;
  }
  return EffetCredit(plan, besoin0, horizon, plan.interetsJusqua(horizon));
}

String _f(double x) => fmtF(x.roundToDouble());
String _pc(double x) => '${x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1).replaceAll('.', ',')} %';

/// Cartes « Crédit » (mensualité, coût sur le projet, bénéfice après crédit).
List<CarteRes> cartesCredit(EffetCredit e, double benefice) => [
      CarteRes('mensualite', 'MENSUALITÉ DU CRÉDIT', _f(e.plan.mensualite),
          'Ce que vous remboursez chaque mois à la banque ou à l\'institution, capital et intérêts compris.',
          detail: '${_f(e.plan.montant)} sur ${e.plan.mois} mois à ${_pc(e.plan.tauxAn)} par an'),
      CarteRes('coutcredit', 'COÛT DU CRÉDIT SUR CE PROJET', _f(e.coutProjet),
          'Les intérêts de la durée du projet, plus les frais de dossier. C\'est déjà retiré de votre bénéfice.',
          detail: 'Reste à devoir à la fin : ${_f(e.resteFin)}', ton: 2),
      CarteRes('apresCredit', benefice >= 0 ? 'BÉNÉFICE APRÈS CRÉDIT' : 'PERTE APRÈS CRÉDIT', _f(benefice),
          'Le bénéfice du projet une fois les intérêts et les frais du crédit payés.', ton: benefice >= 0 ? 1 : 2),
    ];

/// Section « Crédit » (mode détaillé et PDF).
SectionRes sectionCredit(EffetCredit e, double besoinApres) => SectionRes('CRÉDIT (FINANCEMENT)', [
      ('Montant emprunté', _f(e.plan.montant)),
      ('Taux par an', _pc(e.plan.tauxAn)),
      ('Durée du crédit', '${e.plan.mois} mois${e.plan.differe > 0 ? ' (dont ${e.plan.differe} de différé)' : ''}'),
      ('Mensualité', _f(e.plan.mensualite)),
      ('Frais de dossier (payés au début)', _f(e.plan.fraisDossier)),
      ('Intérêts courus pendant le projet', _f(e.interetsProjet)),
      ('Reste à devoir à la fin du projet', _f(e.resteFin)),
      ('Argent à avoir sans crédit', _f(e.besoinSansCredit)),
      ('Apport personnel avec ce crédit', _f(besoinApres)),
      ('Coût total du crédit (si gardé jusqu\'au bout)', _f(e.plan.totalInterets + e.plan.fraisDossier)),
    ], ('Coût du crédit sur ce projet', _f(e.coutProjet)));

/// Échéancier : mois par mois, ce qu'on paie.
TableauRes tableauCredit(EffetCredit e) => TableauRes(
      'ÉCHÉANCIER DU CRÉDIT',
      'Chaque mois : la mensualité, ce qui part en intérêts (le coût du crédit), ce qui rembourse l\'argent emprunté (le capital), et ce qu\'il reste à devoir. '
      '${e.plan.differe > 0 ? 'Pendant le différé, vous ne payez que les intérêts. ' : ''}Le projet couvre les ${e.moisPayes} premier${e.moisPayes > 1 ? 's' : ''} mois ; la suite se paie avec les bandes ou les cycles suivants.',
      ['Mois', 'Mensualité', 'Intérêts', 'Capital', 'Reste à devoir'],
      [2, 3, 3, 3, 3],
      [for (final l in e.plan.lignes) ['${l.mois}', _f(l.mensualite), _f(l.interets), _f(l.capital), _f(l.reste)]],
    );

/// Phrases claires sur la capacité à rembourser.
List<String> constatsCredit(EffetCredit e, double beneficeAvantCredit, double beneficeApres, double besoinApres) {
  final c = <String>[];
  c.add('Crédit de ${_f(e.plan.montant)} sur ${e.plan.mois} mois à ${_pc(e.plan.tauxAn)} par an : vous payez ${_f(e.plan.mensualite)} par mois. '
      'Si vous le gardez jusqu\'au bout, il coûte ${_f(e.plan.totalInterets + e.plan.fraisDossier)} (intérêts et frais de dossier).');
  c.add('Pendant ce projet, le crédit vous coûte ${_f(e.coutProjet)}. Il vous restera ${_f(e.resteFin)} à rembourser à la fin.');
  final gainMois = e.horizonMois > 0 ? beneficeAvantCredit / e.horizonMois : 0.0;
  final m = e.plan.mensualite;
  if (m > 0) {
    final cov = gainMois / m;
    if (beneficeAvantCredit <= 0) {
      c.add('Le projet ne gagne rien avant crédit : vous ne pourrez pas payer les mensualités avec ses bénéfices. Il faudrait les payer avec d\'autres revenus.');
    } else if (cov >= 1.5) {
      c.add('Le projet gagne environ ${_f(gainMois)} par mois en moyenne, pour une mensualité de ${_f(m)} : le crédit se rembourse confortablement.');
    } else if (cov >= 1) {
      c.add('Le projet gagne environ ${_f(gainMois)} par mois en moyenne, pour une mensualité de ${_f(m)} : c\'est juste. Un mauvais mois peut vous mettre en difficulté.');
    } else {
      c.add('Le projet gagne environ ${_f(gainMois)} par mois en moyenne, moins que la mensualité de ${_f(m)} : le crédit est trop lourd pour ce projet. '
          'Empruntez moins, allongez la durée ou demandez un différé.');
    }
  }
  if (beneficeApres <= 0 && beneficeAvantCredit > 0) {
    c.add('Attention : sans le crédit, le projet gagne ${_f(beneficeAvantCredit)} ; avec les intérêts et les frais, il ne gagne plus rien.');
  }
  c.add('Avec ce crédit, il vous faut ${_f(besoinApres)} de votre poche (contre ${_f(e.besoinSansCredit)} sans crédit).');
  return c;
}

/// Champs de saisie du crédit, communs à tous les simulateurs.
List<Object> saisieCredit(String Function(Valeurs) suggestion) => [
      CaseDef('avecCredit', 'Je finance avec un crédit',
          'Cochez si vous empruntez à une banque, une institution de microfinance ou un proche. Le logiciel calcule la mensualité, le coût du crédit, '
          'l\'apport qu\'il vous reste à mettre et si le projet peut rembourser.', simple: true),
      GroupeDef('', [
        ChampDef('creditMontant', 'Montant emprunté', 'F', 'La somme que l\'on vous prête. Laissez 0 pour ne pas utiliser le crédit.', 0, simple: true),
        ChampDef('creditTaux', 'Taux d\'intérêt par an', '%', 'Le taux annuel demandé. Les microfinances demandent souvent 12 à 24 % par an ; une banque 8 à 14 %.', 14, simple: true),
        ChampDef('creditMois', 'Durée du crédit', 'mois', 'Sur combien de mois vous remboursez.', 12, simple: true),
        ChampDef('creditDiffere', 'Différé', 'mois', 'Les premiers mois où vous ne payez que les intérêts (utile pendant l\'élevage, quand vous ne vendez encore rien).', 0),
        ChampDef('creditFrais', 'Frais de dossier', '%', 'Frais payés une fois au début, en pourcentage du montant emprunté.', 1),
      ], visible: (v) => (v['avecCredit'] ?? 0) == 1, note: suggestion),
    ];

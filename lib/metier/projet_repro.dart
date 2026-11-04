import 'dart:math' as math;

import '../utilitaires/formats.dart';
import 'previsions_pondeuses.dart' show dateLongue, libelleMois;
import 'conso_aliment.dart';
import 'financement.dart';
import 'projet_base.dart';

/// Prévision « reproducteurs » : élevage des reproducteurs, puis vente d'œufs à couver ou de poussins d'un jour.
class ModeleRepro extends ModeleProjet {
  /// Formules de la bibliothèque : reproducteurs chair (« rc ») ou reproducteurs pondeuse (« rp »).
  static String _fam(Valeurs v) => (v['rp'] ?? 0) == 1 ? 'rp' : 'rc';

  /// Formules (avec leur poids en semaines) pour un stade 0 à 3 : démarrage, croissance, développement + pré-ponte, reproduction.
  static List<(String, double)> _parts(Valeurs v, int stade) {
    final p = _fam(v);
    final s = math.max(18, math.min(30, (v['debutPonte'] ?? 22).round()));
    switch (stade) {
      case 0:
        return [('${p}_dem', 1)];
      case 1:
        return [('${p}_cro', 1)];
      case 2:
        return [('${p}_dev', (s - 14).toDouble()), ('${p}_pre', 2)];
      default:
        return [('${p}_ponte', 1)];
    }
  }

  @override
  String get cle => 'repro';
  @override
  String get titre => '🐓 Reproducteurs — prévision';
  @override
  String get perfLabel => 'Taux de ponte maximal';
  @override
  String get perfUnite => '%';
  @override
  double get perfMin => -20;
  @override
  double get perfMax => 10;
  @override
  double get perfPas => 1;
  @override
  double get perfPrudent => -3;
  @override
  double get perfOptimiste => 1;
  @override
  bool get perfHausseBonne => true;
  @override
  double perfBase(Valeurs v) => v['pic'] ?? 80;
  @override
  double pertesBase(Valeurs v) => v['mortElevage'] ?? 5;

  bool _maison(Valeurs v) => (v['alimentMaison'] ?? 0) == 1;
  bool _couver(Valeurs v) => (v['couver'] ?? 0) == 1;
  bool _date(Valeurs v) => (v['arrivee'] ?? 0) > 0;

  @override
  late final List<Object> saisie = [
    GroupeDef('VOTRE PROJET', [
      ChampDef('poules', 'Nombre de poules reproductrices', 'poules',
          'Le nombre de femelles que vous achetez au départ. Les coqs sont calculés à part, selon le rapport indiqué.', 500, simple: true),
      ChampDef('poulesParCoq', 'Nombre de poules pour 1 coq', 'poules', 'Rapport mâles/femelles. En général 1 coq pour 8 à 10 poules.', 10, simple: true),
      ChampDef('prixPoussin', 'Prix d\'un poussin reproducteur', 'F',
          'Ce que vous demande le fournisseur pour un poussin reproducteur (mâle ou femelle). Il est souvent plus cher qu\'un poussin ordinaire.', 900, simple: true),
      ChampDef('dureePonteSem', 'Durée de la reproduction', 'semaines', 'Combien de semaines les reproducteurs produisent avant d\'être réformés. Souvent 40 à 45.', 40),
      ChampDef('debutPonte', 'Début de la ponte', 'semaines d\'âge', 'À quel âge les poules commencent à pondre des œufs à couver. Souvent 22 semaines.', 22),
    ]),
    GroupeDef('CE QUE VOUS VENDEZ', []),
    CaseDef('couver', 'Je fais couver et je vends des poussins d\'un jour',
        'Décoché : vous vendez les œufs fécondés à couver. Coché : vous les mettez en couveuse et vous vendez les poussins nés. '
        'Vendre des poussins rapporte plus, mais il faut une couveuse et de l\'électricité fiable.'),
    GroupeDef('', [
      ChampDef('prixOeufFec', 'Prix de vente d\'un œuf à couver', 'F', 'Le prix auquel vous vendez un œuf fécondé à un couvoir ou à un éleveur.', 250, simple: true),
    ], visible: (v) => !_couver(v)),
    GroupeDef('', [
      ChampDef('prixPoussinVente', 'Prix de vente d\'un poussin d\'un jour', 'F', 'Le prix auquel vous vendez un poussin né chez vous.', 650, simple: true),
      ChampDef('eclosion', 'Éclosion', '%', 'Sur 100 œufs mis en couveuse, combien de poussins naissent. Un bon couvoir : 80 à 85.', 80, simple: true),
      ChampDef('couvoirOeuf', 'Coût de la couveuse par œuf', 'F/œuf', 'Courant, désinfection et manipulation pour chaque œuf mis à couver.', 15),
    ], visible: _couver),
    CaseDef('avecCouveuse', 'Compter l\'achat de la couveuse',
        'Cochez si vous devez acheter une couveuse. Son prix est étalé sur sa durée de vie.', visible: _couver),
    GroupeDef('', [
      ChampDef('prixCouveuse', 'Prix de la couveuse', 'F', 'Le prix d\'achat de votre couveuse.', 1500000, simple: true),
      ChampDef('dureeCouveuse', 'Durée de vie de la couveuse', 'mois', 'Pendant combien de mois la couveuse sert.', 60, simple: true),
    ], visible: (v) => _couver(v) && (v['avecCouveuse'] ?? 0) == 1),
    GroupeDef('', [
      ChampDef('prixReforme', 'Prix d\'une poule de réforme', 'F', 'Prix de vente d\'une poule à la fin de la reproduction.', 3000),
      ChampDef('prixCoqReforme', 'Prix d\'un coq de réforme', 'F', 'Prix de vente d\'un coq à la fin de la reproduction.', 3500),
    ], detailSeulement: true),
    GroupeDef('ALIMENT', []),
    CaseDef('alimentMaison', 'Je fabrique mon propre aliment',
        'Au lieu d\'acheter des sacs tout faits, vous mélangez vous-même maïs, soja, son, poisson, coquilles et prémix. '
        'Le logiciel calcule le prix du sac fabriqué et le compare au sac acheté. Les recettes sont des exemples : '
        'faites-les valider par votre fournisseur de prémix ou un vétérinaire.'),
    GroupeDef('', [
      ChampDef('prixSac1', 'Sac de 50 kg · démarrage', 'F', 'Prix d\'un sac de 50 kg d\'aliment démarrage (0 à 6 semaines).', 20000, simple: true),
      ChampDef('prixSac2', 'Sac de 50 kg · croissance', 'F', 'Prix d\'un sac de 50 kg d\'aliment croissance (7 à 12 semaines).', 18000, simple: true),
      ChampDef('prixSac3', 'Sac de 50 kg · développement', 'F', 'Prix d\'un sac de 50 kg d\'aliment développement (13 semaines jusqu\'à la ponte).', 17000, simple: true),
      ChampDef('prixSacPonte', 'Sac de 50 kg · reproducteur', 'F', 'Prix d\'un sac de 50 kg d\'aliment reproducteur. C\'est le plus gros poste de dépense : soyez précis.', 17500, simple: true),
    ], visible: (v) => !_maison(v)),
    GroupeDef('', champsIngredients(), visible: _maison, vraisPrix: true, note: (v) =>
        '${boostLigne(v)}Prix du sac de 50 kg fabriqué :\n'
        '•  Démarrage : ${fmtF(coutKgFormules(v, _parts(v, 0)) * 50)}\n'
        '•  Croissance : ${fmtF(coutKgFormules(v, _parts(v, 1)) * 50)}\n'
        '•  Développement : ${fmtF(coutKgFormules(v, _parts(v, 2)) * 50)}\n'
        '•  Reproducteur : ${fmtF(coutKgFormules(v, _parts(v, 3)) * 50)}\n'
        'Les formules se règlent dans « Formules d\'aliment » (onglet Prévisions).'),
    GroupeDef('CONSOMMATION', [
      ChampDef('g1', 'Démarrage', 'g/poule/jour', 'Quantité d\'aliment mangée par jour, en grammes (0 à 6 semaines).', 27),
      ChampDef('g2', 'Croissance', 'g/poule/jour', 'Quantité d\'aliment mangée par jour (7 à 12 semaines).', 55),
      ChampDef('g3', 'Développement', 'g/poule/jour', 'Quantité d\'aliment mangée par jour (13 semaines jusqu\'à la ponte).', 75),
      ChampDef('gPonte', 'Reproduction', 'g/poule/jour', 'Quantité d\'aliment mangée par jour pendant la reproduction.', 135),
    ], detailSeulement: true),
    GroupeDef('PERFORMANCES', [
      ChampDef('pic', 'Taux de ponte maximal (le pic)', '%',
          'Au meilleur moment, sur 100 poules, combien pondent chaque jour. 80 % = 80 œufs par jour pour 100 poules.', 80),
      ChampDef('declin', 'Baisse du taux après le pic', 'point/semaine', 'Après le pic, la ponte baisse doucement. 0,5 veut dire : chaque semaine, 0,5 œuf de moins pour 100 poules.', 0.5),
      ChampDef('mortElevage', 'Pertes pendant l\'élevage', '%', 'Pourcentage de poussins qui meurent avant la ponte.', 5),
      ChampDef('mortPonteMois', 'Pertes pendant la reproduction', '% par mois', 'Pourcentage de poules et coqs qui meurent chaque mois.', 1),
      ChampDef('casse', 'Œufs cassés, sales ou hors norme', '%', 'Œufs qui ne peuvent pas être mis à couver ni vendus.', 6),
      ChampDef('baisseChaleur', 'Baisse de ponte en saison chaude', '%',
          'Quand il fait très chaud (mars à juin), les poules pondent moins. Utilisé seulement avec une date d\'arrivée.', 8, visible: _date),
    ], detailSeulement: true),
    GroupeDef('AUTRES COÛTS', [
      ChampDef('vaccinPoussin', 'Vaccins et médicaments (élevage)', 'F/poussin', 'Vaccins, vitamines et soins d\'un poussin jusqu\'à la ponte.', 450),
      ChampDef('chauffage', 'Chauffage et éclairage (élevage)', 'F/poussin', 'Chauffage des premières semaines, par poussin.', 150),
      ChampDef('litiere', 'Litière, eau, électricité (élevage)', 'F/poussin', 'Copeaux ou paille, eau et courant pendant tout l\'élevage.', 100),
      ChampDef('transport', 'Transport des poussins', 'F/poussin', 'Frais pour amener les poussins jusqu\'à la ferme.', 50),
      ChampDef('vaccinPouleMois', 'Vaccins et médicaments (reproduction)', 'F/poule/mois', 'Soins d\'une poule ou d\'un coq chaque mois.', 60),
      ChampDef('eclairagePouleMois', 'Éclairage, eau, électricité (reproduction)', 'F/poule/mois', 'Courant, eau et éclairage, par poule et par mois.', 40),
      ChampDef('emballageUnite', 'Emballage', 'F/unité vendue', 'Plateau, boîte ou carton, par œuf ou poussin vendu.', 5),
      ChampDef('mainOeuvreMois', 'Main-d\'œuvre (0 si vous travaillez seul)', 'F/mois', 'Salaire des ouvriers chaque mois.', 0),
      ChampDef('imprevus', 'Marge pour imprévus', '%', 'Réserve pour les dépenses non prévues. 3 à 5 % est courant.', 3),
    ], detailSeulement: true),
    GroupeDef('MATÉRIEL ET BÂTIMENT (facultatif)', []),
    CaseDef('avecMateriel', 'Compter le matériel', 'Cages, pondoirs, mangeoires, abreuvoirs... Cochez si vous devez les acheter. Leur prix est étalé sur leur durée de vie.'),
    GroupeDef('', [
      ChampDef('materielPoule', 'Matériel', 'F/poule', 'Coût du matériel divisé par le nombre de poules et de coqs.', 3500, simple: true),
      ChampDef('dureeMateriel', 'Durée de vie du matériel', 'mois', 'Pendant combien de mois le matériel sert.', 60, simple: true),
    ], visible: (v) => (v['avecMateriel'] ?? 0) == 1),
    CaseDef('avecBatiment', 'Compter le bâtiment', 'Le poulailler. Cochez si vous devez le construire ou le louer. S\'il est déjà à vous et ne coûte rien, laissez décoché.'),
    GroupeDef('', [
      ChampDef('batimentPoule', 'Bâtiment', 'F/poule', 'Coût de construction (ou location) divisé par le nombre de poules et de coqs.', 4000, simple: true),
      ChampDef('dureeBatiment', 'Durée de vie du bâtiment', 'mois', 'Pendant combien de mois le bâtiment sert.', 120, simple: true),
    ], visible: (v) => (v['avecBatiment'] ?? 0) == 1),
    ...saisieCredit(_suggestionCredit),
  ];

  @override
  final List<RaceDef> races = const [
    RaceDef('Reproducteurs chair (Cobb, Ross…)', {
      'rp': 0, 'pic': 80, 'declin': 0.55, 'mortElevage': 5, 'mortPonteMois': 1, 'g1': 28, 'g2': 56, 'g3': 75, 'gPonte': 140, 'eclosion': 82,
    }),
    RaceDef('Reproducteurs pondeuse (ISA, Lohmann…)', {
      'rp': 1, 'pic': 85, 'declin': 0.4, 'mortElevage': 4, 'mortPonteMois': 0.8, 'g1': 27, 'g2': 55, 'g3': 72, 'gPonte': 125, 'eclosion': 80,
    }),
    RaceDef('Locale ou croisée', {
      'rp': 1, 'pic': 55, 'declin': 0.5, 'mortElevage': 8, 'mortPonteMois': 1.2, 'g1': 22, 'g2': 45, 'g3': 60, 'gPonte': 100, 'eclosion': 75,
    }),
  ];

  /// Taux de ponte (%) à un âge donné : montée jusqu'au pic, plateau, puis baisse.
  static double taux(double age, double debut, double pic, double declin) {
    if (age < debut) return 0;
    final pointPic = debut + 8;
    if (age < pointPic) return 5 + (pic - 5) * (age - debut) / 8;
    if (age <= pointPic + 3) return pic;
    return math.max(30.0, pic - declin * (age - pointPic - 3));
  }

  double _chaleur(Valeurs v, double semaine) {
    final a = arriveeDe(v);
    final b = v['baisseChaleur'] ?? 0;
    if (a == null || b <= 0) return 1.0;
    final d = a.add(Duration(days: (semaine * 7).round()));
    return estChaud(d) ? 1 - b / 100 : 1.0;
  }

  @override
  Valeurs varier(Valeurs v, {double alimentPct = 0, double prixPct = 0, double pertesPct = 0, double perfDelta = 0}) {
    final c = Map<String, double>.from(v);
    appliquerPrixAliment(c, alimentPct);
    final fp = 1 + prixPct / 100;
    for (final k in ['prixOeufFec', 'prixPoussinVente']) {
      c[k] = c[k]! * fp;
    }
    final fm = math.max(0.0, 1 + pertesPct / 100);
    c['mortElevage'] = math.min(90.0, c['mortElevage']! * fm);
    c['mortPonteMois'] = math.min(40.0, c['mortPonteMois']! * fm);
    c['pic'] = math.max(30.0, math.min(99.0, c['pic']! + perfDelta));
    return c;
  }

  @override
  List<String> attention(Valeurs v) => [
        'Les reproducteurs demandent plus de soin que les poulets de chair : biosécurité stricte, désinfection, accès limité à l\'élevage.',
        'Vos acheteurs d\'œufs ou de poussins doivent être trouvés avant le début de la ponte : un œuf à couver ne se garde pas longtemps.',
        'La chaleur fait baisser la ponte et la fertilité : prévoyez de l\'ombre, de l\'eau fraîche et une bonne aération.',
        'Un rapport mâles/femelles mal réglé (trop peu de coqs) fait baisser la fertilité des œufs.',
        'Si vous couvez : le courant doit être fiable (groupe ou panneau solaire). Une coupure peut faire perdre toute une fournée.',
        'Les chiffres de ce logiciel sont des exemples : mettez vos vrais prix et vos vrais taux d\'éclosion pour une prévision fiable.',
        if ((v['avecMateriel'] ?? 0) == 0 && (v['avecBatiment'] ?? 0) == 0)
          'Le matériel et le bâtiment ne sont pas comptés : cochez-les si vous devez les acheter ou les construire.',
      ];

  /// Texte d'aide sous les champs du crédit : l'argent à avoir sans crédit et une suggestion de montant.
  String _suggestionCredit(Valeurs v) {
    final c = Map<String, double>.of(v);
    c['avecCredit'] = 0;
    final b = calculer(c).besoinFinancement;
    if (b <= 0) return 'Sans crédit, ce projet n\'a pas besoin d\'argent de départ.';
    return 'Sans crédit, il faut avoir ${fmtF(b.roundToDouble())} avant de commencer. Un crédit de 70 % serait d\'environ ${fmtF((b * 0.7 / 1000).round() * 1000.0)}.';
  }

  /// Le boost (aliment maison seulement) : taux de ponte maximal +2 points à 100 %.
  Valeurs _boostee(Valeurs v) {
    final b = ((v['boost'] ?? 0) / 100).clamp(0.0, 1.0);
    if (!_maison(v) || b <= 0) return v;
    final c = Map<String, double>.of(v);
    c['pic'] = math.min(99.0, (c['pic'] ?? 80) + 2 * b);
    return c;
  }

  @override
  ResultatSimu calculer(Valeurs v0) {
    final v = _boostee(v0);
    double g(String k) => v[k] ?? 0;
    final f = math.max(0.0, g('poules'));
    final coqs = f > 0 ? math.max(1.0, (f / math.max(1.0, g('poulesParCoq'))).ceilToDouble()) : 0.0;
    final n = f + coqs;
    final S = math.max(18, math.min(30, g('debutPonte').round()));
    final nB = math.max(1, math.min(150, g('dureePonteSem').round()));
    final totalSem = S + nB;
    final mA = (g('mortElevage') / 100).clamp(0.0, 0.95).toDouble();
    final mB = (g('mortPonteMois') / 100).clamp(0.0, 0.5).toDouble();
    final couver = _couver(v);
    final maison = _maison(v);
    final arr = arriveeDe(v);
    final imp = g('imprevus') / 100;

    // ------------------------------------------------ élevage
    final debut = [n, n * (1 - mA * 0.5), n * (1 - mA * 0.75)];
    final fin = [n * (1 - mA * 0.5), n * (1 - mA * 0.75), n * (1 - mA)];
    final sem = [6, 6, S - 12];
    final gr = [g('g1'), g('g2'), g('g3')];
    final prixSac = [
      for (var i = 0; i < 4; i++) maison ? coutKgFormules(v, _parts(v, i)) * 50 : g(i == 3 ? 'prixSacPonte' : 'prixSac${i + 1}'),
    ];
    const nomsEtape = ['Démarrage (0 à 6 semaines)', 'Croissance (7 à 12 semaines)'];
    final nomDev = 'Développement (13 à $S semaines)';
    final coutEtape = <double>[];
    final kgEtape = <double>[];
    for (var i = 0; i < 3; i++) {
      final kgPoule = sem[i] * 7 * gr[i] / 1000;
      final kgT = kgPoule * (debut[i] + fin[i]) / 2;
      kgEtape.add(kgT);
      coutEtape.add(kgT * prixSac[i] / 50);
    }
    final surv = n * (1 - mA), survF = f * (1 - mA), survM = coqs * (1 - mA);
    final matMens = (v['avecMateriel'] ?? 0) == 1 && g('dureeMateriel') > 0 ? g('materielPoule') * n / g('dureeMateriel') : 0.0;
    final batMens = (v['avecBatiment'] ?? 0) == 1 && g('dureeBatiment') > 0 ? g('batimentPoule') * n / g('dureeBatiment') : 0.0;
    var couveuseMens = 0.0;
    if (couver && (v['avecCouveuse'] ?? 0) == 1 && g('dureeCouveuse') > 0) couveuseMens = g('prixCouveuse') / g('dureeCouveuse');
    final amortSem = (matMens + batMens) * 12 / 52;
    final couveuseSem = couveuseMens * 12 / 52;
    final mainSem = g('mainOeuvreMois') * 12 / 52;

    final dep = List<double>.filled(totalSem, 0.0);
    final rec = List<double>.filled(totalSem, 0.0);
    final kgSem = List<double>.filled(totalSem, 0.0), coutAlimSem = List<double>.filled(totalSem, 0.0), oisSem = List<double>.filled(totalSem, 0.0);
    var aPoussins = 0.0, aAliment = 0.0, aVacc = 0.0, aChauf = 0.0, aLit = 0.0, aTrans = 0.0, aMain = 0.0, aAmort = 0.0, aImp = 0.0;
    for (var w = 1; w <= S; w++) {
      final e = w <= 6 ? 0 : (w <= 12 ? 1 : 2);
      final alim = coutEtape[e] / sem[e];
      kgSem[w - 1] = kgEtape[e] / sem[e];
      coutAlimSem[w - 1] = alim;
      oisSem[w - 1] = (debut[e] + fin[e]) / 2;
      final pous = w == 1 ? n * g('prixPoussin') : 0.0;
      final trans = w == 1 ? n * g('transport') : 0.0;
      final vacc = n * g('vaccinPoussin') / S;
      final chauf = w <= 4 ? n * g('chauffage') / 4 : 0.0;
      final lit = n * g('litiere') / S;
      final base = pous + trans + alim + vacc + chauf + lit + mainSem;
      final ip = base * imp;
      aPoussins += pous;
      aTrans += trans;
      aAliment += alim;
      aVacc += vacc;
      aChauf += chauf;
      aLit += lit;
      aMain += mainSem;
      aAmort += amortSem;
      aImp += ip;
      dep[w - 1] = base + ip + amortSem;
    }
    final totalA = aPoussins + aTrans + aAliment + aVacc + aChauf + aLit + aMain + aAmort + aImp;

    // ------------------------------------------------ reproduction
    var bAlim = 0.0, bVacc = 0.0, bEcl = 0.0, bEmb = 0.0, bCouv = 0.0, bMain = 0.0, bAmort = 0.0, bImp = 0.0;
    var recProd = 0.0, unites = 0.0, oeufsBons = 0.0, maxMisSem = 0.0, maxUnitesSem = 0.0;
    for (var t = 1; t <= nB; t++) {
      final age = S + t - 0.5;
      final dec = math.pow(1 - mB, (t - 0.5) / semainesParMois).toDouble();
      final vivF = survF * dec, vivM = survM * dec, vivT = vivF + vivM;
      final tx = taux(age, S.toDouble(), g('pic'), g('declin')) * _chaleur(v, age);
      final bons = vivF * 7 * tx / 100 * (1 - g('casse') / 100);
      final u = couver ? bons * g('eclosion') / 100 : bons;
      final r = u * (couver ? g('prixPoussinVente') : g('prixOeufFec'));
      oeufsBons += bons;
      unites += u;
      maxMisSem = math.max(maxMisSem, bons);
      maxUnitesSem = math.max(maxUnitesSem, u);
      final alim = vivT * 7 * g('gPonte') / 1000 * prixSac[3] / 50;
      kgSem[S + t - 1] = vivT * 7 * g('gPonte') / 1000;
      coutAlimSem[S + t - 1] = alim;
      oisSem[S + t - 1] = vivT;
      final vacc = vivT * g('vaccinPouleMois') * 12 / 52;
      final ecl = vivT * g('eclairagePouleMois') * 12 / 52;
      final emb = u * g('emballageUnite');
      final cv = couver ? bons * g('couvoirOeuf') : 0.0;
      final base = alim + vacc + ecl + emb + cv + mainSem;
      final ip = base * imp;
      bAlim += alim;
      bVacc += vacc;
      bEcl += ecl;
      bEmb += emb;
      bCouv += cv;
      bMain += mainSem;
      bAmort += amortSem + couveuseSem;
      bImp += ip;
      recProd += r;
      dep[S + t - 1] = base + ip + amortSem + couveuseSem;
      rec[S + t - 1] = r;
    }
    final decFin = math.pow(1 - mB, nB / semainesParMois).toDouble();
    final refF = survF * decFin, refM = survM * decFin;
    final recReforme = refF * g('prixReforme') + refM * g('prixCoqReforme');
    rec[totalSem - 1] += recReforme;
    final totalB = bAlim + bVacc + bEcl + bEmb + bCouv + bMain + bAmort + bImp;

    // financement : frais, argent emprunté et mensualités entrent dans la trésorerie ; les intérêts courus sont une dépense du projet
    final cred = injecterCredit(v, dep, rec);
    final cFin = cred?.coutProjet ?? 0.0;
    final coutTotal = totalA + totalB + cFin;
    final recetteTotale = recProd + recReforme;
    final benefice = recetteTotale - coutTotal;
    final alimentTotal = aAliment + bAlim;
    final nomUnite = couver ? 'poussin d\'un jour' : 'œuf à couver';
    final prixUnite = couver ? g('prixPoussinVente') : g('prixOeufFec');
    final coutUnitaire = unites > 0 ? (coutTotal - recReforme) / unites : 0.0;

    // ------------------------------------------------ trésorerie par mois
    final nbMois = (totalSem / semainesParMois).ceil();
    final depM = List<double>.filled(nbMois, 0.0), recM = List<double>.filled(nbMois, 0.0);
    for (var i = 0; i < totalSem; i++) {
      final m = math.min(nbMois - 1, (i / semainesParMois).floor());
      depM[m] += dep[i];
      recM[m] += rec[i];
    }
    final (besoin, pm) = besoinEtPointMort(dep, rec);
    final flux = construireFlux(depM, recM, (i) => libelleMois(arr, i));
    final pmMois = pm == null ? null : (pm / semainesParMois).ceil();
    final moisPonte = nB / semainesParMois;
    final benefMensuel = moisPonte > 0 ? (recProd - totalB) / moisPonte : 0.0;

    // ------------------------------------------------ présentation
    final constats = <String>[];
    if (arr != null) {
      final dp = arr.add(Duration(days: S * 7));
      final fp = dp.add(Duration(days: nB * 7));
      constats.add('Si les poussins arrivent le ${dateLongue(arr)}, la ponte commence vers le ${dateLongue(dp)} et la reproduction se termine vers le ${dateLongue(fp)}.');
    }
    constats.add('Pendant les ${(S / semainesParMois).toStringAsFixed(1).replaceAll('.', ',')} premiers mois (jusqu\'à $S semaines), vous dépensez ${fmtF(totalA)} sans rien encaisser.');
    constats.add('Vous achetez ${fmtF(f.roundToDouble(), unite: '')} poules et ${fmtF(coqs, unite: '')} coqs.');
    if (couver) {
      final capacite = (maxMisSem * 3).ceil();
      constats.add('Au plus fort de la ponte, il faut mettre en couveuse environ ${fmtF(maxMisSem.roundToDouble(), unite: '')} œufs par semaine. '
          'Comme un œuf reste 3 semaines, votre couveuse doit pouvoir contenir au moins ${fmtF(capacite.toDouble(), unite: '')} œufs.');
      constats.add('Vous aurez au plus fort environ ${fmtF(maxUnitesSem.roundToDouble(), unite: '')} poussins à vendre par semaine : trouvez les acheteurs avant de commencer.');
    } else {
      constats.add('Au plus fort de la ponte, vous aurez environ ${fmtF(maxUnitesSem.roundToDouble(), unite: '')} œufs à couver à vendre par semaine : '
          'trouvez les acheteurs avant de commencer.');
      constats.add('Pour comparer : en couvant vous-même, le prix de vente d\'un poussin et le taux d\'éclosion décideraient du gain. Cochez « Je fais couver » pour le voir.');
    }
    if (maison) {
      final ach = g('prixSacPonte');
      final eco = ach - prixSac[3];
      constats.add('Aliment fabriqué : le sac reproducteur vous revient à ${fmtF(prixSac[3])} (contre ${fmtF(ach)} acheté tout fait : '
          '${eco >= 0 ? 'vous économisez' : 'vous perdez'} ${fmtF(eco.abs())} par sac).');
    }

    final cartes = <CarteRes>[
      if (arr != null)
        CarteRes('oeuf', 'PREMIERS ŒUFS', dateLongue(arr.add(Duration(days: S * 7))),
            'Les poules commencent à pondre à $S semaines d\'âge. Avant, vous dépensez sans rien vendre.', detail: 'Arrivée : ${dateLongue(arr)}'),
      CarteRes('cout', 'COÛT DE REVIENT D\'UN ${nomUnite.toUpperCase()}', fmtF(coutUnitaire),
          'Ce que vous coûte chaque ${couver ? 'poussin' : 'œuf'} vendu, en comptant toutes les dépenses (moins la vente des poules et coqs de réforme).',
          detail: 'Vente prévue : ${fmtF(prixUnite)}', ton: coutUnitaire <= prixUnite ? 1 : 2),
      CarteRes('benef', benefice >= 0 ? 'BÉNÉFICE DU CYCLE' : 'PERTE DU CYCLE', fmtF(benefice),
          'Ce qui reste en poche à la fin : toutes les ventes moins toutes les dépenses.', detail: 'Dépenses ${fmtF(coutTotal)}', ton: benefice >= 0 ? 1 : 2),
      CarteRes('mois', 'BÉNÉFICE MOYEN PAR MOIS DE REPRODUCTION', fmtF(benefMensuel),
          'Bénéfice divisé par les mois de reproduction. Il ne compte pas la période d\'élevage, où vous ne vendez rien.',
          detail: 'Sans compter l\'élevage', ton: benefMensuel >= 0 ? 1 : 2),
      CarteRes('fonds', 'ARGENT À AVOIR AVANT DE COMMENCER', fmtF(besoin),
          'Le point le plus bas de votre trésorerie : la somme à avoir de côté (ou emprunter) pour tenir sans être bloqué.'),
      CarteRes('recup', 'ARGENT RÉCUPÉRÉ', pmMois == null ? 'Pas dans ce cycle' : libelleMois(arr, pmMois),
          'Le mois où les ventes ont remboursé tout l\'argent avancé depuis le début.', detail: 'Sur $nbMois mois en tout', ton: pmMois == null ? 2 : 0),
    ];

    final sections = <SectionRes>[
      SectionRes('① DU POUSSIN À $S SEMAINES (ÉLEVAGE)', [
        ('Aliment · ${nomsEtape[0]}', fmtF(coutEtape[0])),
        ('Aliment · ${nomsEtape[1]}', fmtF(coutEtape[1])),
        ('Aliment · $nomDev', fmtF(coutEtape[2])),
        ('Poussins', fmtF(aPoussins)),
        ('Transport des poussins', fmtF(aTrans)),
        ('Vaccins et médicaments', fmtF(aVacc)),
        ('Chauffage et éclairage', fmtF(aChauf)),
        ('Litière, eau, électricité', fmtF(aLit)),
        if (aMain > 0) ('Main-d\'œuvre', fmtF(aMain)),
        if (aAmort > 0) ('Matériel et bâtiment (part de la période)', fmtF(aAmort)),
        ('Imprévus', fmtF(aImp)),
      ], ('Total élevage', fmtF(totalA))),
      SectionRes('② LA REPRODUCTION', [
        ('Aliment reproducteur', fmtF(bAlim)),
        ('Vaccins et médicaments', fmtF(bVacc)),
        ('Éclairage, eau, électricité', fmtF(bEcl)),
        ('Emballage', fmtF(bEmb)),
        if (couver) ('Couveuse (courant, manipulation)', fmtF(bCouv)),
        if (bMain > 0) ('Main-d\'œuvre', fmtF(bMain)),
        if (bAmort > 0) ('Matériel, bâtiment, couveuse (part de la période)', fmtF(bAmort)),
        ('Imprévus', fmtF(bImp)),
      ], ('Total reproduction', fmtF(totalB))),
      SectionRes('③ CE QUE VOUS ENCAISSEZ', [
        ('Œufs bons pour la vente ou la couveuse', fmtF(oeufsBons.roundToDouble(), unite: '')),
        (couver ? 'Vente de ${fmtF(unites.roundToDouble(), unite: '')} poussins' : 'Vente de ${fmtF(unites.roundToDouble(), unite: '')} œufs à couver', fmtF(recProd)),
        ('Vente de ${fmtF(refF.roundToDouble(), unite: '')} poules et ${fmtF(refM.roundToDouble(), unite: '')} coqs de réforme', fmtF(recReforme)),
      ], ('Total recettes', fmtF(recetteTotale))),
      if (cred != null) sectionCredit(cred, besoin),
    ];

    final lignesProd = <List<String>>[];
    final nbMP = (nB / semainesParMois).ceil();
    for (var m = 1; m <= nbMP; m++) {
      final age = S + (m - 0.5) * semainesParMois;
      final tx = taux(age, S.toDouble(), g('pic'), g('declin')) * _chaleur(v, age);
      final vf = survF * math.pow(1 - mB, m - 0.5);
      final bonsJ = vf * tx / 100 * (1 - g('casse') / 100);
      final uJ = couver ? bonsJ * g('eclosion') / 100 : bonsJ;
      final semM = math.min(semainesParMois, nB - (m - 1) * semainesParMois);
      lignesProd.add([
        libelleMois(arr, m, decalageSemaines: S, prefixe: 'Mois de ponte'),
        fmtF(vf.roundToDouble(), unite: ''),
        '${tx.round()} %',
        fmtF(bonsJ.roundToDouble(), unite: ''),
        fmtF(uJ.roundToDouble(), unite: ''),
        fmtF(uJ * 7 * math.max(0.0, semM), unite: ''),
      ]);
    }
    final uTitre = couver ? 'Poussins' : 'Œufs à couver';
    final consoMois = consoParPeriode(parJour(kgSem), parJour(coutAlimSem), parJour(oisSem),
        joursParPeriode: 30.4, label: (i) => libelleMoisConso(arr, i));
    final tableaux = <TableauRes>[
      if (cred != null) tableauCredit(cred),
      tableauConso('ALIMENT MOIS PAR MOIS (depuis l\'arrivée des poussins)',
          'Le mois 1 commence le jour de l\'arrivée des poussins : les premiers mois sont l\'élevage, puis vient la reproduction. '
          '« Par jour » est la moyenne du mois pour tout le troupeau (poules et coqs), puis pour un seul oiseau. Les sacs sont les sacs de 50 kg à commander.',
          consoMois, periode: 'Mois'),
      TableauRes('PRODUCTION PENDANT LA REPRODUCTION (mois de ponte)',
          'Ce tableau ne parle que de la ponte. Le « mois de ponte 1 » est le premier mois où les poules pondent : il commence $S semaines après l\'arrivée des poussins.\n'
          '• Poules : nombre de poules vivantes.\n• Taux de ponte : sur 100 poules, combien pondent chaque jour.\n'
          '• Œufs bons par jour : œufs utilisables (cassés retirés).\n• $uTitre par jour et dans le mois : ce que vous avez à vendre.',
          ['Mois de ponte', 'Poules', 'Taux de ponte', 'Œufs bons par jour', '$uTitre par jour', '$uTitre dans le mois'], [4, 2, 2, 2, 2, 2], lignesProd),
    ];
    if (cred != null) {
      constats.addAll(constatsCredit(cred, benefice + cFin, benefice, besoin));
      cartes.addAll(cartesCredit(cred, benefice));
    }

    return ResultatSimu(
      benefice: benefice, coutTotal: coutTotal, recetteTotale: recetteTotale, besoinFinancement: besoin, alimentTotal: alimentTotal,
      coutUnitaire: coutUnitaire, prixUnitaire: prixUnite, unitesVendues: unites, recettesAnnexes: recReforme, unite: nomUnite,
      periodePointMort: pmMois, periodeNom: 'Mois', flux: flux, cartes: cartes, sections: sections, tableaux: tableaux, constats: constats,
    );
  }
}

import 'dart:math' as math;

import '../utilitaires/formats.dart';
import 'previsions_pondeuses.dart' show dateLongue, libelleMois;
import 'conso_aliment.dart';
import 'financement.dart';
import 'projet_base.dart';

/// Prévision « poulet de chair » : d'une bande de poussins à la vente des poulets.
class ModeleChair extends ModeleProjet {
  /// Formules de la bibliothèque utilisées selon la souche : poulet de chair moderne ou croissance lente / local.
  static List<String> _ids(Valeurs v) {
    final p = (v['lent'] ?? 0) == 1 ? 'lent' : 'chair';
    return ['${p}_dem', '${p}_cro', '${p}_fin'];
  }

  static const _parts = [0.15, 0.35, 0.50]; // part de l'aliment total mangée à chaque étape
  static const _noms = ['Démarrage (jours 1 à 10)', 'Croissance (jours 11 à 24)', 'Finition (à partir du jour 25)'];

  @override
  String get cle => 'chair';
  @override
  String get titre => '🍗 Poulet de chair — prévision';
  @override
  String get perfLabel => 'Indice de consommation';
  @override
  String get perfUnite => 'kg d\'aliment par kg de poulet';
  @override
  double get perfMin => -0.3;
  @override
  double get perfMax => 1.0;
  @override
  double get perfPas => 0.05;
  @override
  double get perfPrudent => 0.15;
  @override
  double get perfOptimiste => -0.1;
  @override
  bool get perfHausseBonne => false;
  @override
  double perfBase(Valeurs v) => v['ic'] ?? 1.8;
  @override
  double pertesBase(Valeurs v) => v['pertes'] ?? 5;

  bool _maison(Valeurs v) => (v['alimentMaison'] ?? 0) == 1;
  bool _date(Valeurs v) => (v['arrivee'] ?? 0) > 0;

  @override
  late final List<Object> saisie = [
    GroupeDef('VOTRE PROJET', [
      ChampDef('poussins', 'Nombre de poussins achetés', 'poussins',
          'Le nombre de poussins d\'un jour dans la bande. Plus il est grand, plus l\'argent à avoir est important.', 500, simple: true),
      ChampDef('prixPoussin', 'Prix d\'un poussin', 'F', 'Ce que vous demande le fournisseur pour un poussin de chair d\'un jour.', 600, simple: true),
      ChampDef('prixVente', 'Prix de vente d\'un poulet', 'F',
          'Le prix auquel vous vendez un poulet vivant ou prêt à cuire. Prenez un prix prudent : celui d\'une période calme.', 3500, simple: true),
      ChampDef('duree', 'Durée d\'élevage', 'jours',
          'Du jour d\'arrivée des poussins au jour de la vente. Poulet de chair moderne : 35 à 45 jours. Souche locale ou lente : 70 à 90 jours.', 45, simple: true),
      ChampDef('vide', 'Repos du poulailler entre deux bandes', 'jours',
          'Le temps de nettoyage et de désinfection entre deux bandes (vide sanitaire). Sert à calculer combien de bandes vous pouvez faire par an.', 14),
    ]),
    GroupeDef('ALIMENT', []),
    CaseDef('alimentMaison', 'Je fabrique mon propre aliment',
        'Au lieu d\'acheter des sacs tout faits, vous mélangez vous-même maïs, soja, son, poisson, coquilles et prémix. '
        'Le logiciel calcule le prix du sac fabriqué et le compare au sac acheté. Les recettes sont des exemples : '
        'faites-les valider par votre fournisseur de prémix ou un vétérinaire.'),
    GroupeDef('', [
      ChampDef('prixSac1', 'Sac de 50 kg · démarrage', 'F', 'Prix d\'un sac de 50 kg d\'aliment démarrage.', 20000, simple: true),
      ChampDef('prixSac2', 'Sac de 50 kg · croissance', 'F', 'Prix d\'un sac de 50 kg d\'aliment croissance.', 18500, simple: true),
      ChampDef('prixSac3', 'Sac de 50 kg · finition', 'F', 'Prix d\'un sac de 50 kg d\'aliment finition.', 17500, simple: true),
    ], visible: (v) => !_maison(v)),
    GroupeDef('', champsIngredients(ponte: false), visible: _maison, vraisPrix: true, note: (v) =>
        '${boostLigne(v)}Prix du sac de 50 kg fabriqué :\n'
        '•  Démarrage : ${fmtF(coutKgFormules(v, [(_ids(v)[0], 1)]) * 50)}\n'
        '•  Croissance : ${fmtF(coutKgFormules(v, [(_ids(v)[1], 1)]) * 50)}\n'
        '•  Finition : ${fmtF(coutKgFormules(v, [(_ids(v)[2], 1)]) * 50)}\n'
        'Les formules se règlent dans « Formules d\'aliment » (onglet Prévisions).'),
    GroupeDef('PERFORMANCES', [
      ChampDef('poids', 'Poids d\'un poulet à la vente', 'kg', 'Le poids moyen d\'un poulet vivant le jour de la vente.', 2.2),
      ChampDef('ic', 'Indice de consommation', 'kg/kg',
          'Combien de kilos d\'aliment il faut pour fabriquer 1 kg de poulet. 1,7 est très bon ; 2 est moyen ; au-delà de 2,3 l\'élevage coûte cher.', 1.8),
      ChampDef('pertes', 'Pertes (poussins qui meurent)', '%', 'Pourcentage de poussins qui meurent avant la vente. Avec une bonne conduite : 3 à 6 %.', 5),
      ChampDef('surmortChaleur', 'Pertes en plus en saison chaude', 'points',
          'Quand il fait très chaud (mars à juin), il meurt plus de poulets. Utilisé seulement si vous avez indiqué la date d\'arrivée.', 2,
          visible: _date),
      ChampDef('hausseFetes', 'Hausse du prix en décembre (fêtes)', '%',
          'Si la vente tombe en décembre, le prix monte souvent. Utilisé seulement avec une date d\'arrivée. Pour la Tabaski, ajustez le prix à la main.', 10,
          visible: _date),
    ], detailSeulement: true),
    GroupeDef('AUTRES COÛTS', [
      ChampDef('sante', 'Vaccins et médicaments', 'F/poulet', 'Tout ce que coûtent vaccins, vitamines et soins pour un poulet.', 150),
      ChampDef('chauffage', 'Chauffage et éclairage', 'F/poulet', 'Chauffage des premiers jours (lampes, charbon, gaz), par poulet.', 100),
      ChampDef('litiere', 'Litière, eau, électricité', 'F/poulet', 'Copeaux ou paille, eau et courant, par poulet.', 80),
      ChampDef('transport', 'Transport des poussins', 'F/poussin', 'Frais pour amener les poussins jusqu\'à votre ferme.', 50),
      ChampDef('preparation', 'Préparation du poulailler (par bande)', 'F',
          'Désinfection, chaux, nettoyage, matériel de départ : ce que vous dépensez avant l\'arrivée des poussins, pour toute la bande.', 15000),
      ChampDef('transportVente', 'Livraison ou emballage à la vente', 'F/poulet', 'Frais pour livrer ou emballer chaque poulet vendu.', 50),
      ChampDef('mainOeuvreMois', 'Main-d\'œuvre (0 si vous travaillez seul)', 'F/mois', 'Salaire des ouvriers chaque mois.', 0),
      ChampDef('imprevus', 'Marge pour imprévus', '%', 'Réserve pour les dépenses non prévues. 3 à 5 % est courant.', 3),
    ], detailSeulement: true),
    GroupeDef('MATÉRIEL ET BÂTIMENT (facultatif)', []),
    CaseDef('avecMateriel', 'Compter le matériel',
        'Mangeoires, abreuvoirs, lampes, bâche... Cochez si vous devez les acheter. Leur prix est étalé sur leur durée de vie.'),
    GroupeDef('', [
      ChampDef('materielPlace', 'Matériel', 'F/poulet', 'Coût du matériel divisé par le nombre de poulets que le poulailler peut contenir.', 1500, simple: true),
      ChampDef('dureeMateriel', 'Durée de vie du matériel', 'mois', 'Pendant combien de mois le matériel sert.', 60, simple: true),
    ], visible: (v) => (v['avecMateriel'] ?? 0) == 1),
    CaseDef('avecBatiment', 'Compter le bâtiment',
        'Le poulailler. Cochez si vous devez le construire ou le louer. S\'il est déjà à vous et ne coûte rien, laissez décoché.'),
    GroupeDef('', [
      ChampDef('batimentPlace', 'Bâtiment', 'F/poulet', 'Coût de construction (ou location) divisé par le nombre de poulets.', 2500, simple: true),
      ChampDef('dureeBatiment', 'Durée de vie du bâtiment', 'mois', 'Pendant combien de mois le bâtiment sert.', 120, simple: true),
    ], visible: (v) => (v['avecBatiment'] ?? 0) == 1),
    ...saisieCredit(_suggestionCredit),
  ];

  @override
  final List<RaceDef> races = const [
    RaceDef('Cobb 500 / Ross 308 (chair moderne)', {'poids': 2.2, 'ic': 1.8, 'pertes': 5, 'duree': 45, 'lent': 0}),
    RaceDef('Hubbard / autre souche rapide', {'poids': 2.1, 'ic': 1.85, 'pertes': 5, 'duree': 45, 'lent': 0}),
    RaceDef('Poulet à croissance lente (label)', {'poids': 2.0, 'ic': 2.6, 'pertes': 4, 'duree': 70, 'lent': 1}),
    RaceDef('Poulet local amélioré', {'poids': 1.7, 'ic': 3.2, 'pertes': 8, 'duree': 90, 'lent': 1}),
  ];

  @override
  Valeurs varier(Valeurs v, {double alimentPct = 0, double prixPct = 0, double pertesPct = 0, double perfDelta = 0}) {
    final c = Map<String, double>.from(v);
    appliquerPrixAliment(c, alimentPct);
    c['prixVente'] = c['prixVente']! * (1 + prixPct / 100);
    c['pertes'] = math.min(90.0, c['pertes']! * math.max(0.0, 1 + pertesPct / 100));
    c['ic'] = math.max(1.0, c['ic']! + perfDelta);
    return c;
  }

  @override
  List<String> attention(Valeurs v) => [
        'Un poulet qui reste trop longtemps mange beaucoup pour peu de poids en plus : vendez à la date prévue, sans attendre.',
        'La chaleur fait mourir des poulets : prévoyez de l\'ombre, de l\'eau fraîche et une bonne aération.',
        'Les prix changent selon la saison et les fêtes : testez d\'autres prix avec « Et si… ».',
        'Trouvez vos clients avant d\'acheter les poussins : une bande qui ne se vend pas vite coûte chaque jour de l\'aliment en plus.',
        'Achetez des poussins vaccinés chez un fournisseur sérieux et respectez le calendrier de vaccination.',
        'Les chiffres de ce logiciel sont des exemples : mettez vos vrais prix pour avoir une prévision fiable.',
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

  /// Le boost (aliment maison seulement) : meilleur indice de consommation (-0,07 à 100 %) et poulet un peu plus lourd (+2 %).
  Valeurs _boostee(Valeurs v) {
    final b = ((v['boost'] ?? 0) / 100).clamp(0.0, 1.0);
    if (!_maison(v) || b <= 0) return v;
    final c = Map<String, double>.of(v);
    c['ic'] = math.max(1.0, (c['ic'] ?? 1.8) - 0.07 * b);
    c['poids'] = (c['poids'] ?? 2.2) * (1 + 0.02 * b);
    return c;
  }

  @override
  ResultatSimu calculer(Valeurs v0) {
    final v = _boostee(v0);
    double g(String k) => v[k] ?? 0;
    final n = math.max(0.0, g('poussins'));
    final duree = math.max(7.0, g('duree'));
    final jours = duree.round();
    final arr = arriveeDe(v);
    final maison = _maison(v);

    var mortPct = g('pertes');
    var facteurPrix = 1.0;
    var chaud = false, fetes = false;
    DateTime? vente;
    if (arr != null) {
      vente = arr.add(Duration(days: jours));
      final milieu = arr.add(Duration(days: (jours / 2).round()));
      if (estChaud(milieu)) {
        mortPct += g('surmortChaleur');
        chaud = true;
      }
      if (vente.month == 12) {
        facteurPrix = 1 + g('hausseFetes') / 100;
        fetes = true;
      }
    }
    mortPct = math.max(0.0, math.min(95.0, mortPct));
    final vivants = n * (1 - mortPct / 100);

    // aliment : quantité totale, répartie sur trois étapes (selon les jours réellement vécus dans chaque étape)
    final jEtape = [math.min(10, jours), math.max(0, math.min(24, jours) - 10), math.max(0, jours - 24)];
    final poids = [for (var i = 0; i < 3; i++) jEtape[i] > 0 ? _parts[i] : 0.0];
    final somme = poids.fold<double>(0, (a, b) => a + b);
    final kgTotal = vivants * g('poids') * g('ic');
    final kg = [for (var i = 0; i < 3; i++) kgTotal * poids[i] / somme];
    final prixSac = [
      for (var i = 0; i < 3; i++) maison ? coutKgFormules(v, [(_ids(v)[i], 1)]) * 50 : g('prixSac${i + 1}'),
    ];
    final coutEtape = [for (var i = 0; i < 3; i++) kg[i] * prixSac[i] / 50];
    final alimentTotal = coutEtape.fold<double>(0, (a, b) => a + b);

    final cPoussins = n * g('prixPoussin');
    final cTransport = n * g('transport');
    final cPrep = g('preparation');
    final cSante = n * g('sante');
    final cChauffage = n * g('chauffage');
    final cLitiere = n * g('litiere');
    final cMain = g('mainOeuvreMois') * duree / 30.4;
    final cVente = vivants * g('transportVente');
    final base = cPoussins + cTransport + cPrep + alimentTotal + cSante + cChauffage + cLitiere + cMain + cVente;
    final cImprevus = base * g('imprevus') / 100;
    final moisOccupe = (duree + g('vide')) / 30.4;
    final cMateriel = (v['avecMateriel'] ?? 0) == 1 && g('dureeMateriel') > 0 ? g('materielPlace') * n / g('dureeMateriel') * moisOccupe : 0.0;
    final cBatiment = (v['avecBatiment'] ?? 0) == 1 && g('dureeBatiment') > 0 ? g('batimentPlace') * n / g('dureeBatiment') * moisOccupe : 0.0;
    final amort = cMateriel + cBatiment;
    var coutTotal = base + cImprevus + amort;
    final prixVente = g('prixVente') * facteurPrix;
    final recette = vivants * prixVente;
    var benefice = recette - coutTotal;
    var coutUnitaire = vivants > 0 ? coutTotal / vivants : 0.0;

    // trésorerie semaine par semaine
    final nbSem = math.max(1, (duree / 7).ceil());
    final dep = List<double>.filled(nbSem, 0.0);
    final rec = List<double>.filled(nbSem, 0.0);
    for (var w = 1; w <= nbSem; w++) {
      final d0 = (w - 1) * 7 + 1, d1 = math.min(w * 7, jours);
      var alim = 0.0;
      for (var d = d0; d <= d1; d++) {
        final e = d <= 10 ? 0 : (d <= 24 ? 1 : 2);
        alim += jEtape[e] > 0 ? coutEtape[e] / jEtape[e] : 0.0;
      }
      var x = alim + (cSante + cLitiere + cMain + cImprevus + amort) / nbSem;
      if (w <= 3) x += cChauffage / math.min(nbSem, 3);
      if (w == 1) x += cPoussins + cTransport + cPrep;
      if (w == nbSem) {
        x += cVente;
        rec[w - 1] = recette;
      }
      dep[w - 1] = x;
    }
    // financement : frais, argent emprunté et mensualités entrent dans la trésorerie ; les intérêts courus sont une dépense du projet
    final cred = injecterCredit(v, dep, rec);
    final beneficeAvantCredit = benefice;
    if (cred != null) {
      coutTotal += cred.coutProjet;
      benefice -= cred.coutProjet;
      coutUnitaire = vivants > 0 ? coutTotal / vivants : 0.0;
    }
    final (besoin, pm0) = besoinEtPointMort(dep, rec);
    final flux = construireFlux(dep, rec, (i) => 'Semaine $i');

    // consommation d'aliment jour par jour (puis regroupée par semaine et par mois)
    final kgJour = <double>[], coutJourA = <double>[], oisJour = <double>[];
    for (var d = 1; d <= jours; d++) {
      final e = d <= 10 ? 0 : (d <= 24 ? 1 : 2);
      kgJour.add(jEtape[e] > 0 ? kg[e] / jEtape[e] : 0.0);
      coutJourA.add(jEtape[e] > 0 ? coutEtape[e] / jEtape[e] : 0.0);
      oisJour.add(n - (n - vivants) * d / jours);
    }
    final consoSem = consoParPeriode(kgJour, coutJourA, oisJour, joursParPeriode: 7, label: (i) => libelleSemaine(arr, i));
    final consoMois = consoParPeriode(kgJour, coutJourA, oisJour, joursParPeriode: 30.4, label: (i) => libelleMoisConso(arr, i));

    // résultats lisibles
    final bandesAn = 365 / (duree + g('vide'));
    final beneficeAn = benefice * bandesAn;
    final kgParPoulet = g('poids') * g('ic');
    final constats = <String>[];
    if (arr != null && vente != null) {
      constats.add('Si les poussins arrivent le ${dateLongue(arr)}, la vente se fait vers le ${dateLongue(vente)}.');
      if (chaud) constats.add('Cette bande tombe en saison chaude (mars à juin) : ${g('surmortChaleur').round()} points de pertes en plus sont déjà comptés.');
      if (fetes) constats.add('La vente tombe en décembre : le prix est relevé de ${g('hausseFetes').round()} % (fêtes), c\'est déjà compté.');
    }
    constats.add('Chaque poulet mange environ ${kgParPoulet.toStringAsFixed(1).replaceAll('.', ',')} kg d\'aliment pour atteindre '
        '${g('poids').toStringAsFixed(1).replaceAll('.', ',')} kg : cela fait ${fmtF(vivants > 0 ? alimentTotal / vivants : 0)} d\'aliment par poulet.');
    constats.add('Une bande dure ${duree.round()} jours, plus ${g('vide').round()} jours de repos : environ ${bandesAn.toStringAsFixed(1).replaceAll('.', ',')} bandes par an. '
        'Si chaque bande ressemble à celle-ci, le bénéfice serait d\'environ ${fmtF(beneficeAn)} par an (sans compter vos dépenses personnelles).');
    if (maison) {
      final ach = [g('prixSac1'), g('prixSac2'), g('prixSac3')];
      final eco = [for (var i = 0; i < 3; i++) ach[i] - prixSac[i]];
      constats.add('Aliment fabriqué : le sac de finition vous revient à ${fmtF(prixSac[2])} '
          '(contre ${fmtF(ach[2])} acheté tout fait : ${eco[2] >= 0 ? 'vous économisez' : 'vous perdez'} ${fmtF(eco[2].abs())} par sac).');
    }

    final cartes = <CarteRes>[
      if (vente != null)
        CarteRes('vente', 'DATE DE VENTE', dateLongue(vente), 'Le jour où les poulets atteignent leur poids et sont vendus.', detail: 'Arrivée : ${dateLongue(arr!)}'),
      CarteRes('cout', 'COÛT DE REVIENT D\'UN POULET', fmtF(coutUnitaire),
          'Ce que vous coûte un poulet vendu, en comptant toutes les dépenses de la bande. Vendez au-dessus de ce prix pour gagner.',
          detail: 'Vente prévue : ${fmtF(prixVente)}', ton: coutUnitaire <= prixVente ? 1 : 2),
      CarteRes('benef', benefice >= 0 ? 'BÉNÉFICE DE LA BANDE' : 'PERTE DE LA BANDE', fmtF(benefice),
          'Ce qui reste en poche à la fin de la bande : toutes les ventes moins toutes les dépenses.',
          detail: 'Dépenses ${fmtF(coutTotal)}', ton: benefice >= 0 ? 1 : 2),
      CarteRes('parpoulet', 'BÉNÉFICE PAR POULET', fmtF(vivants > 0 ? benefice / vivants : 0), 'Le bénéfice de la bande divisé par le nombre de poulets vendus.',
          detail: '${fmtF(vivants.roundToDouble(), unite: '')} poulets vendus', ton: benefice >= 0 ? 1 : 2),
      CarteRes('fonds', 'ARGENT À AVOIR AVANT DE COMMENCER', fmtF(besoin),
          'Le point le plus bas de votre trésorerie : la somme à avoir de côté (ou emprunter) avant que les ventes ne remboursent.'),
      CarteRes('an', 'BÉNÉFICE SUR UN AN', fmtF(beneficeAn),
          'Si vous enchaînez les bandes avec le même repos entre elles, et que chaque bande ressemble à celle-ci.',
          detail: '${bandesAn.toStringAsFixed(1).replaceAll('.', ',')} bandes par an', ton: beneficeAn >= 0 ? 1 : 2),
    ];

    final sections = <SectionRes>[
      SectionRes('DÉPENSES DE LA BANDE', [
        ('Poussins', fmtF(cPoussins)),
        ('Transport des poussins', fmtF(cTransport)),
        ('Préparation du poulailler', fmtF(cPrep)),
        for (var i = 0; i < 3; i++) ('Aliment · ${_noms[i]}', fmtF(coutEtape[i])),
        ('Vaccins et médicaments', fmtF(cSante)),
        ('Chauffage et éclairage', fmtF(cChauffage)),
        ('Litière, eau, électricité', fmtF(cLitiere)),
        ('Livraison ou emballage', fmtF(cVente)),
        if (cMain > 0) ('Main-d\'œuvre', fmtF(cMain)),
        if (amort > 0) ('Matériel et bâtiment (part de la bande)', fmtF(amort)),
        ('Imprévus', fmtF(cImprevus)),
        if (cred != null) ('Intérêts et frais du crédit', fmtF(cred.coutProjet)),
      ], ('Total dépenses', fmtF(coutTotal))),
      SectionRes('CE QUE VOUS ENCAISSEZ', [
        ('Vente de ${fmtF(vivants.roundToDouble(), unite: '')} poulets à ${fmtF(prixVente)}', fmtF(recette)),
      ], ('Bénéfice', fmtF(benefice))),
      if (cred != null) sectionCredit(cred, besoin),
    ];
    final tableaux = <TableauRes>[
      if (cred != null) tableauCredit(cred),
      tableauConso('ALIMENT MOIS PAR MOIS (depuis l\'arrivée des poussins)',
          'Le mois 1 commence le jour de l\'arrivée des poussins. « Par jour » est la moyenne du mois pour tout le troupeau, puis pour un seul poulet (le nombre de poulets baisse un peu avec les pertes). '
          'Les sacs sont les sacs de 50 kg à commander.',
          consoMois, periode: 'Mois'),
      tableauConso('ALIMENT SEMAINE PAR SEMAINE',
          'Une bande de poulets dure peu de temps : la semaine est plus pratique pour commander. Un poulet mange de plus en plus chaque semaine.',
          consoSem, periode: 'Semaine'),
      TableauRes('ALIMENT PAR ÉTAPE', 'La quantité totale est calculée avec le poids final et l\'indice de consommation ; elle est répartie selon l\'âge des poulets.',
          ['Étape', 'kg par poulet', 'Sacs de 50 kg', 'Coût'], [4, 2, 2, 3],
          [for (var i = 0; i < 3; i++) [_noms[i], vivants > 0 ? (kg[i] / vivants).toStringAsFixed(2) : '0', (kg[i] / 50).toStringAsFixed(1), fmtF(coutEtape[i])]]),
    ];
    if (cred != null) {
      constats.addAll(constatsCredit(cred, beneficeAvantCredit, benefice, besoin));
      cartes.addAll(cartesCredit(cred, benefice));
    }

    return ResultatSimu(
      benefice: benefice, coutTotal: coutTotal, recetteTotale: recette, besoinFinancement: besoin, alimentTotal: alimentTotal,
      coutUnitaire: coutUnitaire, prixUnitaire: prixVente, unitesVendues: vivants, recettesAnnexes: 0, unite: 'poulet',
      periodePointMort: benefice > 0 ? (pm0 ?? nbSem) : null, periodeNom: 'Semaine', flux: flux, cartes: cartes,
      sections: sections, tableaux: tableaux, constats: constats,
    );
  }
}

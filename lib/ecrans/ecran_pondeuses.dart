import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/parametres.dart';
import '../metier/previsions.dart';
import '../metier/financement.dart';
import '../metier/formules_aliment.dart';
import '../metier/previsions_pondeuses.dart';
import '../metier/projet_base.dart' show tableauConso;
import '../services/pdf_pondeuses.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogues.dart';
import '../widgets/toast.dart';

const _cleSauvegarde = 'prev_pondeuses';

/// Ouvre la prévision « pondeuses d'œufs de table » (simulation pure, indépendante des bandes).
Future<void> ouvrirPrevisionPondeuses(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _DialoguePondeuses(),
    );

/// Un chiffre réglable à l'écran, avec une explication qui s'ouvre au clic sur le « ? ».
class _Champ {
  final String cle, label, unite, aide;
  final double Function(ParamsPondeuses) lire;
  final void Function(ParamsPondeuses, double) ecrire;
  const _Champ(this.cle, this.label, this.unite, this.aide, this.lire, this.ecrire);
}

final _champsProjet = <_Champ>[
  _Champ('poussins', 'Nombre de poussins achetés', 'poussins',
      'Le nombre de poussins d\'un jour que vous achetez au départ. Plus vous en achetez, plus l\'argent à avoir est important.',
      (p) => p.poussins, (p, v) => p.poussins = v),
  _Champ('prixPoussin', 'Prix d\'un poussin', 'F',
      'Ce que vous demande le fournisseur pour un poussin pondeuse d\'un jour (souvent déjà vacciné). Demandez le prix réel à votre fournisseur.',
      (p) => p.prixPoussin, (p, v) => p.prixPoussin = v),
  _Champ('prixPlateau', 'Prix de vente d\'un plateau de 30 œufs', 'F',
      'Le prix auquel vous vendez un plateau de 30 œufs. Prenez un prix prudent : celui du marché en période calme.',
      (p) => p.prixPlateau, (p, v) => p.prixPlateau = v),
  _Champ('prixReforme', 'Prix de vente d\'une poule de réforme', 'F',
      'À la fin de la ponte, les poules sont revendues (viande). C\'est le prix d\'une poule vendue à ce moment-là.',
      (p) => p.prixReforme, (p, v) => p.prixReforme = v),
  _Champ('dureePonteSem', 'Durée de la ponte (à partir de 19 sem.)', 'semaines',
      'Combien de semaines les poules pondent avant d\'être vendues. Une durée courante est 52 à 72 semaines. Plus la ponte est longue, plus le taux de ponte baisse.',
      (p) => p.dureePonteSem, (p, v) => p.dureePonteSem = v),
];

final _champsSacs = <_Champ>[
  _Champ('prixSac1', 'Sac de 50 kg · démarrage', 'F',
      'Prix d\'un sac de 50 kg d\'aliment démarrage (de 0 à 6 semaines).', (p) => p.prixSac1, (p, v) => p.prixSac1 = v),
  _Champ('prixSac2', 'Sac de 50 kg · croissance', 'F',
      'Prix d\'un sac de 50 kg d\'aliment croissance (de 7 à 12 semaines).', (p) => p.prixSac2, (p, v) => p.prixSac2 = v),
  _Champ('prixSac3', 'Sac de 50 kg · développement', 'F',
      'Prix d\'un sac de 50 kg d\'aliment développement ou poulette (de 13 à 19 semaines).', (p) => p.prixSac3, (p, v) => p.prixSac3 = v),
  _Champ('prixSacPonte', 'Sac de 50 kg · pondeuse', 'F',
      'Prix d\'un sac de 50 kg d\'aliment pondeuse (à partir de 19 semaines). C\'est le plus gros poste de dépense : soyez précis.',
      (p) => p.prixSacPonte, (p, v) => p.prixSacPonte = v),
];

final _champsConsommation = <_Champ>[
  _Champ('g1', 'Consommation démarrage', 'g/poule/jour',
      'Quantité d\'aliment mangée par une poule chaque jour, en grammes. Voir la fiche technique de la race.', (p) => p.g1, (p, v) => p.g1 = v),
  _Champ('g2', 'Consommation croissance', 'g/poule/jour',
      'Quantité d\'aliment mangée par jour entre 7 et 12 semaines.', (p) => p.g2, (p, v) => p.g2 = v),
  _Champ('g3', 'Consommation développement', 'g/poule/jour',
      'Quantité d\'aliment mangée par jour entre 13 et 19 semaines.', (p) => p.g3, (p, v) => p.g3 = v),
  _Champ('gPonte', 'Consommation en ponte', 'g/poule/jour',
      'Quantité d\'aliment mangée par jour en ponte.', (p) => p.gPonte, (p, v) => p.gPonte = v),
];

final _champsMaison = <_Champ>[
  _Champ('mais', 'Maïs', 'F/kg', 'Prix d\'un kilo de maïs.', (p) => p.mais, (p, v) => p.mais = v),
  _Champ('soja', 'Tourteau de soja', 'F/kg', 'Prix d\'un kilo de soja torréfié (source de protéines).', (p) => p.soja, (p, v) => p.soja = v),
  _Champ('son', 'Son de blé', 'F/kg', 'Prix d\'un kilo de son.', (p) => p.son, (p, v) => p.son = v),
  _Champ('poisson', 'Farine de poisson', 'F/kg', 'Prix d\'un kilo de farine de poisson.', (p) => p.poisson, (p, v) => p.poisson = v),
  _Champ('coquille', 'Coquilles broyées', 'F/kg', 'Prix d\'un kilo de coquilles (calcium pour des coquilles d\'œufs solides).', (p) => p.coquille, (p, v) => p.coquille = v),
  _Champ('sel', 'Sel', 'F/kg', 'Prix d\'un kilo de sel.', (p) => p.sel, (p, v) => p.sel = v),
  _Champ('huile', 'Huile (palme ou soja)', 'F/kg', 'Prix d\'un kilo d\'huile.', (p) => p.huile, (p, v) => p.huile = v),
  _Champ('premixPonte', 'Prémix ponte (concentré)', 'F/kg', 'Prix d\'un kilo de prémix ponte : un concentré qui apporte vitamines, minéraux, phosphore, lysine et méthionine. Sa quantité dans la formule se règle dans « Formules d\'aliment ».', (p) => p.premixPonte, (p, v) => p.premixPonte = v),
  _Champ('fraisFabrication', 'Frais de broyage et mélange', 'F/kg',
      'Ce que coûtent le broyage, le mélange, le courant ou la main-d\'œuvre pour chaque kilo d\'aliment fabriqué.',
      (p) => p.fraisFabrication, (p, v) => p.fraisFabrication = v),
];

final _champsPerformance = <_Champ>[
  _Champ('pic', 'Taux de ponte maximal (le pic)', '%',
      'Au meilleur moment, sur 100 poules, combien pondent chaque jour. Exemple : 94 % = 94 œufs par jour pour 100 poules. Ce chiffre dépend de la race et de l\'élevage.',
      (p) => p.pic, (p, v) => p.pic = v),
  _Champ('declin', 'Baisse du taux après le pic', 'point/semaine',
      'Après le pic, la ponte baisse doucement. 0,35 veut dire : chaque semaine, 0,35 œuf de moins pour 100 poules.', (p) => p.declin, (p, v) => p.declin = v),
  _Champ('mortElevage', 'Pertes de 0 à 19 semaines', '%',
      'Pourcentage de poussins qui meurent pendant l\'élevage. Avec une bonne conduite : 3 à 6 %.', (p) => p.mortElevage, (p, v) => p.mortElevage = v),
  _Champ('mortPonteMois', 'Pertes pendant la ponte', '% par mois',
      'Pourcentage de poules qui meurent chaque mois en ponte.', (p) => p.mortPonteMois, (p, v) => p.mortPonteMois = v),
  _Champ('casse', 'Œufs cassés ou perdus', '%',
      'Œufs fêlés, sales ou perdus avant la vente. Ils sont mangés par l\'éleveur ou jetés.', (p) => p.casse, (p, v) => p.casse = v),
  _Champ('baisseChaleur', 'Baisse de ponte en saison chaude', '%',
      'Quand il fait très chaud (de mars à juin), les poules pondent moins. Ce chiffre n\'est utilisé que si vous avez indiqué la date d\'arrivée.',
      (p) => p.baisseChaleur, (p, v) => p.baisseChaleur = v),
];

final _champsCouts = <_Champ>[
  _Champ('vaccinPoussin', 'Vaccins et médicaments (élevage)', 'F/poussin',
      'Tout ce que coûtent vaccins, vitamines et soins d\'un poussin jusqu\'à 19 semaines.', (p) => p.vaccinPoussin, (p, v) => p.vaccinPoussin = v),
  _Champ('chauffage', 'Chauffage et éclairage (élevage)', 'F/poussin',
      'Chauffage des premières semaines (lampes, charbon, gaz) par poussin.', (p) => p.chauffage, (p, v) => p.chauffage = v),
  _Champ('litiere', 'Litière, eau, électricité (élevage)', 'F/poussin',
      'Copeaux ou paille, eau et courant, pour un poussin pendant tout l\'élevage.', (p) => p.litiere, (p, v) => p.litiere = v),
  _Champ('transport', 'Transport des poussins', 'F/poussin',
      'Frais pour amener les poussins jusqu\'à votre ferme, par poussin.', (p) => p.transport, (p, v) => p.transport = v),
  _Champ('vaccinPouleMois', 'Vaccins et médicaments (ponte)', 'F/poule/mois',
      'Soins et vitamines pour une poule chaque mois pendant la ponte.', (p) => p.vaccinPouleMois, (p, v) => p.vaccinPouleMois = v),
  _Champ('eclairagePouleMois', 'Éclairage, eau, électricité (ponte)', 'F/poule/mois',
      'Courant, eau et éclairage, par poule et par mois pendant la ponte.', (p) => p.eclairagePouleMois, (p, v) => p.eclairagePouleMois = v),
  _Champ('emballagePlateau', 'Emballage', 'F/plateau',
      'Prix du plateau en carton ou plastique et du sac, pour chaque plateau vendu.', (p) => p.emballagePlateau, (p, v) => p.emballagePlateau = v),
  _Champ('mainOeuvreMois', 'Main-d\'œuvre (0 si vous travaillez seul)', 'F/mois',
      'Salaire du ou des ouvriers chaque mois. Mettez 0 si vous faites tout vous-même, mais pensez que votre temps a une valeur.',
      (p) => p.mainOeuvreMois, (p, v) => p.mainOeuvreMois = v),
  _Champ('imprevus', 'Marge pour imprévus', '%',
      'Une petite réserve pour les dépenses qu\'on n\'a pas prévues (pannes, soins urgents). 3 à 5 % est courant.', (p) => p.imprevus, (p, v) => p.imprevus = v),
];

final _champsMateriel = <_Champ>[
  _Champ('materielPoule', 'Matériel (cages, mangeoires, abreuvoirs…)', 'F/poule',
      'Ce que coûte le matériel, divisé par le nombre de poules. Exemple : 3 000 000 F pour 1 000 poules = 3 000 F par poule.',
      (p) => p.materielPoule, (p, v) => p.materielPoule = v),
  _Champ('dureeMaterielMois', 'Durée de vie du matériel', 'mois',
      'Pendant combien de mois le matériel sert avant d\'être remplacé. Seule la part utilisée pendant ce cycle est comptée.',
      (p) => p.dureeMaterielMois, (p, v) => p.dureeMaterielMois = v),
];

final _champsBatiment = <_Champ>[
  _Champ('batimentPoule', 'Bâtiment (poulailler)', 'F/poule',
      'Coût de construction (ou de location), divisé par le nombre de poules.', (p) => p.batimentPoule, (p, v) => p.batimentPoule = v),
  _Champ('dureeBatimentMois', 'Durée de vie du bâtiment', 'mois',
      'Pendant combien de mois le bâtiment sert. Seule la part utilisée pendant ce cycle est comptée.',
      (p) => p.dureeBatimentMois, (p, v) => p.dureeBatimentMois = v),
];

final _champsCredit = <_Champ>[
  _Champ('creditMontant', 'Montant emprunté', 'F', 'La somme que l\'on vous prête.', (p) => p.creditMontant, (p, v) => p.creditMontant = v),
  _Champ('creditTaux', 'Taux d\'intérêt par an', '%', 'Le taux annuel demandé. Les microfinances demandent souvent 12 à 24 % par an ; une banque 8 à 14 %.', (p) => p.creditTaux, (p, v) => p.creditTaux = v),
  _Champ('creditMois', 'Durée du crédit', 'mois', 'Sur combien de mois vous remboursez.', (p) => p.creditMois, (p, v) => p.creditMois = v),
  _Champ('creditDiffere', 'Différé', 'mois', 'Les premiers mois où vous ne payez que les intérêts (utile pendant l\'élevage, quand vous ne vendez encore rien).', (p) => p.creditDiffere, (p, v) => p.creditDiffere = v),
  _Champ('creditFrais', 'Frais de dossier', '%', 'Frais payés une fois au début, en pourcentage du montant emprunté.', (p) => p.creditFrais, (p, v) => p.creditFrais = v),
];

final _tousChamps = <_Champ>[
  ..._champsCredit, ..._champsProjet, ..._champsSacs, ..._champsConsommation, ..._champsMaison,
  ..._champsPerformance, ..._champsCouts, ..._champsMateriel, ..._champsBatiment,
];

class _DialoguePondeuses extends StatefulWidget {
  const _DialoguePondeuses();

  @override
  State<_DialoguePondeuses> createState() => _DialoguePondeusesState();
}

class _DialoguePondeusesState extends State<_DialoguePondeuses> {
  final ParamsPondeuses _p = ParamsPondeuses();
  final Map<String, TextEditingController> _ctl = {};
  final Set<String> _aides = {};
  String _race = racesPondeuses.first.nom;
  bool _simple = true;
  late ResultatPondeuses _r;
  // « Et si… » (non sauvegardé) : variations en %
  double _siAliment = 0, _siPrix = 0, _siPertes = 0, _siPonte = 0;

  @override
  void initState() {
    super.initState();
    for (final c in _tousChamps) {
      _ctl[c.cle] = TextEditingController();
    }
    _r = PrevisionPondeuses.calculer(_p);
    _remplirChamps();
    _charger();
    FormulesAliment.charger().then((_) {
      _p.boost = FormulesAliment.boost;
      if (mounted) setState(() => _r = PrevisionPondeuses.calculer(_p));
    });
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _texte(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _remplirChamps() {
    for (final c in _tousChamps) {
      _ctl[c.cle]!.text = _texte(c.lire(_p));
    }
  }

  Future<void> _charger() async {
    try {
      final brut = await Parametres.lire(_cleSauvegarde);
      if (brut.isEmpty) return;
      final m = jsonDecode(brut) as Map<String, dynamic>;
      for (final c in _tousChamps) {
        final v = m[c.cle];
        if (v is num) c.ecrire(_p, v.toDouble());
      }
      _p.avecMateriel = m['avecMateriel'] == true;
      _p.avecBatiment = m['avecBatiment'] == true;
      _p.alimentMaison = m['alimentMaison'] == true;
      _p.avecCredit = m['avecCredit'] == true;
      final a = m['arrivee'];
      if (a is String && a.isNotEmpty) _p.arrivee = DateTime.tryParse(a);
      final r = m['race'];
      if (r is String && racesPondeuses.any((x) => x.nom == r)) _race = r;
      if (!mounted) return;
      setState(() {
        _simple = m['simple'] != false;
        _remplirChamps();
        _r = PrevisionPondeuses.calculer(_p);
      });
    } catch (_) {}
  }

  Future<void> _sauver() async {
    try {
      final m = <String, dynamic>{
        for (final c in _tousChamps) c.cle: c.lire(_p),
        'avecMateriel': _p.avecMateriel,
        'avecBatiment': _p.avecBatiment,
        'alimentMaison': _p.alimentMaison,
        'avecCredit': _p.avecCredit,
        'arrivee': _p.arrivee?.toIso8601String() ?? '',
        'race': _race,
        'simple': _simple,
      };
      await Parametres.ecrire(_cleSauvegarde, jsonEncode(m));
    } catch (_) {}
  }

  void _recalculer() {
    setState(() => _r = PrevisionPondeuses.calculer(_p));
    _sauver();
  }

  void _surSaisie(_Champ c, String t) {
    final v = double.tryParse(t.replaceAll(',', '.').replaceAll(' ', ''));
    if (v == null || v < 0) return;
    c.ecrire(_p, v);
    _recalculer();
  }

  void _choisirRace(String nom) {
    final r = racesPondeuses.firstWhere((x) => x.nom == nom);
    _race = nom;
    _p.pic = r.pic;
    _p.declin = r.declin;
    _p.g1 = r.g1;
    _p.g2 = r.g2;
    _p.g3 = r.g3;
    _p.gPonte = r.gPonte;
    _p.mortElevage = r.mortElevage;
    _p.mortPonteMois = r.mortPonteMois;
    _remplirChamps();
    _recalculer();
  }

  void _reinitialiser() {
    final d = ParamsPondeuses();
    for (final c in _tousChamps) {
      c.ecrire(_p, c.lire(d));
    }
    _p.avecMateriel = false;
    _p.avecBatiment = false;
    _p.alimentMaison = false;
    _p.avecCredit = false;
    _p.arrivee = null;
    _race = racesPondeuses.first.nom;
    _remplirChamps();
    _recalculer();
  }

  /// Reprend les prix des ingrédients saisis dans l'onglet Prévisions (maïs, soja, son, poisson, coquilles, prémix, sel).
  Future<void> _vraisPrix() async {
    await Previsions.charger();
    _p.mais = Previsions.mais;
    _p.soja = Previsions.soja;
    _p.son = Previsions.son;
    _p.poisson = Previsions.poisson;
    _p.coquille = Previsions.coquille;
    _p.premix = Previsions.premix;
    _p.sel = Previsions.sel;
    await FormulesAliment.charger();
    _p.huile = FormulesAliment.prixDe('huile');
    _p.premixPonte = FormulesAliment.prixDe('premixPonte');
    _p.boost = FormulesAliment.boost;
    _p.alimentMaison = true;
    _remplirChamps();
    _recalculer();
    if (mounted) {
      Toast.afficher(context, 'Prix des ingrédients repris de l\'onglet Prévisions. Aliment fabriqué activé.',
          couleur: Palette.de(context).succes, dureeMs: 3200);
    }
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _p.arrivee ?? maintenant,
      firstDate: DateTime(maintenant.year - 1),
      lastDate: DateTime(maintenant.year + 4),
      helpText: 'Date d\'arrivée des poussins',
    );
    if (d == null) return;
    _p.arrivee = DateTime(d.year, d.month, d.day);
    _recalculer();
  }

  Future<void> _exporterPdf() async {
    try {
      if (await PdfPondeuses.exporter(_p, _race) && mounted) {
        Toast.afficher(context, '🥚 Prévision PDF enregistrée.', couleur: Palette.de(context).succes);
      }
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', 'Détails : $e');
    }
  }

  void _basculerAide(String cle) => setState(() => _aides.contains(cle) ? _aides.remove(cle) : _aides.add(cle));

  // ------------------------------------------------------------------ construction

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final taille = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: p.fond,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1180, maxHeight: taille.height * 0.92),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
              child: Row(children: [
                Expanded(
                  child: Text('🥚 Pondeuses d\'œufs de table — prévision',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Simple')),
                    ButtonSegment(value: false, label: Text('Détaillé')),
                  ],
                  selected: {_simple},
                  onSelectionChanged: (s) {
                    setState(() => _simple = s.first);
                    _sauver();
                  },
                ),
                const SizedBox(width: 6),
                TextButton.icon(onPressed: _exporterPdf, icon: const Icon(Icons.picture_as_pdf, size: 18), label: const Text('Exporter en PDF')),
                TextButton(onPressed: _reinitialiser, child: const Text('Valeurs de départ')),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Divider(height: 1, color: p.bordure),
            Expanded(
              child: LayoutBuilder(builder: (ctx, c) {
                final large = c.maxWidth > 820;
                if (large) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 430, child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: _contenuSaisie(p))),
                    VerticalDivider(width: 1, color: p.bordure),
                    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: _contenuResultats(p))),
                  ]);
                }
                return ListView(children: [
                  Padding(padding: const EdgeInsets.all(12), child: _contenuSaisie(p)),
                  Divider(color: p.bordure),
                  Padding(padding: const EdgeInsets.all(12), child: _contenuResultats(p)),
                ]);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titre(Palette p, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
      );

  Widget _boutonAide(Palette p, String cle) => InkResponse(
        onTap: () => _basculerAide(cle),
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 2),
          child: Icon(_aides.contains(cle) ? Icons.help : Icons.help_outline, size: 16, color: p.cuivre),
        ),
      );

  Widget _texteAide(Palette p, String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.bordure)),
        child: Text(t, style: TextStyle(fontSize: 11, color: p.txtDoux)),
      );

  Widget _ligneChamp(Palette p, _Champ c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(c.label, style: TextStyle(fontSize: 12, color: p.txtPrinc))),
            _boutonAide(p, c.cle),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _ctl[c.cle],
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                onChanged: (t) => _surSaisie(c, t),
              ),
            ),
            SizedBox(
              width: 78,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(c.unite, style: TextStyle(fontSize: 10, color: p.txtGris)),
              ),
            ),
          ]),
        ),
        if (_aides.contains(c.cle)) _texteAide(p, c.aide),
      ]);

  Widget _caseACocher(Palette p, String cle, String titre, String aide, bool valeur, ValueChanged<bool> onChange) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: CheckboxListTile(
              value: valeur,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: p.cuivre,
              title: Text(titre, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
              onChanged: (v) => onChange(v ?? false),
            ),
          ),
          _boutonAide(p, cle),
        ]),
        if (_aides.contains(cle)) _texteAide(p, aide),
      ]);

  Widget _contenuSaisie(Palette p) {
    final detail = !_simple;
    final dateTxt = _p.arrivee == null ? 'Choisir une date' : dateLongue(_p.arrivee!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
        child: Text(
          'Simulation libre : rien n\'est lu dans vos bandes ni vos ventes. Les chiffres proposés sont des exemples '
          'courants : remplacez-les par vos vrais prix. Cliquez sur le « ? » à côté d\'un champ pour comprendre à quoi il sert.'
          '${_simple ? '\n\nMode Simple : seulement l\'essentiel. Passez en Détaillé pour tout régler.' : ''}',
          style: TextStyle(fontSize: 11, color: p.txtDoux),
        ),
      ),
      _titre(p, 'RACE (remplit les valeurs de départ)'),
      DropdownButtonFormField<String>(
        value: _race,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [for (final r in racesPondeuses) DropdownMenuItem(value: r.nom, child: Text(r.nom, style: const TextStyle(fontSize: 13)))],
        onChanged: (v) {
          if (v != null) _choisirRace(v);
        },
      ),
      _titre(p, 'DATE D\'ARRIVÉE DES POUSSINS'),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _choisirDate,
            icon: const Icon(Icons.event, size: 18),
            label: Text(dateTxt),
          ),
        ),
        if (_p.arrivee != null)
          IconButton(
            tooltip: 'Effacer la date',
            onPressed: () {
              _p.arrivee = null;
              _recalculer();
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        _boutonAide(p, 'date'),
      ]),
      if (_aides.contains('date'))
        _texteAide(p, 'Avec la date d\'arrivée, le logiciel vous dit quand commence la ponte, quand elle finit, '
            'quels mois tombent en saison chaude, et il écrit les vrais mois dans les tableaux.'),
      _titre(p, 'VOTRE PROJET'),
      for (final c in _champsProjet)
        if (detail || c.cle != 'dureePonteSem') _ligneChamp(p, c),
      _titre(p, 'ALIMENT'),
      _caseACocher(p, 'maison', 'Je fabrique mon propre aliment',
          'Au lieu d\'acheter des sacs tout faits, vous mélangez vous-même maïs, soja, son, poisson, coquilles et prémix. '
          'Le logiciel calcule le prix du sac fabriqué et le compare au sac acheté. Les recettes sont des exemples : '
          'faites-les valider par votre fournisseur de prémix ou un vétérinaire.',
          _p.alimentMaison, (v) {
        _p.alimentMaison = v;
        _recalculer();
      }),
      if (!_p.alimentMaison) for (final c in _champsSacs) _ligneChamp(p, c),
      if (_p.alimentMaison) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _vraisPrix,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Utiliser mes vrais prix (onglet Prévisions)'),
          ),
        ),
        for (final c in _champsMaison) _ligneChamp(p, c),
        const SizedBox(height: 4),
        Text('Prix du sac de 50 kg fabriqué :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        for (final e in [('Démarrage', 0), ('Croissance', 1), ('Développement', 2), ('Pondeuse', 3)])
          Text('•  ${e.$1} : ${fmtF(_p.coutKgMaison(e.$2) * 50)}', style: TextStyle(fontSize: 11, color: p.txtDoux)),
      ],
      if (detail) ...[
        _titre(p, 'CONSOMMATION DES POULES'),
        for (final c in _champsConsommation) _ligneChamp(p, c),
        _titre(p, 'PERFORMANCES'),
        for (final c in _champsPerformance)
          if (c.cle != 'baisseChaleur' || _p.arrivee != null) _ligneChamp(p, c),
        _titre(p, 'AUTRES COÛTS'),
        for (final c in _champsCouts) _ligneChamp(p, c),
      ],
      _titre(p, 'MATÉRIEL ET BÂTIMENT (facultatif)'),
      _caseACocher(p, 'cmat', 'Compter le matériel',
          'Cages, mangeoires, abreuvoirs, éclairage... Cochez si vous devez les acheter. Leur prix est étalé sur leur durée de vie.',
          _p.avecMateriel, (v) {
        _p.avecMateriel = v;
        _recalculer();
      }),
      if (_p.avecMateriel) for (final c in _champsMateriel) _ligneChamp(p, c),
      _caseACocher(p, 'cbat', 'Compter le bâtiment',
          'Le poulailler. Cochez si vous devez le construire ou le louer. Si vous l\'avez déjà et qu\'il ne vous coûte rien, laissez décoché.',
          _p.avecBatiment, (v) {
        _p.avecBatiment = v;
        _recalculer();
      }),
      if (_p.avecBatiment) for (final c in _champsBatiment) _ligneChamp(p, c),
      _titre(p, 'FINANCEMENT (facultatif)'),
      _caseACocher(p, 'ccred', 'Je finance avec un crédit',
          'Cochez si vous empruntez à une banque, une institution de microfinance ou un proche. Le logiciel calcule la mensualité, le coût du crédit, l\'apport qu\'il vous reste à mettre et si le projet peut rembourser.',
          _p.avecCredit, (v) {
        _p.avecCredit = v;
        _recalculer();
      }),
      if (_p.avecCredit) ...[
        for (final c in _champsCredit) _ligneChamp(p, c),
        Text(_suggestionCredit(), style: TextStyle(fontSize: 11, color: p.txtDoux)),
      ],
      Text('Le coût est étalé sur la durée de vie : seule la part correspondant à ce cycle est comptée.',
          style: TextStyle(fontSize: 10, color: p.txtGris)),
    ]);
  }

  // ------------------------------------------------------------------ résultats

  Widget _carte(Palette p, String cle, String titre, String valeur, String aide, {String? detail, Color? couleur}) {
    final ouvert = _aides.contains('k$cle');
    return InkWell(
      onTap: () => _basculerAide('k$cle'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(titre, style: TextStyle(fontSize: 10, color: p.txtGris))),
            Icon(ouvert ? Icons.help : Icons.help_outline, size: 14, color: p.cuivre),
          ]),
          const SizedBox(height: 4),
          Text(valeur, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: couleur ?? p.txtPrinc)),
          if (detail != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: TextStyle(fontSize: 10, color: p.txtDoux))),
          if (ouvert)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(aide, style: TextStyle(fontSize: 10, color: p.txtDoux, fontStyle: FontStyle.italic))),
        ]),
      ),
    );
  }

  Widget _ligne(Palette p, String a, String b, {bool gras = false, String c = '', String d = ''}) {
    final st = TextStyle(fontSize: 12, color: p.txtPrinc, fontWeight: gras ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 5, child: Text(a, style: st)),
        if (c.isNotEmpty) Expanded(flex: 2, child: Text(c, textAlign: TextAlign.right, style: st)),
        if (d.isNotEmpty) Expanded(flex: 2, child: Text(d, textAlign: TextAlign.right, style: st)),
        Expanded(flex: 3, child: Text(b, textAlign: TextAlign.right, style: st)),
      ]),
    );
  }

  /// Une ligne de tableau à colonnes libres : (texte, largeur relative).
  Widget _ligneN(Palette p, List<(String, int)> cases, {bool gras = false, Color? couleur}) {
    final st = TextStyle(fontSize: 11, color: couleur ?? p.txtPrinc, fontWeight: gras ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cases.length; i++)
          Expanded(flex: cases[i].$2, child: Text(cases[i].$1, textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: st)),
      ]),
    );
  }

  String _suggestionCredit() {
    final c = _p.copie();
    c.avecCredit = false;
    final b = PrevisionPondeuses.calculer(c).besoinFinancement;
    if (b <= 0) return 'Sans crédit, ce projet n\'a pas besoin d\'argent de départ.';
    return 'Sans crédit, il faut avoir ${fmtF(b.roundToDouble())} avant de commencer. Un crédit de 70 % serait d\'environ ${fmtF((b * 0.7 / 1000).round() * 1000.0)}.';
  }

  /// Le crédit : chiffres et échéancier.
  List<Widget> _blocCredit(Palette p, ResultatPondeuses r) {
    final e = r.credit;
    if (e == null) return [];
    final s = sectionCredit(e, r.besoinFinancement);
    final t = tableauCredit(e);
    return [
      _titre(p, '⑪ ${s.titre}'),
      for (final l in s.lignes) _ligne(p, l.$1, l.$2),
      const Divider(),
      _ligne(p, s.total!.$1, s.total!.$2, gras: true),
      _titre(p, '⑫ ${t.titre}'),
      _noteTableau(p, t.note),
      _ligneN(p, [for (var i = 0; i < t.entetes.length; i++) (t.entetes[i], t.flex[i])], gras: true),
      for (final l in t.lignes) _ligneN(p, [for (var i = 0; i < l.length; i++) (l[i], t.flex[i])]),
    ];
  }

  /// Aliment mois par mois (kilos par jour, kilos du mois, sacs, coût), d'après les formules de la bibliothèque.
  List<Widget> _tableauAliment(Palette p, ResultatPondeuses r) {
    final t = tableauConso('⑩ ALIMENT MOIS PAR MOIS (depuis l\'arrivée des poussins)',
        'Le mois 1 commence le jour de l\'arrivée des poussins : les premiers mois sont l\'élevage, puis vient la ponte. '
        '« Par jour » est la moyenne du mois pour tout le troupeau, puis pour une seule poule. Les sacs sont les sacs de 50 kg à commander.',
        r.conso, periode: 'Mois');
    return [
      _titre(p, t.titre),
      _noteTableau(p, t.note),
      _ligneN(p, [for (var i = 0; i < t.entetes.length; i++) (t.entetes[i], t.flex[i])], gras: true),
      for (final l in t.lignes) _ligneN(p, [for (var i = 0; i < l.length; i++) (l[i], t.flex[i])]),
    ];
  }

  Widget _noteTableau(Palette p, String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 11, color: p.txtDoux)),
      );

  String _cumulClair(double c) => c < 0 ? '${fmtF(c.abs())} avancés' : '${fmtF(c)} gagnés';

  Widget _contenuResultats(Palette p) {
    final r = _r;
    final gain = r.benefice >= 0;
    final pm = r.moisPointMort;
    final detail = !_simple;
    final sc = AnalysePondeuses.scenarios(_p);
    final v = AnalysePondeuses.verdict(_p, sc);
    final seuils = AnalysePondeuses.seuils(_p, r);
    final arr = _p.arrivee;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _bandeauVerdict(p, v),
      const SizedBox(height: 12),
      Text('Cliquez sur une carte pour comprendre ce qu\'elle veut dire.', style: TextStyle(fontSize: 10, color: p.txtGris)),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (arr != null)
          _carte(p, 'oeuf', 'PREMIERS ŒUFS', dateLongue(arr.add(const Duration(days: semainesDebutPonte * 7))),
              'Les poules commencent à pondre à $semainesDebutPonte semaines d\'âge. Avant cette date, vous dépensez sans rien vendre.',
              detail: 'Arrivée des poussins : ${dateLongue(arr)}'),
        _carte(p, 'poule', 'COÛT D\'UNE POULE PRÊTE À PONDRE', fmtF(r.coutParPoule),
            'Tout ce qu\'une poule vous a coûté (poussin, aliment, vaccins...) entre son arrivée et ses 19 semaines. C\'est ce que vaudrait une poulette prête à pondre.',
            detail: '${_texte(r.survivantes.roundToDouble())} poules à 19 semaines'),
        _carte(p, 'plateau', 'COÛT DE REVIENT D\'UN PLATEAU', fmtF(r.coutPlateau),
            'Ce que vous coûte un plateau de 30 œufs, en comptant toutes les dépenses du cycle (moins la vente des poules de réforme). Vendez au-dessus de ce prix pour gagner.',
            detail: 'Vente prévue : ${fmtF(_p.prixPlateau)}', couleur: r.coutPlateau <= _p.prixPlateau ? p.succes : p.danger),
        _carte(p, 'benef', gain ? 'BÉNÉFICE DU CYCLE' : 'PERTE DU CYCLE', fmtF(r.benefice),
            'Ce qui reste en poche à la fin du cycle : toutes les ventes moins toutes les dépenses.',
            detail: 'Dépenses ${fmtF(r.coutTotal)}', couleur: gain ? p.succes : p.danger),
        _carte(p, 'mois', 'BÉNÉFICE MOYEN PAR MOIS DE PONTE', fmtF(r.beneficeMensuelPonte),
            'Bénéfice divisé par les mois de ponte. Il ne compte pas la période d\'élevage, où vous ne vendez rien.',
            detail: 'Sans compter la phase d\'élevage', couleur: r.beneficeMensuelPonte >= 0 ? p.succes : p.danger),
        _carte(p, 'fonds', 'ARGENT À AVOIR AVANT DE COMMENCER', fmtF(r.besoinFinancement),
            'Le point le plus bas de votre trésorerie : c\'est la somme que vous devez avoir de côté (ou emprunter) pour tenir sans être bloqué.',
            detail: 'Le point le plus bas de votre trésorerie'),
        _carte(p, 'recup', 'ARGENT RÉCUPÉRÉ', pm == null ? 'Pas dans ce cycle' : libelleMois(arr, pm),
            'Le mois où les ventes ont remboursé tout l\'argent avancé depuis le début.',
            detail: 'Sur ${r.moisTotal} mois en tout', couleur: pm == null ? p.danger : p.txtPrinc),
        if (r.credit != null)
          for (final c in cartesCredit(r.credit!, r.benefice))
            _carte(p, c.cle, c.titre, c.valeur, c.aide, detail: c.detail, couleur: c.ton == 1 ? p.succes : (c.ton == 2 ? p.danger : null)),
      ]),
      _titre(p, '① SEUIL DE RENTABILITÉ : LES LIMITES À NE PAS DÉPASSER'),
      _blocSeuils(p, seuils, r),
      _titre(p, '② TROIS SITUATIONS POSSIBLES'),
      _ligne(p, 'Situation', 'Argent à avoir', c: 'Bénéfice', d: 'Plateau', gras: true),
      for (final s in sc) ...[
        _ligne(p, s.nom, fmtF(s.r.besoinFinancement), c: fmtF(s.r.benefice, unite: ''), d: fmtF(s.r.coutPlateau, unite: ''), gras: s.nom == 'Normal'),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s.description, style: TextStyle(fontSize: 10, color: p.txtGris))),
      ],
      _titre(p, '③ ET SI… ? (faites glisser)'),
      _blocEtSi(p),
      _titre(p, '④ TRÉSORERIE : ARGENT GAGNÉ OU AVANCÉ'),
      SizedBox(
        height: 190,
        child: CustomPaint(
          size: Size.infinite,
          painter: _PeintreTresorerie([for (final m in r.mois) m.cumul], p),
        ),
      ),
      const SizedBox(height: 4),
      Text('Sous la ligne : vous avez de l\'argent avancé. Au-dessus : vous avez tout récupéré et vous gagnez.',
          style: TextStyle(fontSize: 10, color: p.txtGris)),
      if (detail) ...[
        _titre(p, '⑤ DU POUSSIN À 19 SEMAINES (ÉLEVAGE)'),
        _ligne(p, 'Étape', 'Coût', c: 'Sacs', d: 'kg/poule', gras: true),
        for (final e in r.etapes)
          _ligne(p, e.nom, fmtF(e.cout), c: _texte(double.parse(e.sacs.toStringAsFixed(1))), d: _texte(double.parse(e.kgParPoule.toStringAsFixed(2)))),
        for (final a in r.autresCoutsA) _ligne(p, a.$1, fmtF(a.$2)),
        Divider(color: p.bordure),
        _ligne(p, 'Total élevage', fmtF(r.totalA), gras: true),
        _titre(p, '⑥ LA PONTE'),
        _ligne(p, 'Œufs vendables (après casse)', _texte(r.oeufs.roundToDouble())),
        _ligne(p, 'Plateaux de 30', _texte(r.plateaux.roundToDouble())),
        _ligne(p, 'Aliment consommé', '${_texte(r.kgAlimentB.roundToDouble())} kg (${_texte(double.parse(r.sacsB.toStringAsFixed(0)))} sacs)'),
        for (final a in r.coutsB) _ligne(p, a.$1, fmtF(a.$2)),
        Divider(color: p.bordure),
        _ligne(p, 'Total ponte', fmtF(r.totalB), gras: true),
        _titre(p, '⑦ CE QUE VOUS ENCAISSEZ'),
        _ligne(p, 'Vente des plateaux', fmtF(r.recettePlateaux)),
        _ligne(p, 'Vente de ${_texte(r.pouleReforme.roundToDouble())} poules de réforme', fmtF(r.recetteReforme)),
        Divider(color: p.bordure),
        _ligne(p, 'Total recettes', fmtF(r.recetteTotale), gras: true),
        _ligne(p, gain ? 'Bénéfice' : 'Perte', fmtF(r.benefice), gras: true),
        _titre(p, '⑧ PRODUCTION PENDANT LA PONTE (mois de ponte)'),
        _noteTableau(p,
            'Ce tableau ne parle que de la ponte. Le « mois de ponte 1 » est le premier mois où les poules pondent : '
            'il commence $semainesDebutPonte semaines après l\'arrivée des poussins (voir la date des premiers œufs plus haut).\n'
            '• Poules vivantes : combien il vous reste de poules ce mois-là.\n'
            '• Taux de ponte : sur 100 poules, combien pondent chaque jour. 90 % = 90 œufs par jour pour 100 poules.\n'
            '• Plateaux par jour : combien de plateaux de 30 œufs vous avez à vendre chaque jour (œufs cassés déjà retirés).\n'
            '• Plateaux dans le mois : le total du mois.'),
        _ligneN(p, [('Mois de ponte', 4), ('Poules vivantes', 2), ('Taux de ponte', 2), ('Plateaux par jour', 2), ('Plateaux dans le mois', 2)], gras: true),
        for (final m in AnalysePondeuses.profilPonte(_p, r))
          _ligneN(p, [
            (libelleMois(arr, m.mois, decalageSemaines: semainesDebutPonte, prefixe: 'Mois de ponte'), 4),
            (_texte(m.poules.roundToDouble()), 2),
            ('${m.taux.round()} %', 2),
            (_texte(m.plateauxJour.roundToDouble()), 2),
            (_texte(m.plateauxMois.roundToDouble()), 2),
          ]),
        _titre(p, '⑨ ARGENT MOIS PAR MOIS (depuis l\'arrivée des poussins)'),
        _noteTableau(p,
            'Ce tableau compte depuis le jour où les poussins arrivent : le « mois 1 » est donc le premier mois d\'élevage, '
            'avant que les poules ne pondent. Ce n\'est pas le même comptage que le tableau de production.\n'
            '• Dépenses du mois : tout ce que vous payez ce mois-là.\n'
            '• Recettes du mois : tout ce que vous encaissez ce mois-là (les premières recettes arrivent quand la ponte commence).\n'
            '• Argent depuis le début : le total gagné moins le total dépensé depuis le début. '
            '« Avancés » = vous avez encore de l\'argent investi ; « gagnés » = vous avez tout récupéré et vous êtes en bénéfice.'),
        _ligneN(p, [('Mois', 4), ('Étape', 3), ('Dépenses du mois', 3), ('Recettes du mois', 3), ('Argent depuis le début', 4)], gras: true),
        for (final m in r.mois)
          _ligneN(p, [
            (libelleMois(arr, m.mois), 4),
            (AnalysePondeuses.phaseMois(m.mois), 3),
            (fmtF(m.depenses), 3),
            (fmtF(m.recettes), 3),
            (_cumulClair(m.cumul), 4),
          ], couleur: m.cumul < 0 ? p.danger : p.succes),
        ..._tableauAliment(p, r),
        ..._blocCredit(p, r),
      ],
      _titre(p, 'CE QU\'IL FAUT RETENIR'),
      for (final c in v.constats) _puce(p, c),
      _titre(p, 'POINTS D\'ATTENTION'),
      for (final a in v.attention) _puce(p, a),
      if (_simple)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text('Pour voir tous les tableaux (élevage, ponte, trésorerie mois par mois), passez en mode Détaillé en haut.',
              style: TextStyle(fontSize: 11, color: p.txtGris)),
        ),
    ]);
  }

  Widget _blocSeuils(Palette p, SeuilsPondeuses s, ResultatPondeuses r) {
    String pct(double? v, String sinon) => v == null ? sinon : '${v.round()} %';
    final perdu = r.benefice <= 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tant que vous restez du bon côté de ces limites, vous ne perdez pas d\'argent sur le cycle.',
            style: TextStyle(fontSize: 11, color: p.txtDoux)),
        const SizedBox(height: 6),
        _ligne(p, 'Prix minimum d\'un plateau', fmtF(s.prixPlateauMin), gras: true),
        _ligne(p, 'Votre prix prévu', fmtF(_p.prixPlateau)),
        _ligne(p, 'Plateaux à vendre au minimum', '${_texte(s.plateauxMinTotal.ceilToDouble())} sur ${_texte(r.plateaux.roundToDouble())}'),
        _ligne(p, 'Soit', '${s.pctProduction.round()} % de la production'),
        _ligne(p, 'Plateaux minimum par jour de ponte', _texte(double.parse(s.plateauxMinJour.toStringAsFixed(1)))),
        _ligne(p, 'Taux de ponte maximal minimum', s.picMin == null ? 'Impossible, même à 99 %' : '${s.picMin!.round()} %'),
        _ligne(p, 'Hausse maximale du prix de l\'aliment', perdu ? 'Déjà dépassée' : pct(s.hausseAlimentMax, 'Plus de 500 %')),
        _ligne(p, 'Pertes maximales pendant l\'élevage', perdu ? 'Déjà dépassées' : pct(s.pertesElevageMax, 'Plus de 90 %')),
      ]),
    );
  }

  Widget _puce(Palette p, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: TextStyle(fontSize: 12, color: p.accent)),
          Expanded(child: Text(t, style: TextStyle(fontSize: 12, color: p.txtPrinc))),
        ]),
      );

  Widget _bandeauVerdict(Palette p, VerdictPondeuses v) {
    final couleur = v.niveau == 2 ? p.succes : (v.niveau == 1 ? p.alerte : p.danger);
    final icone = v.niveau == 2 ? '✅' : (v.niveau == 1 ? '⚠️' : '⛔');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        border: Border.all(color: couleur, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$icone  ${v.titre}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: couleur)),
        const SizedBox(height: 6),
        Text(v.resume, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
      ]),
    );
  }

  Widget _curseur(Palette p, String titre, double valeur, double min, double max, ValueChanged<double> onChange) => Row(children: [
        SizedBox(width: 150, child: Text(titre, style: TextStyle(fontSize: 11, color: p.txtPrinc))),
        Expanded(
          child: Slider(
            value: valeur,
            min: min,
            max: max,
            divisions: (max - min).round(),
            activeColor: p.cuivre,
            onChanged: (x) => setState(() => onChange(x.roundToDouble())),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text('${valeur > 0 ? '+' : ''}${valeur.round()} ${titre.contains('Ponte') ? 'pt' : '%'}',
              textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ),
      ]);

  Widget _blocEtSi(Palette p) {
    final base = _r;
    final v = PrevisionPondeuses.calculer(_p.varie(alimentPct: _siAliment, prixPct: _siPrix, pertesPct: _siPertes, picPoints: _siPonte));
    final diff = v.benefice - base.benefice;
    final aucun = _siAliment == 0 && _siPrix == 0 && _siPertes == 0 && _siPonte == 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _curseur(p, 'Prix de l\'aliment', _siAliment, -30, 50, (x) => _siAliment = x),
        _curseur(p, 'Prix du plateau', _siPrix, -40, 40, (x) => _siPrix = x),
        _curseur(p, 'Pertes (mortalité)', _siPertes, -50, 200, (x) => _siPertes = x),
        _curseur(p, 'Ponte maximale', _siPonte, -15, 5, (x) => _siPonte = x),
        const SizedBox(height: 6),
        _ligne(p, 'Bénéfice du cycle', fmtF(v.benefice), gras: true),
        _ligne(p, 'Coût d\'un plateau', fmtF(v.coutPlateau)),
        _ligne(p, 'Argent à avoir avant de commencer', fmtF(v.besoinFinancement)),
        if (!aucun)
          Text('${diff >= 0 ? 'Cela vous rapporte' : 'Cela vous coûte'} ${fmtF(diff.abs())} de ${diff >= 0 ? 'plus' : 'moins'} sur le cycle.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: diff >= 0 ? p.succes : p.danger)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: aucun ? null : () => setState(() => _siAliment = _siPrix = _siPertes = _siPonte = 0),
            child: const Text('Remettre à zéro'),
          ),
        ),
      ]),
    );
  }
}

/// Courbe de la trésorerie cumulée, mois par mois, avec la ligne du zéro.
class _PeintreTresorerie extends CustomPainter {
  final List<double> valeurs;
  final Palette p;
  _PeintreTresorerie(this.valeurs, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    if (valeurs.isEmpty) return;
    const gauche = 52.0, bas = 18.0, haut = 6.0, droite = 8.0;
    final w = size.width - gauche - droite, h = size.height - bas - haut;
    if (w <= 0 || h <= 0) return;
    var vmin = 0.0, vmax = 0.0;
    for (final v in valeurs) {
      if (v < vmin) vmin = v;
      if (v > vmax) vmax = v;
    }
    if (vmax - vmin < 1) vmax = vmin + 1;
    double y(double v) => haut + h * (1 - (v - vmin) / (vmax - vmin));
    double x(int i) => gauche + (valeurs.length == 1 ? w / 2 : w * i / (valeurs.length - 1));

    final grille = Paint()
      ..color = p.bordure
      ..strokeWidth = 1;
    final zero = Paint()
      ..color = p.txtGris
      ..strokeWidth = 1.5;
    void etiquette(String t, double px, double py, {bool droite = false}) {
      final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 9, color: p.txtGris)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(droite ? px - tp.width : px, py - tp.height / 2));
    }

    for (var k = 0; k <= 4; k++) {
      final v = vmin + (vmax - vmin) * k / 4;
      canvas.drawLine(Offset(gauche, y(v)), Offset(gauche + w, y(v)), grille);
      etiquette(formaterAxe(v), gauche - 4, y(v), droite: true);
    }
    canvas.drawLine(Offset(gauche, y(0)), Offset(gauche + w, y(0)), zero);

    final chemin = Path();
    for (var i = 0; i < valeurs.length; i++) {
      i == 0 ? chemin.moveTo(x(i), y(valeurs[i])) : chemin.lineTo(x(i), y(valeurs[i]));
    }
    canvas.drawPath(
        chemin,
        Paint()
          ..color = p.accent
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke);
    for (var i = 0; i < valeurs.length; i++) {
      canvas.drawCircle(Offset(x(i), y(valeurs[i])), 3, Paint()..color = valeurs[i] >= 0 ? p.succes : p.danger);
      if (i == 0 || (i + 1) % 2 == 0 || i == valeurs.length - 1) {
        etiquette('${i + 1}', x(i) - 3, size.height - 7);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreTresorerie old) => old.valeurs != valeurs || old.p != p;
}

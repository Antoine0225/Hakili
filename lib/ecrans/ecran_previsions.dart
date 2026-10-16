import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../metier/previsions.dart';
import '../services/pdf_previsions.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/champ_date.dart';
import '../widgets/dialogues.dart';
import '../widgets/icones.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/toast.dart';
import 'dialogue_formule.dart';
import 'dialogue_planificateur.dart';

const _orange = Color(0xFFD99A3D), _vertP = Color(0xFF4C7A4A), _bleu = Color(0xFF5A83A6), _rougeP = Color(0xFFAF5A4A);
const _entete = Color(0xFF877A66), _objectif = Color(0xFFABA49D), _txtDouxP = Color(0xFF98998E);
const _ecartVert = Color(0xFF547E4D), _ecartRouge = Color(0xFFAE513A);
const _txtP = Color(0xFF1A1F1C), _miniP = Color(0xFFF2EDE0), _pisteP = Color(0xFFE6DFCD);
const _couleursSegments = [Color(0xFFD99A3D), Color(0xFF4C7A4A), Color(0xFF5A83A6), Color(0xFFAF5A4A), Color(0xFF8A6D2F), Color(0xFF7A5C8A), Color(0xFF6F7D75), Color(0xFFB8651F)];

class EcranPrevisions extends StatefulWidget {
  const EcranPrevisions({super.key});

  @override
  State<EcranPrevisions> createState() => _EcranPrevisionsState();
}

class _EcranPrevisionsState extends State<EcranPrevisions> {
  int _onglet = 0;
  String _vue = 'attente'; // 'attente' | 'formule' | 'pilotage'
  bool _evaluationFaite = false;
  ResultatProjet? _res;
  bool _pret = false;
  final Map<String, TextEditingController> _c = {};
  String _derniereMaj = '';

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  Future<void> _initialiser() async {
    await Previsions.charger();
    String t(double v) => nombreCourt(v);
    _c.addAll({
      'mais': TextEditingController(text: t(Previsions.mais)),
      'soja': TextEditingController(text: t(Previsions.soja)),
      'son': TextEditingController(text: t(Previsions.son)),
      'poisson': TextEditingController(text: t(Previsions.poisson)),
      'coquille': TextEditingController(text: t(Previsions.coquille)),
      'sel': TextEditingController(text: t(Previsions.sel)),
      'premix': TextEditingController(text: t(Previsions.premix)),
      'sujets': TextEditingController(text: '${Previsions.nbSujets}'),
      'poussin': TextEditingController(text: t(Previsions.prixPoussin)),
      'sante': TextEditingController(text: t(Previsions.fraisSante)),
      'vif': TextEditingController(text: t(Previsions.prixVenteChair)),
      'oeuf': TextEditingController(text: t(Previsions.prixOeufFec)),
      'poussin1': TextEditingController(text: t(Previsions.prixPoussinUnJour)),
      'ponte': TextEditingController(text: t(Previsions.tauxPonte)),
      'eclosion': TextEditingController(text: t(Previsions.tauxEclosion)),
      'pertes': TextEditingController(text: '${Previsions.nbPertes}'),
    });
    if (mounted) setState(() => _pret = true);
  }

  @override
  void dispose() {
    Previsions.sauvegarder();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ lecture des champs
  double _n(String k, double defaut) {
    final v = double.tryParse(_c[k]!.text.trim().replaceAll(' ', '').replaceAll(',', '.'));
    return v ?? defaut;
  }

  void _lireChamps() {
    Previsions.mais = _n('mais', Previsions.mais);
    Previsions.soja = _n('soja', Previsions.soja);
    Previsions.son = _n('son', Previsions.son);
    Previsions.poisson = _n('poisson', Previsions.poisson);
    Previsions.coquille = _n('coquille', Previsions.coquille);
    Previsions.sel = _n('sel', Previsions.sel);
    Previsions.premix = _n('premix', Previsions.premix);
    Previsions.nbSujets = _n('sujets', Previsions.nbSujets.toDouble()).toInt();
    Previsions.prixPoussin = _n('poussin', Previsions.prixPoussin);
    Previsions.fraisSante = _n('sante', Previsions.fraisSante);
    Previsions.prixVenteChair = _n('vif', Previsions.prixVenteChair);
    Previsions.prixOeufFec = _n('oeuf', Previsions.prixOeufFec);
    Previsions.prixPoussinUnJour = _n('poussin1', Previsions.prixPoussinUnJour);
    Previsions.tauxPonte = _n('ponte', Previsions.tauxPonte);
    Previsions.tauxEclosion = _n('eclosion', Previsions.tauxEclosion);
    Previsions.nbPertes = _n('pertes', Previsions.nbPertes.toDouble()).toInt();
  }

  String _heure() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------------ actions
  Future<void> _evaluer() async {
    _lireChamps();
    final r = await Previsions.calculer();
    await Previsions.sauvegarder();
    if (!mounted) return;
    setState(() {
      _res = r;
      _evaluationFaite = true;
      _vue = 'pilotage';
      _derniereMaj = _heure();
    });
  }

  void _montrerFormule(String etape) {
    _lireChamps();
    Previsions.derniereEtape = etape;
    setState(() {
      _vue = 'formule';
      _derniereMaj = _heure();
    });
  }

  /// Ouvre la fenêtre « Ma formule » ; si la formule change, les chiffres déjà affichés sont recalculés sur place.
  Future<void> _editerFormule(String etape, String titre) async {
    _lireChamps();
    final change = await editerFormulePerso(context, etape, titre);
    if (!change || !mounted) return;
    ResultatProjet? r;
    if (_evaluationFaite) r = await Previsions.calculer();
    if (!mounted) return;
    setState(() {
      if (r != null) _res = r;
      _derniereMaj = _heure();
    });
    Toast.afficher(context, '✅ Formule mise à jour.', couleur: Palette.de(context).succes);
  }

  /// Planificateur de fête : calcule à l'envers quand recevoir les poussins, quoi acheter et ce que cela rapporte.
  Future<void> _planifier() async {
    _lireChamps();
    if (!Previsions.chair) {
      Dialogues.info(context, 'Planificateur de fête',
          "Le planificateur est prévu pour l'élevage de chair (poulets à vendre à une date précise).\n\n"
          'Pour une ferme de pondeuses, dites-nous ce dont vous avez besoin : nous pouvons ajouter un planificateur adapté aux œufs.');
      return;
    }
    final plan = await ouvrirPlanificateur(context);
    if (plan == null || !mounted) return;
    // « Utiliser dans Prévisions » : on reprend le nombre de poussins, les pertes prévues et la durée
    Previsions.nbSujets = plan.poussins;
    Previsions.nbPertes = plan.poussins - plan.cible;
    Previsions.dureeChair = plan.cycle;
    _c['sujets']?.text = '${plan.poussins}';
    _c['pertes']?.text = '${plan.poussins - plan.cible}';
    await Previsions.sauvegarder();
    if (!mounted) return;
    if (_evaluationFaite) {
      await _evaluer();
    } else {
      setState(() {});
    }
    if (mounted) {
      Toast.afficher(context, '📋 Prévisions mises à jour avec votre plan (${plan.poussins} poussins).',
          couleur: Palette.de(context).succes, dureeMs: 2600);
    }
  }

  void _filiereChangee() {
    _lireChamps();
    setState(() {});
    if (_vue == 'formule') {
      _montrerFormule(Previsions.derniereEtape);
    } else if (_evaluationFaite) {
      _evaluer();
    }
  }

  void _sliderChange() {
    _lireChamps();
    setState(() {
      _vue = 'formule';
      _derniereMaj = _heure();
    });
  }

  Future<void> _pdf() async {
    _lireChamps();
    try {
      if (await PdfPrevisions.exporter() && mounted) {
        Toast.afficher(context, '🔥 Rapport PDF enregistré.', couleur: Palette.de(context).succes);
      }
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', 'Détails : $e');
    }
  }

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    if (!_pret) return const SizedBox.shrink();
    return MiseEnPageModule(
      gauche: Column(children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [_barreOnglets(p), Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(5), child: _contenuOnglet(p)))]),
          ),
        ),
        SizedBox(
          width: double.infinity, height: 45,
          child: FilledButton(
            onPressed: _evaluer,
            style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('🔥 ÉVALUER ET CALCULER LE PROJET', style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 45,
          child: FilledButton(
            onPressed: _pdf,
            style: FilledButton.styleFrom(backgroundColor: p.succes, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('📊 GÉNÉRER LE RAPPORT PDF ET LES GRAPHES', style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 40,
          child: OutlinedButton(
            onPressed: _planifier,
            style: OutlinedButton.styleFrom(
                foregroundColor: p.cuivre, side: BorderSide(color: p.cuivre, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('📅 PLANIFIER UNE FÊTE (Tabaski, Noël…)', style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
      droite: _droite(p),
    );
  }

  Widget _barreOnglets(Palette p) {
    const noms = [' 🌽 Prix Intrants ', ' 📊 Ma Bande ', ' 📉 Pertes '];
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        for (var i = 0; i < noms.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _onglet = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 30, alignment: Alignment.center,
                decoration: BoxDecoration(color: _onglet == i ? p.cuivre : Colors.transparent, borderRadius: BorderRadius.circular(15)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(noms[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _onglet == i ? Colors.white : p.txtDoux)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _champ(Palette p, String libelle, String cle, {double largeur = 90}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: Row(children: [
          Expanded(child: Text(libelle, style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc))),
          SizedBox(
            width: largeur, height: 32,
            child: TextField(
              controller: _c[cle], keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13), onChanged: (_) => _lireChamps(),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
        ]),
      );

  Widget _bloc(Palette p, List<Widget> enfants) => Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants),
      );

  Widget _radio(Palette p, String texte, String valeur, String groupe, ValueChanged<String> onChange) =>
      RadioListTile<String>(
        value: valeur, groupValue: groupe, dense: true, activeColor: p.cuivre, contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        title: Text(texte, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
        onChanged: (v) {
          if (v != null) onChange(v);
        },
      );

  Widget _contenuOnglet(Palette p) {
    final chair = Previsions.chair;
    switch (_onglet) {
      case 0:
        return Column(children: [
          _bloc(p, [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 4, 15, 0),
              child: Text("Filière d'exploitation actuelle :", style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            _radio(p, '🍗 Poulet de Chair', 'chair', Session.typeElevage, (v) {
              Session.typeElevage = v;
              _filiereChangee();
            }),
            _radio(p, '🐓 Reproducteur / Ponte', 'repro', Session.typeElevage, (v) {
              Session.typeElevage = v;
              _filiereChangee();
            }),
          ]),
          _bloc(p, [
            _champ(p, 'Maïs grain :', 'mais'),
            _champ(p, 'Soja Torréfié :', 'soja'),
            _champ(p, 'Son de blé :', 'son'),
            _champ(p, 'Farine poisson :', 'poisson'),
            _champ(p, 'Coquilles :', 'coquille'),
            _champ(p, 'Sel :', 'sel'),
            _champ(p, chair ? 'Prémix Chair :' : 'Prémix Repro :', 'premix'),
          ]),
        ]);
      case 1:
        return Column(children: [
          _bloc(p, [
            _champ(p, 'Sujets lancés :', 'sujets', largeur: 100),
            _champ(p, 'Prix Poussin :', 'poussin', largeur: 100),
            _champ(p, 'Budget santé :', 'sante', largeur: 100),
          ]),
          if (chair)
            _bloc(p, [
              _champ(p, 'Prix vente vif (FCFA) :', 'vif', largeur: 120),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                child: Text("Durée d'élevage :", style: TextStyle(fontSize: 13, color: p.txtPrinc)),
              ),
              _radio(p, '30-45 jours (Cobb 500)', '45', Previsions.dureeChair, (v) {
                setState(() => Previsions.dureeChair = v);
                if (_evaluationFaite) _evaluer();
              }),
              _radio(p, '90 jours (3 mois)', '90', Previsions.dureeChair, (v) {
                setState(() => Previsions.dureeChair = v);
                if (_evaluationFaite) _evaluer();
              }),
            ])
          else
            _bloc(p, [
              _radio(p, 'Œufs Fécondés', 'oeuf', Previsions.typeVenteRepro, (v) {
                setState(() => Previsions.typeVenteRepro = v);
                _evaluer();
              }),
              _radio(p, 'Poussins 1 Jour', 'poussin', Previsions.typeVenteRepro, (v) {
                setState(() => Previsions.typeVenteRepro = v);
                _evaluer();
              }),
              _champ(p, 'Prix Œuf :', 'oeuf', largeur: 80),
              _champ(p, 'Prix Poussin :', 'poussin1', largeur: 80),
              _champ(p, 'Taux ponte % :', 'ponte', largeur: 80),
              _champ(p, 'Taux éclos % :', 'eclosion', largeur: 80),
            ]),
        ]);
      default:
        return _bloc(p, [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 2),
            child: Text('Mortalité constatée (morts) :', style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 100, height: 38,
                child: TextField(
                  controller: _c['pertes'], keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), onChanged: (_) => _lireChamps(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 2),
            child: Text('📅 Date de réception des poussins :', style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.accent)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ChampDate(
                valeur: Session.dateReceptionPoussins, largeur: 150,
                onChange: (d) => setState(() => Session.dateReceptionPoussins = d),
              ),
            ),
          ),
        ]);
    }
  }

  // ------------------------------------------------------------------ partie droite
  Widget _droite(Palette p) {
    final chair = Previsions.chair;
    Widget etape(String t, String cle) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: () => _montrerFormule(cle),
                style: FilledButton.styleFrom(backgroundColor: p.cuivre),
                child: Text(t, style: const TextStyle(fontFamily: policeTexte, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );

    Widget curseur(String gauche, String centre, String droite, double valeur, ValueChanged<double> onChange, {Color? couleur}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 5, 25, 0),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text(gauche, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.txtDoux))),
              Text(centre, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.accent)),
              Expanded(child: Text(droite, textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.txtDoux))),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: couleur ?? p.cuivre, thumbColor: couleur ?? p.cuivre, inactiveTrackColor: p.panneau2),
              child: Slider(value: valeur, min: 0, max: 100, onChanged: onChange),
            ),
          ]),
        );

    return Column(children: [
      if (chair)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Row(children: [etape('👶 Démarrage', 'demarrage'), etape('🐓 Croissance', 'croissance'), etape('🍗 Finition', 'finition')]),
        ),
      if (chair)
        curseur('📊 OPTIMISÉ (Économique)', 'PERFORMANCE RATION CHAIR', '🔥 BOOSTÉ (Rapide)', Previsions.boost, (v) {
          Previsions.boost = v;
          _sliderChange();
        })
      else
        curseur('🥚 STANDARD (Économe)', 'INTENSITÉ STIMULATION REPRO', '🔥 INTENSIF (Ponte Max)', Previsions.boostRepro, (v) {
          Previsions.boostRepro = v;
          _sliderChange();
        }, couleur: p.alerte),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(25, 10, 25, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFAF3), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A3A30) : const Color(0xFFE8E2D7)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_vue) {
                  'formule' => _vueFormule(),
                  'pilotage' => _vuePilotage(),
                  _ => _vueAttente(),
                },
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------ vue « prêt à évaluer »
  Widget _vueAttente() => SizedBox(
        key: const ValueKey('attente'), height: 430,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64, alignment: Alignment.center,
              decoration: const BoxDecoration(color: _miniP, shape: BoxShape.circle),
              child: const IconeFine('barres', couleur: Color(0xFFD99A3D), taille: 30),
            ),
            const SizedBox(height: 16),
            const Text('Prêt à évaluer votre projet', style: TextStyle(fontFamily: policeTitre, fontSize: 22, fontWeight: FontWeight.bold, color: _txtP)),
            const SizedBox(height: 6),
            const SizedBox(
              width: 460,
              child: Text(
                  "Cliquez sur « Évaluer et calculer le projet » pour afficher le tableau de pilotage et le rapport comptable,\n"
                  "ou sur une étape (Démarrage, Croissance, Finition) pour voir sa formule d'aliment.",
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: _txtDouxP)),
            ),
          ]),
        ),
      );

  // ------------------------------------------------------------------ vue « formule »
  Widget _vueFormule() {
    final etapeCle = Previsions.chair ? Previsions.derniereEtape : 'reproducteur';
    final d = Previsions.formule(etapeCle);
    final nomF = (Session.nomFerme.trim().isEmpty ? 'ANTOINE SOFTWARE' : Session.nomFerme.trim()).toUpperCase();
    Widget petit(String t, {bool gras = false, Color c = _txtP, double taille = 13}) =>
        Text(t, style: TextStyle(fontFamily: policeTexte, fontSize: taille, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: c));
    Widget mini(String titre, Widget corps) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(16), border: Border.all(color: _pisteP)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [petit(titre, c: _txtDouxP, taille: 12), const SizedBox(height: 4), corps]),
          ),
        );
    return Padding(
      key: const ValueKey('formule'),
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        petit('$nomF · ${d.eyebrow}', gras: true, c: _entete, taille: 10),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(d.titre, style: const TextStyle(fontFamily: policeTitre, fontSize: 26, fontWeight: FontWeight.bold, color: _txtP))),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: () => _editerFormule(etapeCle, d.titre),
              style: FilledButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white, minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('✏️ Ma formule', style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        petit(d.perso ? '${d.sous} · ✏️ Formule personnalisée' : d.sous, c: _txtDouxP),
        const SizedBox(height: 16),
        Row(children: [
          mini('Coût de la formule', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            petit('${d.coutKg.toStringAsFixed(1)} F / kg', gras: true, taille: 24),
            petit('Sac de 100 kg : ${fmtF(d.totalCout)}', c: _txtDouxP, taille: 11),
          ])),
          if (d.perso)
            mini('Formule', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              petit('Personnalisée', gras: true, taille: 24),
              const SizedBox(height: 6),
              petit("Le curseur d'intensité ne la modifie pas.", c: _txtDouxP, taille: 11),
            ]))
          else
            mini('Intensité', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              petit('${d.intensite.toStringAsFixed(0)} %', gras: true, taille: 24),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (d.intensite / 100).clamp(0.0, 1.0), minHeight: 8, color: _orange, backgroundColor: _pisteP),
              ),
            ])),
        ]),
        const SizedBox(height: 18),
        petit('RÉPARTITION DU COÛT DU SAC', gras: true, c: _entete, taille: 9),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (var i = 0; i < d.lignes.length; i++)
                if (d.totalCout > 0 && d.lignes[i].cout > 0)
                  Expanded(flex: math.max(1, math.min(10000, (d.lignes[i].cout / d.totalCout * 10000).round())), child: Container(color: _couleursSegments[i % _couleursSegments.length])),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Table(
          columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
          children: [
            TableRow(children: [for (final t in ['INGRÉDIENT', 'QUANTITÉ', 'COÛT', 'PART']) Padding(padding: const EdgeInsets.only(bottom: 10), child: petit(t, gras: true, c: _entete, taille: 9))]),
            for (var i = 0; i < d.lignes.length; i++)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: _couleursSegments[i % _couleursSegments.length], shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Flexible(child: petit(d.lignes[i].nom)),
                  ]),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: petit('${d.lignes[i].kg.toStringAsFixed(1)} kg', gras: true)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: petit(fmtF(d.lignes[i].cout), gras: true)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: petit('${(d.totalCout > 0 ? d.lignes[i].cout / d.totalCout * 100.0 : 0.0).toStringAsFixed(1)} %', c: _objectif),
                ),
              ]),
            TableRow(children: [
              Padding(padding: const EdgeInsets.only(top: 10), child: petit('Total du sac', gras: true)),
              Padding(padding: const EdgeInsets.only(top: 10), child: petit('${d.totalKg.toStringAsFixed(1)} kg', gras: true)),
              Padding(padding: const EdgeInsets.only(top: 10), child: petit(fmtF(d.totalCout), gras: true)),
              Padding(padding: const EdgeInsets.only(top: 10), child: petit('100 %', gras: true)),
            ]),
          ],
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: _pisteP, height: 1)),
        Row(children: [
          petit(d.perso ? '◐  Calculée avec votre formule et vos prix' : "◐  Calculée avec vos prix d'intrants", c: _entete, taille: 10),
          const Spacer(),
          petit('Mis à jour à $_derniereMaj  ●', c: _ecartVert, taille: 10),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ vue « pilotage »
  Widget _vuePilotage() {
    final r = _res;
    if (r == null) return _vueAttente();
    final nomF = (Session.nomFerme.trim().isEmpty ? 'ANTOINE SOFTWARE' : Session.nomFerme.trim()).toUpperCase();
    String f(double v) => '${milliersAnglais(v).replaceAll(',', ' ')} F';
    Widget petit(String t, {bool gras = false, Color c = _txtP, double taille = 13}) =>
        Text(t, style: TextStyle(fontFamily: policeTexte, fontSize: taille, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: c));

    (String, Color) ecart(double reel, double obj, {bool basMieux = false}) {
      if (obj <= 0) return ('—', _objectif);
      final pct = (reel - obj) / obj * 100.0;
      final bon = basMieux ? pct <= 0.05 : pct >= -0.05;
      return ('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)} %', bon ? _ecartVert : _ecartRouge);
    }

    final survie = r.sujetsLances > 0 ? r.sujetsActifs / r.sujetsLances * 100.0 : 0.0;
    final mort = r.sujetsLances > 0 ? r.pertes / r.sujetsLances * 100.0 : 0.0;
    final (tAl, cAl) = ecart(r.coutKg, r.objectifKg, basMieux: true);
    final (tSu, cSu) = ecart(survie, 95.0);
    final (tEn, cEn) = ecart(r.encaisse, r.objectifEncaisse);
    final gain = r.benefice >= 0;

    Widget miniCarte(String titre, String valeur, double part, Color couleur, {Color? couleurValeur}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(16), border: Border.all(color: _pisteP)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              petit(titre, c: _txtDouxP, taille: 12),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: petit(valeur, gras: true, taille: 24, c: couleurValeur ?? _txtP)),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: part.clamp(0.0, 1.0), minHeight: 8, color: couleur, backgroundColor: _pisteP)),
            ]),
          ),
        );

    TableRow ligne(Color couleur, String nom, String reel, String obj, String ec, Color cEc) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              petit(nom),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: petit(reel, gras: true)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: petit(obj, c: _objectif)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 11), child: petit(ec, gras: true, c: cEc)),
        ]);

    return Padding(
      key: const ValueKey('pilotage'),
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              petit('$nomF · PILOTAGE', gras: true, c: _entete, taille: 10),
              const SizedBox(height: 4),
              const Text('Tableau de pilotage', style: TextStyle(fontFamily: policeTitre, fontSize: 26, fontWeight: FontWeight.bold, color: _txtP)),
            ]),
          ),
          const IconeFine('barres', couleur: Color(0xFFD99A3D), taille: 20),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          miniCarte('Coût de production', f(r.cout), r.recette > 0 ? r.cout / r.recette : 0, _orange),
          miniCarte('Marge prévisionnelle', '${gain ? '+ ' : '− '}${f(r.benefice.abs())}', r.recette > 0 ? r.benefice.abs() / r.recette : 0,
              gain ? _vertP : _rougeP, couleurValeur: gain ? _txtP : _ecartRouge),
        ]),
        const SizedBox(height: 18),
        Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
          children: [
            TableRow(children: [for (final t in ['INDICATEUR', 'RÉEL', 'OBJECTIF', 'ÉCART']) Padding(padding: const EdgeInsets.only(bottom: 10), child: petit(t, gras: true, c: _entete, taille: 9))]),
            ligne(_orange, 'Aliment / kg', '${milliersAnglais(r.coutKg).replaceAll(',', ' ')} F', '${milliersAnglais(r.objectifKg).replaceAll(',', ' ')} F', tAl, cAl),
            ligne(_vertP, 'Taux de survie', '${survie.toStringAsFixed(1)} %', '95.0 %', tSu, cSu),
            ligne(_bleu, 'Mortalité', '${mort.toStringAsFixed(1)} %', '< 3,0 %', mort <= 3.0 ? 'Bon' : 'Élevée', mort <= 3.0 ? _ecartVert : _ecartRouge),
            ligne(_rougeP, 'Encaissement', f(r.encaisse), f(r.objectifEncaisse), tEn, cEn),
          ],
        ),
        const Padding(padding: EdgeInsets.fromLTRB(0, 8, 0, 12), child: Divider(color: _pisteP, height: 1)),
        _rapport(r.rapport, petit),
        const SizedBox(height: 6),
        Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(8)),
            child: SizedBox(width: 540, height: 200, child: CustomPaint(painter: _PeintreGraphiquePilotage(Previsions.chair))),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          petit('◐  Données enregistrées localement', c: _entete, taille: 10),
          const Spacer(),
          petit('Mis à jour à $_derniereMaj  ●', c: _ecartVert, taille: 10),
        ]),
      ]),
    );
  }

  Widget _titreSection(String titre, String sous, Widget Function(String, {bool gras, Color c, double taille}) petit) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Text(titre, style: const TextStyle(fontFamily: policeTitre, fontSize: 16, fontWeight: FontWeight.bold, color: _txtP)),
          const Spacer(),
          if (sous.isNotEmpty) petit(sous, c: _txtDouxP, taille: 11, gras: false),
        ]),
      );

  Widget _rapport(RapportComptable r, Widget Function(String, {bool gras, Color c, double taille}) petit) {
    Color couleur(Object? code) => switch (code) { 'orange' => _orange, 'vert' => _vertP, 'bleu' => _bleu, _ => _rougeP };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      petit('RAPPORT COMPTABLE & LOGISTIQUE', gras: true, c: _entete, taille: 10),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(r.titre, style: const TextStyle(fontFamily: policeTitre, fontSize: 20, fontWeight: FontWeight.bold, color: _txtP)),
      ),
      Wrap(spacing: 8, children: [
        for (final c in r.chips)
          Container(
            height: 26, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
            decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(13)),
            child: petit(c, gras: true, taille: 11),
          ),
      ]),
      for (final s in r.sections)
        if (s.type == 'seuil')
          Container(
            margin: const EdgeInsets.only(top: 18, bottom: 4),
            decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(16), border: Border.all(color: _pisteP)),
            child: Row(children: [
              SizedBox(
                width: 108,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
                  child: Text('${s.nombre}', style: const TextStyle(fontFamily: policeTitre, fontSize: 34, fontWeight: FontWeight.bold, color: _orange)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    petit('🎯 SEUIL DE RENTABILITÉ (POINT MORT)', gras: true, c: _entete, taille: 9),
                    const SizedBox(height: 2),
                    petit(s.texte, gras: true),
                    petit(s.detail, c: _txtDouxP, taille: 11),
                  ]),
                ),
              ),
            ]),
          )
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _titreSection(s.titre, s.sous, petit),
            if (s.type == 'table') ...[
              Table(
                columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
                children: [
                  TableRow(children: [for (final t in s.colonnes) Padding(padding: const EdgeInsets.only(bottom: 6), child: petit(t, gras: true, c: _entete, taille: 9))]),
                  for (final l in s.lignes)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: couleur(l[3]), shape: BoxShape.circle)),
                          const SizedBox(width: 12),
                          petit('${l[0]}'),
                        ]),
                      ),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: petit('${l[1]}', gras: true)),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: petit('${l[2]}', c: _txtDouxP)),
                    ]),
                  TableRow(children: [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(top: 10), child: petit(s.total![i], gras: true))]),
                ],
              ),
            ] else ...[
              for (var i = 0; i < s.lignes.length; i++) ...[
                if (i > 0) const Divider(color: _pisteP, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    petit('${s.lignes[i][0]}', gras: s.lignes[i][2] == true),
                    const Spacer(),
                    petit('${s.lignes[i][1]}', gras: true),
                  ]),
                ),
              ],
              if (s.bilan != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(color: _miniP, borderRadius: BorderRadius.circular(16), border: Border.all(color: _pisteP)),
                  child: Row(children: [
                    petit(s.bilan!.$1, c: _txtDouxP, taille: 12),
                    const Spacer(),
                    petit('${s.bilan!.$2 >= 0 ? '+ ' : '− '}${fmtF(s.bilan!.$2.abs(), unite: 'FCFA')}', gras: true, taille: 20,
                        c: s.bilan!.$2 >= 0 ? _ecartVert : _ecartRouge),
                  ]),
                ),
            ],
          ]),
    ]);
  }
}

/// Courbes décoratives du tableau de pilotage (mêmes tracés que tracer_graphique_boursier_premium).
class _PeintreGraphiquePilotage extends CustomPainter {
  final bool chair;
  _PeintreGraphiquePilotage(this.chair);

  void _courbe(Canvas c, List<Offset> pts, Color couleur) {
    final p = Paint()..color = couleur..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final ch = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      ch.lineTo(q.dx, q.dy);
    }
    c.drawPath(ch, p);
  }

  void _texte(Canvas c, String t, Offset centre, Color couleur) {
    final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: policeTexte, fontSize: 9, fontWeight: FontWeight.bold, color: couleur)),
        textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grille = Paint()..color = _pisteP..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(Offset(i * 54.0, 0), Offset(i * 54.0, 200), grille);
    }
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, i * 40.0), Offset(540, i * 40.0), grille);
    }
    if (chair) {
      _courbe(canvas, const [Offset(40, 170), Offset(140, 150), Offset(240, 130), Offset(340, 110), Offset(440, 90), Offset(500, 50)], _rougeP);
      _courbe(canvas, const [Offset(40, 180), Offset(140, 140), Offset(240, 95), Offset(340, 65), Offset(440, 40), Offset(500, 20)], _vertP);
      _texte(canvas, '📈 Poids des sujets (Rentabilité)', const Offset(110, 20), _vertP);
      _texte(canvas, '📉 Dépenses cumulées (Coût)', const Offset(290, 20), _rougeP);
    } else {
      _courbe(canvas, const [Offset(40, 160), Offset(140, 120), Offset(240, 80), Offset(340, 50), Offset(440, 30), Offset(500, 15)], _orange);
      _texte(canvas, '📊 Courbe de stimulation de ponte (%)', const Offset(130, 20), _orange);
    }
  }

  @override
  bool shouldRepaint(_PeintreGraphiquePilotage a) => a.chair != chair;
}

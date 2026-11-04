import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/parametres.dart';
import '../metier/formules_aliment.dart';
import '../metier/previsions.dart';
import '../metier/previsions_pondeuses.dart' show dateLongue;
import '../metier/projet_base.dart';
import '../services/pdf_projet.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogues.dart';
import '../widgets/toast.dart';

/// Ouvre un simulateur de projet (poulet de chair, reproducteurs…) : mêmes écrans, chiffres propres à chaque élevage.
Future<void> ouvrirProjet(BuildContext context, ModeleProjet modele) => showDialog<void>(
      context: context,
      builder: (_) => _DialogueProjet(modele),
    );

class _DialogueProjet extends StatefulWidget {
  final ModeleProjet m;
  const _DialogueProjet(this.m);

  @override
  State<_DialogueProjet> createState() => _DialogueProjetState();
}

class _DialogueProjetState extends State<_DialogueProjet> {
  late final ModeleProjet m = widget.m;
  late Valeurs _v;
  final Map<String, TextEditingController> _ctl = {};
  final Set<String> _aides = {};
  String _race = '';
  bool _simple = true;
  late ResultatSimu _r;
  double _siAliment = 0, _siPrix = 0, _siPertes = 0, _siPerf = 0;

  String get _cle => 'prev_${m.cle}';

  @override
  void initState() {
    super.initState();
    _v = m.defauts();
    _race = m.races.first.nom;
    for (final e in m.saisie) {
      if (e is GroupeDef) {
        for (final c in e.champs) {
          _ctl[c.cle] = TextEditingController();
        }
      }
    }
    _r = m.calculer(_v);
    _remplir();
    _charger();
    FormulesAliment.charger().then((_) {
      _v['boost'] = FormulesAliment.boost;
      if (mounted) setState(() => _r = m.calculer(_v));
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

  void _remplir() {
    _ctl.forEach((k, c) => c.text = _texte(_v[k] ?? 0));
  }

  Future<void> _charger() async {
    try {
      final brut = await Parametres.lire(_cle);
      if (brut.isEmpty) return;
      final j = jsonDecode(brut) as Map<String, dynamic>;
      for (final k in _v.keys.toList()) {
        final x = j[k];
        if (x is num) _v[k] = x.toDouble();
      }
      final r = j['race'];
      if (r is String && m.races.any((x) => x.nom == r)) _race = r;
      if (!mounted) return;
      setState(() {
        _simple = j['simple'] != false;
        _remplir();
        _r = m.calculer(_v);
      });
    } catch (_) {}
  }

  Future<void> _sauver() async {
    try {
      await Parametres.ecrire(_cle, jsonEncode({..._v, 'race': _race, 'simple': _simple}));
    } catch (_) {}
  }

  void _recalculer() {
    setState(() => _r = m.calculer(_v));
    _sauver();
  }

  void _saisie(String cle, String t) {
    final x = double.tryParse(t.replaceAll(',', '.').replaceAll(' ', ''));
    if (x == null || x < 0) return;
    _v[cle] = x;
    _recalculer();
  }

  void _choisirRace(String nom) {
    _race = nom;
    _v.addAll(m.races.firstWhere((x) => x.nom == nom).valeurs);
    _remplir();
    _recalculer();
  }

  void _reinitialiser() {
    _v = m.defauts();
    _race = m.races.first.nom;
    _remplir();
    _recalculer();
  }

  Future<void> _vraisPrix() async {
    await Previsions.charger();
    _v['mais'] = Previsions.mais;
    _v['soja'] = Previsions.soja;
    _v['son'] = Previsions.son;
    _v['poisson'] = Previsions.poisson;
    _v['coquille'] = Previsions.coquille;
    _v['premix'] = Previsions.premix;
    _v['sel'] = Previsions.sel;
    await FormulesAliment.charger();
    for (final k in ['huile', 'premixPonte']) {
      _v[k] = FormulesAliment.prixDe(k);
    }
    _v['boost'] = FormulesAliment.boost;
    _v['alimentMaison'] = 1;
    _remplir();
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
      initialDate: arriveeDe(_v) ?? maintenant,
      firstDate: DateTime(maintenant.year - 1),
      lastDate: DateTime(maintenant.year + 4),
      helpText: 'Date d\'arrivée des poussins',
    );
    if (d == null) return;
    _v['arrivee'] = jourDe(d);
    _recalculer();
  }

  Future<void> _exporterPdf() async {
    try {
      if (await PdfProjet.exporter(m, _v, _race) && mounted) {
        Toast.afficher(context, 'Prévision PDF enregistrée.', couleur: Palette.de(context).succes);
      }
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', 'Détails : $e');
    }
  }

  void _basculer(String cle) => setState(() => _aides.contains(cle) ? _aides.remove(cle) : _aides.add(cle));

  // ------------------------------------------------------------------ cadre

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final taille = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: p.fond,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1180, maxHeight: taille.height * 0.92),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
            child: Row(children: [
              Expanded(child: Text(m.titre, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: p.txtPrinc))),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: true, label: Text('Simple')), ButtonSegment(value: false, label: Text('Détaillé'))],
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
              if (c.maxWidth > 820) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 430, child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: _saisieUI(p))),
                  VerticalDivider(width: 1, color: p.bordure),
                  Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: _resultatsUI(p))),
                ]);
              }
              return ListView(children: [
                Padding(padding: const EdgeInsets.all(12), child: _saisieUI(p)),
                Divider(color: p.bordure),
                Padding(padding: const EdgeInsets.all(12), child: _resultatsUI(p)),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _titre(Palette p, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
      );

  Widget _boutonAide(Palette p, String cle) => InkResponse(
        onTap: () => _basculer(cle),
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

  Widget _champUI(Palette p, ChampDef c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(c.label, style: TextStyle(fontSize: 12, color: p.txtPrinc))),
            _boutonAide(p, c.cle),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _ctl[c.cle],
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                onChanged: (t) => _saisie(c.cle, t),
              ),
            ),
            SizedBox(width: 78, child: Padding(padding: const EdgeInsets.only(left: 6), child: Text(c.unite, style: TextStyle(fontSize: 10, color: p.txtGris)))),
          ]),
        ),
        if (_aides.contains(c.cle)) _texteAide(p, c.aide),
      ]);

  Widget _caseUI(Palette p, CaseDef c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: CheckboxListTile(
              value: (_v[c.cle] ?? 0) == 1,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: p.cuivre,
              title: Text(c.label, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
              onChanged: (x) {
                _v[c.cle] = (x ?? false) ? 1 : 0;
                _recalculer();
              },
            ),
          ),
          _boutonAide(p, c.cle),
        ]),
        if (_aides.contains(c.cle)) _texteAide(p, c.aide),
      ]);

  Widget _saisieUI(Palette p) {
    final detail = !_simple;
    final arr = arriveeDe(_v);
    final enfants = <Widget>[
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
      _titre(p, 'RACE OU SOUCHE (remplit les valeurs de départ)'),
      DropdownButtonFormField<String>(
        value: _race,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [for (final r in m.races) DropdownMenuItem(value: r.nom, child: Text(r.nom, style: const TextStyle(fontSize: 13)))],
        onChanged: (x) {
          if (x != null) _choisirRace(x);
        },
      ),
      _titre(p, 'DATE D\'ARRIVÉE DES POUSSINS'),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _choisirDate,
            icon: const Icon(Icons.event, size: 18),
            label: Text(arr == null ? 'Choisir une date' : dateLongue(arr)),
          ),
        ),
        if (arr != null)
          IconButton(
            tooltip: 'Effacer la date',
            onPressed: () {
              _v['arrivee'] = 0;
              _recalculer();
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        _boutonAide(p, 'date'),
      ]),
      if (_aides.contains('date'))
        _texteAide(p, 'Avec la date d\'arrivée, le logiciel vous dit quand a lieu la vente (ou la ponte), quelle partie tombe en saison chaude '
            '(mars à juin) ou en décembre, et il écrit les vrais mois dans les tableaux.'),
    ];
    for (final e in m.saisie) {
      if (e is GroupeDef) {
        if (e.visible != null && !e.visible!(_v)) continue;
        if (e.detailSeulement && !detail) continue;
        if (e.titre.isNotEmpty) enfants.add(_titre(p, e.titre));
        if (e.vraisPrix) {
          enfants.add(Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _vraisPrix,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Utiliser mes vrais prix (onglet Prévisions)'),
            ),
          ));
        }
        for (final c in e.champs) {
          if (!detail && !c.simple) continue;
          if (c.visible != null && !c.visible!(_v)) continue;
          enfants.add(_champUI(p, c));
        }
        if (e.note != null) {
          enfants.add(Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(e.note!(_v), style: TextStyle(fontSize: 11, color: p.txtDoux)),
          ));
        }
      } else if (e is CaseDef) {
        if (!detail && !e.simple) continue;
        if (e.visible != null && !e.visible!(_v)) continue;
        enfants.add(_caseUI(p, e));
      }
    }
    enfants.add(Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('Le coût du matériel et du bâtiment est étalé sur leur durée de vie : seule la part correspondant à ce cycle est comptée.',
          style: TextStyle(fontSize: 10, color: p.txtGris)),
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants);
  }

  // ------------------------------------------------------------------ résultats

  Widget _carte(Palette p, CarteRes c) {
    final cle = 'k${c.cle}';
    final ouvert = _aides.contains(cle);
    final couleur = c.ton == 1 ? p.succes : (c.ton == 2 ? p.danger : p.txtPrinc);
    return InkWell(
      onTap: () => _basculer(cle),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(c.titre, style: TextStyle(fontSize: 10, color: p.txtGris))),
            Icon(ouvert ? Icons.help : Icons.help_outline, size: 14, color: p.cuivre),
          ]),
          const SizedBox(height: 4),
          Text(c.valeur, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: couleur)),
          if (c.detail != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(c.detail!, style: TextStyle(fontSize: 10, color: p.txtDoux))),
          if (ouvert)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.aide, style: TextStyle(fontSize: 10, color: p.txtDoux, fontStyle: FontStyle.italic))),
        ]),
      ),
    );
  }

  Widget _ligne(Palette p, String a, String b, {bool gras = false}) {
    final st = TextStyle(fontSize: 12, color: p.txtPrinc, fontWeight: gras ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 6, child: Text(a, style: st)),
        Expanded(flex: 4, child: Text(b, textAlign: TextAlign.right, style: st)),
      ]),
    );
  }

  Widget _ligneN(Palette p, List<String> cases, List<int> flex, {bool gras = false, Color? couleur}) {
    final st = TextStyle(fontSize: 11, color: couleur ?? p.txtPrinc, fontWeight: gras ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cases.length; i++)
          Expanded(flex: flex[i], child: Text(cases[i], textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: st)),
      ]),
    );
  }

  Widget _note(Palette p, String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 11, color: p.txtDoux)),
      );

  Widget _puce(Palette p, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: TextStyle(fontSize: 12, color: p.accent)),
          Expanded(child: Text(t, style: TextStyle(fontSize: 12, color: p.txtPrinc))),
        ]),
      );

  String _cumulClair(double c) => c < 0 ? '${fmtF(c.abs())} avancés' : '${fmtF(c)} gagnés';

  Widget _resultatsUI(Palette p) {
    final r = _r;
    final detail = !_simple;
    final sc = AnalyseProjet.scenarios(m, _v);
    final vd = AnalyseProjet.verdict(m, _v, sc);
    final seuils = AnalyseProjet.seuils(m, _v, r);
    final arr = arriveeDe(_v);
    final couleur = vd.niveau == 2 ? p.succes : (vd.niveau == 1 ? p.alerte : p.danger);
    final icone = vd.niveau == 2 ? '✅' : (vd.niveau == 1 ? '⚠️' : '⛔');
    final enfants = <Widget>[
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          border: Border.all(color: couleur, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$icone  ${vd.titre}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: couleur)),
          const SizedBox(height: 6),
          Text(vd.resume, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
        ]),
      ),
      const SizedBox(height: 12),
      Text('Cliquez sur une carte pour comprendre ce qu\'elle veut dire.', style: TextStyle(fontSize: 10, color: p.txtGris)),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 10, children: [for (final c in r.cartes) _carte(p, c)]),
      _titre(p, '① SEUIL DE RENTABILITÉ : LES LIMITES À NE PAS DÉPASSER'),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tant que vous restez du bon côté de ces limites, vous ne perdez pas d\'argent sur le cycle.', style: TextStyle(fontSize: 11, color: p.txtDoux)),
          const SizedBox(height: 6),
          for (var i = 0; i < seuils.length; i++) _ligne(p, seuils[i].$1, seuils[i].$2, gras: i == 0),
        ]),
      ),
      _titre(p, '② TROIS SITUATIONS POSSIBLES'),
      _ligneN(p, ['Situation', 'Argent à avoir', 'Bénéfice', 'Prix de revient'], [3, 3, 3, 3], gras: true),
      for (final s in sc) ...[
        _ligneN(p, [s.nom, fmtF(s.r.besoinFinancement), fmtF(s.r.benefice), fmtF(s.r.coutUnitaire)], [3, 3, 3, 3], gras: s.nom == 'Normal'),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s.description, style: TextStyle(fontSize: 10, color: p.txtGris))),
      ],
      _titre(p, '③ ET SI… ? (faites glisser)'),
      _etSi(p),
      _titre(p, '④ TRÉSORERIE : ARGENT GAGNÉ OU AVANCÉ'),
      SizedBox(height: 190, child: CustomPaint(size: Size.infinite, painter: _PeintreTresorerie([for (final f in r.flux) f.cumul], p))),
      const SizedBox(height: 4),
      Text('Sous la ligne : vous avez de l\'argent avancé. Au-dessus : vous avez tout récupéré et vous gagnez.', style: TextStyle(fontSize: 10, color: p.txtGris)),
    ];
    if (detail) {
      for (final s in r.sections) {
        enfants.add(_titre(p, s.titre));
        for (final l in s.lignes) {
          enfants.add(_ligne(p, l.$1, l.$2));
        }
        if (s.total != null) {
          enfants.add(Divider(color: p.bordure));
          enfants.add(_ligne(p, s.total!.$1, s.total!.$2, gras: true));
        }
      }
      for (final t in r.tableaux) {
        enfants.add(_titre(p, t.titre));
        enfants.add(_note(p, t.note));
        enfants.add(_ligneN(p, t.entetes, t.flex, gras: true));
        for (final l in t.lignes) {
          enfants.add(_ligneN(p, l, t.flex));
        }
      }
      enfants.add(_titre(p, 'ARGENT ${r.periodeNom == 'Semaine' ? 'SEMAINE PAR SEMAINE' : 'MOIS PAR MOIS'} (depuis l\'arrivée des poussins)'));
      enfants.add(_note(p,
          'Ce tableau compte depuis le jour où les poussins arrivent : la ${r.periodeNom == 'Semaine' ? 'semaine 1' : 'période 1'} est la première, avant les ventes.\n'
          '• Dépenses : tout ce que vous payez sur la période.\n• Recettes : tout ce que vous encaissez sur la période.\n'
          '• Argent depuis le début : le total gagné moins le total dépensé. « Avancés » = il reste de l\'argent investi ; « gagnés » = tout est récupéré et vous êtes en bénéfice.'));
      enfants.add(_ligneN(p, [r.periodeNom, 'Dépenses', 'Recettes', 'Argent depuis le début'], [4, 3, 3, 4], gras: true));
      for (final f in r.flux) {
        enfants.add(_ligneN(p, [f.label, fmtF(f.depenses), fmtF(f.recettes), _cumulClair(f.cumul)], [4, 3, 3, 4], couleur: f.cumul < 0 ? p.danger : p.succes));
      }
    }
    enfants.add(_titre(p, 'CE QU\'IL FAUT RETENIR'));
    for (final c in vd.constats) {
      enfants.add(_puce(p, c));
    }
    enfants.add(_titre(p, 'POINTS D\'ATTENTION'));
    for (final a in vd.attention) {
      enfants.add(_puce(p, a));
    }
    if (_simple) {
      enfants.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text('Pour voir tous les tableaux (dépenses ligne par ligne, production, trésorerie), passez en mode Détaillé en haut.',
            style: TextStyle(fontSize: 11, color: p.txtGris)),
      ));
    }


    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants);
  }

  Widget _curseur(Palette p, String titre, double valeur, double min, double max, double pas, String unite, ValueChanged<double> onChange) {
    final txt = valeur == valeur.roundToDouble() ? valeur.toInt().toString() : valeur.toStringAsFixed(2).replaceAll('.', ',');
    return Row(children: [
      SizedBox(width: 150, child: Text(titre, style: TextStyle(fontSize: 11, color: p.txtPrinc))),
      Expanded(
        child: Slider(
          value: valeur.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: ((max - min) / pas).round(),
          activeColor: p.cuivre,
          onChanged: (x) => setState(() => onChange((x / pas).round() * pas)),
        ),
      ),
      SizedBox(
        width: 70,
        child: Text('${valeur > 0 ? '+' : ''}$txt $unite', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      ),
    ]);
  }

  Widget _etSi(Palette p) {
    final v2 = m.calculer(m.varier(_v, alimentPct: _siAliment, prixPct: _siPrix, pertesPct: _siPertes, perfDelta: _siPerf));
    final diff = v2.benefice - _r.benefice;
    final aucun = _siAliment == 0 && _siPrix == 0 && _siPertes == 0 && _siPerf == 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _curseur(p, 'Prix de l\'aliment', _siAliment, -30, 50, 1, '%', (x) => _siAliment = x),
        _curseur(p, 'Prix de vente', _siPrix, -40, 40, 1, '%', (x) => _siPrix = x),
        _curseur(p, 'Pertes (mortalité)', _siPertes, -50, 200, 1, '%', (x) => _siPertes = x),
        _curseur(p, m.perfLabel, _siPerf, m.perfMin, m.perfMax, m.perfPas, m.perfUnite == '%' ? 'pt' : '', (x) => _siPerf = x),
        const SizedBox(height: 6),
        _ligne(p, 'Bénéfice du cycle', fmtF(v2.benefice), gras: true),
        _ligne(p, 'Prix de revient d\'un ${v2.unite}', fmtF(v2.coutUnitaire)),
        _ligne(p, 'Argent à avoir avant de commencer', fmtF(v2.besoinFinancement)),
        if (!aucun)
          Text('${diff >= 0 ? 'Cela vous rapporte' : 'Cela vous coûte'} ${fmtF(diff.abs())} de ${diff >= 0 ? 'plus' : 'moins'} sur le cycle.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: diff >= 0 ? p.succes : p.danger)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: aucun ? null : () => setState(() => _siAliment = _siPrix = _siPertes = _siPerf = 0),
            child: const Text('Remettre à zéro'),
          ),
        ),
      ]),
    );
  }
}

/// Courbe de la trésorerie cumulée avec la ligne du zéro.
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
      if (i == 0 || (i + 1) % 2 == 0 || i == valeurs.length - 1) etiquette('${i + 1}', x(i) - 3, size.height - 7);
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreTresorerie old) => old.valeurs != valeurs || old.p != p;
}

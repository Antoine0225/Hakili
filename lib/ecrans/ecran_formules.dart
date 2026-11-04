import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../metier/formules_aliment.dart';
import '../metier/previsions.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogues.dart';
import '../widgets/toast.dart';

// Couleurs fixes : ce panneau s'affiche dans le grand cadre clair de la page Prévisions.
const _txt = Color(0xFF1A1F1C), _gris = Color(0xFF6F7D75), _carte = Color(0xFFF2EDE0), _piste = Color(0xFFE6DFCD);
const _vert = Color(0xFF2F7D4F), _orange = Color(0xFFC2691F), _rouge = Color(0xFFB3372A), _cuivre = Color(0xFFB8651F);
const _teintes = <Color>[
  Color(0xFFD9A441), Color(0xFF3F7D5C), Color(0xFF9C6B3F), Color(0xFF4C7FA8),
  Color(0xFFB9B3A4), Color(0xFFB8651F), Color(0xFF8A8F8C), Color(0xFFC9892B), Color(0xFF7D5BA6),
];

class _RaceDef {
  final String id, titre, emoji, texte;
  const _RaceDef(this.id, this.titre, this.emoji, this.texte);
}

const _races = <_RaceDef>[
  _RaceDef('chair', 'Poulet de chair / RLA', '🍗', 'Poulet de chair (Cobb, Ross…) et poulet à croissance lente ou local amélioré (RLA).'),
  _RaceDef('repro', 'Reproducteurs', '🐓', 'Parentaux chair (Cobb, Ross…) et parentaux pondeuse (ISA, Lohmann…).'),
  _RaceDef('pond', 'Pondeuses œufs de table', '🥚', 'Poules pondeuses pour la vente d\'œufs de consommation.'),
];

double _prixIng(String cle) {
  switch (cle) {
    case 'mais': return Previsions.mais;
    case 'soja': return Previsions.soja;
    case 'son': return Previsions.son;
    case 'poisson': return Previsions.poisson;
    case 'coquille': return Previsions.coquille;
    case 'premix': return Previsions.premix;
    case 'sel': return Previsions.sel;
  }
  return FormulesAliment.prixDe(cle);
}

String _num(double v, [int d = 2]) {
  final t = v.toStringAsFixed(d);
  final s = t.contains('.') ? t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : t;
  return s.replaceAll('.', ',');
}

/// Panneau « Formules d'aliment » : race → étape → formules (avec graphiques). S'affiche dans le grand cadre de Prévisions.
class PanneauFormules extends StatefulWidget {
  final VoidCallback onFermer;
  /// Boost (0 à 100 %) de la barre de la page Prévisions : appliqué à toutes les formules affichées.
  final double boost;
  const PanneauFormules({super.key, required this.onFermer, this.boost = 0});
  @override
  State<PanneauFormules> createState() => _EtatPanneau();
}

class _EtatPanneau extends State<PanneauFormules> {
  String? _race;
  String? _etape;
  final Map<String, List<TextEditingController>> _ctl = {};
  final Map<String, TextEditingController> _prix = {};
  final Set<String> _edition = {}; // formules en cours de modification
  final Set<String> _ouvertes = {}; // formules dépliées
  final Map<String, Set<int>> _ajoutes = {}; // ingrédients ajoutés (encore à 0 kg) pendant la modification

  @override
  void dispose() {
    for (final l in _ctl.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    for (final c in _prix.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _lire(String s) => double.tryParse(s.trim().replaceAll(',', '.').replaceAll(' ', '')) ?? 0;

  List<TextEditingController> _ctrl(String id) => _ctl.putIfAbsent(id, () {
        final p = FormulesAliment.pourcentages(id);
        return [for (final v in p) TextEditingController(text: _num(v))];
      });

  TextEditingController _ctrlPrix(String cle) => _prix.putIfAbsent(cle, () => TextEditingController(text: _num(_prixIng(cle))));

  List<double> _valeurs(String id) => [for (final c in _ctrl(id)) _lire(c.text)];

  void _remplir(String id) {
    final p = FormulesAliment.pourcentages(id);
    final l = _ctrl(id);
    for (var i = 0; i < l.length; i++) {
      l[i].text = _num(p[i]);
    }
  }

  List<FormuleDef> _deLaRace(String r) => formules.where((f) => f.race == r).toList();

  List<String> _etapes(String r) {
    final l = <String>[];
    for (final f in _deLaRace(r)) {
      if (!l.contains(f.etape)) l.add(f.etape);
    }
    return l;
  }

  List<FormuleDef> _deLEtape() => _deLaRace(_race!).where((f) => f.etape == _etape).toList();

  Future<void> _enregistrer(FormuleDef f) async {
    final p = _valeurs(f.id);
    final t = FormulesAliment.total(p);
    if ((t - 100).abs() > 0.05) {
      await Dialogues.erreur(context, 'Le total doit faire 100 kg',
          'Vos quantités font ${_num(t)} kg. Une formule se fait pour 100 kg d\'aliment : ajustez les chiffres, ou utilisez « Compléter avec le maïs ».');
      return;
    }
    await FormulesAliment.enregistrer(f.id, p);
    if (!mounted) return;
    Toast.afficher(context, 'Formule enregistrée');
    setState(() {
      _edition.remove(f.id);
      _ajoutes.remove(f.id);
    });
  }

  void _completer(FormuleDef f) {
    final p = _valeurs(f.id);
    final mais = 100 - (FormulesAliment.total(p) - p[0]);
    if (mais < 0) {
      Toast.afficher(context, 'Les autres ingrédients dépassent déjà 100 kg');
      return;
    }
    _ctrl(f.id)[0].text = _num(double.parse(mais.toStringAsFixed(2)));
    setState(() {});
  }

  Future<void> _restaurer(FormuleDef f) async {
    final ok = await Dialogues.confirmer(context, 'Restaurer cette formule', 'Remettre « ${f.groupe} — ${f.etape} » comme à l\'origine ?',
        oui: 'Restaurer', non: 'Annuler');
    if (!ok) return;
    await FormulesAliment.restaurer(f.id);
    if (!mounted) return;
    _remplir(f.id);
    setState(() {
      _edition.remove(f.id);
      _ajoutes.remove(f.id);
    });
    Toast.afficher(context, 'Formule restaurée');
  }

  Future<void> _restaurerTout() async {
    final ok = await Dialogues.confirmer(context, 'Restaurer toutes les formules',
        'Toutes vos modifications de formules seront perdues et les formules d\'origine reviendront. Continuer ?',
        oui: 'Tout restaurer', non: 'Annuler');
    if (!ok) return;
    await FormulesAliment.restaurerTout();
    if (!mounted) return;
    for (final f in formules) {
      if (_ctl.containsKey(f.id)) _remplir(f.id);
    }
    setState(() {
      _edition.clear();
      _ajoutes.clear();
    });
    Toast.afficher(context, 'Toutes les formules sont restaurées');
  }

  Future<void> _enregistrerPrix() async {
    for (final e in _prix.entries) {
      final v = _lire(e.value.text);
      if (v <= 0) continue;
      switch (e.key) {
        case 'mais': Previsions.mais = v; break;
        case 'soja': Previsions.soja = v; break;
        case 'son': Previsions.son = v; break;
        case 'poisson': Previsions.poisson = v; break;
        case 'coquille': Previsions.coquille = v; break;
        case 'premix': Previsions.premix = v; break;
        case 'sel': Previsions.sel = v; break;
        default: await FormulesAliment.enregistrerPrix(e.key, v);
      }
    }
    await Previsions.sauvegarder();
    if (!mounted) return;
    Toast.afficher(context, 'Prix enregistrés');
    setState(() {});
  }

  // ------------------------------------------------------------------ éléments communs
  /// Case de saisie claire (fond blanc, texte sombre) : le panneau est toujours clair, même en mode sombre.
  /// Sans ces couleurs imposées, le thème sombre mettait un fond foncé derrière un texte foncé : les chiffres disparaissaient.
  InputDecoration _decoSaisie({String? suffixe}) {
    OutlineInputBorder bord(Color c, [double l = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: l));
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      suffixText: suffixe,
      suffixStyle: const TextStyle(fontSize: 12, color: _gris),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      border: bord(_piste),
      enabledBorder: bord(_piste),
      focusedBorder: bord(_cuivre, 1.6),
    );
  }

  Widget _t(String s, {double taille = 13, bool gras = false, Color c = _txt, TextAlign? al}) =>
      Text(s, textAlign: al, style: TextStyle(fontFamily: policeTexte, fontSize: taille, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: c));

  Widget _etiquette(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: _t(s, taille: 11, gras: true, c: c),
      );

  Widget _fil() {
    Widget lien(String texte, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _t(texte, taille: 13, gras: true, c: onTap == null ? _txt : _cuivre)),
        );
    final r = _race == null ? null : _races.firstWhere((x) => x.id == _race);
    return Row(children: [
      lien('🧪 Formules', _race == null ? null : () => setState(() { _race = null; _etape = null; })),
      if (r != null) ...[
        _t('  ›  ', c: _gris),
        lien(r.titre, _etape == null ? null : () => setState(() => _etape = null)),
      ],
      if (_etape != null) ...[_t('  ›  ', c: _gris), lien(_etape!, null)],
      const Spacer(),
      TextButton(onPressed: _restaurerTout, child: const Text('Restaurer toutes les formules')),
      IconButton(onPressed: widget.onFermer, tooltip: 'Fermer', icon: const Icon(Icons.close, color: _gris)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fil(),
        const SizedBox(height: 8),
        if (_race == null) _niveauRaces() else if (_etape == null) _niveauEtapes() else _niveauFormules(),
      ]),
    );
  }

  // ------------------------------------------------------------------ niveau 1 : races
  Widget _niveauRaces() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Formules d\'aliment', style: const TextStyle(fontFamily: policeTitre, fontSize: 26, fontWeight: FontWeight.bold, color: _txt)),
        const SizedBox(height: 4),
        _t('Choisissez le type d\'oiseau. Vous verrez ensuite chaque étape, puis les formules avec leurs graphiques.', c: _gris),
        const SizedBox(height: 16),
        for (final r in _races)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() { _race = r.id; _etape = null; }),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: _carte, borderRadius: BorderRadius.circular(16), border: Border.all(color: _piste)),
                child: Row(children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _t(r.titre, taille: 17, gras: true),
                      const SizedBox(height: 3),
                      _t(r.texte, taille: 12, c: _gris),
                      const SizedBox(height: 5),
                      _t('${_etapes(r.id).length} étapes · ${_deLaRace(r.id).length} formules', taille: 12, c: _cuivre, gras: true),
                    ]),
                  ),
                  if (_deLaRace(r.id).any((f) => FormulesAliment.modifiee(f.id))) _etiquette('modifiée', _orange),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _gris),
                ]),
              ),
            ),
          ),
      ]);

  // ------------------------------------------------------------------ niveau 2 : étapes
  Widget _niveauEtapes() {
    final r = _races.firstWhere((x) => x.id == _race);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${r.emoji} ${r.titre}', style: const TextStyle(fontFamily: policeTitre, fontSize: 24, fontWeight: FontWeight.bold, color: _txt)),
      const SizedBox(height: 4),
      _t('Choisissez l\'étape d\'élevage.', c: _gris),
      const SizedBox(height: 14),
      for (final e in _etapes(r.id))
        Builder(builder: (_) {
          final fs = _deLaRace(r.id).where((f) => f.etape == e).toList();
          final quand = <String>[];
          for (final f in fs) {
            if (!quand.contains(f.quand)) quand.add(f.quand);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _etape = e),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _carte, borderRadius: BorderRadius.circular(14), border: Border.all(color: _piste)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _t(e, taille: 16, gras: true),
                      const SizedBox(height: 2),
                      _t(quand.join(' · '), taille: 12, c: _gris),
                      const SizedBox(height: 4),
                      _t(fs.map((f) => f.groupe.split(' (').first).join('  +  '), taille: 12, c: _cuivre, gras: true),
                    ]),
                  ),
                  if (fs.any((f) => FormulesAliment.modifiee(f.id))) _etiquette('modifiée', _orange),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _gris),
                ]),
              ),
            ),
          );
        }),
    ]);
  }

  // ------------------------------------------------------------------ niveau 3 : formules de l'étape
  Widget _niveauFormules() {
    final fs = _deLEtape();
    final utilises = <int>{};
    for (final f in fs) {
      final p = _valeurs(f.id);
      for (var i = 0; i < p.length; i++) {
        if (p[i] > 0) utilises.add(i);
      }
      utilises.addAll(_ajoutes[f.id] ?? {});
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_etape!, style: const TextStyle(fontFamily: policeTitre, fontSize: 24, fontWeight: FontWeight.bold, color: _txt)),
      const SizedBox(height: 4),
      _t('Cliquez sur une formule pour l\'ouvrir. Elle est en lecture seule : cliquez sur « Modifier » pour changer les kilos ou les ingrédients. '
          'Les quantités sont pour 100 kg d\'aliment.', c: _gris, taille: 12),
      if (widget.boost > 0) ...[
        const SizedBox(height: 4),
        _t('🔥 Boost ${widget.boost.toStringAsFixed(0)} % : les formules affichées sont renforcées (un peu plus de soja et d\'huile, un peu moins de maïs). '
            'En mode « Modifier », vous travaillez sur la formule de base, sans boost.', c: _cuivre, taille: 12),
      ],
      const SizedBox(height: 12),
      for (final f in fs) _carteFormule(f),
      _cartePrix(utilises),
      const SizedBox(height: 10),
      _t('Important : ce sont des formules de départ, calculées avec des valeurs moyennes. Faites-les valider par un nutritionniste ou votre '
          'fournisseur de prémix. Le prémix est supposé être un concentré (3 à 5 kg pour 100 kg) qui apporte vitamines, minéraux, phosphore, '
          'lysine et méthionine : si votre prémix est différent, suivez la dose et la composition du fabricant. La qualité des ingrédients '
          '(maïs sain, sans moisissure ni aflatoxines) compte beaucoup. Ces formules sont celles utilisées par les simulateurs quand vous choisissez « aliment fabriqué ».',
          taille: 11.5, c: _gris),
    ]);
  }

  /// Indices des ingrédients à montrer pour une formule.
  List<int> _lignes(FormuleDef f, List<double> pct) {
    final aj = _ajoutes[f.id] ?? <int>{};
    return [for (var i = 0; i < ingredients.length; i++) if (pct[i] > 0 || aj.contains(i)) i];
  }

  void _modifier(FormuleDef f) => setState(() {
        _remplir(f.id);
        _edition.add(f.id);
        _ouvertes.add(f.id);
      });

  void _annuler(FormuleDef f) => setState(() {
        _remplir(f.id);
        _edition.remove(f.id);
        _ajoutes.remove(f.id);
      });

  Widget _carteFormule(FormuleDef f) {
    final edit = _edition.contains(f.id);
    final ouverte = _ouvertes.contains(f.id);
    final base = _valeurs(f.id);
    final pct = edit ? base : FormulesAliment.avecBoost(base, widget.boost);
    final total = FormulesAliment.total(pct);
    final okTotal = (total - 100).abs() <= 0.05;
    final n = FormulesAliment.nutriments(pct);
    final b = f.besoin;
    final cout = FormulesAliment.coutKg(pct, _prixIng);
    final idx = _lignes(f, pct);
    final absents = [for (var i = 0; i < ingredients.length; i++) if (!idx.contains(i)) i];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: _carte, borderRadius: BorderRadius.circular(16), border: Border.all(color: edit ? _cuivre : _piste, width: edit ? 1.6 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            if (ouverte) {
              _ouvertes.remove(f.id);
            } else {
              _ouvertes.add(f.id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _t(f.groupe, taille: 15, gras: true),
                  _t('${f.etape} · ${f.quand}', taille: 12, c: _gris),
                  _t('1 kg : ${fmtF(cout.roundToDouble())}   ·   sac de 50 kg : ${fmtF((cout * 50).roundToDouble())}', taille: 12, c: _cuivre, gras: true),
                ]),
              ),
              if (edit) _etiquette('en modification', _cuivre) else if (FormulesAliment.modifiee(f.id)) _etiquette('modifiée', _orange),
              const SizedBox(width: 6),
              Icon(ouverte ? Icons.expand_less : Icons.expand_more, color: _gris),
            ]),
          ),
        ),
        if (ouverte)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 150,
                  child: Column(children: [
                    SizedBox(
                      width: 140, height: 140,
                      child: CustomPaint(painter: _PeintreDonut([for (final i in idx) math.max(0.0, pct[i])], [for (final i in idx) _teintes[i % _teintes.length]])),
                    ),
                    const SizedBox(height: 4),
                    _t('100 kg d\'aliment', taille: 11, c: _gris),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(children: [
                    Row(children: [
                      const SizedBox(width: 18),
                      Expanded(child: _t('Ingrédient', taille: 11.5, gras: true, c: _gris)),
                      SizedBox(width: 90, child: _t('Kilos pour 100 kg', taille: 11, gras: true, c: _gris, al: TextAlign.center)),
                      SizedBox(width: 70, child: _t('Pour 50 kg', taille: 11, gras: true, c: _gris, al: TextAlign.right)),
                      if (edit) const SizedBox(width: 34),
                    ]),
                    for (final i in idx)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: _teintes[i % _teintes.length], shape: BoxShape.circle)),
                          Expanded(child: _t(ingredients[i].nom, taille: 12.5)),
                          SizedBox(
                            width: 90, height: 30,
                            child: edit
                                ? TextField(
                                    controller: _ctrl(f.id)[i],
                                    textAlign: TextAlign.center,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    cursorColor: _cuivre,
                                    style: const TextStyle(fontSize: 13, color: _txt),
                                    decoration: _decoSaisie(suffixe: 'kg'),
                                    onChanged: (_) => setState(() {}),
                                  )
                                : Center(child: _t('${_num(pct[i])} kg', gras: true)),
                          ),
                          SizedBox(width: 70, child: _t('${_num(pct[i] / 2)} kg', taille: 12, c: _gris, al: TextAlign.right)),
                          if (edit)
                            SizedBox(
                              width: 34,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: 'Retirer cet ingrédient',
                                icon: const Icon(Icons.close, size: 16, color: _rouge),
                                onPressed: () => setState(() {
                                  _ctrl(f.id)[i].text = '0';
                                  _ajoutes[f.id]?.remove(i);
                                }),
                              ),
                            ),
                        ]),
                      ),
                    const Divider(height: 14),
                    Row(children: [
                      Expanded(child: _t('TOTAL', gras: true)),
                      _t('${_num(total)} kg  ${okTotal ? '✔' : '✘ doit faire 100 kg'}', gras: true, c: okTotal ? _vert : _rouge),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (!edit) FilledButton.icon(onPressed: () => _modifier(f), icon: const Icon(Icons.edit, size: 16), label: const Text('Modifier')),
                if (edit) FilledButton(onPressed: () => _enregistrer(f), child: const Text('Enregistrer')),
                if (edit) OutlinedButton(onPressed: () => _annuler(f), child: const Text('Annuler')),
                if (edit)
                  PopupMenuButton<int>(
                    tooltip: 'Ajouter un ingrédient',
                    onSelected: (i) => setState(() {
                      (_ajoutes[f.id] ??= <int>{}).add(i);
                      _ctrl(f.id)[i].text = '0';
                    }),
                    itemBuilder: (_) => [for (final i in absents) PopupMenuItem<int>(value: i, child: Text(ingredients[i].nom))],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(border: Border.all(color: _cuivre), borderRadius: BorderRadius.circular(20)),
                      child: _t('＋ Ajouter un ingrédient', taille: 13, gras: true, c: _cuivre),
                    ),
                  ),
                if (edit) OutlinedButton(onPressed: () => _completer(f), child: const Text('Compléter avec le maïs')),
                if (FormulesAliment.modifiee(f.id) || edit) OutlinedButton(onPressed: () => _restaurer(f), child: const Text('Restaurer la formule d\'origine')),
              ]),
              const SizedBox(height: 14),
              _t('Contrôle nutritionnel', taille: 14, gras: true),
              _t('Ce que la formule apporte, comparé au besoin (zone verte). Le trait montre où vous êtes.', taille: 11.5, c: _gris),
              const SizedBox(height: 6),
              _jauge('Énergie', 'kcal/kg', n.em, b.em.min, b.em.max, FormulesAliment.statutPlage(n.em, b.em, 0.03), 0),
              _jauge('Protéine', '%', n.pb, b.pb.min, b.pb.max, FormulesAliment.statutPlage(n.pb, b.pb, 0.08), 1),
              _jauge('Lysine', '%', n.lys, b.lysMin, null, FormulesAliment.statutMin(n.lys, b.lysMin, 0.08), 2),
              _jauge('Méthionine', '%', n.met, b.metMin, null, FormulesAliment.statutMin(n.met, b.metMin, 0.08), 2),
              _jauge('Calcium', '%', n.ca, b.ca.min, b.ca.max, FormulesAliment.statutPlage(n.ca, b.ca, 0.08), 2),
              _jauge('Phosphore disponible', '%', n.pd, b.pd.min, b.pd.max, FormulesAliment.statutPlage(n.pd, b.pd, 0.08), 2),
              _jauge('Sodium', '%', n.na, b.na.min, b.na.max, FormulesAliment.statutPlage(n.na, b.na, 0.08), 2),
              const SizedBox(height: 12),
              _t('Coût', taille: 14, gras: true),
              const SizedBox(height: 4),
              _t('1 kg : ${fmtF(cout.roundToDouble())}   ·   100 kg : ${fmtF((cout * 100).roundToDouble())}   ·   sac de 50 kg : ${fmtF((cout * 50).roundToDouble())}', taille: 13),
              _t('Sans les frais de broyage et de mélange (ils sont ajoutés dans les simulateurs).', taille: 11, c: _gris),
              const SizedBox(height: 6),
              _barreCout(pct, idx, cout),
            ]),
          ),
      ]),
    );
  }

  Color _coul(StatutNut s) => switch (s) { StatutNut.ok => _vert, StatutNut.proche => _orange, StatutNut.hors => _rouge };
  String _mot(StatutNut s) => switch (s) { StatutNut.ok => 'Bon', StatutNut.proche => 'Un peu à côté', StatutNut.hors => 'Hors besoin' };

  Widget _jauge(String nom, String unite, double v, double min, double? max, StatutNut s, int d) {
    final c = _coul(s);
    final bas = max == null ? 0.0 : min - (max - min) * 1.0;
    final haut = max == null ? min * 1.7 : max + (max - min) * 1.0;
    final besoin = max == null ? 'au moins ${_num(min)}' : '${_num(min, d)} à ${_num(max, d)}';
    final val = v.toStringAsFixed(d).replaceAll('.', ',');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 130, child: _t(nom, taille: 12.5)),
        Expanded(
          child: LayoutBuilder(builder: (_, cs) {
            final w = cs.maxWidth;
            double pos(double x) => ((x - bas) / (haut - bas)).clamp(0.0, 1.0) * w;
            final g = pos(min), dr = max == null ? w : pos(max);
            return SizedBox(
              height: 18,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: 0, right: 0, top: 6, height: 6, child: Container(decoration: BoxDecoration(color: _piste, borderRadius: BorderRadius.circular(3)))),
                Positioned(left: g, width: math.max(2.0, dr - g), top: 4, height: 10, child: Container(decoration: BoxDecoration(color: _vert.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(4)))),
                Positioned(left: pos(v) - 2, top: 0, width: 4, height: 18, child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)))),
              ]),
            );
          }),
        ),
        SizedBox(width: 150, child: _t('$val $unite', taille: 12.5, gras: true, c: c, al: TextAlign.right)),
        SizedBox(width: 130, child: _t('$besoin · ${_mot(s)}', taille: 11, c: c, al: TextAlign.right)),
      ]),
    );
  }

  Widget _barreCout(List<double> pct, List<int> idx, double cout) {
    final vis = [for (final i in idx) ingredients[i]];
    if (cout <= 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _t('Où part l\'argent dans 1 kg d\'aliment', taille: 11.5, c: _gris),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            for (var k = 0; k < vis.length; k++)
              Builder(builder: (_) {
                final part = pct[idx[k]] * _prixIng(vis[k].cle) / 100;
                final fl = (part / cout * 1000).round();
                return fl <= 0 ? const SizedBox.shrink() : Expanded(flex: fl, child: Container(color: _teintes[idx[k] % _teintes.length]));
              }),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 12, runSpacing: 2, children: [
        for (var k = 0; k < vis.length; k++)
          if (pct[idx[k]] > 0)
            _t('${vis[k].nom.split(' (').first} ${(pct[idx[k]] * _prixIng(vis[k].cle) / 100 / cout * 100).round()} %', taille: 11, c: _gris),
      ]),
    ]);
  }

  Widget _cartePrix(Set<int> utilises) {
    final liste = [for (var i = 0; i < ingredients.length; i++) if (utilises.contains(i)) ingredients[i]];
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _carte, borderRadius: BorderRadius.circular(16), border: Border.all(color: _piste)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _t('💰 Prix des ingrédients (FCFA par kg)', taille: 14, gras: true),
        _t('Ces prix servent au calcul du coût des formules et des simulateurs.', taille: 11.5, c: _gris),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 8, children: [
          for (final g in liste)
            SizedBox(
              width: 250,
              child: Row(children: [
                Expanded(child: _t(g.nom, taille: 12.5)),
                SizedBox(
                  width: 90, height: 30,
                  child: TextField(
                    controller: _ctrlPrix(g.cle),
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    cursorColor: _cuivre,
                    style: const TextStyle(fontSize: 13, color: _txt),
                    decoration: _decoSaisie(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        FilledButton(onPressed: _enregistrerPrix, child: const Text('Enregistrer les prix')),
      ]),
    );
  }
}

class _PeintreDonut extends CustomPainter {
  final List<double> valeurs;
  final List<Color> couleurs;
  _PeintreDonut(this.valeurs, this.couleurs);

  @override
  void paint(Canvas canvas, Size size) {
    final total = valeurs.fold<double>(0, (a, b) => a + b);
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    final fond = Paint()..style = PaintingStyle.stroke..strokeWidth = 24..color = _piste;
    canvas.drawCircle(c, r, fond);
    if (total <= 0) return;
    var a = -math.pi / 2;
    for (var i = 0; i < valeurs.length; i++) {
      if (valeurs[i] <= 0) continue;
      final ang = valeurs[i] / total * 2 * math.pi;
      final pn = Paint()..style = PaintingStyle.stroke..strokeWidth = 24..color = couleurs[i];
      canvas.drawArc(rect, a, math.max(0.0, ang - 0.012), false, pn);
      a += ang;
    }
    final tp = TextPainter(
      text: TextSpan(text: '${total.toStringAsFixed(0)} kg', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _txt)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PeintreDonut old) => true;
}

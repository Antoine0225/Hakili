import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../metier/calendrier_fetes.dart';
import '../metier/plan_fete.dart';
import '../metier/previsions.dart';
import '../services/pdf_planning.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/champ_date.dart';
import '../widgets/dialogues.dart';
import '../widgets/toast.dart';

/// Ouvre le planificateur « à l'envers ». Renvoie le plan si l'utilisateur choisit « Utiliser dans Prévisions », sinon null.
Future<PlanFete?> ouvrirPlanificateur(BuildContext context) async {
  final enregistre = await PlanFete.charger();
  if (!context.mounted) return null;
  return showDialog<PlanFete>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialoguePlanificateur(initial: enregistre),
  );
}

class _DialoguePlanificateur extends StatefulWidget {
  final PlanFete? initial;
  const _DialoguePlanificateur({this.initial});

  @override
  State<_DialoguePlanificateur> createState() => _DialoguePlanificateurState();
}

class _DialoguePlanificateurState extends State<_DialoguePlanificateur> {
  late final List<Occasion> _occasions;
  late int _choix; // index dans _occasions, ou _occasions.length = « Autre date »
  late DateTime _date;
  late String _cycle;
  final _nomAutre = TextEditingController(text: 'Ma fête');
  final _cible = TextEditingController();
  final _mortalite = TextEditingController();
  final _avant = TextEditingController();
  bool _enregistre = false;

  @override
  void initState() {
    super.initState();
    _occasions = CalendrierFetes.prochaines(aujourdhui());
    final p = widget.initial;
    _enregistre = p != null;
    _cycle = p?.cycle ?? Previsions.dureeChair;
    _cible.text = '${p?.cible ?? math.max(1, Previsions.nbSujets - Previsions.nbPertes)}';
    _mortalite.text = nombreCourt(p?.mortalitePct ?? 5);
    _avant.text = '${p?.joursAvant ?? 2}';
    if (p != null) {
      final i = _occasions.indexWhere((o) => o.nom == p.occasion && CalendrierFetes.jours(o.date, p.dateFete) == 0);
      _choix = i >= 0 ? i : _occasions.length;
      _date = p.dateFete;
      if (i < 0) _nomAutre.text = p.occasion;
    } else {
      _choix = _occasions.isEmpty ? 0 : 0;
      _date = _occasions.isEmpty ? aujourdhui().add(const Duration(days: 120)) : _occasions.first.date;
    }
  }

  @override
  void dispose() {
    _nomAutre.dispose();
    _cible.dispose();
    _mortalite.dispose();
    _avant.dispose();
    super.dispose();
  }

  bool get _autre => _choix >= _occasions.length;
  String get _nomFete => _autre ? (_nomAutre.text.trim().isEmpty ? 'Ma fête' : _nomAutre.text.trim()) : _occasions[_choix].nom;

  PlanFete? _plan([String? cycle]) {
    final c = int.tryParse(_cible.text.trim());
    final m = double.tryParse(_mortalite.text.trim().replaceAll(',', '.'));
    final a = int.tryParse(_avant.text.trim());
    if (c == null || c <= 0 || m == null || m < 0 || m > 60 || a == null || a < 0 || a > 30) return null;
    return PlanFete(occasion: _nomFete, dateFete: _date, joursAvant: a, cible: c, cycle: cycle ?? _cycle, mortalitePct: m);
  }

  // ------------------------------------------------------------------ actions
  Future<void> _pdf(PlanFete plan) async {
    try {
      if (await PdfPlanning.exporter(plan, plan.chiffres()) && mounted) {
        Toast.afficher(context, '🔥 Planning enregistré en PDF.', couleur: Palette.de(context).succes);
      }
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', 'Détails : $e');
    }
  }

  Future<void> _memoriser(PlanFete plan) async {
    await plan.enregistrer();
    if (!mounted) return;
    setState(() => _enregistre = true);
    Toast.afficher(context, '✅ Plan enregistré : les prochaines étapes apparaîtront sur la Vue d\'ensemble.',
        couleur: Palette.de(context).succes, dureeMs: 2800);
  }

  Future<void> _oublier() async {
    final ok = await Dialogues.confirmer(context, 'Supprimer le plan',
        'Voulez-vous supprimer ce plan ? Les rappels sur la Vue d\'ensemble disparaîtront.',
        oui: 'Supprimer', non: 'Garder');
    if (!ok || !mounted) return;
    await PlanFete.supprimer();
    if (mounted) setState(() => _enregistre = false);
  }

  // ------------------------------------------------------------------ éléments d'affichage
  Widget _etiquette(Palette p, String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtDoux)),
      );

  InputDecoration _deco({String? suffixe}) => InputDecoration(
        isDense: true, suffixText: suffixe,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      );

  Widget _carte(Palette p, String titre, String valeur, {String sous = '', Color? couleur}) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.txtGris)),
            const SizedBox(height: 3),
            Text(valeur, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: couleur ?? p.txtPrinc)),
            if (sous.isNotEmpty) Text(sous, style: TextStyle(fontSize: 10, color: p.txtDoux)),
          ]),
        ),
      );

  Widget _bandeau(Palette p, Color fond, String texte) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10)),
        child: Text(texte, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  String _dans(int n) => n < 0 ? 'passé' : (n == 0 ? "aujourd'hui" : (n == 1 ? 'demain' : 'dans $n j'));

  Widget _resultats(Palette p, PlanFete plan) {
    final c = plan.chiffres();
    final auj = aujourdhui();
    final joursAvantArrivee = CalendrierFetes.jours(auj, plan.dateReception);
    final etapes = plan.etapes(chiffres: c);

    final avertissements = <Widget>[];
    if (!plan.faisable) {
      final court = _plan('45');
      final suggestion = (plan.cycle == '90' && court != null && court.faisable)
          ? '\n👉 Le cycle court (30-45 jours) est possible : poussins à recevoir le ${jourEnTexte(court.dateReception)}.'
          : '\n👉 Avec ce cycle, la plus proche date possible si vous commandez aujourd\'hui est le ${jourEnTexte(plan.fetePossibleAuPlusTot)}.';
      avertissements.add(_bandeau(p, p.danger,
          '⛔ Trop tard pour cette date : les poussins auraient dû arriver le ${jourEnTexte(plan.dateReception)} (déjà passé).$suggestion'));
    } else if (joursAvantArrivee <= 7) {
      avertissements.add(_bandeau(p, p.alerte,
          '⏳ Il reste ${joursAvantArrivee <= 0 ? 'moins d\'un jour' : '$joursAvantArrivee jour(s)'} avant l\'arrivée des poussins : commandez dès maintenant.'));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...avertissements,
      Row(children: [
        _carte(p, 'POUSSINS À COMMANDER', '${c.poussins}', sous: 'pour vendre ${c.cible}'),
        _carte(p, 'ARRIVÉE DES POUSSINS', jourEnTexte(plan.dateReception), sous: _dans(joursAvantArrivee)),
        _carte(p, 'PRÊTS À VENDRE LE', jourEnTexte(plan.dateVente), sous: '${plan.joursAvant} j avant la fête'),
      ]),
      Row(children: [
        _carte(p, 'ALIMENT TOTAL', '${c.sacsTotal} sacs', sous: '${c.kgTotal.toStringAsFixed(0)} kg de 50 kg/sac'),
        _carte(p, 'CAPITAL À INVESTIR', fmtF(c.capital, unite: 'F')),
        _carte(p, 'BÉNÉFICE ESTIMÉ', fmtF(c.benefice, unite: 'F'), couleur: c.benefice >= 0 ? p.succes : p.danger),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text('CALENDRIER À SUIVRE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
      ),
      for (final e in etapes)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: e.achat ? p.cuivre.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            SizedBox(
              width: 82,
              child: Text(jourEnTexte(e.date), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            Text(e.icone, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.titre, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                if (e.detail.isNotEmpty) Text(e.detail, style: TextStyle(fontSize: 11, color: p.txtDoux)),
              ]),
            ),
            Text(_dans(CalendrierFetes.jours(auj, e.date)),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: CalendrierFetes.jours(auj, e.date) < 0 ? p.txtGris : p.txtDoux)),
          ]),
        ),
      const SizedBox(height: 6),
      Text(
          'Les chiffres utilisent vos prix de la page Prévisions. Les dates des fêtes musulmanes sont indicatives (±1 jour selon la lune) : corrigez la date si besoin.',
          style: TextStyle(fontSize: 10, color: p.txtGris)),
    ]);
  }

  Widget _formulaire(Palette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _etiquette(p, 'Quelle fête visez-vous ?'),
      DropdownButton<int>(
        isExpanded: true,
        value: _choix,
        items: [
          for (var i = 0; i < _occasions.length; i++)
            DropdownMenuItem(value: i, child: Text('${_occasions[i].nom} — ${jourEnTexte(_occasions[i].date)}', style: const TextStyle(fontSize: 13))),
          DropdownMenuItem(value: _occasions.length, child: const Text('Autre date…', style: TextStyle(fontSize: 13))),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _choix = v;
            if (v < _occasions.length) _date = _occasions[v].date;
          });
        },
      ),
      if (_autre) ...[
        _etiquette(p, 'Nom de la fête'),
        TextField(controller: _nomAutre, style: const TextStyle(fontSize: 13), decoration: _deco(), onChanged: (_) => setState(() {})),
      ],
      _etiquette(p, 'Date de la fête (modifiable)'),
      ChampDate(
        valeur: _date, largeur: 150,
        onChange: (d) => setState(() {
          _date = d;
          // si on change la date d'une fête de la liste, on passe en « Autre date » en gardant son nom
          if (!_autre) {
            _nomAutre.text = _occasions[_choix].nom;
            _choix = _occasions.length;
          }
        }),
      ),
      _etiquette(p, 'Combien de poulets voulez-vous vendre ?'),
      TextField(
          controller: _cible, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13),
          decoration: _deco(suffixe: 'poulets'), onChanged: (_) => setState(() {})),
      _etiquette(p, "Durée d'élevage"),
      Row(children: [
        for (final e in dureesChair.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value.libelle, style: const TextStyle(fontSize: 12)),
                selected: _cycle == e.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _cycle = e.key),
              ),
            ),
          ),
      ]),
      _etiquette(p, 'Pertes prévues (poussins qui meurent)'),
      TextField(
          controller: _mortalite, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13), decoration: _deco(suffixe: '%'), onChanged: (_) => setState(() {})),
      _etiquette(p, 'Être prêt à vendre combien de jours avant la fête ?'),
      TextField(
          controller: _avant, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 13),
          decoration: _deco(suffixe: 'jours'), onChanged: (_) => setState(() {})),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final plan = _plan();
    return Dialog(
      backgroundColor: p.panneau,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📅  PLANIFICATEUR DE FÊTE',
                style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 2),
            Text("Donnez la date et le nombre de poulets à vendre : Hakili calcule quand commander, quoi acheter et ce que ça rapporte.",
                style: TextStyle(fontSize: 11, color: p.txtGris)),
            const SizedBox(height: 8),
            Flexible(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 300, child: SingleChildScrollView(child: _formulaire(p))),
                const SizedBox(width: 22),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8, right: 4),
                    child: plan == null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Text('Remplissez toutes les cases à gauche avec des nombres valides pour voir le plan.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.txtDoux)),
                          )
                        : _resultats(p, plan),
                  ),
                ),
              ]),
            ),
            const Divider(height: 18),
            Row(children: [
              if (_enregistre)
                TextButton(
                  onPressed: _oublier,
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  child: const Text('🗑️ Supprimer le plan'),
                ),
              const Spacer(),
              TextButton(
                onPressed: plan == null ? null : () => _pdf(plan),
                child: const Text('🖨️ PDF'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: plan == null ? null : () => _memoriser(plan),
                child: Text(_enregistre ? '💾 Mettre à jour le plan' : '💾 Enregistrer ce plan'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: plan == null ? null : () => Navigator.pop(context, plan),
                child: const Text('📋 Utiliser dans Prévisions'),
              ),
              const SizedBox(width: 6),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
            ]),
          ]),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/bandes_repo.dart';
import '../data/journal_repo.dart';
import '../metier/alerte_chaleur.dart';
import '../metier/plan_fete.dart';
import '../data/parametres.dart';
import '../data/ventes_repo.dart';
import '../services/meteo.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/icones.dart';
import '../widgets/toast.dart';
import 'dialogue_journal.dart';

/// La « Vue d'ensemble » : bonjour, 3 indicateurs, graphique Encaissements & bénéfice,
/// « À surveiller aujourd'hui » et « Activités récentes ». Mêmes calculs que le logiciel actuel.
class EcranAccueil extends StatefulWidget {
  final void Function(String) onNaviguer;
  const EcranAccueil({super.key, required this.onNaviguer});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _Donnees {
  final List<Vente> ventes;
  final List<Map<String, Object?>> bandes;
  final int nbDus;
  final List<Activite> activites;
  const _Donnees(this.ventes, this.bandes, this.nbDus, this.activites);
}

class _EcranAccueilState extends State<EcranAccueil> with SingleTickerProviderStateMixin {
  _Donnees? _d;
  ({PlanFete plan, EtapePlan etape, int jours})? _planProchain; // prochaine étape du plan de fête (si un plan est enregistré)
  int _journalAVerifier = 0; // modifications / suppressions de l'Ouvrier ou de l'autre PC, et PIN faux, pas encore vus
  String _chaleurMasquee = ''; // « AAAA-MM-JJ|niveau » : alerte chaleur fermée pour aujourd'hui
  int _periode = 30;
  late final AnimationController _clignote;

  @override
  void initState() {
    super.initState();
    _clignote = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _charger();
    _lireChaleurMasquee();
    ServiceCloud.versionDonnees.addListener(_charger); // données de l'autre PC : l'écran se met à jour seul
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_charger);
    _clignote.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final ventes = await VentesRepo.toutes();
    final bandes = await BandesRepo.toutes();
    final nbDus = Session.peutVoirModule3 ? await BandesRepo.compterRappelsDus() : 0;
    final act = await BandesRepo.activites(ventes, bandes,
        limite: 3, estHorsCA: ligneEstHorsChiffreAffaires, fcfa: formaterFcfa);
    final plan = Session.estPatron ? await PlanFete.prochaineEtape() : null;
    final aVerifier = Session.estPatron ? await JournalRepo.compterAVerifier() : 0;
    if (mounted) {
      setState(() {
        _d = _Donnees(ventes, bandes, nbDus, act);
        _planProchain = plan;
        _journalAVerifier = aVerifier;
      });
    }
  }

  Future<void> _lireChaleurMasquee() async {
    final v = await Parametres.lire('alerte_chaleur_masquee');
    if (mounted) setState(() => _chaleurMasquee = v);
  }

  String _aujourdhuiIso() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// L'alerte a été fermée aujourd'hui pour ce niveau (ou un niveau plus fort) : on ne l'affiche plus.
  bool _chaleurFermee(AlerteChaleur a) {
    final parts = _chaleurMasquee.split('|');
    if (parts.length != 2 || parts[0] != _aujourdhuiIso()) return false;
    return a.niveau.index <= (int.tryParse(parts[1]) ?? -1);
  }

  Future<void> _fermerChaleur(AlerteChaleur a) async {
    final v = '${_aujourdhuiIso()}|${a.niveau.index}';
    await Parametres.ecrire('alerte_chaleur_masquee', v);
    if (mounted) setState(() => _chaleurMasquee = v);
  }

  void _conseilsChaleur(Palette p, AlerteChaleur a) {
    final chair = Session.typeElevage == 'chair';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        title: Text(a.titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Prévisions à ${Meteo.ville} : ${a.resume}', style: TextStyle(fontSize: 12, color: p.txtDoux)),
              if (!chair)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('🥚 Baisse de ponte possible : environ ${a.baissePonte} (estimation indicative).',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.alerte)),
                ),
              const SizedBox(height: 10),
              for (final c in a.conseils(chair: chair))
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('•  ', style: TextStyle(fontSize: 13, color: p.cuivre)),
                    Expanded(child: Text(c, style: TextStyle(fontSize: 13, color: p.txtPrinc))),
                  ]),
                ),
              const SizedBox(height: 4),
              Text('Conseils généraux. Les prévisions viennent d\'Open-Meteo et peuvent changer.',
                  style: TextStyle(fontSize: 10, color: p.txtGris)),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
  }

  // ------------------------------------------------------------------ variations « ↑ 18.6% vs … »
  (String, Color) _variation(Palette p, double actuel, double precedent, String suffixe, {bool points = false}) {
    if ((actuel - precedent).abs() < 1e-9) return ('—  ${points ? '0.0 pt' : '0%'} $suffixe', p.txtDoux);
    if (points) {
      final diff = actuel - precedent;
      return ('${diff > 0 ? '↑' : '↓'} ${diff.abs().toStringAsFixed(1)} pt $suffixe', diff > 0 ? p.succes : p.danger);
    }
    if (precedent <= 0) return ('↑ Nouveau $suffixe', p.succes);
    final pct = (actuel - precedent) / precedent.abs() * 100.0;
    return ('${pct > 0 ? '↑' : '↓'} ${pct.abs().toStringAsFixed(1)}% $suffixe', pct > 0 ? p.succes : p.danger);
  }

  Color _duo(Color clair, Color sombre) => Theme.of(context).brightness == Brightness.dark ? sombre : clair;

  Widget _carte(Palette p, {Color? fond, required Widget child}) => Container(
        decoration: BoxDecoration(
          color: fond ?? p.panneau,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.bordure),
        ),
        child: child,
      );

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final d = _d;
    if (d == null) return const SizedBox.expand();

    final auj = aujourdhui();
    final debutMois = DateTime(auj.year, auj.month, 1);
    final finMoisPrec = debutMois.subtract(const Duration(days: 1));
    final debutMoisPrec = DateTime(finMoisPrec.year, finMoisPrec.month, 1);
    final memeJourPrec = (debutMoisPrec.add(Duration(days: auj.day - 1))).isAfter(finMoisPrec)
        ? finMoisPrec
        : debutMoisPrec.add(Duration(days: auj.day - 1));
    final ceMois = VentesRepo.totauxPeriode(d.ventes, debutMois, auj);
    final moisPrec = VentesRepo.totauxPeriode(d.ventes, debutMoisPrec, memeJourPrec);
    final sb = BandesRepo.stats(d.bandes);

    return LayoutBuilder(builder: (context, c) {
      final hauteur = c.maxHeight < 690 ? 690.0 : c.maxHeight;
      return SingleChildScrollView(
        child: SizedBox(
          height: hauteur,
          child: Column(
            children: [
              _alertes(p, d),
              _entete(p, d),
              const SizedBox(height: 14),
              _rangeeIndicateurs(p, ceMois, moisPrec, sb),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(builder: (context, c2) {
                  final droite = (c2.maxWidth - 18) / 4 < 300 ? 300.0 : (c2.maxWidth - 18) / 4;
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _performance(p, d)),
                    const SizedBox(width: 18),
                    SizedBox(width: droite, child: _colonneDroite(p, d, sb)),
                  ]);
                }),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      );
    });
  }

  // ------------------------------------------------------------------ bandeaux d'alerte
  Widget _alertes(Palette p, _Donnees d) {
    final age = DateTime.now().difference(Session.dateReceptionPoussins).inDays;
    final enfants = <Widget>[];

    enfants.add(ValueListenableBuilder<double>(
      valueListenable: Meteo.temperature,
      builder: (context, temp, _) {
        if (!(temp >= 38.0 && age >= 30 && Session.typeElevage == 'chair')) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('☀️ ALERTE STRESS THERMIQUE MORIBABOUGOU ($temp°C) — VOS SUJETS ONT $age JOURS !',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 3),
            const Text(
                "Consigne : Distribuez l'eau fraîche + antistress (Vitamine C) entre 11h-16h et coupez l'alimentation aux heures chaudes.",
                style: TextStyle(fontSize: 11, color: Colors.white)),
          ]),
        );
      },
    ));

    // Alerte chaleur d'après les prévisions des 3 prochains jours (en plus de l'alerte « stress thermique » ci-dessus)
    enfants.add(ValueListenableBuilder<List<double>>(
      valueListenable: Meteo.maxPrevus,
      builder: (context, maxPrevus, _) => ValueListenableBuilder<double>(
        valueListenable: Meteo.temperature,
        builder: (context, temp, _) {
          final a = AlerteChaleur.evaluer(maxPrevus, temp);
          final dejaCouvert = temp >= 38.0 && age >= 30 && Session.typeElevage == 'chair';
          if (!a.active || dejaCouvert || _chaleurFermee(a)) return const SizedBox.shrink();
          final chair = Session.typeElevage == 'chair';
          final fond = switch (a.niveau) {
            NiveauChaleur.extreme => p.danger,
            NiveauChaleur.forte => p.alerte,
            _ => const Color(0xFFB8892B),
          };
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.titre, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(a.resume, style: const TextStyle(fontSize: 11, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                      chair
                          ? "Consigne : eau fraîche à volonté, aliment tôt le matin et en fin de journée."
                          : 'Consigne : eau fraîche à volonté ; baisse de ponte possible (environ ${a.baissePonte}).',
                      style: const TextStyle(fontSize: 11, color: Colors.white)),
                ]),
              ),
              TextButton(
                onPressed: () => _conseilsChaleur(p, a),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Voir les conseils', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _fermerChaleur(a),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Compris', style: TextStyle(fontSize: 12)),
              ),
            ]),
          );
        },
      ),
    ));

    // Journal : le Patron voit ce que l'Ouvrier (ou l'autre PC) a modifié ou supprimé depuis sa dernière visite
    if (Session.estPatron && _journalAVerifier > 0) {
      enfants.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Material(
          color: p.alerte,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await ouvrirJournal(context);
              _charger();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                    '🔍 $_journalAVerifier événement(s) à vérifier dans le journal (modifications, suppressions ou code PIN faux) — Cliquez pour voir',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ),
      ));
    }

    // Rappel du plan de fête : prochaine étape dans les 7 jours
    final plan = _planProchain;
    if (plan != null) {
      final quand = plan.jours == 0 ? "aujourd'hui" : (plan.jours == 1 ? 'demain' : 'dans ${plan.jours} jours');
      enfants.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Material(
          color: p.succes,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onNaviguer('previsions'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                    '📅 Plan ${plan.plan.occasion} — $quand : ${plan.etape.icone} ${plan.etape.titre}'
                    '${plan.etape.detail.isNotEmpty && plan.etape.achat ? ' (${plan.etape.detail})' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ),
      ));
    }

    if (Session.peutVoirModule3 && d.nbDus > 0) {
      enfants.add(AnimatedBuilder(
        animation: _clignote,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SizedBox(
            width: double.infinity,
            height: 38,
            child: FilledButton(
              onPressed: () => widget.onNaviguer('elevage'),
              style: FilledButton.styleFrom(
                backgroundColor: Color.lerp(p.danger, p.dangerSurvol, _clignote.value),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('🔔 ${d.nbDus} RAPPEL(S) VÉTÉRINAIRE(S) EN ATTENTE — Cliquez pour traiter',
                  style: const TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ));
    }
    return Column(children: enfants);
  }

  // ------------------------------------------------------------------ en-tête « Bonjour »
  Widget _entete(Palette p, _Donnees d) {
    final n = DateTime.now();
    final nom = titreCase(Session.nomFerme.trim());
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${joursFr[n.weekday - 1]} ${n.day} ${moisFr[n.month - 1]} ${n.year}',
                style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
            Row(children: [
              Flexible(
                child: Text('Bonjour, ${nom.isEmpty ? 'Antoine' : nom}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: policeTitre, fontSize: 34, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: IconeFine('etincelles', couleur: _duo(const Color(0xFFB98A1E), const Color(0xFFE2B23C)), taille: 30),
              ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              SizedBox(
                width: 44, height: 40,
                child: OutlinedButton(
                  onPressed: () {
                    if (Session.peutVoirModule3 && d.nbDus > 0) {
                      widget.onNaviguer('elevage');
                    } else {
                      Toast.afficher(context, '🔔 Aucune nouvelle notification', couleur: p.succes);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: p.panneau, side: BorderSide(color: p.bordure), padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: IconeFine('cloche', couleur: _duo(const Color(0xFF123229), const Color(0xFFF4F1E6)), taille: 20),
                ),
              ),
              if (d.nbDus > 0)
                Positioned(
                  left: 31, top: 7,
                  child: Container(width: 9, height: 9, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle)),
                ),
            ]),
            const SizedBox(width: 14),
            SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: () => widget.onNaviguer('ventes'),
                icon: const IconeFine('plus', couleur: Colors.white, taille: 16),
                label: const Text('Nouvelle saisie',
                    style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ 3 indicateurs
  Widget _rangeeIndicateurs(Palette p, TotauxPeriode ce, TotauxPeriode prec, StatsBandes sb) {
    final (t1, c1) = _variation(p, ce.ca, prec.ca, 'vs mois dernier');
    final diffB = sb.actives - sb.activesPrec;
    final t2 = diffB == 0
        ? '—  ${sb.activesPrec} vs mois dernier'
        : '${diffB > 0 ? '↑' : '↓'} ${diffB.abs()} vs mois dernier';
    final c2 = diffB == 0 ? p.txtDoux : (diffB > 0 ? p.succes : p.danger);
    final (t3, c3) = _variation(p, ce.margePct, prec.margePct, 'vs mois dernier', points: true);

    return Row(children: [
      Expanded(child: _indicateur(p, 'banque', p.iconeVert, const Color(0xFF3F6B4C), const Color(0xFF4FB37A),
          'CA encaissé · ce mois', '${formaterFcfa(ce.ca)} FCFA', t1, c1, 'tendance')),
      const SizedBox(width: 18),
      Expanded(child: _indicateur(p, 'elevage', p.iconeOr, const Color(0xFFB98A1E), const Color(0xFFE2B23C),
          'Bandes actives', '${sb.actives.toString().padLeft(2, '0')} en cours', t2, c2, diffB == 0 ? 'tiret' : 'tendance')),
      const SizedBox(width: 18),
      Expanded(child: _indicateur(p, 'barres', p.iconeVert, const Color(0xFF3F6B4C), const Color(0xFF4FB37A),
          'Marge nette estimée', '${ce.margePct.toStringAsFixed(1)} %', t3, c3, 'tendance')),
    ]);
  }

  Color _couleurBadge(Palette p, Color delta) {
    if (delta == p.succes) return _duo(const Color(0xFF2F7D4F), const Color(0xFF4FB37A));
    if (delta == p.danger) return _duo(const Color(0xFFB3372A), const Color(0xFFE2574C));
    return _duo(const Color(0xFFB98A1E), const Color(0xFFE2B23C));
  }

  Widget _indicateur(Palette p, String icone, Color fondIcone, Color couleurClair, Color couleurSombre,
      String titre, String valeur, String delta, Color couleurDelta, String badge) {
    return _carte(
      p,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 24, 18),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: fondIcone, borderRadius: BorderRadius.circular(10)),
                child: IconeFine(icone, couleur: _duo(couleurClair, couleurSombre), taille: 20),
              ),
              const SizedBox(height: 12),
              Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtDoux)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(valeur,
                    style: TextStyle(fontFamily: policeTitre, fontSize: 26, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              ),
              const SizedBox(height: 4),
              Text(delta, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: couleurDelta)),
            ]),
          ),
          IconeFine(badge, couleur: _couleurBadge(p, couleurDelta), taille: 20),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ performance + graphique
  Widget _performance(Palette p, _Donnees d) {
    final auj = aujourdhui();
    final debut = auj.subtract(Duration(days: _periode - 1));
    final cur = VentesRepo.totauxPeriode(d.ventes, debut, auj);
    final prec = VentesRepo.totauxPeriode(
        d.ventes, debut.subtract(Duration(days: _periode)), debut.subtract(const Duration(days: 1)));
    final jours = [for (var i = 0; i < _periode; i++) debut.add(Duration(days: i))];
    final ca = [for (final j in jours) cur.parJour[j]?[0] ?? 0.0];
    final ben = [for (final j in jours) cur.parJour[j]?[1] ?? 0.0];
    final suf = 'vs $_periode derniers jours';

    final stats = [
      ('Encaissements totaux', '${formaterFcfa(cur.ca)} FCFA', _variation(p, cur.ca, prec.ca, suf)),
      ('Bénéfice total', '${formaterFcfa(cur.benefice)} FCFA', _variation(p, cur.benefice, prec.benefice, suf)),
      ('Ticket moyen', '${formaterFcfa(cur.ticket)} FCFA', _variation(p, cur.ticket, prec.ticket, suf)),
      ('Taux de marge', '${cur.margePct.toStringAsFixed(1)} %',
          _variation(p, cur.margePct, prec.margePct, suf, points: true)),
    ];

    return _carte(
      p,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("PERFORMANCE DE L'EXPLOITATION",
                    style: TextStyle(fontFamily: policeTexte, fontSize: 10, fontWeight: FontWeight.bold, color: p.txtDoux)),
                Text('Encaissements & bénéfice',
                    style: TextStyle(fontFamily: policeTitre, fontSize: 19, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              ]),
            ),
            _menuPeriode(p),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('$_periode-${d.ventes.length}'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                size: Size.infinite,
                painter: _PeintreGraphique(p: p, jours: jours, ca: ca, ben: ben, progression: v),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          decoration: BoxDecoration(
              color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: Row(children: [
            for (final (titre, valeur, (delta, couleur)) in stats)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtDoux)),
                    FittedBox(
                      fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                      child: Text(valeur,
                          style: TextStyle(fontFamily: policeTitre, fontSize: 18, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                    ),
                    Text(delta,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: policeTexte, fontSize: 10, color: couleur)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _menuPeriode(Palette p) {
    return PopupMenuButton<int>(
      tooltip: '',
      color: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.bordure)),
      onSelected: (v) => setState(() => _periode = v),
      itemBuilder: (_) => [
        for (final j in [7, 30, 90])
          PopupMenuItem(
              value: j,
              height: 36,
              child: Text('$j derniers jours', style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc))),
      ],
      child: Container(
        width: 170, height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: p.panneau, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
        child: Row(children: [
          Expanded(child: Text('$_periode derniers jours',
              style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc))),
          IconeFine('chevron_bas', couleur: p.txtPrinc, taille: 12),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ colonne de droite
  Widget _colonneDroite(Palette p, _Donnees d, StatsBandes sb) {
    final sacs = Session.sacsAlimentEnStock;
    final dettes = VentesRepo.dettesOuvertes(d.ventes, seuil: 0.5);
    final dehors = dettes.fold<double>(0, (s, v) => s + v.reste);
    final patron = Session.estPatron;
    final doree = _duo(const Color(0xFFB98A1E), const Color(0xFFE2B23C));

    final lignes = [
      (
        'poule',
        sb.proches > 0
            ? '${sb.proches} bande${sb.proches > 1 ? 's' : ''} proche${sb.proches > 1 ? 's' : ''} de la fin'
            : 'Aucune bande proche de la fin',
        sb.proches > 0 ? 'Fin prévue cette semaine' : 'Rien à clôturer cette semaine',
        'elevage',
        false
      ),
      (
        'sac',
        sacs <= 2 ? "Stock d'aliment faible" : "Stock d'aliment",
        '$sacs sac${sacs > 1 ? 's' : ''} en réserve',
        'stocks',
        true
      ),
      (
        'facture',
        'Paiements en attente',
        dettes.isNotEmpty
            ? '${dettes.length} facture${dettes.length > 1 ? 's' : ''} à relancer · ${formaterFcfa(dehors)} F'
            : 'Aucune facture à relancer',
        patron ? 'credits' : 'ventes',
        false
      ),
    ];

    return Column(children: [
      _carte(
        p,
        fond: p.creme,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text("À SURVEILLER AUJOURD'HUI",
                style: TextStyle(fontFamily: policeTexte, fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          ),
          for (var i = 0; i < lignes.length; i++) ...[
            if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Container(height: 1, color: p.bordure)),
            _ligneSurveiller(p, doree, lignes[i].$1, lignes[i].$2, lignes[i].$3, lignes[i].$4, lignes[i].$5, patron),
          ],
          const SizedBox(height: 8),
        ]),
      ),
      const SizedBox(height: 14),
      Expanded(child: _activites(p, d)),
    ]);
  }

  Widget _ligneSurveiller(Palette p, Color doree, String icone, String titre, String sous, String cible,
      bool avecSacs, bool patron) {
    final texte = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      Text(sous, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtDoux)),
    ]);
    final contenu = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 14, 8),
      child: Row(children: [
        Container(
          width: 42, height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(color: p.iconeOr, shape: BoxShape.circle),
          child: IconeFine(icone, couleur: doree, taille: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: avecSacs && !patron
              ? texte
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, onTap: () => widget.onNaviguer(cible), child: texte),
                ),
        ),
        if (avecSacs) ...[
          _boutonRond(p, '−', p.panneau2, p.txtPrinc, _utiliserSac),
          const SizedBox(width: 4),
          _boutonRond(p, '+', p.cuivre, Colors.white, _ajouterSac),
        ] else
          IconeFine('chevron_droit', couleur: _duo(const Color(0xFF123229), const Color(0xFFF4F1E6)), taille: 16),
      ]),
    );
    if (avecSacs) return contenu;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.onNaviguer(cible), child: contenu),
    );
  }

  Widget _boutonRond(Palette p, String t, Color fond, Color texte, VoidCallback action) => SizedBox(
        width: 24, height: 24,
        child: FilledButton(
          onPressed: action,
          style: FilledButton.styleFrom(
              backgroundColor: fond, foregroundColor: texte, padding: EdgeInsets.zero,
              minimumSize: const Size(24, 24), shape: const CircleBorder()),
          child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      );

  Future<void> _ajouterSac() async {
    setState(() => Session.sacsAlimentEnStock++);
    await Parametres.ecrire('stock_aliment_sacs', '${Session.sacsAlimentEnStock}');
  }

  Future<void> _utiliserSac() async {
    if (Session.sacsAlimentEnStock > 0) {
      setState(() => Session.sacsAlimentEnStock--);
      await Parametres.ecrire('stock_aliment_sacs', '${Session.sacsAlimentEnStock}');
    } else {
      final p = Palette.de(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: p.panneau,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
          title: Text('Stock Vide', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          content: Text("⚠️ Antoine, tu n'as plus aucun sac d'aliment en stock !", style: TextStyle(color: p.txtPrinc)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  // ------------------------------------------------------------------ activités récentes
  Widget _activites(Palette p, _Donnees d) {
    Color couleur(String c) => switch (c) { 'or' => p.or, 'succes' => p.succes, _ => p.txtPrinc };
    return _carte(
      p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text('ACTIVITÉS RÉCENTES',
              style: TextStyle(fontFamily: policeTexte, fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (d.activites.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Text('Aucune activité pour le moment.\nVos ventes et arrivages apparaîtront ici.',
                    style: TextStyle(fontFamily: policeTexte, fontSize: 11, fontStyle: FontStyle.italic, color: p.txtGris)),
              ),
            for (final a in d.activites)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 10),
                    child: Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur(a.couleur), shape: BoxShape.circle)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(a.titre,
                              style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                        ),
                        Text(a.quand, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtDoux)),
                      ]),
                      Text(a.detail, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtDoux)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onNaviguer('ventes'),
                child: Text('Voir tout  ›', style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.accent)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ======================================================================== graphique
class _PeintreGraphique extends CustomPainter {
  final Palette p;
  final List<DateTime> jours;
  final List<double> ca, ben;
  final double progression; // 0 → 1 : les courbes se dessinent en douceur
  _PeintreGraphique({required this.p, required this.jours, required this.ca, required this.ben, required this.progression});

  TextPainter _texte(String t, double taille, Color c, {FontStyle style = FontStyle.normal}) => TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: policeTexte, fontSize: taille, color: c, fontStyle: style)),
        textDirection: TextDirection.ltr,
      )..layout();

  void _tracerPointille(Canvas canvas, List<Offset> pts, Paint peinture, double trait, double vide) {
    if (pts.length < 2) return;
    final chemin = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      chemin.lineTo(q.dx, q.dy);
    }
    for (final PathMetric m in chemin.computeMetrics()) {
      var pos = 0.0;
      while (pos < m.length) {
        canvas.drawPath(m.extractPath(pos, math.min(pos + trait, m.length)), peinture);
        pos += trait + vide;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    if (W < 120 || H < 100) return;
    final fond = p.panneau;
    final texte = p.txtDoux;
    final grille = melanger(fond, p.txtPrinc, 0.09);
    final c1 = p.courbe1, c2 = p.courbe2;

    const x0 = 62.0, y0 = 44.0;
    final x1 = W - 12, y1 = H - 30;
    final n = jours.length;
    final vmax = [...ca, ...ben, 0.0].reduce((a, b) => a > b ? a : b);
    final (pas, nb) = vmax > 0 ? echelleAgreable(vmax, 6) : (100000.0, 6);
    final ymax = pas * nb;

    double px(int i) => x0 + (x1 - x0) * i / (n - 1 > 0 ? n - 1 : 1);
    double py(double v) => y1 - (y1 - y0) * v.clamp(0.0, ymax) / ymax;

    final lisseCa = courbeLisse([for (var i = 0; i < n; i++) Offset(px(i), py(ca[i]))], sousPas: 6, yMax: y1);
    final lisseBe = courbeLisse([for (var i = 0; i < n; i++) Offset(px(i), py(ben[i]))], sousPas: 6, yMax: y1);

    // la courbe se dévoile de gauche à droite
    final limiteX = x0 + (x1 - x0) * progression;
    List<Offset> coupe(List<Offset> l) => l.where((o) => o.dx <= limiteX + 0.5).toList();

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, W, H));

    if (vmax > 0) {
      final ca2 = coupe(lisseCa);
      if (ca2.length > 1) {
        final zone = Path()..moveTo(ca2.first.dx, ca2.first.dy);
        for (final q in ca2.skip(1)) {
          zone.lineTo(q.dx, q.dy);
        }
        zone..lineTo(ca2.last.dx, y1)..lineTo(ca2.first.dx, y1)..close();
        canvas.drawPath(zone, Paint()..color = melanger(fond, c1, 0.10));
      }
    }

    final trait = Paint()..color = grille..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTRB(x0, y0, x1, y1), trait);
    for (var k = 0; k <= nb; k++) {
      final y = y1 - (y1 - y0) * k / nb;
      if (k > 0 && k < nb) canvas.drawLine(Offset(x0, y), Offset(x1, y), trait);
      final t = _texte(formaterAxe(k * pas), 9, texte);
      t.paint(canvas, Offset(x0 - 10 - t.width, y - t.height / 2));
    }
    for (var k = 0; k < 7; k++) {
      final i = (k * (n - 1) / 6).round();
      final d = jours[i];
      final t = _texte('${d.day} ${moisAbr[d.month - 1]}', 9, texte);
      final x = px(i);
      final gauche = k == 0 ? x : (k == 6 ? x - t.width : x - t.width / 2);
      t.paint(canvas, Offset(gauche, y1 + 9));
    }

    if (vmax > 0) {
      _tracerPointille(canvas, coupe(lisseBe),
          Paint()..color = c2..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round, 7, 5);
      final c = coupe(lisseCa);
      if (c.length > 1) {
        final chemin = Path()..moveTo(c.first.dx, c.first.dy);
        for (final q in c.skip(1)) {
          chemin.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(chemin,
            Paint()..color = c1..style = PaintingStyle.stroke..strokeWidth = 3
              ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      }
    } else {
      final t = _texte('Aucune vente encaissée sur cette période', 11, texte, style: FontStyle.italic);
      t.paint(canvas, Offset((x0 + x1) / 2 - t.width / 2, (y0 + y1) / 2 - t.height / 2));
    }

    // légende
    canvas.drawLine(const Offset(x0, 18), const Offset(x0 + 26, 18),
        Paint()..color = c1..strokeWidth = 3..strokeCap = StrokeCap.round);
    final t1 = _texte('Encaissements (FCFA)', 10, p.txtPrinc);
    t1.paint(canvas, Offset(x0 + 34, 18 - t1.height / 2));
    final lx2 = x0 + 34 + t1.width + 30;
    _tracerPointille(canvas, [Offset(lx2, 18), Offset(lx2 + 26, 18)],
        Paint()..color = c2..style = PaintingStyle.stroke..strokeWidth = 2, 6, 4);
    final t2 = _texte('Bénéfice (FCFA)', 10, p.txtPrinc);
    t2.paint(canvas, Offset(lx2 + 34, 18 - t2.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeintreGraphique a) =>
      a.progression != progression || a.p != p || a.ca != ca || a.ben != ben || a.jours != jours;
}

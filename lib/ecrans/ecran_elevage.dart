import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/bandes_repo.dart';
import '../metier/compta_ponte.dart' as cp;
import '../metier/elevage_service.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/champ_date.dart';
import '../widgets/dialogues.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/toast.dart';
import 'elevage/popups_elevage.dart';

/// Module Élevage (Module 3) : bandes de poulets de chair, RLA / pintades et pondeuses.
class EcranElevage extends StatefulWidget {
  const EcranElevage({super.key});

  @override
  State<EcranElevage> createState() => _EcranElevageState();
}

class _EcranElevageState extends State<EcranElevage> {
  List<Map<String, Object?>> _bandes = [];
  List<Map<String, Object?>> _rappels = [];
  String? _active;
  int _onglet = 0;

  // création
  final _nom = TextEditingController();
  final _batiment = TextEditingController();
  final _effectif = TextEditingController();
  final _prixPoussins = TextEditingController();
  final _coutInvest = TextEditingController();
  final _prixKg = TextEditingController();
  DateTime _dateArrivee = aujourdhui();
  String _type = typesElevageBande.first;
  String _stade = stadePoussins;
  String _erreurCreation = '';

  // saisie
  final _morts = TextEditingController();
  final _oeufs = TextEditingController();
  String _erreurSaisie = '';

  @override
  void initState() {
    super.initState();
    _initialiser();
    ServiceCloud.versionDonnees.addListener(_charger);
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_charger);
    for (final c in [_nom, _batiment, _effectif, _prixPoussins, _coutInvest, _prixKg, _morts, _oeufs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initialiser() async {
    await ElevageService.verifierBasculeStadePondeuses();
    await ElevageService.verifierEpuisementStocksBandes();
    await _charger();
  }

  Future<void> _charger() async {
    final b = await BandesRepo.toutes();
    final r = _active == null ? <Map<String, Object?>>[] : await ElevageService.rappelsDeBande(_active!);
    if (!mounted) return;
    setState(() {
      _bandes = b;
      _rappels = r;
      if (_active != null && !b.any((x) => x['uid'] == _active)) _active = null;
    });
  }

  Map<String, Object?>? get _bande {
    for (final b in _bandes) {
      if (b['uid'] == _active) return b;
    }
    return null;
  }

  Future<void> _selectionner(String uid) async {
    _active = uid;
    _erreurSaisie = '';
    await _charger();
  }

  int _ageJours(Map<String, Object?> b) {
    final d = lireJma(b['date_arrivee']);
    return d == null ? 0 : DateTime.now().difference(d).inDays;
  }

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return MiseEnPageModule(
      droitePapier: true,
      gauche: Column(children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.or)),
          child: Column(children: [
            _boutonPremium(p, '🌾 Nouvel Arrivage Aliment', p.or,
                () => ouvrirPopupArrivageAliment(context, apres: _charger, bandeActiveUid: _active)),
            const SizedBox(height: 6),
            _boutonPremium(p, '🩺 Nouveau Frais de Santé', p.succes,
                () => ouvrirPopupFraisSante(context, apres: _charger, bandeActiveUid: _active)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [_barreOnglets(p), Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: _contenuOnglet(p)))]),
          ),
        ),
      ]),
      droite: _resume(Palette.papier),
    );
  }

  Widget _boutonPremium(Palette p, String t, Color c, VoidCallback action) => SizedBox(
        width: double.infinity, height: 46,
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
              backgroundColor: p.panneau, foregroundColor: c, side: BorderSide(color: c),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(t, style: const TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _barreOnglets(Palette p) {
    const noms = ['📋 Mes Bandes', '➕ Créer', '🩺 Planning Véto', '📅 Saisie du Jour', '🚚 Transfert & Stock'];
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        for (var i = 0; i < noms.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _onglet = i);
                _charger();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 30, alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: _onglet == i ? p.cuivre : Colors.transparent, borderRadius: BorderRadius.circular(15)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(noms[i],
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _onglet == i ? Colors.white : p.txtDoux)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _contenuOnglet(Palette p) {
    switch (_onglet) {
      case 0:
        return _ongletListe(p);
      case 1:
        return _ongletCreation(p);
      case 2:
        return _ongletPlanning(p);
      case 3:
        return _ongletSaisie(p);
      default:
        return _ongletTransfert(p);
    }
  }

  Widget _titre(Palette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Align(alignment: Alignment.centerLeft,
            child: Text(t, style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.accent))),
      );

  Widget _vide(Palette p, String t) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.txtGris))),
      );

  // ------------------------------------------------------------------ 1) Mes bandes
  Widget _ongletListe(Palette p) {
    return Column(key: const ValueKey('liste'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titre(p, '📋 BANDES ENREGISTRÉES'),
      Expanded(
        child: _bandes.isEmpty
            ? _vide(p, "Aucune bande enregistrée pour l'instant.\nCréez-en une dans l'onglet « ➕ Créer ».")
            : ListView(padding: const EdgeInsets.all(5), children: [for (final b in _bandes) _carteBande(p, b)]),
      ),
    ]);
  }

  Widget _carteBande(Palette p, Map<String, Object?> b) {
    final actif = b['uid'] == _active;
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: actif ? (sombre ? const Color(0xFF2C301D) : const Color(0xFFF3EAD9)) : p.carte,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: actif ? p.accent : p.bordure, width: actif ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🐣 ${b['nom']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        Text('${b['type_elevage']} • Bât. ${b['batiment']} • ${b['effectif_actuel']} vivants • ${b['statut']}',
            style: TextStyle(fontSize: 10, color: p.txtGris)),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            height: 28,
            child: FilledButton(
              onPressed: () => _selectionner('${b['uid']}'),
              style: FilledButton.styleFrom(backgroundColor: actif ? p.txtGris : p.cuivre, padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text(actif ? '✔️ Bande active' : '✅ Sélectionner cette bande',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          if (Session.estPatron) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 32, height: 28,
              child: FilledButton(
                onPressed: () => _supprimerBande(b),
                style: FilledButton.styleFrom(backgroundColor: p.danger, padding: EdgeInsets.zero, minimumSize: const Size(32, 28)),
                child: const Text('🗑️', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Future<void> _supprimerBande(Map<String, Object?> b) async {
    if (!Session.estPatron) {
      Dialogues.erreur(context, 'Accès Restreint', '⚠️ Seul le Boss peut supprimer une bande.');
      return;
    }
    final ok = await Dialogues.confirmer(
        context,
        'Supprimer la bande',
        "Supprimer définitivement la bande « ${b['nom']} » ?\n\n"
        "Son planning vétérinaire et son journal d'événements seront effacés.\n"
        'Les ventes déjà enregistrées en Caisse pour cette bande restent intactes.\n\n'
        'Cette action sera aussi répercutée sur les autres PC connectés.');
    if (!ok) return;
    await BandesRepo.supprimer(b);
    if (_active == b['uid']) _active = null;
    await _charger();
  }

  // ------------------------------------------------------------------ 2) Créer
  Widget _lib(Palette p, String t, {Color? couleur, bool gras = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
        child: Align(alignment: Alignment.centerLeft,
            child: Text(t, style: TextStyle(fontSize: 11, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: couleur ?? p.txtPrinc))),
      );

  Widget _entree(TextEditingController c, {String? indice, bool numerique = false, ValueChanged<String>? onChange}) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: c, onChanged: onChange,
            keyboardType: numerique ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(hintText: indice, isDense: true),
          ),
        ),
      );

  Widget _ongletCreation(Palette p) {
    final pondeuse = _type == 'Poules Pondeuses';
    final adulte = pondeuse && _stade == cp.stadeAdulte;
    final brut = _coutInvest.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final investissement = double.tryParse(brut) ?? 0;
    final parJour = cp.amortissementJournalier(investissement);
    final base =
        "ℹ️ Ce montant est amorti sur ${cp.joursProductionPonte} jours (${cp.joursProductionPonte ~/ 7} semaines de ponte) : "
        "il ne pèse plus d'un bloc sur les premières alvéoles.";

    Widget bloc(Color? fond, List<Widget> enfants) => Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants),
        );

    return SingleChildScrollView(
      key: const ValueKey('creation'),
      padding: const EdgeInsets.all(5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lib(p, 'Nom visible de la bande (ex : B-2026-001)'),
        _entree(_nom),
        _lib(p, 'Bâtiment'),
        _entree(_batiment, indice: 'Ex : Poulailler 1'),
        _lib(p, 'Effectif initial'),
        _entree(_effectif, indice: 'Nombre de sujets', numerique: true),
        _lib(p, "Date d'arrivée (J0)"),
        Padding(padding: const EdgeInsets.fromLTRB(10, 2, 10, 2), child: Align(alignment: Alignment.centerLeft, child: ChampDate(valeur: _dateArrivee, largeur: 150, onChange: (d) => setState(() => _dateArrivee = d)))),
        _lib(p, "Type d'élevage"),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 250, height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: p.saisie, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _type, isExpanded: true, isDense: true, dropdownColor: p.panneau,
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc),
                  items: [for (final t in typesElevageBande) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
            ),
          ),
        ),
        if (pondeuse)
          bloc(null, [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text('🥚 Stade Biologique Initial (Poules Pondeuses)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
            ),
            RadioListTile<String>(
                value: stadePoussins, groupValue: _stade, dense: true, activeColor: p.cuivre,
                onChanged: (v) => setState(() => _stade = v ?? _stade),
                title: Text('🐣 Poussins (Démarrage à J0)', style: TextStyle(fontSize: 12, color: p.txtPrinc))),
            RadioListTile<String>(
                value: cp.stadeAdulte, groupValue: _stade, dense: true, activeColor: p.cuivre,
                onChanged: (v) => setState(() => _stade = v ?? _stade),
                title: Text('🐔 Déjà en Production (Adulte)', style: TextStyle(fontSize: 12, color: p.txtPrinc))),
          ]),
        if (adulte)
          bloc(null, [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text("💰 Coût d'investissement initial de la bande adulte (FCFA)\n(valeur d'achat globale du cheptel déjà mature)",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
            ),
            _entree(_coutInvest, indice: 'Ex : 1500000', numerique: true, onChange: (_) => setState(() {})),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Text(parJour > 0 ? '$base\n≈ ${milliersAnglais(parJour).replaceAll(',', ' ')} FCFA d\'amortissement par jour' : base,
                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtDoux)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text("🌾 Prix du kilo de votre aliment de ponte (FCFA)\n(sert à calculer ce que mangent vos poules chaque jour)",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
            ),
            _entree(_prixKg, indice: 'Ex : 280', numerique: true),
            const SizedBox(height: 10),
          ])
        else
          bloc(null, [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text("🐣 Prix d'achat total des poussins (FCFA)  •  obligatoire",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
            ),
            _entree(_prixPoussins, indice: 'Ex : 75000', numerique: true),
            const SizedBox(height: 10),
          ]),
        if (_erreurCreation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Text(_erreurCreation, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity, height: 44,
            child: FilledButton(
              onPressed: _creerBande,
              style: FilledButton.styleFrom(backgroundColor: p.succes, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('✅ Créer la Bande & Générer le Planning Vétérinaire',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _creerBande() async {
    setState(() => _erreurCreation = '');
    final (erreur, uid) = await ElevageService.creerBande(
      nom: _nom.text, batiment: _batiment.text, effectifTexte: _effectif.text, dateArrivee: _dateArrivee, type: _type,
      stade: _stade, coutInvestissementTexte: _coutInvest.text, prixKgTexte: _prixKg.text, prixPoussinsTexte: _prixPoussins.text,
    );
    if (erreur != null) {
      setState(() => _erreurCreation = erreur);
      return;
    }
    final nomBande = _nom.text.trim();
    for (final c in [_nom, _batiment, _effectif, _prixPoussins, _coutInvest, _prixKg]) {
      c.clear();
    }
    setState(() {
      _active = uid;
      _onglet = 0;
    });
    await _charger();
    if (mounted) Toast.afficher(context, '🐣 Bande « $nomBande » créée — planning vétérinaire généré.', couleur: Palette.de(context).succes);
  }

  // ------------------------------------------------------------------ 3) Planning vétérinaire
  Widget _ongletPlanning(Palette p) {
    final b = _bande;
    return Column(key: const ValueKey('planning'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titre(p, '🩺 CALENDRIER VÉTÉRINAIRE — bande sélectionnée'),
      Expanded(
        child: b == null
            ? _vide(p, "Sélectionnez d'abord une bande dans « 📋 Mes Bandes ».")
            : _rappels.isEmpty
                ? _vide(p, 'Aucun rappel généré pour cette bande.')
                : ListView(padding: const EdgeInsets.all(5), children: [for (final r in _rappels) _ligneRappel(p, r, b)]),
      ),
    ]);
  }

  Widget _ligneRappel(Palette p, Map<String, Object?> r, Map<String, Object?> b) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final statut = '${r['statut']}';
    final date = lireJma(r['date_prevue']) ?? DateTime.now();
    final estDu = statut == 'À faire' && !DateTime(date.year, date.month, date.day).isAfter(aujourdhui());
    final fond = estDu
        ? (sombre ? const Color(0xFF3A1F1D) : const Color(0xFFFBE9E5))
        : (statut == 'Fait' ? (sombre ? const Color(0xFF16301F) : const Color(0xFFEAF3EC)) : p.carte);
    final bord = estDu ? p.danger : (statut == 'Fait' ? p.succes : p.bordure);
    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10), border: Border.all(color: bord)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📅 ${r['date_prevue']}  —  ${r['tache']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        if (statut == 'Fait')
          Text('✔️ Fait le ${r['fait_le']} par ${r['fait_par']}', style: TextStyle(fontSize: 10, color: p.succes))
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 26,
              child: FilledButton(
                onPressed: () async {
                  await ElevageService.marquerRappelFait(r, '${b['uid']}', Session.role);
                  await _charger();
                  if (mounted) Toast.afficher(context, '✅ Rappel vétérinaire marqué comme FAIT et journalisé.', couleur: p.succes);
                },
                style: FilledButton.styleFrom(backgroundColor: p.succes, padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: const Text('✅ Marquer comme FAIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------ 4) Saisie du jour
  Widget _ongletSaisie(Palette p) {
    final b = _bande;
    final enProduction = b != null && b['type_elevage'] == 'Poules Pondeuses' && b['stade_biologique'] == cp.stadeAdulte;
    return SingleChildScrollView(
      key: const ValueKey('saisie'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titre(p, "📅 SAISIE À L'INCIDENT — bande sélectionnée"),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text("Aucune saisie quotidienne obligatoire : n'ouvrez cet écran\nque lorsqu'un événement survient (mort, récolte d'œufs...).",
              style: TextStyle(fontSize: 10, color: p.txtDoux)),
        ),
        if (b == null)
          _vide(p, "Sélectionnez d'abord une bande dans « 📋 Mes Bandes ».")
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Text("Bande active : 🐣 ${b['nom']}  (${b['effectif_actuel']} vivants)",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          ),
          _lib(p, "☠️ Nombre de morts constatés aujourd'hui"),
          _entree(_morts, indice: '0', numerique: true),
          if (enProduction) ...[
            _lib(p, "🥚 Nombre d'œufs récoltés aujourd'hui (obligatoire)", couleur: p.accent, gras: true),
            _entree(_oeufs, indice: 'Ex : 320', numerique: true),
          ],
          if (enProduction && cp.estBandeLissee(b) && !cp.estReformee(b))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(
                  "💡 Saisissez la récolte CHAQUE jour : l'aliment (${cp.consoAlimentGParPondeuseJour} g par poule et par jour) est compté jour par jour. "
                  "Un jour sans saisie coûte quand même, mais ses œufs ne sont pas comptés.",
                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtDoux)),
            ),
          if (_erreurSaisie.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(_erreurSaisie, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity, height: 42,
              child: FilledButton(
                onPressed: () => _enregistrerEvenement('${b['uid']}'),
                style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text("💾 Enregistrer l'événement du jour",
                    style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _enregistrerEvenement(String uid) async {
    setState(() => _erreurSaisie = '');
    final (erreur, infos) = await ElevageService.enregistrerEvenementQuotidien(uid, _morts.text, _oeufs.text);
    if (erreur != null) {
      setState(() => _erreurSaisie = erreur);
      return;
    }
    _morts.clear();
    _oeufs.clear();
    await _charger();
    if (!mounted) return;
    final p = Palette.de(context);
    for (final (msg, alerte) in infos) {
      Toast.afficher(context, msg, couleur: alerte ? p.alerte : p.succes, dureeMs: alerte ? 3000 : 1800);
    }
  }

  // ------------------------------------------------------------------ 5) Transfert & stock
  Widget _ongletTransfert(Palette p) {
    final b = _bande;
    final enfants = <Widget>[_titre(p, '🚚 TRANSFERT VERS LA CAISSE (VENTES)')];
    Widget texte(String t, {Color? c, bool gras = false, double taille = 12, bool italique = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(t, style: TextStyle(fontSize: taille, fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              fontStyle: italique ? FontStyle.italic : FontStyle.normal, color: c ?? p.txtPrinc)),
        );
    Widget gros(String t, Color fond, VoidCallback? action) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: SizedBox(
            width: double.infinity, height: 44,
            child: FilledButton(
              onPressed: action,
              style: FilledButton.styleFrom(backgroundColor: fond, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(t, style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        );

    if (b == null) {
      enfants.add(texte("Sélectionnez d'abord une bande dans « 📋 Mes Bandes ».", c: p.txtGris));
    } else if (b['type_elevage'] == 'Poules Pondeuses') {
      enfants.add(texte("🥚 Filière Œufs : chaque récolte saisie dans « 📅 Saisie du Jour »\nest automatiquement transférée en stock sous le nom :"));
      enfants.add(texte("📦 « Alvéoles d'œufs — Bande ${b['nom']} »", c: p.accent, gras: true, taille: 13));
      enfants.add(texte("Le coût de production de l'alvéole reste masqué en tâche de fond.\nLe prix de vente devra toujours être saisi manuellement en Caisse.",
          c: p.txtGris, taille: 10, italique: true));
      if (cp.estBandeLissee(b)) enfants.addAll(_blocReforme(p, b, texte, gros));
    } else {
      final seuil = maturiteCommercialeJours[b['type_elevage']] ?? 0;
      final age = _ageJours(b);
      if (b['statut'] == 'En vente') {
        enfants.add(texte("✅ Cette bande est déjà EN VENTE, sous le produit :\n📦 « ${b['produit_stock_nom']} »", c: p.succes, gras: true));
      } else if (b['statut'] == 'Épuisée') {
        enfants.add(texte("🏁 Stock de cette bande épuisé (statut : Épuisée).\nConsultez le Rapport Flash (Marge Boss) pour ses résultats.", c: p.txtGris, gras: true));
      } else if (age < seuil) {
        enfants.add(texte('🔒 Maturité commerciale non atteinte.\nJour $age / $seuil — le bouton se débloque à J$seuil.', c: p.danger, gras: true));
        enfants.add(gros('🔒 Prête pour vente (verrouillé)', p.txtGris, null));
      } else {
        enfants.add(texte("✅ Maturité commerciale atteinte (jour $age ≥ $seuil).\nEffectif actuellement disponible : ${b['effectif_actuel']}.", c: p.succes, gras: true));
        enfants.add(gros('🚀 Prête pour vente — Transférer à la Caisse', p.succes, () => _mettreEnVente(b)));
      }
    }
    return SingleChildScrollView(key: const ValueKey('transfert'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants));
  }

  List<Widget> _blocReforme(Palette p, Map<String, Object?> b, Widget Function(String, {Color? c, bool gras, double taille, bool italique}) texte,
      Widget Function(String, Color, VoidCallback?) gros) {
    final auj = aujourdhui();
    final sep = Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 6), child: Container(height: 1, color: p.bordure));
    if (cp.estReformee(b)) {
      return [
        sep,
        texte("🏁 Bande réformée le ${b['date_reforme']}.\nLes poules de réforme sont en Caisse sous : 📦 « Poules de réforme — Bande ${b['nom']} ».",
            c: p.txtGris, gras: true),
      ];
    }
    final jours = cp.joursDePonte(b, auj);
    if (cp.reformePossible(b, auj)) {
      return [
        sep,
        texte('✅ ${cp.moisAvantReforme} mois de ponte atteints (jour $jours).\nVous pouvez réformer la bande et vendre les poules.', c: p.succes, gras: true),
        gros('🐔 Réformer la bande — Transférer à la Caisse', p.succes, () => _reformer(b)),
      ];
    }
    return [
      sep,
      texte('🔒 Réforme possible après ${cp.moisAvantReforme} mois de ponte.\nJour $jours / ${cp.joursAvantReforme} — le bouton se débloque à J${cp.joursAvantReforme}.', c: p.danger, gras: true),
      gros('🔒 Réformer la bande (verrouillé)', p.txtGris, null),
    ];
  }

  Future<void> _mettreEnVente(Map<String, Object?> b) async {
    if (b['statut'] != 'En élevage') return;
    if (((b['effectif_actuel'] as num?) ?? 0) <= 0) {
      Dialogues.erreur(context, 'Effectif Nul', '⚠️ Aucun sujet vivant à transférer pour cette bande.');
      return;
    }
    final ok = await Dialogues.confirmer(context, 'Confirmer la mise en vente',
        "Transférer les ${b['effectif_actuel']} sujets de « ${b['nom']} » vers le catalogue de la Caisse ?\nCette action fige le coût unitaire de revient.");
    if (!ok) return;
    final nom = await ElevageService.mettreEnVente('${b['uid']}');
    await _charger();
    if (nom != null && mounted) {
      Toast.afficher(context, '🚀 « $nom » transféré en Caisse — prix de vente à saisir manuellement.', couleur: Palette.de(context).succes);
    }
  }

  Future<void> _reformer(Map<String, Object?> b) async {
    if (((b['effectif_actuel'] as num?) ?? 0) <= 0) {
      Dialogues.erreur(context, 'Effectif Nul', '⚠️ Aucune poule vivante à transférer pour cette bande.');
      return;
    }
    if (((b['prix_kg_aliment'] as num?) ?? 0) <= 0) {
      Dialogues.erreur(context, 'Prix du kilo manquant', '⚠️ Renseignez d\'abord le prix du kilo d\'aliment (Rapport Flash) pour finir les calculs.');
      return;
    }
    final ok = await Dialogues.confirmer(context, 'Confirmer la réforme',
        "Transférer les ${b['effectif_actuel']} poules de « ${b['nom']} » vers le catalogue de la Caisse ?\nLa saisie des œufs de cette bande sera clôturée.");
    if (!ok) return;
    final nom = await ElevageService.reformer('${b['uid']}');
    await _charger();
    if (nom != null && mounted) {
      Toast.afficher(context, '🐔 « $nom » transféré en Caisse — prix de vente à saisir manuellement.', couleur: Palette.de(context).succes);
    }
  }

  // ------------------------------------------------------------------ résumé à droite
  Widget _resume(Palette p) {
    final b = _bande;
    if (b == null) {
      return Center(
        child: Text("🐣 Sélectionnez une bande dans l'onglet\n« 📋 Mes Bandes » pour voir son suivi.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.txtGris)),
      );
    }
    final age = _ageJours(b);
    Widget carte(String titre, String valeur, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
            child: Column(children: [
              Text(titre, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c)),
              const SizedBox(height: 2),
              Text(valeur, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ]),
          ),
        );
    final statutCouleur = {'En élevage': p.or, 'En vente': p.succes, 'Épuisée': p.txtGris}[b['statut']] ?? p.txtGris;
    final pondeuse = b['type_elevage'] == 'Poules Pondeuses';
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: p.menu, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('🐣 ${b['nom']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text('${b['type_elevage']}  •  Bâtiment ${b['batiment']}', style: TextStyle(fontSize: 12, color: p.menuDoux)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            carte('EFFECTIF VIVANT', '${b['effectif_actuel']}', p.accent),
            carte('MORTS CUMULÉES', '${b['morts_cumulees']}', p.danger),
            carte('ÂGE', '$age j', p.or),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            carte('STATUT COMMERCIAL', '${b['statut']}', statutCouleur),
            if (pondeuse) carte('STADE BIOLOGIQUE', ('${b['stade_biologique'] ?? ''}').isEmpty ? '—' : '${b['stade_biologique']}', p.accent),
            if (pondeuse) carte('ŒUFS RÉCOLTÉS (CUMUL)', milliersAnglais((b['oeufs_cumules'] as num?) ?? 0).replaceAll(',', ' '), p.or),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text("🔒 Coûts de revient et marges masqués ici — consultez le Rapport\nFlash (PIN) dans l'onglet Marge & Bénéfice Boss.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtGris)),
        ),
      ]),
    );
  }
}

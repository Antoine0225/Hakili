import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/arrivages_repo.dart';
import '../data/stock_repo.dart';
import '../services/pdf_stocks.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/champ_date.dart';
import '../widgets/dialogue_periode.dart';
import '../widgets/dialogues.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/tableau_stock.dart';
import '../widgets/toast.dart';

/// Module Stocks : à gauche le formulaire d'arrivage, à droite deux onglets
/// « Stock & Historique » et « Répertoire Fournisseurs ».
class EcranStocks extends StatefulWidget {
  const EcranStocks({super.key});

  @override
  State<EcranStocks> createState() => _EcranStocksState();
}

class _EcranStocksState extends State<EcranStocks> {
  static const _vide = '(catalogue vide)';

  DateTime _date = aujourdhui();
  List<Produit> _catalogue = [];
  String _produit = _vide;
  String _reglement = 'Espèces';
  final _qte = TextEditingController();
  final _poids = TextEditingController();
  final _prix = TextEditingController();
  final _bonus = TextEditingController(text: '0');
  final _fournisseur = TextEditingController();
  bool _bonusManuel = false;

  int _onglet = 0;
  DateTime _dateHistorique = aujourdhui();
  List<Arrivage> _duJour = [];
  StatsFournisseurs? _stats;
  String _filtre = 'Tous les fournisseurs';
  final _cleStock = GlobalKey<TableauStockState>();

  @override
  void initState() {
    super.initState();
    _chargerCatalogue();
    _chargerHistorique();
    _chargerFournisseurs();
    ServiceCloud.versionDonnees.addListener(_toutRecharger);
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_toutRecharger);
    for (final c in [_qte, _poids, _prix, _bonus, _fournisseur]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toutRecharger() {
    _chargerCatalogue();
    _chargerHistorique();
    _chargerFournisseurs();
  }

  Future<void> _chargerCatalogue() async {
    final c = await StockRepo.catalogue();
    if (!mounted) return;
    setState(() {
      _catalogue = c;
      if (c.isEmpty) {
        _produit = _vide;
      } else if (!c.any((p) => p.nom == _produit)) {
        _produit = c.first.nom;
      }
    });
  }

  Future<void> _chargerHistorique() async {
    final l = await ArrivagesRepo.du(jourEnTexte(_dateHistorique));
    if (mounted) setState(() => _duJour = l);
  }

  Future<void> _chargerFournisseurs() async {
    final s = await ArrivagesRepo.statistiquesFournisseurs();
    if (mounted && s != null) setState(() => _stats = s);
  }

  String get _unite => _catalogue.where((p) => p.nom == _produit).map((p) => p.unite).firstOrNull ?? 'piece';

  // ------------------------------------------------------------------ enregistrer un arrivage
  Future<void> _valider() async {
    final p = Palette.de(context);
    if (_produit == _vide) {
      Dialogues.erreur(context, 'Produit Manquant', '⚠️ Ajoutez d\'abord un produit au catalogue avec le bouton ➕.');
      return;
    }
    final unite = _unite;
    final fournisseur = _fournisseur.text.trim();
    if (_reglement == 'À Crédit' && fournisseur.isEmpty) {
      Dialogues.erreur(context, 'Fournisseur Obligatoire',
          '⛔ Indiquez le nom du fournisseur pour un arrivage pris À CRÉDIT.');
      return;
    }
    String nettoie(String t) => t.trim().replaceAll(' ', '').replaceAll(',', '.');
    final qteBrute = nettoie(_qte.text), prixBrut = nettoie(_prix.text);
    if (qteBrute.isEmpty || prixBrut.isEmpty) {
      Dialogues.erreur(context, 'Champs Vides', '⚠️ Veuillez remplir tous les champs de l\'arrivage.');
      return;
    }
    final quantiteSaisie = double.tryParse(qteBrute);
    final prixSaisi = double.tryParse(prixBrut);
    if (quantiteSaisie == null || prixSaisi == null) {
      Dialogues.erreur(context, 'Saisie Invalide', '⚠️ Erreur de format : vérifiez les chiffres saisis.');
      return;
    }
    if (quantiteSaisie <= 0 || prixSaisi <= 0) {
      Dialogues.erreur(context, 'Valeurs Invalides', '⚠️ Les quantités et prix doivent être supérieurs à zéro.');
      return;
    }

    double poidsSac, quantiteAjoutee, coutUnitaire;
    final prixAchatTotal = quantiteSaisie * prixSaisi;
    if (unite == 'sac') {
      final poidsBrut = nettoie(_poids.text);
      if (poidsBrut.isEmpty) {
        Dialogues.erreur(context, 'Champ Vide', '⚠️ Indiquez le poids du sac (kg).');
        return;
      }
      final poids = double.tryParse(poidsBrut);
      if (poids == null) {
        Dialogues.erreur(context, 'Saisie Invalide', '⚠️ Erreur de format : vérifiez les chiffres saisis.');
        return;
      }
      if (poids <= 0) {
        Dialogues.erreur(context, 'Valeur Invalide', '⚠️ Le poids du sac doit être supérieur à zéro.');
        return;
      }
      poidsSac = poids;
      quantiteAjoutee = quantiteSaisie * poids;
      coutUnitaire = prixSaisi / poids;
    } else {
      poidsSac = 0;
      quantiteAjoutee = quantiteSaisie;
      coutUnitaire = prixSaisi;
    }

    var bonus = 0.0;
    if (_produit == "Alvéole d'œufs") {
      final b = double.tryParse(nettoie(_bonus.text));
      bonus = (b ?? 0) < 0 ? 0 : (b ?? 0);
    }

    final date = jourEnTexte(_date);
    final id = await ArrivagesRepo.enregistrer(
      date: date, produit: _produit, unite: unite, quantiteSaisie: quantiteSaisie, poidsSac: poidsSac,
      prixAchatTotal: prixAchatTotal, coutUnitaire: coutUnitaire, quantiteAjoutee: quantiteAjoutee,
      reglement: _reglement, fournisseur: fournisseur, alveolesBonus: bonus,
    );
    if (!mounted) return;
    if (id == null) {
      Dialogues.avertissement(context, 'Arrivage non enregistré',
          "⚠️ L'arrivage n'a pas pu être écrit dans la base de données. Réessayez ; "
          'si le message revient, consultez donnies_antoine_diagnostic.log.');
    }

    _qte.clear();
    _prix.clear();
    _poids.clear();
    _fournisseur.clear();
    setState(() {
      _reglement = 'Espèces';
      _dateHistorique = _date;
      _bonusManuel = false;
      _bonus.text = '0';
    });
    _cleStock.currentState?.recharger();
    await _chargerHistorique();
    await _chargerFournisseurs();

    final lib = StockRepo.libelleUnite(unite);
    final libPrix = lib == 'kg' ? 'kg' : 'pièce';
    final msgBonus = bonus > 0 ? ' 🎁 +${milliersAnglais(bonus)} bonus offert(s).' : '';
    if (mounted) {
      Toast.afficher(
          context,
          '✅ ${milliersAnglais(quantiteAjoutee, 1)} $lib de « $_produit » ajoutés '
          '(${milliersAnglais(coutUnitaire)} F/$libPrix).$msgBonus',
          couleur: p.succes, dureeMs: 2600);
    }
  }

  Future<void> _exporterPdf() async {
    final periode = await choisirPeriode(context,
        titre: "📅 PÉRIODE DU RAPPORT D'ARRIVAGES", texteBouton: '🖨️ Générer le PDF', moisCourantParDefaut: true);
    if (periode == null || !mounted) return;
    try {
      final arrivages = await ArrivagesRepo.periode(periode.debut, periode.fin);
      final ok = await PdfStocks.exporterArrivages(arrivages, periode.debut, periode.fin, periode.texteDebut, periode.texteFin);
      if (ok && mounted) Toast.afficher(context, '🔥 Rapport d\'arrivages exporté et classé !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
    }
  }

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    return MiseEnPageModule(
      papierDirect: true,
      gauche: SingleChildScrollView(child: _formulaire(Palette.de(context))),
      droite: _droite(),
    );
  }

  Widget _etiq(Palette p, String t, {Color? couleur, bool gras = false, double haut = 5}) => Padding(
        padding: EdgeInsets.fromLTRB(15, haut, 15, 2),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: couleur ?? p.txtPrinc)),
      );

  Widget _champ(TextEditingController c, {Color? bordure, ValueChanged<String>? onChange, double haut = 2}) => Padding(
        padding: EdgeInsets.fromLTRB(15, haut, 15, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 120, height: 34,
            child: TextField(
              controller: c,
              onChanged: onChange,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: bordure == null
                    ? null
                    : OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: bordure)),
              ),
            ),
          ),
        ),
      );

  Widget _liste(Palette p, String valeur, List<String> choix, double largeur, ValueChanged<String> onChange) => Container(
        width: largeur, height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: p.saisie, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: choix.contains(valeur) ? valeur : null,
            isExpanded: true, isDense: true, dropdownColor: p.panneau,
            style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc),
            items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v != null) onChange(v);
            },
          ),
        ),
      );

  Widget _formulaire(Palette p) {
    final unite = _unite;
    final (libQte, libPrix) = switch (unite) {
      'sac' => ('Quantité de sacs :', "Prix d'achat d'un sac (FCFA) :"),
      'kilo' => ('Quantité reçue (kg) :', "Prix d'achat d'un kilo (FCFA) :"),
      _ => ('Quantité reçue (pièces) :', "Prix d'achat d'une pièce (FCFA) :"),
    };
    final credit = _reglement == 'À Crédit';
    return Container(
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
          child: Text('📥 NOUVEL ARRIVAGE',
              style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
        ),
        _etiq(p, "Date de l'arrivage :"),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          child: ChampDate(valeur: _date, onChange: (d) => setState(() => _date = d)),
        ),
        _etiq(p, 'Nature du produit :', haut: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 2, 15, 2),
          child: Row(children: [
            _liste(p, _produit, _catalogue.isEmpty ? [_vide] : [for (final c in _catalogue) c.nom], 190,
                (v) => setState(() => _produit = v)),
            const SizedBox(width: 6),
            SizedBox(
              width: 34, height: 28,
              child: FilledButton(
                onPressed: () => ouvrirPopupNouveauProduit(context, apresAjout: (nom) async {
                  await _chargerCatalogue();
                  setState(() => _produit = nom);
                  _cleStock.currentState?.recharger();
                }),
                style: FilledButton.styleFrom(
                    backgroundColor: p.succes, padding: EdgeInsets.zero, minimumSize: const Size(34, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('➕'),
              ),
            ),
          ]),
        ),
        _etiq(p, libQte, haut: 2),
        _champ(_qte, onChange: (v) {
          if (_produit == "Alvéole d'œufs" && !_bonusManuel) {
            final q = double.tryParse(v.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
            _bonus.text = '${(q ~/ 100)}';
          }
        }),
        if (unite == 'sac') ...[
          _etiq(p, '⚖️ Poids du sac (kg) :', couleur: p.alerte, gras: true, haut: 8),
          _champ(_poids, bordure: p.alerte),
        ],
        _etiq(p, libPrix, haut: 8),
        _champ(_prix),
        if (_produit == "Alvéole d'œufs") ...[
          _etiq(p, '🎁 Alvéoles Bonus (offertes par le fournisseur) :', couleur: p.succes, gras: true, haut: 8),
          _champ(_bonus, bordure: p.succes, onChange: (_) => _bonusManuel = true),
        ],
        _etiq(p, 'Mode de règlement :', haut: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 2, 15, 2),
          child: _liste(p, _reglement, const ['Espèces', 'À Crédit'], 220, (v) => setState(() => _reglement = v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(credit ? '🧑‍🌾 Nom du Fournisseur (obligatoire) :' : '🧑‍🌾 Nom du Fournisseur :',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: credit ? p.danger : p.accent)),
            ),
            SizedBox(
              width: 220, height: 34,
              child: TextField(
                controller: _fournisseur,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: credit ? 'Obligatoire à crédit' : 'Facultatif en Espèces',
                  hintStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: credit ? p.danger : p.accent)),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: SizedBox(
            width: double.infinity, height: 36,
            child: FilledButton(
              onPressed: _valider,
              style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text("➕ Enregistrer l'arrivage",
                  style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          child: SizedBox(
            width: double.infinity, height: 30,
            child: FilledButton(
              onPressed: _exporterPdf,
              style: FilledButton.styleFrom(backgroundColor: p.succes, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('🖨️ Exporter les arrivages en PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ onglets à droite
  Widget _droite() {
    return Builder(builder: (context) {
      final p = Palette.de(context);
      Widget onglet(int i, String t) => Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _onglet = i);
                if (i == 1) _chargerFournisseurs();
                if (i == 0) {
                  _chargerHistorique();
                  _cleStock.currentState?.recharger();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 32, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: _onglet == i ? p.accent : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                child: Text(t,
                    style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold,
                        color: _onglet == i ? Colors.white : p.txtDoux)),
              ),
            ),
          );
      return Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(15, 12, 15, 4),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [onglet(0, '📦 Stock & Historique'), onglet(1, '📊 Répertoire Fournisseurs')]),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _onglet == 0 ? _ongletStock(p) : _ongletFournisseurs(p),
          ),
        ),
      ]);
    });
  }

  Widget _ongletStock(Palette p) {
    var depense = 0.0;
    for (final a in _duJour) {
      depense += a.totalAchete;
    }
    return Column(key: const ValueKey('stock'), children: [
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 10, 15, 10),
          decoration: BoxDecoration(
              color: p.panneau, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.bordure)),
          child: TableauStock(key: _cleStock, autoriserSuppression: true),
        ),
      ),
      Container(
        height: 290,
        margin: const EdgeInsets.fromLTRB(15, 0, 15, 10),
        decoration: BoxDecoration(
            color: p.panneau, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.bordure)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Text('📅 ARRIVAGES ENREGISTRÉS LE :',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              const SizedBox(width: 10),
              ChampDate(
                  valeur: _dateHistorique, largeur: 120,
                  onChange: (d) {
                    setState(() => _dateHistorique = d);
                    _chargerHistorique();
                  }),
            ]),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(15, 2, 15, 4),
              decoration: BoxDecoration(
                  color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
              child: _duJour.isEmpty
                  ? Center(
                      child: Text('Aucun arrivage enregistré à cette date',
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: p.txtGris)))
                  : ListView(padding: const EdgeInsets.all(4), children: [for (final a in _duJour) _ligneArrivage(p, a)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                _duJour.isEmpty
                    ? ''
                    : '${_duJour.length} arrivage(s) — dépense totale du jour : ${milliersAnglais(depense)} FCFA',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
          ),
        ]),
      ),
    ]);
  }

  Widget _ligneArrivage(Palette p, Arrivage a) {
    final u = StockRepo.libelleUnite(a.unite);
    final prixTxt = u == 'kg' ? 'kg' : 'pièce';
    final detail = a.poidsSac > 0
        ? '${milliersAnglais(a.quantiteSaisie)} sac(s) × ${milliersAnglais(a.poidsSac, 1)} kg = ${milliersAnglais(a.quantiteAjoutee, 1)} kg'
        : '${milliersAnglais(a.quantiteAjoutee, 1)} $u';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.produit, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        Text(detail, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.succes)),
        if (a.fournisseur.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('🧑‍🌾 Fournisseur : ${a.fournisseur.trim()}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.accent)),
          ),
        Text('Coût : ${milliersAnglais(a.coutUnitaire)} F / $prixTxt   •   Total acheté : ${milliersAnglais(a.totalAchete)} F',
            style: TextStyle(fontSize: 10, color: p.txtGris)),
      ]),
    );
  }

  // ------------------------------------------------------------------ répertoire fournisseurs
  Widget _ongletFournisseurs(Palette p) {
    final st = _stats;
    final par = st?.parFournisseur ?? {};
    final noms = par.keys.toList()..sort((a, b) => par[b]!.livraisons.compareTo(par[a]!.livraisons));
    final valeurs = ['Tous les fournisseurs', ...noms];
    final filtre = valeurs.contains(_filtre) ? _filtre : 'Tous les fournisseurs';

    Widget carte({required Widget child, Color? bordure}) => Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: BoxDecoration(
              color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: bordure ?? p.bordure)),
          child: child,
        );

    final enfants = <Widget>[];
    if (par.isEmpty) {
      enfants.add(Padding(
        padding: const EdgeInsets.all(30),
        child: Center(
          child: Text("Aucun arrivage n'a encore de nom de fournisseur renseigné.",
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)),
        ),
      ));
    } else if (filtre == 'Tous les fournisseurs') {
      final meilleur = st!.meilleurPrix;
      if (meilleur.isNotEmpty) {
        final produits = meilleur.keys.toList()..sort();
        enfants.add(carte(
          bordure: p.succes,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🏆 MEILLEUR PRIX ACTUEL PAR PRODUIT',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.succes)),
              const SizedBox(height: 6),
              for (final prod in produits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Text(prod, style: TextStyle(fontSize: 11, color: p.txtPrinc)),
                    const Spacer(),
                    Text('${meilleur[prod]!.$1} — ${milliersAnglais(meilleur[prod]!.$2)} F/${StockRepo.libelleUnite(meilleur[prod]!.$3)}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.succes)),
                  ]),
                ),
            ]),
          ),
        ));
      }
      for (final nom in noms) {
        final f = par[nom]!;
        enfants.add(carte(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nom, style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                  Text('Dernière livraison : ${f.derniereDate.isEmpty ? '—' : f.derniereDate}',
                      style: TextStyle(fontSize: 10, color: p.txtGris)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('🔁 ${f.livraisons} livraison(s)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
                Text('💰 ${milliersAnglais(f.totalDepense)} FCFA dépensés au total',
                    style: TextStyle(fontSize: 11, color: p.txtDoux)),
              ]),
            ]),
          ),
        ));
      }
    } else {
      final f = par[filtre]!;
      final produits = f.produits.keys.toList()..sort();
      enfants.add(carte(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🧑‍🌾 $filtre', style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 4),
            Text(
                '🔁 ${f.livraisons} livraison(s) au total  •  💰 ${milliersAnglais(f.totalDepense)} FCFA dépensés  •  '
                'Dernière livraison : ${f.derniereDate.isEmpty ? '—' : f.derniereDate}',
                style: TextStyle(fontSize: 11, color: p.txtDoux)),
            const SizedBox(height: 10),
            for (final prod in produits)
              Builder(builder: (context) {
                final pf = f.produits[prod]!;
                final lib = StockRepo.libelleUnite(pf.unite);
                final moyen = pf.n > 0 ? pf.sommeCout / pf.n : 0.0;
                final m = st?.meilleurPrix[prod];
                final moinsCher = m != null && m.$1 == filtre;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Text('${moinsCher ? '🏆 ' : ''}$prod',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                    const Spacer(),
                    Text('${pf.n}× — moyen ${milliersAnglais(moyen)} F • meilleur ${milliersAnglais(pf.coutMin ?? 0)} F/$lib',
                        style: TextStyle(fontSize: 10, color: p.txtDoux)),
                  ]),
                );
              }),
          ]),
        ),
      ));
    }

    return Column(key: const ValueKey('fournisseurs'), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
        child: Row(children: [
          Text('🔎 Filtrer par fournisseur :', style: TextStyle(fontSize: 11, color: p.txtPrinc)),
          const SizedBox(width: 8),
          _liste(p, filtre, valeurs, 240, (v) => setState(() => _filtre = v)),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 12, 15, 15),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: ListView(padding: const EdgeInsets.all(4), children: enfants),
        ),
      ),
    ]);
  }
}

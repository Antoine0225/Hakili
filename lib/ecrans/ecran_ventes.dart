import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/stock_repo.dart';
import '../data/ventes_repo.dart';
import '../services/pdf_caisse.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../metier/modes_paiement.dart';
import '../widgets/champ_date.dart';
import '../widgets/choix_mode_paiement.dart';
import '../widgets/dialogue_periode.dart';
import '../widgets/dialogues.dart';
import '../widgets/mise_en_page_module.dart';
import '../widgets/tableau_stock.dart';
import '../widgets/toast.dart';
import 'dialogue_cloture_caisse.dart';
import 'vues_caisse.dart';

/// Module Ventes : à gauche la caisse (formulaire + livre du jour), à droite le stock en soute
/// ou la facture détaillée de la vente sélectionnée. Mêmes champs, mêmes boutons, mêmes messages.
class EcranVentes extends StatefulWidget {
  /// Actions qui ouvrent d'autres vues (Archives, Bilan global, Marges, PDF) : branchées par la coque.
  final void Function(String action)? onAction;
  const EcranVentes({super.key, this.onAction});

  @override
  State<EcranVentes> createState() => _EcranVentesState();
}

class _EcranVentesState extends State<EcranVentes> {
  static const _aucunStock = '(aucun stock disponible)';

  DateTime _date = aujourdhui();
  List<Vente> _ventes = [];
  List<Produit> _catalogue = [];
  Map<String, (double, double)> _stocks = {};
  List<String> _disponibles = [];
  String _produit = _aucunStock;
  String _reglement = 'Espèces';
  final _qte = TextEditingController();
  final _pu = TextEditingController();
  final _client = TextEditingController();
  Vente? _edition;
  Vente? _facture;
  bool _depuisArchives = false; // la facture ouverte vient-elle des Archives ? (bouton « Retour aux Archives »)
  String _vue = 'stock'; // 'stock' | 'bilan' | 'marges' | 'archives'
  final _cleStock = GlobalKey<TableauStockState>();

  @override
  void initState() {
    super.initState();
    _charger();
    ServiceCloud.versionDonnees.addListener(_charger);
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_charger);
    _qte.dispose();
    _pu.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final v = await VentesRepo.toutes();
    final c = await StockRepo.catalogue();
    final s = await StockRepo.tousLesStocks();
    if (!mounted) return;
    final dispo = [for (final p in c) if ((s[p.nom] ?? (0.0, 0.0)).$1 > 0.0001) p.nom];
    setState(() {
      _ventes = v;
      _catalogue = c;
      _stocks = s;
      _disponibles = dispo;
      if (_edition != null && !dispo.contains(_produit) && _produit != _aucunStock) {
        // en modification, le produit de la vente reste sélectionnable même si son stock est à 0
      } else if (dispo.isEmpty) {
        _produit = _aucunStock;
      } else if (!dispo.contains(_produit)) {
        _produit = dispo.first;
      }
      // la facture ouverte suit la base (modifiée par l'autre PC, par exemple)
      if (_facture != null) {
        final id = _facture!.id;
        _facture = v.where((x) => x.id == id).isEmpty ? null : v.firstWhere((x) => x.id == id);
      }
    });
  }

  // ------------------------------------------------------------------ alerte de stock sous le produit
  (String, Color) _alerteStock(Palette p) {
    final qte = (_stocks[_produit] ?? (0.0, 0.0)).$1;
    final unite = StockRepo.libelleUnite(_catalogue.where((c) => c.nom == _produit).map((c) => c.unite).firstOrNull ?? 'piece');
    if (qte <= 0) return ('', p.txtGris);
    if (qte < 5) return ('🚨 PÉNURIE — il ne reste que ${milliersAnglais(qte, 1)} $unite !', p.danger);
    return ('📦 Stock disponible : ${milliersAnglais(qte, 1)} $unite', p.txtGris);
  }

  // ------------------------------------------------------------------ enregistrer une vente
  Future<void> _ajouter() async {
    final p = Palette.de(context);
    if (_produit == _aucunStock) {
      Dialogues.erreur(context, 'Aucun Stock',
          "⚠️ Aucun produit n'est disponible en stock. Demandez au Patron d'enregistrer un arrivage.");
      return;
    }
    final qteBrute = _qte.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final puBrute = _pu.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (qteBrute.isEmpty || puBrute.isEmpty) {
      Dialogues.erreur(context, 'Champs Vides', '⚠️ Veuillez remplir les cases Quantité et Prix avant de valider.');
      return;
    }
    final qte = double.tryParse(qteBrute);
    final pu = double.tryParse(puBrute);
    if (qte == null || pu == null) {
      Dialogues.erreur(context, 'Saisie Invalide',
          '⚠️ Erreur de format : Veuillez entrer uniquement des chiffres entiers ou à virgule dans les cases Quantité et Prix.');
      return;
    }
    var client = _client.text.trim();
    if (_reglement == 'À Crédit') {
      if (client.isEmpty) {
        Dialogues.erreur(context, 'Nom du Client Obligatoire',
            '⛔ Impossible de valider une vente À CRÉDIT sans indiquer le nom du client.\n'
            'Veuillez renseigner le champ « Nom du Client » avant de continuer.');
        return;
      }
    } else if (client.isEmpty) {
      client = 'Client Comptant';
    }

    final (qteDispo, coutAchat) = _stocks[_produit] ?? (0.0, 0.0);
    var qteEffective = qteDispo;
    if (_edition != null && _edition!.type == _produit) qteEffective += _edition!.qte;
    if (qte > qteEffective + 0.0001) {
      final unite = StockRepo.libelleUnite(_catalogue.where((c) => c.nom == _produit).map((c) => c.unite).firstOrNull ?? 'piece');
      Dialogues.erreur(context, 'Stock Insuffisant',
          '⚠️ Il ne reste que ${milliersAnglais(qteEffective, 1)} $unite de « $_produit » en stock.\n'
          'Demandez un arrivage avant de continuer.');
      return;
    }

    final date = jourEnTexte(_date);
    if (_edition != null) {
      await VentesRepo.modifier(_edition!,
          date: date, type: _produit, qte: qte, pu: pu, reglement: _reglement, client: client, coutAchat: coutAchat);
      _edition = null;
      _facture = null;
    } else {
      await VentesRepo.ajouter(
          date: date, type: _produit, qte: qte, pu: pu, reglement: _reglement, client: client, coutAchat: coutAchat);
    }
    _qte.clear();
    _pu.clear();
    _client.clear();
    setState(() => _reglement = 'Espèces');
    await _charger();
    _cleStock.currentState?.recharger();
    if (mounted) Toast.afficher(context, '💰 Transaction enregistrée et synchronisée !', couleur: p.succes);
  }

  // ------------------------------------------------------------------ actions sur une facture
  void _preparerModification(Vente v) {
    setState(() {
      _edition = v;
      _date = lireJma(v.date) ?? _date;
      if (!_disponibles.contains(v.type)) _disponibles = [..._disponibles, v.type];
      _produit = v.type;
      _qte.text = nombreCourt(v.qte);
      _pu.text = nombreCourt(v.pu);
      _reglement = v.reglement;
      _client.text = (v.client.isNotEmpty && v.client != 'Client Comptant') ? v.client : '';
    });
  }

  Future<void> _encaisser(Vente v) async {
    final reste = v.reste < 0 ? 0.0 : v.reste;
    final mode = await choisirModePaiement(context,
        titre: '💵 Encaisser la dette',
        message: '${v.client.isEmpty ? 'Le client' : v.client} règle ${milliersAnglais(reste)} FCFA.');
    if (mode == null) return;
    await VentesRepo.reglerCredit(v, reste, mode: mode);
    await _charger();
  }

  Future<void> _figer(Vente v) async {
    await VentesRepo.cloturer(v);
    await _charger();
  }

  Future<void> _supprimer(Vente v) async {
    await VentesRepo.supprimer(v);
    setState(() {
      _facture = null;
      _vue = _depuisArchives ? 'archives' : (Session.estPatron ? 'bilan' : 'stock');
      _depuisArchives = false;
      if (_edition?.id == v.id) _edition = null;
    });
    await _charger();
    _cleStock.currentState?.recharger();
  }

  // ------------------------------------------------------------------ vues annexes de la caisse
  void _voirVue(String vue) => setState(() {
        _facture = null;
        _depuisArchives = false;
        _vue = vue;
      });

  void _ouvrirArchives() {
    if (!Session.estPatron) {
      Dialogues.erreur(context, 'Accès Restreint',
          '⚠️ Accès refusé. Seul le Patron Antoine possède la clé des archives historiques.');
      return;
    }
    _voirVue('archives');
  }

  Future<void> _exporterJournal() async {
    final periode = await choisirPeriode(context, titre: '📅 PLAGE DE DATES DU JOURNAL', texteBouton: '📊 Générer le PDF Filtré');
    if (periode == null || !mounted) return;
    try {
      final ok = await PdfCaisse.exporterJournal(_ventes, periode.debut, periode.fin, periode.texteDebut, periode.texteFin);
      if (ok && mounted) Toast.afficher(context, '🔥 Livre de compte exporté et classé !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
    }
  }

  Future<void> _ticket(Vente v) async {
    try {
      final idx = _ventes.indexWhere((x) => x.id == v.id);
      final ok = await PdfCaisse.ticketClient(v, idx);
      if (ok && mounted) Toast.afficher(context, '🔥 Ticket sur mesure enregistré !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur Ticket', 'Détails : $e');
    }
  }

  Widget _vueDroite() {
    if (_facture != null) return _vueFacture(Palette.papier, _facture!);
    switch (_vue) {
      case 'bilan':
        return VueBilanGlobal(ventes: _ventes);
      case 'marges':
        return VueMarges(ventes: _ventes, onRetourStock: () => _voirVue('stock'));
      case 'archives':
        return VueArchives(
            ventes: _ventes, onOuvrir: (v) => setState(() {
              _facture = v;
              _depuisArchives = true;
            }), onFermer: () => _voirVue('bilan'));
      default:
        return TableauStock(key: _cleStock);
    }
  }

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return MiseEnPageModule(
      droitePapier: true,
      gauche: Column(children: [
        _formulaire(p),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 2),
          child: Row(children: [
            Expanded(
              child: Text('📝 LIVRE DE CAISSE DU JOUR SÉLECTIONNÉ',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
            ),
            SizedBox(
              height: 26,
              child: FilledButton(
                onPressed: () => ouvrirClotureCaisse(context, _ventes, _date),
                style: FilledButton.styleFrom(
                    backgroundColor: p.cuivre, padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('🧮 Clôturer la caisse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
        _resumeModes(p),
        Expanded(child: _journal(p)),
        const SizedBox(height: 5),
      ]),
      droite: _vueDroite(),
    );
  }

  /// « 💵 Espèces … · 📱 Mobile … » pour le jour sélectionné.
  Widget _resumeModes(Palette p) {
    final r = ModesPaiement.calculer(_ventes, _date, _date);
    if (r.entrees < 0.5) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
            '💵 Espèces ${milliersAnglais(r.entreesEspeces)} F   ·   📱 Mobile ${milliersAnglais(r.entreesMobile)} F'
            '${r.entreesMobile > 0.5 ? '  (${r.partMobile.toStringAsFixed(0)} %)' : ''}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtDoux)),
      ),
    );
  }

  Widget _etiquette(Palette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 2),
        child: Align(alignment: Alignment.centerLeft, child: Text(t, style: TextStyle(fontSize: 11, color: p.txtPrinc))),
      );

  Widget _champ(TextEditingController c, double largeur, {String? indice, Color? bordure, bool numerique = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 2, 15, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: largeur, height: 34,
            child: TextField(
              controller: c,
              keyboardType: numerique ? TextInputType.number : TextInputType.text,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: indice, isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: bordure == null
                    ? null
                    : OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: bordure)),
              ),
            ),
          ),
        ),
      );

  Widget _liste(Palette p, String valeur, List<String> choix, ValueChanged<String> onChange) => Padding(
        padding: const EdgeInsets.fromLTRB(15, 2, 15, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 220, height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: p.saisie, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: choix.contains(valeur) ? valeur : null,
                isExpanded: true, isDense: true,
                dropdownColor: p.panneau,
                borderRadius: BorderRadius.circular(10),
                style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc),
                items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v != null) onChange(v);
                },
              ),
            ),
          ),
        ),
      );

  Widget _petitBouton(String t, Color fond, Color texte, VoidCallback action) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            height: 28,
            child: FilledButton(
              onPressed: action,
              style: FilledButton.styleFrom(
                  backgroundColor: fond, foregroundColor: texte, padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      );

  Widget _formulaire(Palette p) {
    final (alerte, couleurAlerte) = _alerteStock(p);
    final credit = _reglement == 'À Crédit';
    final enEdition = _edition != null;
    return Container(
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
          child: Text(enEdition ? '💾 MODIFIER LA TRANSACTION' : '📅 ENREGISTRER UNE TRANSACTION',
              style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold,
                  color: enEdition ? p.alerte : p.accent)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          child: Row(children: [
            _petitBouton('🗄️ Les Archives', p.cuivre, Colors.white, () => _ouvrirArchives()),
            _petitBouton('🖨️ Exporter PDF', p.succes, Colors.white, () => _exporterJournal()),
          ]),
        ),
        if (Session.estPatron)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 5),
            child: Row(children: [
              _petitBouton('↩️ Bilan global', p.neutre, p.txtPrinc, () => _voirVue('bilan')),
              _petitBouton('📊 Marges Réelles', p.cuivre, Colors.white, () => _voirVue('marges')),
            ]),
          ),
        _etiquette(p, "Date de l'opération :"),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChampDate(valeur: _date, onChange: (d) => setState(() => _date = d)),
          ),
        ),
        _etiquette(p, 'Nature de la marchandise vendue :'),
        _liste(p, _produit, _disponibles.isEmpty ? [_aucunStock] : _disponibles, (v) => setState(() => _produit = v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 2, 15, 0),
          child: Text(alerte, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: couleurAlerte)),
        ),
        _etiquette(p, 'Quantité exacte vendue (pièces/kg) :'),
        _champ(_qte, 120, numerique: true),
        _etiquette(p, 'Prix Unitaire négocié (FCFA) :'),
        _champ(_pu, 120, numerique: true),
        _etiquette(p, 'Mode de règlement :'),
        _liste(p, _reglement, const ['Espèces', 'Mobile Money', 'À Crédit'], (v) => setState(() => _reglement = v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(credit ? '👤 Nom du Client (obligatoire à crédit) :' : '👤 Nom du Client :',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: credit ? p.danger : p.alerte)),
            ),
            SizedBox(
              width: 220, height: 34,
              child: TextField(
                controller: _client,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: credit ? 'Nom du client — obligatoire' : 'Laisser vide = « Client Comptant »',
                  hintStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.alerte)),
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
              onPressed: _ajouter,
              style: FilledButton.styleFrom(
                  backgroundColor: enEdition ? p.alerte : p.cuivre,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(enEdition ? '💾 Confirmer la modification' : '➕ Ajouter la vente au journal',
                  style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ livre de caisse du jour
  Widget _journal(Palette p) {
    final jour = jourEnTexte(_date);
    final duJour = [for (var i = 0; i < _ventes.length; i++) if (_ventes[i].date.trim() == jour) (i, _ventes[i])];
    return Container(
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
      child: duJour.isEmpty
          ? Center(
              child: Text('Aucun flux enregistré à cette date',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: p.txtGris)))
          : ListView.builder(
              padding: const EdgeInsets.all(6),
              itemCount: duJour.length,
              itemBuilder: (context, k) {
                final (i, v) = duJour[k];
                final client = v.client.isEmpty ? 'Client Comptant' : v.client;
                final icone = v.estCredit ? '⚠️' : '💰';
                final texte = '${v.type} | $icone [${v.reglement}] 👤 $client\n'
                    '⚡ ${milliersAnglais(v.qte)} x ${milliersAnglais(v.pu)} F = ${milliersAnglais(v.total)} F';
                final fige = v.statut == 'Clôturé';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                  child: Material(
                    color: fige ? p.neutre : p.panneau2,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: p.survol2,
                      onTap: () => setState(() {
                        _facture = v;
                        _depuisArchives = false;
                      }),
                      child: Container(
                        height: 50, alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('$texte', maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.txtPrinc)),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ------------------------------------------------------------------ facture comptable détaillée
  Widget _vueFacture(Palette p, Vente v) {
    final idx = _ventes.indexWhere((x) => x.id == v.id);
    final reste = v.reste < 0 ? 0.0 : v.reste;
    String statutTexte;
    if (v.estCredit) {
      statutTexte = reste > 0.01
          ? '⚠️ CRÉDIT : Reste ${milliersAnglais(reste)} F dû par ${v.client}'
          : '✅ DETTE SOLDÉE (${v.client})';
    } else {
      statutTexte = '✅ ENCAISSÉ (${v.reglement})';
    }
    if (v.statut == 'Clôturé') statutTexte += ' [🔒 REÇU FIGÉ]';

    final txt = '📄 FACTURE COMPTABLE DÉTAILLÉE N°$idx\n'
        '${Session.nomFerme} — Moribabougou, Mali  (propulsé par Hakili de Antoine Software)\n'
        '-----------------------------------------------------------\n\n'
        "  • Date de l'opération     :  ${v.date}\n\n"
        '  • Nature du produit       :  ${v.type}\n\n'
        '  • Quantité livrée          :  ${milliersAnglais(v.qte, 1)}\n\n'
        '  • Prix unitaire appliqué   :  ${milliersAnglais(v.pu)} FCFA\n\n'
        '  • Règlement enregistré    :  $statutTexte\n\n'
        '-----------------------------------------------------------\n\n'
        ' 💰 MONTANT TOTAL TRANSACTION : ${milliersAnglais(v.total)} FCFA';

    Widget bouton(String t, Color fond, VoidCallback action, {Color? texte, double? largeur}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                    backgroundColor: fond, foregroundColor: texte ?? Colors.white, padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );

    final fige = v.statut == 'Clôturé';
    return Column(children: [
      if (_depuisArchives)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 28,
              child: FilledButton(
                onPressed: () => setState(() {
                  _facture = null;
                  _depuisArchives = false;
                  _vue = 'archives';
                }),
                style: FilledButton.styleFrom(
                    backgroundColor: p.cuivre, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('⬅️ Retour aux Archives', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      Expanded(
        child: Container(
          margin: EdgeInsets.fromLTRB(20, _depuisArchives ? 8 : 20, 20, 5),
          decoration: BoxDecoration(
              color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
            child: SizedBox(
              width: double.infinity,
              child: Text(txt,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Consolas', fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 5, 15, 20),
        child: Row(children: [
          if (!fige) ...[
            bouton('✏️ Modifier', p.alerte, () => _preparerModification(v)),
            if (v.estCredit && reste > 0.01) bouton('✅ Encaisser', p.succes, () => _encaisser(v)),
            bouton('🔒 Figer Vente', p.cuivre, () => _figer(v)),
            bouton('❌ Supprimer', p.danger, () => _supprimer(v)),
          ] else if (Session.estPatron)
            bouton('❌ Supprimer la Facture Verrouillée (Boss)', p.dangerSurvol, () => _supprimer(v)),
          bouton('🖨️ Ticket PDF', p.cuivre, () => _ticket(v)),
          if (Session.estPatron)
            bouton('↩️ Bilan global', p.neutre, () => _voirVue('bilan'), texte: p.txtPrinc)
          else
            bouton('↩️ Voir le Stock', p.neutre, () => _voirVue('stock'), texte: p.txtPrinc),
        ]),
      ),
    ]);
  }
}

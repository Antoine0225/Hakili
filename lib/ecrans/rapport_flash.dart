import 'package:flutter/material.dart';

import '../data/bandes_repo.dart';
import '../data/stock_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/compta_ponte.dart' as cp;
import '../metier/elevage_service.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogue_pin.dart';

/// 🔐 Rapport Flash : demande le PIN du Patron, puis affiche la performance bande par bande.
Future<void> ouvrirRapportFlash(BuildContext context) async {
  final ok = await demanderPinPatron(context,
      titre: '🔐 RAPPORT FLASH — CODE PIN', sousTitre: 'Performance Bande & Œufs — tapez votre code PIN Boss');
  if (!ok || !context.mounted) return;
  await ElevageService.verifierEpuisementStocksBandes();
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => const _FenetreRapportFlash());
}

class _Resultat {
  double coutProductionGlobal = 0, coutUnitaireFige = 0, caReel = 0, qteVendue = 0, margeBruteReelle = 0;
  double tauxPerte = 0, perteEstimee = 0;
  int? tempsDeVente;
  bool lissee = false, stabilisation = false, reformee = false;
  // pondeuses lissées
  int joursPonte = 0;
  double consoTotaleKg = 0, consoJourKg = 0, prixKg = 0, caReforme = 0, qteReforme = 0, margeReforme = 0;
  double? beneficeParAlveole;
  double beneficeTotal = 0;
}

double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);

/// Port de calculer_rapport_flash_bande.
Future<_Resultat> _calculer(Map<String, Object?> bande, List<Vente> ventes) async {
  final r = _Resultat();
  final produit = '${bande['produit_stock_nom'] ?? ''}';
  for (final v in ventes) {
    if (v.type == produit) {
      r.caReel += v.total;
      r.qteVendue += v.qte;
    }
  }
  var coutUnitaire = _d(bande['cout_unitaire_fige']);
  r.lissee = cp.estBandeLissee(bande);
  if (bande['type_elevage'] == 'Poules Pondeuses') {
    r.coutProductionGlobal = _d(bande['cout_direct_cumule_ponte']);
    if (_d(bande['alveoles_cumulees']) != 0) {
      coutUnitaire = _d(bande['cout_direct_cumule_ponte']) / _d(bande['alveoles_cumulees']);
    } else if (r.lissee) {
      coutUnitaire = cp.prixRevientAlveoleStabilisation;
      r.stabilisation = true;
    }
  } else {
    r.coutProductionGlobal = _d(bande['cout_direct_cumule']);
  }
  r.coutUnitaireFige = coutUnitaire;
  r.margeBruteReelle = r.caReel - (r.qteVendue * coutUnitaire);
  if (maturiteCommercialeJours.containsKey(bande['type_elevage']) && ('${bande['date_maturite_commerciale'] ?? ''}').isNotEmpty) {
    final debut = lireJma(bande['date_maturite_commerciale']);
    final fin = lireJma(bande['date_epuisement']);
    if (debut != null && fin != null) {
      final j = fin.difference(debut).inDays;
      r.tempsDeVente = j < 0 ? 0 : j;
    }
  }
  final init = _d(bande['effectif_initial']);
  r.tauxPerte = init > 0 ? _d(bande['morts_cumulees']) / init * 100.0 : 0.0;
  r.perteEstimee = coutUnitaire != 0 ? _d(bande['morts_cumulees']) * coutUnitaire : 0.0;
  if (r.lissee) {
    final nomReforme = 'Poules de réforme — Bande ${bande['nom']}';
    for (final v in ventes) {
      if (v.type == nomReforme) {
        r.caReforme += v.total;
        r.qteReforme += v.qte;
      }
    }
    final (_, coutReforme) = await StockRepo.stockProduit(nomReforme);
    r.margeReforme = r.caReforme - r.qteReforme * coutReforme;
    final auj = DateTime.now();
    r.joursPonte = cp.joursDePonte(bande, DateTime(auj.year, auj.month, auj.day));
    r.consoTotaleKg = _d(bande['conso_aliment_kg_cumulee']);
    r.consoJourKg = cp.quantiteConsommeeKgJour((bande['effectif_actuel'] as num?)?.toInt() ?? 0);
    r.prixKg = _d(bande['prix_kg_aliment']);
    r.reformee = cp.estReformee(bande);
    r.beneficeParAlveole = r.qteVendue > 0 ? r.margeBruteReelle / r.qteVendue : null;
    r.beneficeTotal = r.margeBruteReelle + r.margeReforme;
  }
  return r;
}

class _FenetreRapportFlash extends StatefulWidget {
  const _FenetreRapportFlash();

  @override
  State<_FenetreRapportFlash> createState() => _FenetreRapportFlashState();
}

class _FenetreRapportFlashState extends State<_FenetreRapportFlash> {
  List<Map<String, Object?>> _bandes = [];
  List<Vente> _ventes = [];
  String? _choix;
  Map<String, Object?>? _bande;
  _Resultat? _res;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  Future<void> _initialiser() async {
    _bandes = await BandesRepo.toutes();
    _ventes = await VentesRepo.toutes();
    if (_bandes.isNotEmpty) _choix = '${_bandes.first['nom']}';
    await _recalculer();
    if (mounted) setState(() => _charge = true);
  }

  Future<void> _recalculer() async {
    if (_choix == null) return;
    final base = _bandes.firstWhere((b) => '${b['nom']}' == _choix, orElse: () => _bandes.first);
    final b = await BandesRepo.parUid('${base['uid']}') ?? base; // toujours les chiffres à jour
    final r = await _calculer(b, _ventes);
    if (mounted) {
      setState(() {
        _bande = b;
        _res = r;
      });
    }
  }

  String _f(num v, [int dec = 0]) => milliersAnglais(v, dec);

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🐣 RAPPORT FLASH — PERFORMANCE BANDE & ŒUFS',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 12),
            if (!_charge)
              const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())
            else if (_bandes.isEmpty)
              Padding(padding: const EdgeInsets.all(20), child: Text('Aucune bande enregistrée.', style: TextStyle(color: p.txtDoux)))
            else ...[
              Container(
                width: 280, height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: p.saisie, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _choix, isExpanded: true, isDense: true, dropdownColor: p.panneau,
                    style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc),
                    items: [for (final b in _bandes) DropdownMenuItem(value: '${b['nom']}', child: Text('${b['nom']}'))],
                    onChanged: (v) async {
                      _choix = v;
                      await _recalculer();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
                  child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 8), child: _contenu(p)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 32,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc),
                child: const Text('Fermer', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _contenu(Palette p) {
    final b = _bande, r = _res;
    if (b == null || r == null) return const SizedBox.shrink();
    Widget ligne(String label, String valeur, [Color? c]) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: p.txtGris))),
            Text(valeur, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c ?? p.txtPrinc)),
          ]),
        );
    Color signe(double v) => v >= 0 ? p.succes : p.danger;
    final adulteNonLissee = b['stade_biologique'] == cp.stadeAdulte;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
        child: Text('🐣 ${b['nom']}  •  ${b['type_elevage']}  •  ${b['statut']}',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.accent)),
      ),
      if (r.lissee) ...[
        ligne('📅 Jours de ponte :', '${r.joursPonte} / ${cp.joursAvantReforme} (réforme)'),
        ligne('🐔 Poules vivantes :', '${b['effectif_actuel']} / ${b['effectif_initial']}'),
        ligne('🌾 Consommation par jour :', '${_f(r.consoJourKg, 1)} kg'),
        ligne('🌾 Consommation totale :', '${_f(r.consoTotaleKg)} kg  (≈ ${_f(r.consoTotaleKg / cp.poidsSacPonteKg, 1)} sacs de ${cp.poidsSacPonteKg.toInt()} kg)'),
        ligne("💲 Prix du kilo d'aliment :", '${_f(r.prixKg)} FCFA', p.or),
      ],
      ligne('💰 Coût de Production Global :', '${_f(r.coutProductionGlobal)} FCFA'),
      if (r.lissee) ...[
        ligne("🐔 Investissement initial (amorti sur ${cp.joursProductionPonte} j) :", '${_f(_d(b['cout_investissement_initial']))} FCFA'),
        ligne('📉 dont Amortissement déjà imputé :', '${_f(_d(b['cout_amortissement_cumule']))} FCFA'),
        ligne('🌾 dont Aliment consommé (réel) :', '${_f(_d(b['cout_aliment']))} FCFA', p.or),
      ] else ...[
        ligne(adulteNonLissee ? '🐔 dont Investissement (bande adulte) :' : '🐣 dont Prix Poussins :',
            '${_f(adulteNonLissee ? _d(b['cout_investissement_initial']) : _d(b['cout_initial_poussins']))} FCFA'),
        ligne('🌾 dont Coût Aliment cumulé :', '${_f(_d(b['cout_aliment']))} FCFA', p.or),
      ],
      ligne('🩺 dont Coût Santé cumulé :', '${_f(_d(b['cout_sante_cumule']))} FCFA', p.succes),
      ligne(r.lissee ? "🏷️ Coût de production d'une alvéole :" : '🏷️ Coût Unitaire Figé :', '${_f(r.coutUnitaireFige)} FCFA'),
      if (r.stabilisation)
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(cp.msgStabilisation, style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.alerte)),
          ),
        ),
      ligne("📈 Chiffre d'Affaires Réel :", '${_f(r.caReel)} FCFA', p.succes),
      ligne('📦 Quantité vendue :', _f(r.qteVendue, 1)),
      ligne('💵 Marge Brute Réelle :', '${_f(r.margeBruteReelle)} FCFA', signe(r.margeBruteReelle)),
      if (r.lissee) ...[
        if (r.beneficeParAlveole != null)
          ligne('🥚 Bénéfice par alvéole vendue :', '${_f(r.beneficeParAlveole!)} FCFA', signe(r.beneficeParAlveole!)),
        if (r.reformee || r.qteReforme > 0) ligne('🐔 Bénéfice de la réforme :', '${_f(r.margeReforme)} FCFA', signe(r.margeReforme)),
        ligne('🏆 Bénéfice total (œufs + réforme) :', '${_f(r.beneficeTotal)} FCFA', signe(r.beneficeTotal)),
      ],
      ligne('⏱️ Temps de Vente :', r.tempsDeVente != null ? '${r.tempsDeVente} jour(s)' : 'En cours (stock non épuisé)'),
      ligne('☠️ Taux de perte (effectif) :', '${r.tauxPerte.toStringAsFixed(1)} %', p.danger),
      ligne('📉 Perte financière estimée :', '${_f(r.perteEstimee)} FCFA', p.danger),
      if (r.lissee)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () => _journalProduction('${b['uid']}', '${b['nom']}'),
                  style: FilledButton.styleFrom(backgroundColor: p.cuivre),
                  child: const Text('📒 Journal de production', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () => _prixKg('${b['uid']}', '${b['nom']}', r.prixKg),
                  style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc),
                  child: const Text("✏️ Prix du kilo d'aliment", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }

  // ------------------------------------------------------------------ prix du kilo
  Future<void> _prixKg(String uid, String nom, double courant) async {
    final p = Palette.de(context);
    final c = TextEditingController(text: courant > 0 ? nombreCourt(courant) : '');
    var erreur = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
        Future<void> valider() async {
          final prix = double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));
          if (prix == null || prix <= 0) {
            setL(() => erreur = '⚠️ Entrez un prix du kilo supérieur à 0.');
            return;
          }
          await ElevageService.modifierPrixKg(uid, prix);
          if (ctx.mounted) Navigator.pop(ctx, true);
        }

        return Dialog(
          backgroundColor: p.panneau,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("🌾 Prix du kilo d'aliment — $nom",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                const SizedBox(height: 6),
                Text('Ce prix sert aux calculs des jours à venir.\nLes jours déjà comptés ne changent pas.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: TextField(
                      controller: c, autofocus: true, textAlign: TextAlign.center, keyboardType: TextInputType.number,
                      onSubmitted: (_) => valider(), decoration: const InputDecoration(hintText: 'Ex : 280')),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity, height: 36,
                  child: FilledButton(onPressed: valider, style: FilledButton.styleFrom(backgroundColor: p.succes), child: const Text('✅ Enregistrer')),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ]),
            ),
          ),
        );
      }),
    );
    Future.delayed(const Duration(milliseconds: 600), c.dispose); // après la fermeture animée du dialogue
    if (ok == true) await _recalculer();
  }

  // ------------------------------------------------------------------ journal de production
  Future<void> _journalProduction(String uid, String nom) async {
    final lignes = await ElevageService.journalProduction(uid);
    if (!mounted) return;
    final p = Palette.de(context);
    var totalKg = 0.0, totalCout = 0.0, totalAlv = 0.0;
    final rangees = <Widget>[];
    Widget cellule(String t, double larg, {bool gras = false, Color? c}) => SizedBox(
          width: larg,
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: gras ? FontWeight.bold : FontWeight.normal, color: c ?? p.txtPrinc)),
        );
    const largeurs = [86.0, 62.0, 86.0, 96.0, 70.0, 190.0];
    rangees.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(children: [
        for (final (i, n) in ['Date', 'Poules', 'Aliment (kg)', 'Coût aliment', 'Alvéoles', "Coût de l'alvéole"].indexed)
          cellule(n, largeurs[i], gras: true, c: p.accent),
      ]),
    ));
    for (final l in lignes) {
      final coutAli = _d(l['cout_aliment']), amort = _d(l['amortissement']), annexes = _d(l['annexes']);
      final alv = _d(l['alveoles']), conso = _d(l['conso_kg']);
      totalKg += conso;
      totalCout += coutAli;
      totalAlv += alv;
      final pr = cp.prixRevientAlveole(coutAli + amort + annexes, alv);
      String texte;
      Color couleur;
      if ((l['saisi'] ?? 0) == 0) {
        texte = 'jour sans récolte saisie';
        couleur = p.alerte;
      } else if (pr.stabilisation) {
        texte = cp.msgStabilisation;
        couleur = p.txtGris;
      } else {
        texte = '${milliersAnglais(pr.prix).replaceAll(',', ' ')} FCFA';
        couleur = p.txtPrinc;
      }
      rangees.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(children: [
          cellule('${l['jour']}', largeurs[0]),
          cellule('${l['vivants']}', largeurs[1]),
          cellule(milliersAnglais(conso, 1).replaceAll(',', ' '), largeurs[2]),
          cellule(milliersAnglais(coutAli).replaceAll(',', ' '), largeurs[3]),
          cellule(milliersAnglais(alv, 1).replaceAll(',', ' '), largeurs[4]),
          cellule(texte, largeurs[5], c: couleur),
        ]),
      ));
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('📒 JOURNAL DE PRODUCTION — $nom',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Text("Consommation, coût de l'aliment et coût de production de l'alvéole, jour par jour.",
                    style: TextStyle(fontSize: 11, color: p.txtDoux)),
              ),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10)),
                  child: lignes.isEmpty
                      ? Padding(padding: const EdgeInsets.all(20), child: Text("Aucune journée comptabilisée pour l'instant.", style: TextStyle(color: p.txtDoux)))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(width: 620, child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(6), children: rangees)),
                        ),
                ),
              ),
              if (lignes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Total : ${milliersAnglais(totalKg).replaceAll(',', ' ')} kg consommés • ${milliersAnglais(totalCout).replaceAll(',', ' ')} FCFA d\'aliment • '
                      '${milliersAnglais(totalAlv, 1).replaceAll(',', ' ')} alvéole(s) ramassée(s)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.or)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity, height: 32,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc),
                  child: const Text('Fermer', style: TextStyle(fontSize: 11)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

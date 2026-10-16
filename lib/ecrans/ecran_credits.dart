import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/arrivages_repo.dart';
import '../data/ventes_repo.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/choix_mode_paiement.dart';
import '../widgets/dialogues.dart';
import '../widgets/mise_en_page_module.dart';

/// Module Crédits : « Dettes Clients » et « Dettes Fournisseurs ». Chaque règlement s'ajoute au
/// livre de caisse du jour (entrée pour un client, sortie pour un fournisseur).
class EcranCredits extends StatefulWidget {
  const EcranCredits({super.key});

  @override
  State<EcranCredits> createState() => _EcranCreditsState();
}

class _EcranCreditsState extends State<EcranCredits> {
  int _onglet = 0;
  List<Vente> _creances = [];
  List<DetteFournisseur>? _dettes = [];
  String _filtreClient = 'Tous les clients';
  String _filtreFournisseur = 'Tous les fournisseurs';

  @override
  void initState() {
    super.initState();
    _charger();
    ServiceCloud.versionDonnees.addListener(_charger);
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_charger);
    super.dispose();
  }

  Future<void> _charger() async {
    final creances = await VentesRepo.creancesOuvertes();
    final dettes = await ArrivagesRepo.dettesActives();
    if (!mounted) return;
    setState(() {
      _creances = creances;
      _dettes = dettes;
    });
  }

  // ------------------------------------------------------------------ fenêtre d'acompte
  Future<void> _acompte({
    required String titre, required String sousTitre, required String indice,
    required Future<bool> Function(double) valider,
  }) async {
    final p = Palette.de(context);
    final c = TextEditingController();
    var erreur = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
        Future<void> ok() async {
          final m = double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));
          if (m == null) {
            setL(() => erreur = '⚠️ Montant invalide.');
            return;
          }
          if (m <= 0) {
            setL(() => erreur = '⚠️ Le montant doit être supérieur à zéro.');
            return;
          }
          if (!await valider(m)) return;
          if (ctx.mounted) Navigator.pop(ctx);
        }

        return Dialog(
          backgroundColor: p.panneau,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 20, 30, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                const SizedBox(height: 4),
                Text(sousTitre, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
                const SizedBox(height: 12),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: c, autofocus: true, textAlign: TextAlign.center,
                    keyboardType: TextInputType.number, onSubmitted: (_) => ok(),
                    decoration: InputDecoration(hintText: indice),
                  ),
                ),
                if (erreur.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 40,
                  child: FilledButton(
                    onPressed: ok,
                    style: FilledButton.styleFrom(backgroundColor: p.succes),
                    child: const Text("✅ Valider l'acompte", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(foregroundColor: p.txtGris),
                    child: const Text('Annuler')),
              ]),
            ),
          ),
        );
      }),
    );
    Future.delayed(const Duration(milliseconds: 600), c.dispose); // après la fermeture animée du dialogue
  }

  Future<void> _acompteClient(Vente v) => _acompte(
        titre: '💵 ACOMPTE — PAIEMENT PARTIEL',
        sousTitre: '${v.client.isEmpty ? 'Débiteur' : v.client} — reste dû : ${milliersAnglais(v.reste)} FCFA',
        indice: 'Montant reçu (FCFA)',
        valider: (m) async {
          final mode = await choisirModePaiement(context,
              titre: '💵 Acompte de ${milliersAnglais(m)} FCFA',
              message: '${v.client.isEmpty ? 'Le client' : v.client} vous verse ${milliersAnglais(m)} FCFA.');
          if (mode == null) return false;
          await VentesRepo.reglerCredit(v, m, mode: mode);
          await _charger();
          return true;
        },
      );

  Future<void> _soldeClient(Vente v) async {
    if (v.reste <= 0.01) return;
    final nom = v.client.isEmpty ? 'ce client' : v.client;
    final mode = await choisirModePaiement(context,
        titre: 'Confirmation', message: 'Solder entièrement la dette de $nom (${milliersAnglais(v.reste)} FCFA) ?');
    if (mode == null) return;
    await VentesRepo.reglerCredit(v, v.reste, mode: mode);
    await _charger();
  }

  Future<void> _acompteFournisseur(DetteFournisseur d) => _acompte(
        titre: '💵 ACOMPTE FOURNISSEUR',
        sousTitre: '${d.fournisseur} — reste à payer : ${milliersAnglais(d.resteDu)} FCFA',
        indice: 'Montant versé (FCFA)',
        valider: (m) async {
          final mode = await choisirModePaiement(context,
              titre: '💸 Acompte de ${milliersAnglais(m)} FCFA',
              message: 'Vous versez ${milliersAnglais(m)} FCFA à ${d.fournisseur}.',
              question: 'Comment avez-vous payé ?');
          if (mode == null) return false;
          await ArrivagesRepo.reglerDette(d.id, m, mode: mode);
          await _charger();
          return true;
        },
      );

  Future<void> _soldeFournisseur(DetteFournisseur d) async {
    if (d.resteDu <= 0.01) return;
    final mode = await choisirModePaiement(context,
        titre: 'Confirmation',
        message: 'Solder entièrement la dette envers ${d.fournisseur} (${milliersAnglais(d.resteDu)} FCFA) ?',
        question: 'Comment payez-vous ?');
    if (mode == null) return;
    await ArrivagesRepo.reglerDette(d.id, d.resteDu, mode: mode);
    await _charger();
  }

  // ------------------------------------------------------------------ construction
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return MiseEnPageModule(
      papierDirect: true,
      gauche: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('👤🧑‍🌾 DOUBLE SUIVI DES CRÉDITS',
                style: TextStyle(fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
            const SizedBox(height: 15),
            Text(
                '« Dettes Clients » : ce que les clients doivent à la ferme.\n'
                '« Dettes Fournisseurs » : ce que la ferme doit à ses fournisseurs.\n'
                "Encaissez un acompte ou soldez entièrement une dette — chaque mouvement "
                "s'ajoute automatiquement au livre de caisse du jour.",
                style: TextStyle(fontSize: 11, color: p.txtDoux)),
          ]),
        ),
      ]),
      droite: Builder(builder: (context) {
        final p = Palette.de(context);
        Widget onglet(int i, String t) => Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _onglet = i);
                  _charger();
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
        return Container(
          margin: const EdgeInsets.fromLTRB(15, 10, 15, 10),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.bordure)),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [onglet(0, '👤 Dettes Clients'), onglet(1, '🧑‍🌾 Dettes Fournisseurs')]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _onglet == 0 ? _clients(p) : _fournisseurs(p),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Widget _filtre(Palette p, String texte, String valeur, List<String> choix, ValueChanged<String> onChange) => Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
        child: Row(children: [
          Text(texte, style: TextStyle(fontSize: 11, color: p.txtPrinc)),
          const SizedBox(width: 8),
          Container(
            width: 220, height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: p.saisie, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: choix.contains(valeur) ? valeur : choix.first,
                isExpanded: true, isDense: true, dropdownColor: p.panneau,
                style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc),
                items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) {
                  if (v != null) onChange(v);
                },
              ),
            ),
          ),
        ]),
      );

  Widget _carte(Palette p, String nom, String sous, String reste, VoidCallback acompte, VoidCallback solde) => Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              Text(sous, style: TextStyle(fontSize: 10, color: p.txtGris)),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(reste, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.danger)),
              ),
            ]),
          ),
          Column(children: [
            SizedBox(
              width: 110, height: 32,
              child: FilledButton(
                onPressed: acompte,
                style: FilledButton.styleFrom(backgroundColor: p.alerte, padding: EdgeInsets.zero),
                child: const Text('💵 Acompte', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 170, height: 32,
              child: FilledButton(
                onPressed: solde,
                style: FilledButton.styleFrom(backgroundColor: p.succes, padding: EdgeInsets.zero),
                child: const Text('✅ Solder Entièrement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ]),
      );

  Widget _clients(Palette p) {
    final noms = {for (final v in _creances) v.client.isEmpty ? 'Débiteur' : v.client}.toList()..sort();
    final valeurs = ['Tous les clients', ...noms];
    final filtre = valeurs.contains(_filtreClient) ? _filtreClient : 'Tous les clients';
    final liste = filtre == 'Tous les clients'
        ? _creances
        : _creances.where((v) => (v.client.isEmpty ? 'Débiteur' : v.client) == filtre).toList();
    return Column(key: const ValueKey('clients'), children: [
      _filtre(p, '🔎 Filtrer par client :', filtre, valeurs, (v) => setState(() => _filtreClient = v)),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 12, 15, 15),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: liste.isEmpty
              ? Center(
                  child: Text('🔥 Aucun crédit en cours, tout est encaissé !',
                      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: p.succes)))
              : ListView(padding: const EdgeInsets.all(4), children: [
                  for (final v in liste)
                    _carte(p, v.client.isEmpty ? 'Débiteur' : v.client, '${v.date} — ${v.type}',
                        'Reste dû : ${milliersAnglais(v.reste)} FCFA', () => _acompteClient(v), () => _soldeClient(v)),
                ]),
        ),
      ),
    ]);
  }

  Widget _fournisseurs(Palette p) {
    final dettes = _dettes;
    if (dettes == null) {
      return Center(
        key: const ValueKey('fournisseurs'),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
              '⚠️ Lecture des dettes fournisseurs impossible pour le moment.\n'
              'Vos données ne sont PAS effacées : réessayez dans un instant.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.danger)),
        ),
      );
    }
    final noms = {for (final d in dettes) d.fournisseur}.toList()..sort();
    final valeurs = ['Tous les fournisseurs', ...noms];
    final filtre = valeurs.contains(_filtreFournisseur) ? _filtreFournisseur : 'Tous les fournisseurs';
    final liste = filtre == 'Tous les fournisseurs' ? dettes : dettes.where((d) => d.fournisseur == filtre).toList();
    return Column(key: const ValueKey('fournisseurs'), children: [
      _filtre(p, '🔎 Filtrer par fournisseur :', filtre, valeurs, (v) => setState(() => _filtreFournisseur = v)),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 12, 15, 15),
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: liste.isEmpty
              ? Center(
                  child: Text('🔥 Aucune dette fournisseur en cours, tout est réglé !',
                      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: p.succes)))
              : ListView(padding: const EdgeInsets.all(4), children: [
                  for (final d in liste)
                    _carte(p, d.fournisseur, '${d.date} — ${d.produit}',
                        'Reste à payer : ${milliersAnglais(d.resteDu)} FCFA', () => _acompteFournisseur(d), () => _soldeFournisseur(d)),
                ]),
        ),
      ),
    ]);
  }
}

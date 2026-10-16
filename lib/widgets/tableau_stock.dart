import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../data/stock_repo.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import 'dialogues.dart';
import 'toast.dart';

/// 📦 « MARCHANDISES ACTUELLEMENT DISPONIBLES EN SOUTE » : une ligne par produit du catalogue,
/// en vert si le stock est correct, en rouge « Pénurie » sous 5. Se met à jour tout seul quand
/// le stock change (vente, arrivage, synchronisation avec l'autre PC).
class TableauStock extends StatefulWidget {
  final bool autoriserSuppression;
  final VoidCallback? apresChangement;
  const TableauStock({super.key, this.autoriserSuppression = false, this.apresChangement});

  @override
  State<TableauStock> createState() => TableauStockState();
}

class TableauStockState extends State<TableauStock> {
  List<Produit> _catalogue = [];
  Map<String, (double, double)> _stocks = {};
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    recharger();
    ServiceCloud.versionDonnees.addListener(recharger);
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(recharger);
    super.dispose();
  }

  Future<void> recharger() async {
    final c = await StockRepo.catalogue();
    final s = await StockRepo.tousLesStocks();
    if (mounted) {
      setState(() {
        _catalogue = c;
        _stocks = s;
        _charge = true;
      });
    }
  }

  Future<void> _supprimer(String nom) async {
    final ok = await Dialogues.confirmer(
      context,
      'Supprimer le produit',
      "⚠️ Voulez-vous vraiment supprimer définitivement « $nom » du catalogue ?\n\n"
      "Il disparaîtra de la liste déroulante des ventes et du stock en soute, sur CE PC "
      "et sur l'autre PC dès la prochaine synchronisation Cloud.\n\nCette action est irréversible.",
    );
    if (!ok || !mounted) return;
    if (await StockRepo.supprimerProduit(nom)) {
      await recharger();
      widget.apresChangement?.call();
      if (mounted) Toast.afficher(context, '🗑️ « $nom » retiré du catalogue.', couleur: Palette.de(context).danger);
    } else if (mounted) {
      Dialogues.erreur(context, 'Erreur', '⚠️ La suppression du produit a échoué.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
        child: Text('📦 MARCHANDISES ACTUELLEMENT DISPONIBLES EN SOUTE',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: policeTexte, fontSize: 17, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          decoration: BoxDecoration(
              color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: !_charge
              ? const SizedBox.shrink()
              : _catalogue.isEmpty
                  ? Center(
                      child: Text('Aucun produit dans le catalogue pour le moment.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(5),
                      itemCount: _catalogue.length,
                      itemBuilder: (context, i) {
                        final prod = _catalogue[i];
                        final qte = (_stocks[prod.nom] ?? (0.0, 0.0)).$1;
                        final unite = StockRepo.libelleUnite(prod.unite);
                        final penurie = qte < 5;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                          decoration: BoxDecoration(
                              color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
                          child: Row(children: [
                            Expanded(
                              child: Text(prod.nom,
                                  style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                            ),
                            Text(penurie ? '🚨 Pénurie — ${milliersAnglais(qte, 1)} $unite' : '${milliersAnglais(qte, 1)} $unite',
                                style: TextStyle(
                                    fontFamily: policeTexte, fontSize: 14, fontWeight: FontWeight.bold,
                                    color: penurie ? p.danger : p.succes)),
                            if (widget.autoriserSuppression && Session.estPatron) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 32, height: 28,
                                child: FilledButton(
                                  onPressed: () => _supprimer(prod.nom),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: p.danger, padding: EdgeInsets.zero, minimumSize: const Size(32, 28),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                  child: const Text('🗑️', style: TextStyle(fontSize: 13)),
                                ),
                              ),
                            ],
                          ]),
                        );
                      },
                    ),
        ),
      ),
    ]);
  }
}

/// Fenêtre « ➕ NOUVEAU PRODUIT » (nom + unité de vente). Appelle [apresAjout] avec le nom ajouté.
Future<void> ouvrirPopupNouveauProduit(BuildContext context, {void Function(String nom)? apresAjout}) async {
  final p = Palette.de(context);
  final nom = TextEditingController();
  var unite = 'piece';
  var erreur = '';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
      Future<void> valider() async {
        final n = nom.text.trim();
        if (n.isEmpty) {
          setL(() => erreur = '⚠️ Le nom du produit est obligatoire.');
          return;
        }
        if (await StockRepo.ajouterProduit(n, unite)) {
          if (ctx.mounted) Navigator.pop(ctx);
          apresAjout?.call(n);
        } else {
          setL(() => erreur = '⚠️ Ce produit existe déjà dans le catalogue.');
        }
      }

      Widget choix(String valeur, String texte) => RadioListTile<String>(
            value: valeur, groupValue: unite, dense: true, activeColor: p.cuivre,
            contentPadding: EdgeInsets.zero,
            title: Text(texte, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
            onChanged: (v) => setL(() => unite = v ?? 'piece'),
          );

      return Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 22, 30, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('➕ NOUVEAU PRODUIT', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              const SizedBox(height: 4),
              Text('Ex : Piment, Riz, Farine…', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: p.txtDoux)),
              const SizedBox(height: 14),
              TextField(
                controller: nom, autofocus: true, textAlign: TextAlign.center,
                onSubmitted: (_) => valider(),
                decoration: const InputDecoration(hintText: 'Nom du produit'),
              ),
              const SizedBox(height: 12),
              Text('Unité de vente :', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
              choix('sac', "📦 Sac et Kilo (poids du sac à l'arrivage)"),
              choix('kilo', '⚖️ Au Kilo (kg)'),
              choix('piece', '🔢 À la Pièce/Unité'),
              if (erreur.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(erreur, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: valider,
                style: FilledButton.styleFrom(backgroundColor: p.succes, minimumSize: const Size(0, 40)),
                child: const Text('✅ Ajouter au catalogue', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: p.txtGris),
                child: const Text('Annuler'),
              ),
            ]),
          ),
        ),
      );
    }),
  );
  Future.delayed(const Duration(milliseconds: 600), nom.dispose); // après la fermeture animée du dialogue
}

import 'package:flutter/material.dart';

import '../../data/bandes_repo.dart';
import '../../metier/elevage_service.dart';
import '../../theme/palette.dart';
import '../../utilitaires/formats.dart';
import '../../widgets/dialogues.dart';
import '../../widgets/toast.dart';

/// Les deux fenêtres rapides de l'Élevage : 🌾 Nouvel Arrivage Aliment et 🩺 Nouveau Frais de Santé.
/// [apres] est appelée après un enregistrement réussi pour rafraîchir les écrans.
Future<void> ouvrirPopupArrivageAliment(BuildContext context, {VoidCallback? apres, String? bandeActiveUid}) =>
    _ouvrir(context, aliment: true, apres: apres, bandeActiveUid: bandeActiveUid);

Future<void> ouvrirPopupFraisSante(BuildContext context, {VoidCallback? apres, String? bandeActiveUid}) =>
    _ouvrir(context, aliment: false, apres: apres, bandeActiveUid: bandeActiveUid);

Future<void> _ouvrir(BuildContext context, {required bool aliment, VoidCallback? apres, String? bandeActiveUid}) async {
  final bandes = [for (final b in await BandesRepo.toutes()) if (b['statut'] != 'Épuisée') b];
  if (!context.mounted) return;
  if (bandes.isEmpty) {
    Dialogues.info(context, 'Aucune bande active', "Créez d'abord une bande dans l'onglet « ➕ Créer ».");
    return;
  }
  final p = Palette.de(context);
  final couleur = aliment ? p.or : p.succes;
  final noms = {for (final b in bandes) '${b['nom']}  (${b['type_elevage']})': '${b['uid']}'};
  final libelles = noms.keys.toList();
  var choix = libelles.firstWhere((l) => noms[l] == bandeActiveUid, orElse: () => libelles.first);
  var typeAliment = 'Démarrage';
  var categorie = 'Vaccination';
  final c1 = TextEditingController(), c2 = TextEditingController();
  var erreur = '';

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
      double? nombre(String t) => double.tryParse(t.trim().replaceAll(' ', '').replaceAll(',', '.'));

      String calcul() {
        final nb = nombre(c1.text) ?? 0, prix = nombre(c2.text) ?? 0;
        final poids = (nb < 0 ? 0 : nb) * poidsSacAlimentKg;
        final kg = poids > 0 ? prix / poids : 0.0;
        return '≈ ${milliersAnglais(poids)} kg au total  •  ${nombreCourt(nb < 0 ? 0 : nb)} sac × $poidsSacAlimentKg kg  •  ${milliersAnglais(kg)} FCFA/kg';
      }

      Future<void> valider() async {
        final uid = noms[choix];
        if (uid == null) {
          setL(() => erreur = '⚠️ Sélectionnez une bande valide.');
          return;
        }
        String? message;
        if (aliment) {
          final nb = nombre(c1.text);
          if (nb == null || nb <= 0) {
            setL(() => erreur = '⚠️ Le nombre de sacs doit être un nombre positif.');
            return;
          }
          final prix = nombre(c2.text);
          if (prix == null || prix <= 0) {
            setL(() => erreur = "⚠️ Le prix d'achat total doit être un nombre positif.");
            return;
          }
          message = await ElevageService.enregistrerArrivageAliment(uid, typeAliment, nb, prix);
        } else {
          final montant = nombre(c2.text);
          if (montant == null || montant <= 0) {
            setL(() => erreur = '⚠️ Le montant doit être un nombre positif.');
            return;
          }
          message = await ElevageService.enregistrerFraisSante(uid, categorie, c1.text.trim(), montant);
        }
        if (ctx.mounted) Navigator.pop(ctx);
        apres?.call();
        if (message != null && context.mounted) Toast.afficher(context, message, couleur: p.succes, dureeMs: 2600);
      }

      Widget lib(String t) => Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 10),
            child: Align(alignment: Alignment.centerLeft, child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtDoux))),
          );

      Widget liste(String valeur, List<String> choix, ValueChanged<String> onChange) => Container(
            height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: p.saisie, borderRadius: BorderRadius.circular(8), border: Border.all(color: couleur)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: valeur, isExpanded: true, isDense: true, dropdownColor: p.panneau,
                style: TextStyle(fontFamily: policeTexte, fontSize: 13, color: p.txtPrinc),
                items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v != null) onChange(v);
                },
              ),
            ),
          );

      InputDecoration deco(String indice) => InputDecoration(
            hintText: indice, isDense: true,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: couleur)),
          );

      return Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: couleur)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(aliment ? '🌾 NOUVEL ARRIVAGE ALIMENT' : '🩺 NOUVEAU FRAIS DE SANTÉ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: couleur)),
              const SizedBox(height: 4),
              Text(
                  aliment
                      ? "Réservé au personnel autorisé — le coût s'ajoute immédiatement\nau prix de revient de la bande choisie."
                      : "Vaccination, antibiotique, vitamine, visite vétérinaire...\nLe coût s'ajoute immédiatement au prix de revient de la bande.",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
              lib('🐣 Bande concernée'),
              liste(choix, libelles, (v) => setL(() => choix = v)),
              if (aliment) ...[
                lib("🌽 Type d'aliment"),
                liste(typeAliment, const ['Démarrage', 'Croissance', 'Finition', 'Ponte'], (v) => setL(() => typeAliment = v)),
                lib('📦 Nombre de sacs (sac standard de $poidsSacAlimentKg kg)'),
                TextField(controller: c1, keyboardType: TextInputType.number, onChanged: (_) => setL(() {}), decoration: deco('Ex : 10')),
                lib("💰 Prix d'achat total (FCFA)"),
                TextField(controller: c2, keyboardType: TextInputType.number, onChanged: (_) => setL(() {}), decoration: deco('Ex : 125000')),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(calcul(), style: TextStyle(fontSize: 10, color: p.txtDoux)),
                ),
              ] else ...[
                lib('💊 Catégorie'),
                liste(categorie, const ['Vaccination', 'Antibiotique', 'Vitamine', 'Vermifuge', 'Visite vétérinaire', 'Autre soin'],
                    (v) => setL(() => categorie = v)),
                lib('📝 Détail (facultatif)'),
                TextField(controller: c1, decoration: deco('Ex : Newcastle, Vitamine C...')),
                lib('💰 Montant (FCFA)'),
                TextField(controller: c2, keyboardType: TextInputType.number, decoration: deco('Ex : 15000')),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(erreur, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: valider,
                  style: FilledButton.styleFrom(backgroundColor: aliment ? p.or : p.succes, foregroundColor: aliment ? Colors.black : Colors.white),
                  child: Text(aliment ? "💾 Enregistrer l'Arrivage" : '💾 Enregistrer le Frais de Santé',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: p.txtGris), child: const Text('Annuler')),
            ]),
          ),
        ),
      );
    }),
  );
  Future.delayed(const Duration(milliseconds: 600), c1.dispose); // après la fermeture animée du dialogue
  Future.delayed(const Duration(milliseconds: 600), c2.dispose); // après la fermeture animée du dialogue
}

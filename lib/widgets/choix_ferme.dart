import 'dart:io';

import 'package:flutter/material.dart';

import '../data/base_locale.dart';
import '../data/parametres.dart';
import '../theme/palette.dart';

/// 🏡 « Une ferme existe déjà sur ce PC » : renvoie 'garder', 'retrouver', 'nouvelle' ou null (annulé).
Future<String?> proposerChoixFerme(BuildContext context, String ancienProprietaire, String nouvelEmail) async {
  final p = Palette.de(context);
  final nomActuel = (await Parametres.lire('nom_ferme')).trim().isEmpty ? 'sans nom' : (await Parametres.lire('nom_ferme')).trim();
  final archive = await BaseLocale.fichierFermeArchivee(nouvelEmail);
  final aUneArchive = await File(archive).exists();
  final nomArchive = aUneArchive ? ((await BaseLocale.nomFermeDans(archive)).isEmpty ? 'sans nom' : await BaseLocale.nomFermeDans(archive)) : '';
  if (!context.mounted) return null;

  Widget bouton(String t, Color fond, Color texte, String valeur, BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
        child: SizedBox(
          width: double.infinity, height: 44,
          child: FilledButton(
            onPressed: () => Navigator.pop(ctx, valeur),
            style: FilledButton.styleFrom(backgroundColor: fond, foregroundColor: texte, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(t, style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
      );
  Widget note(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: p.txtGris)),
      );

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏡', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 2),
            Text('Une ferme existe déjà sur ce PC', style: TextStyle(fontFamily: policeTexte, fontSize: 17, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
              child: Text("Ferme « $nomActuel » — liée à l'adresse $ancienProprietaire\nVous vous connectez avec : $nouvelEmail",
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
            ),
            bouton('✅ Continuer avec la ferme « $nomActuel »', p.succes, Colors.white, 'garder', ctx),
            note('Ses données seront rattachées à votre adresse.'),
            if (aUneArchive) ...[
              bouton('📂 Retrouver ma ferme « $nomArchive »', p.cuivre, Colors.white, 'retrouver', ctx),
              note("La ferme actuelle est mise de côté, rien n'est supprimé."),
            ],
            bouton('🆕 Créer une nouvelle ferme', p.neutre, p.txtPrinc, 'nouvelle', ctx),
            note("Base vierge : aucune donnée de l'autre adresse n'y sera mélangée.\nLa ferme actuelle est mise de côté, rien n'est supprimé."),
            TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: p.txtGris), child: const Text('Annuler')),
          ]),
        ),
      ),
    ),
  );
}

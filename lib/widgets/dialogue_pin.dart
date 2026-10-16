import 'package:flutter/material.dart';

import '../data/parametres.dart';
import '../securite/pin.dart';
import '../theme/palette.dart';

/// Demande le code PIN du Patron avant une action sensible. Renvoie true si le code est bon.
Future<bool> demanderPinPatron(BuildContext context, {required String titre, required String sousTitre}) async {
  final p = Palette.de(context);
  final c = TextEditingController();
  var erreur = '';
  var enCours = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
      Future<void> valider() async {
        if (enCours) return;
        setL(() => enCours = true);
        final bon = await Pin.verifier(c.text.trim(), await Parametres.lire('pin_patron'));
        if (bon) {
          if (ctx.mounted) Navigator.pop(ctx, true);
        } else {
          setL(() {
            erreur = '⛔ Code PIN incorrect.';
            enCours = false;
          });
        }
      }

      return Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(titre, style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              const SizedBox(height: 4),
              Text(sousTitre, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: c, autofocus: true, obscureText: true, obscuringCharacter: '●',
                  textAlign: TextAlign.center, onSubmitted: (_) => valider(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity, height: 40,
                child: FilledButton(
                  onPressed: enCours ? null : valider,
                  child: const Text('🔓 Valider', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(foregroundColor: p.txtGris),
                  child: const Text('Annuler')),
            ]),
          ),
        ),
      );
    }),
  );
  Future.delayed(const Duration(milliseconds: 600), c.dispose); // après la fermeture animée du dialogue
  return ok ?? false;
}

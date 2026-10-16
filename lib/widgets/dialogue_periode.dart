import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import 'champ_date.dart';
import 'dialogues.dart';

class PeriodeChoisie {
  final DateTime debut, fin; // fin = dernier instant du dernier jour
  final String texteDebut, texteFin;
  const PeriodeChoisie(this.debut, this.fin, this.texteDebut, this.texteFin);
}

const _moisNoms = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
  'Septembre', 'Octobre', 'Novembre', 'Décembre'
];

/// La fenêtre « Sélection de la période » : deux calendriers « Du » / « Au », ou le choix d'un mois entier
/// qui remplit les deux dates (ajustables ensuite). Renvoie null si on annule.
Future<PeriodeChoisie?> choisirPeriode(BuildContext context,
    {required String titre, required String texteBouton, bool moisCourantParDefaut = false}) {
  final p = Palette.de(context);
  var du = aujourdhui();
  var au = aujourdhui();
  String? mois;
  var annee = DateTime.now().year;
  if (moisCourantParDefaut) {
    mois = _moisNoms[DateTime.now().month - 1];
    du = DateTime(annee, DateTime.now().month, 1);
    au = DateTime(annee, DateTime.now().month + 1, 0);
  }

  return showDialog<PeriodeChoisie>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
      void appliquerMois() {
        if (mois == null) return;
        final num = _moisNoms.indexOf(mois!) + 1;
        du = DateTime(annee, num, 1);
        au = DateTime(annee, num + 1, 0);
      }

      Widget liste(String? valeur, List<String> choix, double largeur, ValueChanged<String> onChange) => Container(
            width: largeur, height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: p.saisie, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: valeur, isExpanded: true, isDense: true, dropdownColor: p.panneau,
                hint: Text('(aucun)', style: TextStyle(fontSize: 12, color: p.txtGris)),
                style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc),
                items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) {
                  if (v != null) onChange(v);
                },
              ),
            ),
          );

      return Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(titre, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: p.accent)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Du :  ', style: TextStyle(color: p.txtPrinc)),
                ChampDate(valeur: du, largeur: 150, onChange: (d) => setL(() => du = d)),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Au :  ', style: TextStyle(color: p.txtPrinc)),
                ChampDate(valeur: au, largeur: 150, onChange: (d) => setL(() => au = d)),
              ]),
              const SizedBox(height: 16),
              Text('— et / ou —  un mois entier :', style: TextStyle(fontSize: 11, color: p.txtDoux)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                liste(mois, _moisNoms, 140, (v) => setL(() {
                      mois = v;
                      appliquerMois();
                    })),
                const SizedBox(width: 10),
                liste('$annee', [for (var a = DateTime.now().year - 5; a <= DateTime.now().year + 1; a++) '$a'], 90,
                    (v) => setL(() {
                          annee = int.parse(v);
                          appliquerMois();
                        })),
              ]),
              const SizedBox(height: 10),
              Text(
                  "Le choix d'un mois remplit automatiquement « Du » et « Au »,\n"
                  'que vous pouvez ensuite ajuster dans les calendriers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtGris)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  if (du.isAfter(au)) {
                    Dialogues.erreur(ctx, 'Période invalide',
                        '⚠️ La date « Du » doit être antérieure ou égale à la date « Au ».');
                    return;
                  }
                  Navigator.pop(
                      ctx,
                      PeriodeChoisie(du, DateTime(au.year, au.month, au.day, 23, 59, 59, 999), jourEnTexte(du),
                          jourEnTexte(au)));
                },
                style: FilledButton.styleFrom(backgroundColor: p.succes, minimumSize: const Size(0, 38)),
                child: Text(texteBouton, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
      );
    }),
  );
}

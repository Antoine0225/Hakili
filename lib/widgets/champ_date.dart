import 'package:flutter/material.dart';

import '../utilitaires/formats.dart';

/// Le champ « Date de l'opération » : affiche JJ/MM/AAAA et ouvre un calendrier au clic
/// (équivalent du DateEntry de la version Python, mêmes couleurs vert forêt / blanc).
class ChampDate extends StatelessWidget {
  final DateTime valeur;
  final ValueChanged<DateTime> onChange;
  final double largeur;
  const ChampDate({super.key, required this.valeur, required this.onChange, this.largeur = 130});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: valeur,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            locale: const Locale('fr'),
          );
          if (d != null) onChange(DateTime(d.year, d.month, d.day));
        },
        child: Container(
          width: largeur, height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: const Color(0xFF123229), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Text(jourEnTexte(valeur), style: const TextStyle(fontSize: 12, color: Colors.white))),
            const Icon(Icons.calendar_month, size: 15, color: Colors.white70),
          ]),
        ),
      ),
    );
  }
}

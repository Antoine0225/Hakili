import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../utilitaires/formats.dart';

/// Une série de barres (ex. « Chiffre d'affaires » sur 6 mois).
class SerieBarres {
  final String nom;
  final Color couleur;
  final List<double> valeurs;
  final List<Color>? couleursParBarre; // pour colorer chaque barre séparément (vert / rouge...)
  const SerieBarres(this.nom, this.couleur, this.valeurs, {this.couleursParBarre});
}

/// Graphique en barres simple, groupé, gérant les valeurs négatives. Dessiné avec Flutter seul
/// (aucune bibliothèque de graphiques ajoutée). L'axe réutilise `echelleAgreable` / `formaterAxe` du logiciel.
class GraphiqueBarres extends StatelessWidget {
  final List<String> etiquettes;
  final List<SerieBarres> series;
  final double hauteur;
  final Palette palette;
  final bool legende;
  const GraphiqueBarres({
    super.key, required this.etiquettes, required this.series, required this.palette,
    this.hauteur = 190, this.legende = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (legende && series.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(spacing: 14, runSpacing: 4, children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.couleur, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Text(s.nom, style: TextStyle(fontSize: 10.5, color: palette.txtDoux)),
              ]),
          ]),
        ),
      SizedBox(
        height: hauteur,
        width: double.infinity,
        child: CustomPaint(painter: _PeintreBarres(etiquettes, series, palette)),
      ),
    ]);
  }
}

class _PeintreBarres extends CustomPainter {
  final List<String> etiquettes;
  final List<SerieBarres> series;
  final Palette p;
  _PeintreBarres(this.etiquettes, this.series, this.p);

  static String _etiq(double v) => v < 0 ? '-${formaterAxe(-v)}' : formaterAxe(v);

  TextPainter _tp(String t, double taille, Color c, {FontWeight poids = FontWeight.normal}) => TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: policeTexte, fontSize: taille, color: c, fontWeight: poids)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const gauche = 46.0, bas = 22.0, haut = 16.0, droite = 6.0;
    final zone = Rect.fromLTWH(gauche, haut, size.width - gauche - droite, size.height - haut - bas);
    if (zone.width <= 20 || zone.height <= 20 || etiquettes.isEmpty || series.isEmpty) return;

    var vmax = 0.0, vmin = 0.0;
    for (final s in series) {
      for (final v in s.valeurs) {
        vmax = math.max(vmax, v);
        vmin = math.min(vmin, v);
      }
    }
    final (pas, _) = echelleAgreable(math.max(vmax, -vmin), 4);
    var haute = vmax > 0 ? (vmax / pas).ceil() * pas : 0.0;
    final basse = vmin < 0 ? -((-vmin) / pas).ceil() * pas : 0.0;
    if (haute == 0 && basse == 0) haute = pas;
    final etendue = haute - basse;
    double y(double v) => zone.top + (haute - v) / etendue * zone.height;

    // grille + axe vertical
    final trait = Paint()..color = p.bordure..strokeWidth = 1;
    final nbGrad = ((haute - basse) / pas).round();
    for (var i = 0; i <= nbGrad; i++) {
      final v = basse + i * pas;
      final yy = y(v);
      canvas.drawLine(Offset(zone.left, yy), Offset(zone.right, yy), trait);
      final tp = _tp(_etiq(v), 9, p.txtGris);
      tp.paint(canvas, Offset(zone.left - 6 - tp.width, yy - tp.height / 2));
    }
    canvas.drawLine(Offset(zone.left, y(0)), Offset(zone.right, y(0)),
        Paint()..color = p.txtGris..strokeWidth = 1.2);

    // barres
    final n = etiquettes.length;
    final largeurGroupe = zone.width / n;
    final nbS = series.length;
    final largeurBarre = math.min(38.0, largeurGroupe * 0.72 / nbS);
    for (var g = 0; g < n; g++) {
      final debutGroupe = zone.left + g * largeurGroupe + (largeurGroupe - largeurBarre * nbS) / 2;
      for (var k = 0; k < nbS; k++) {
        final s = series[k];
        if (g >= s.valeurs.length) continue;
        final v = s.valeurs[g];
        if (v == 0) continue;
        final x = debutGroupe + k * largeurBarre;
        final y0 = y(0), y1 = y(v);
        final rect = Rect.fromLTRB(x + 1.5, math.min(y0, y1), x + largeurBarre - 1.5, math.max(y0, y1));
        final couleur = (s.couleursParBarre != null && g < s.couleursParBarre!.length) ? s.couleursParBarre![g] : s.couleur;
        const r = Radius.circular(4);
        final rr = v > 0
            ? RRect.fromRectAndCorners(rect, topLeft: r, topRight: r)
            : RRect.fromRectAndCorners(rect, bottomLeft: r, bottomRight: r);
        canvas.drawRRect(rr, Paint()..color = couleur);
        if (largeurBarre >= 22 || nbS == 1) {
          final tp = _tp(_etiq(v), 9, p.txtPrinc, poids: FontWeight.bold);
          final yy = v > 0 ? rect.top - tp.height - 1 : rect.bottom + 1;
          tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, yy));
        }
      }
      final tp = _tp(etiquettes[g], 10, p.txtDoux);
      tp.paint(canvas, Offset(zone.left + g * largeurGroupe + (largeurGroupe - tp.width) / 2, zone.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreBarres old) => true;
}

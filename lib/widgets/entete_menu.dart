import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

const double largeurMenu = 219;
const double hauteurEnteteMenu = 181;

/// L'en-tête du menu : plume + collines (image), mention « EXPLOITATION », nom de la ferme en grand
/// (première lettre dorée), filet doré orné de deux losanges. Même composition que
/// fabriquer_entete_menu() de assets_design.py ; le nom se réduit tout seul s'il est long.
class EnteteMenu extends StatelessWidget {
  final String nomFerme;
  const EnteteMenu({super.key, required this.nomFerme});

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: largeurMenu,
      height: hauteurEnteteMenu,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(sombre ? 'assets/entete_sombre.jpg' : 'assets/entete_clair.jpg',
              fit: BoxFit.fill, filterQuality: FilterQuality.high, gaplessPlayback: true),
          CustomPaint(painter: _PeintreEntete(nomFerme, sombre)),
        ],
      ),
    );
  }
}

class _PeintreEntete extends CustomPainter {
  final String nomFerme;
  final bool sombre;
  _PeintreEntete(this.nomFerme, this.sombre);

  static const _or = Color(0xFFE4B53E);

  @override
  void paint(Canvas canvas, Size size) {
    // Tout est dessiné dans le repère de la maquette (438 x 362) puis réduit de moitié.
    canvas.scale(size.width / 438.0);

    final nom = (nomFerme.trim().isEmpty ? 'ANTOINE SOFTWARE' : nomFerme.trim()).toUpperCase();
    final couleurNom = sombre ? const Color(0xFFF3EFE2) : const Color(0xFFF4F1E6);
    const xNom = 112.0, xMention = 116.0, xFin = 358.0;
    const largeurMax = xFin - xNom;
    const baseNom = 113.0, baseMention = 63.0, yFiletY = 139.0;

    TextPainter mesure(String t, double taille, FontWeight poids, Color c, {double espacement = 0}) =>
        TextPainter(
          text: TextSpan(
              text: t,
              style: TextStyle(
                  fontFamily: policeTitre, fontSize: taille, fontWeight: poids, color: c,
                  letterSpacing: espacement, height: 1.0)),
          textDirection: TextDirection.ltr,
        )..layout();

    void poserSurLigneDeBase(TextPainter tp, double x, double base) {
      final haut = base - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(x, haut));
    }

    // 1) mention « EXPLOITATION » : espacement ajusté pour occuper ~162 px
    final largeurNue = mesure('EXPLOITATION', 19, FontWeight.normal, _or).width;
    final espacement = math.max(2.0, math.min(7.0, (162 - largeurNue) / 11));
    poserSurLigneDeBase(mesure('EXPLOITATION', 19, FontWeight.normal, _or, espacement: espacement), xMention, baseMention);

    // 2) nom de la ferme : se réduit pour tenir dans la largeur (jamais coupé)
    var taille = 60.0;
    while (taille > 26 && mesure(nom, taille, FontWeight.bold, couleurNom).width > largeurMax) {
      taille -= 2;
    }
    final premiere = mesure(nom.substring(0, 1), taille, FontWeight.bold, _or);
    poserSurLigneDeBase(premiere, xNom, baseNom);
    if (nom.length > 1) {
      poserSurLigneDeBase(mesure(nom.substring(1), taille, FontWeight.bold, couleurNom), xNom + premiere.width, baseNom);
    }

    // 3) filet doré avec losanges aux extrémités
    final peinture = Paint()..color = _or..isAntiAlias = true;
    void losange(double cx, double cy, double r) => canvas.drawPath(
        Path()..moveTo(cx, cy - r)..lineTo(cx + r, cy)..lineTo(cx, cy + r)..lineTo(cx - r, cy)..close(),
        peinture);
    losange(xNom + 7, yFiletY, 7);
    canvas.drawLine(const Offset(xNom + 22, yFiletY), const Offset(xFin - 6, yFiletY),
        Paint()..color = _or..strokeWidth = 2..isAntiAlias = true);
    losange(xFin - 2, yFiletY, 4);
  }

  @override
  bool shouldRepaint(_PeintreEntete a) => a.nomFerme != nomFerme || a.sombre != sombre;
}

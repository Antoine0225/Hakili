import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Les icônes « trait fin » de Hakili : même dessin (grille de 24 unités) que assets_design.py,
/// mais tracées en vectoriel : nettes à toutes les tailles et dans les deux thèmes.
class IconeFine extends StatelessWidget {
  final String nom;
  final Color couleur;
  final double taille;
  final double epaisseur;
  const IconeFine(this.nom, {super.key, required this.couleur, this.taille = 20, this.epaisseur = 1.7});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: taille,
        height: taille,
        child: CustomPaint(painter: _PeintreIcone(nom, couleur, epaisseur)),
      );
}

class _PeintreIcone extends CustomPainter {
  final String nom;
  final Color couleur;
  final double epaisseur;
  _PeintreIcone(this.nom, this.couleur, this.epaisseur);

  late Canvas _c;
  late double _k;
  late Paint _trait, _plein;

  Offset _p(double x, double y) => Offset(x * _k, y * _k);

  void _ligne(List<(double, double)> pts, {bool ferme = false}) {
    final chemin = Path()..moveTo(pts.first.$1 * _k, pts.first.$2 * _k);
    for (final q in pts.skip(1)) {
      chemin.lineTo(q.$1 * _k, q.$2 * _k);
    }
    if (ferme) chemin.close();
    _c.drawPath(chemin, _trait);
    if (pts.length == 2 && pts[0] == pts[1]) _c.drawCircle(_p(pts[0].$1, pts[0].$2), epaisseur * _k / 2, _plein);
  }

  void _cercle(double cx, double cy, double r, {bool plein = false}) =>
      _c.drawCircle(_p(cx, cy), r * _k, plein ? _plein : _trait);

  void _rect(double x0, double y0, double x1, double y1, {double rayon = 2.0}) => _c.drawRRect(
      RRect.fromLTRBR(x0 * _k, y0 * _k, x1 * _k, y1 * _k, Radius.circular(rayon * _k)), _trait);

  void _arc(double cx, double cy, double r, double debut, double fin) => _c.drawArc(
      Rect.fromCircle(center: _p(cx, cy), radius: r * _k),
      debut * math.pi / 180, (fin - debut) * math.pi / 180, false, _trait);

  void _polygone(List<(double, double)> pts) {
    final chemin = Path()..moveTo(pts.first.$1 * _k, pts.first.$2 * _k);
    for (final q in pts.skip(1)) {
      chemin.lineTo(q.$1 * _k, q.$2 * _k);
    }
    chemin.close();
    _c.drawPath(chemin, _plein);
  }

  void _etoile4(double cx, double cy, double r) {
    final pts = <(double, double)>[];
    for (var i = 0; i < 8; i++) {
      final ang = math.pi / 4 * i - math.pi / 2;
      final rr = i % 2 == 0 ? r : r * 0.32;
      pts.add((cx + rr * math.cos(ang), cy + rr * math.sin(ang)));
    }
    _polygone(pts);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _k = size.width / 24.0;
    _trait = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur * _k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    _plein = Paint()
      ..color = couleur
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (nom) {
      case 'accueil':
        _ligne([(3, 11.5), (12, 3.5), (21, 11.5)]);
        _ligne([(5.5, 10), (5.5, 20.5), (18.5, 20.5), (18.5, 10)]);
        _ligne([(10, 20.5), (10, 14.5), (14, 14.5), (14, 20.5)]);
      case 'previsions':
        _rect(3.5, 3.5, 20.5, 20.5, rayon: 3);
        _ligne([(8, 17), (8, 12)]);
        _ligne([(12, 17), (12, 8)]);
        _ligne([(16, 17), (16, 10.5)]);
      case 'elevage' || 'poule':
        _cercle(12, 14, 6.6);
        _ligne([(8.6, 8.2), (8.2, 4.8), (10.4, 6.2), (12, 3.2), (13.6, 6.2), (15.8, 4.8), (15.4, 8.2)]);
        _cercle(9.4, 12.6, 0.95, plein: true);
        _cercle(14.6, 12.6, 0.95, plein: true);
        _polygone([(12, 14.2), (10.2, 16.6), (13.8, 16.6)]);
      case 'ventes':
        _cercle(12, 13.5, 7.2);
        _ligne([(10, 3.8), (14, 3.8)]);
        _ligne([(12, 3.8), (12, 6.3)]);
        _ligne([(12, 10), (12, 13.6)]);
        _ligne([(12, 13.6), (14.6, 15.4)]);
      case 'stocks':
        _ligne([(12, 3), (20.5, 7.5), (20.5, 16.5), (12, 21), (3.5, 16.5), (3.5, 7.5)], ferme: true);
        _ligne([(3.5, 7.5), (12, 12), (20.5, 7.5)]);
        _ligne([(12, 12), (12, 21)]);
      case 'rapports':
        _rect(3.5, 3.5, 20.5, 20.5, rayon: 3);
        _ligne([(7, 16), (10.5, 11.5), (13.5, 14), (17, 8.5)]);
        _ligne([(7, 9), (7.01, 9)]);
      case 'parametres':
        _cercle(12, 12, 3.2);
        for (var i = 0; i < 8; i++) {
          final a = math.pi / 4 * i;
          _ligne([(12 + 6.6 * math.cos(a), 12 + 6.6 * math.sin(a)), (12 + 9.2 * math.cos(a), 12 + 9.2 * math.sin(a))]);
        }
        _cercle(12, 12, 6.6);
      case 'credits':
        _rect(3, 6.5, 21, 18.5, rayon: 2.5);
        _ligne([(3, 10.5), (21, 10.5)]);
        _ligne([(6.5, 15), (10.5, 15)]);
      case 'expert_ia':
        _etoile4(10, 13, 6.5);
        _etoile4(18, 5.5, 3.2);
      case 'cloche':
        _arc(12, 10, 6, 180, 360);
        _ligne([(6, 10), (6, 15.5), (4.2, 17.5), (19.8, 17.5), (18, 15.5), (18, 10)]);
        _ligne([(10, 20.5), (14, 20.5)]);
      case 'banque':
        _ligne([(3.5, 9), (12, 3.5), (20.5, 9)], ferme: true);
        _ligne([(3.5, 20.5), (20.5, 20.5)]);
        for (final x in [6.5, 10.2, 13.8, 17.5]) {
          _ligne([(x, 10.5), (x, 17.5)]);
        }
      case 'barres':
        _ligne([(6, 20), (6, 12)]);
        _ligne([(12, 20), (12, 5)]);
        _ligne([(18, 20), (18, 9)]);
        _ligne([(3.5, 20.5), (20.5, 20.5)]);
      case 'tendance':
        _ligne([(3, 17), (9, 11), (13, 15), (21, 6.5)]);
        _ligne([(15.5, 6.5), (21, 6.5), (21, 12)]);
      case 'tiret':
        _ligne([(6, 12), (18, 12)]);
      case 'sac':
        _ligne([(8, 5), (16, 5)]);
        _ligne([(8, 5), (6, 9)]);
        _ligne([(16, 5), (18, 9)]);
        _rect(5, 9, 19, 21, rayon: 3.2);
        _cercle(12, 15, 2.4);
      case 'facture':
        _ligne([(6.5, 3), (14.5, 3), (18.5, 7), (18.5, 21), (6.5, 21)], ferme: true);
        _ligne([(14.5, 3), (14.5, 7), (18.5, 7)]);
        _ligne([(9.5, 12), (15.5, 12)]);
        _ligne([(9.5, 15.5), (15.5, 15.5)]);
      case 'chevron_droit':
        _ligne([(9, 5), (16, 12), (9, 19)]);
      case 'chevron_gauche':
        _ligne([(15, 5), (8, 12), (15, 19)]);
      case 'chevron_bas':
        _ligne([(5, 9), (12, 16), (19, 9)]);
      case 'telephone':
        _rect(7, 3, 17, 21, rayon: 2.6);
        _ligne([(10.5, 18), (13.5, 18)]);
      case 'plus':
        _ligne([(12, 5), (12, 19)]);
        _ligne([(5, 12), (19, 12)]);
      case 'etincelles':
        _etoile4(9, 14, 7.5);
        _etoile4(18, 6.5, 4.2);
        _etoile4(18.5, 18, 3.2);
      case 'deconnexion':
        _ligne([(10, 4), (4.5, 4), (4.5, 20), (10, 20)]);
        _ligne([(9, 12), (20, 12)]);
        _ligne([(16, 8), (20, 12), (16, 16)]);
      case 'session':
        _rect(4.5, 10.5, 19.5, 20.5, rayon: 3);
        _arc(12, 10.5, 4.6, 180, 360);
        _ligne([(7.4, 10.5), (7.4, 8.4)]);
        _ligne([(16.6, 10.5), (16.6, 8.4)]);
        _cercle(12, 15.5, 1.4, plein: true);
      case 'soleil':
        _cercle(12, 12, 4.2);
        for (var i = 0; i < 8; i++) {
          final a = math.pi / 4 * i;
          _ligne([(12 + 7 * math.cos(a), 12 + 7 * math.sin(a)), (12 + 9.4 * math.cos(a), 12 + 9.4 * math.sin(a))]);
        }
      case 'lune':
        _arc(12, 12, 8, 40, 320);
        _arc(15.5, 9.5, 7, 100, 230);
      case 'utilisateurs':
        _cercle(9, 8.5, 3.6);
        _arc(9, 21, 7, 200, 340);
        _cercle(17, 9.5, 2.8);
        _arc(17.5, 19, 5, 215, 335);
      case 'info':
        _cercle(12, 12, 8.5);
        _ligne([(12, 11), (12, 16.5)]);
        _cercle(12, 7.8, 0.9, plein: true);
      case 'cadenas':
        _rect(5, 10.5, 19, 21, rayon: 3);
        _arc(12, 10.5, 4.6, 180, 360);
        _ligne([(7.4, 10.5), (7.4, 8)]);
        _ligne([(16.6, 10.5), (16.6, 8)]);
      default:
        _cercle(12, 12, 7);
    }
  }

  @override
  bool shouldRepaint(_PeintreIcone ancien) =>
      ancien.nom != nom || ancien.couleur != couleur || ancien.epaisseur != epaisseur;
}

import 'dart:math' as math;
import 'dart:ui' show Offset, Color;

/// Les petites fonctions de mise en forme partagées par tous les écrans
/// (reprises de interface_principale.py : formater_fcfa, formater_axe, formater_jour_relatif...).

const joursFr = ['LUNDI', 'MARDI', 'MERCREDI', 'JEUDI', 'VENDREDI', 'SAMEDI', 'DIMANCHE'];
const moisFr = [
  'JANVIER', 'FÉVRIER', 'MARS', 'AVRIL', 'MAI', 'JUIN', 'JUILLET', 'AOÛT',
  'SEPTEMBRE', 'OCTOBRE', 'NOVEMBRE', 'DÉCEMBRE'
];
const moisAbr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];

/// Maturité commerciale (jours) par type d'élevage.
const maturiteCommercialeJours = {'Poulet de chair': 30, 'RLA / Pintade': 90};

String _milliers(String entier) {
  final neg = entier.startsWith('-');
  final chiffres = neg ? entier.substring(1) : entier;
  final b = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) b.write(' ');
    b.write(chiffres[i]);
  }
  return (neg ? '-' : '') + b.toString();
}

/// 1 260 000 -> « 1,26 M » ; 128 450 -> « 128 450 »
String formaterFcfa(num? valeur) {
  final v = (valeur ?? 0).toDouble();
  if (v.abs() >= 1000000) {
    final m = (v / 1000000).toStringAsFixed(2);
    final parts = m.split('.');
    return '${_milliers(parts[0])},${parts[1]} M';
  }
  return _milliers(v.round().toString());
}

/// 12 345.6 -> « 12 346 F »
String fmtF(num? valeur, {String unite = 'F'}) =>
    '${_milliers((valeur ?? 0).toDouble().round().toString())}${unite.isEmpty ? '' : ' $unite'}';

String _g(double v) {
  // équivalent de Python « :g »
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Nombre sans zéros inutiles (« 12 » ou « 12.5 »), comme « :g » de Python.
String nombreCourt(num v) => _g(v.toDouble());

/// Étiquettes de l'axe vertical : 0, 100 k, 600 k, 1.5 M…
String formaterAxe(double valeur) {
  if (valeur >= 1000000) return '${_g(valeur / 1000000)} M';
  if (valeur >= 1000) return '${_g(valeur / 1000)} k';
  return _g(valeur);
}

/// Date -> « Aujourd'hui », « Hier » ou « 26 sept. »
String formaterJourRelatif(DateTime d) {
  final auj = DateTime.now();
  final delta = DateTime(auj.year, auj.month, auj.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (delta == 0) return "Aujourd'hui";
  if (delta == 1) return 'Hier';
  return '${d.day} ${moisAbr[d.month - 1]}';
}

/// « JJ/MM/AAAA » (ou « JJ/MM/AAAA HH:MM ») -> date ; null si illisible.
DateTime? lireJma(Object? texte) {
  final s = '${texte ?? ''}'.trim();
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?').firstMatch(s);
  if (m == null) return null;
  final d = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!),
      m[4] == null ? 0 : int.parse(m[4]!), m[5] == null ? 0 : int.parse(m[5]!));
  if (d.day != int.parse(m[1]!) || d.month != int.parse(m[2]!)) return null;
  return d;
}

String jourEnTexte(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

DateTime aujourdhui() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Pas « rond » (1, 2, 2.5, 5 x 10^n) et nombre de graduations pour un axe vertical propre.
(double, int) echelleAgreable(double vmax, [int nb = 5]) {
  if (vmax <= 0) return (20000.0, 5);
  final brut = vmax / nb;
  final puiss = math.pow(10, (math.log(brut) / math.ln10).floor()).toDouble();
  var pas = puiss;
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    pas = m * puiss;
    if (pas * nb >= vmax) break;
  }
  return (pas, math.max(1, (vmax / pas - 1e-9).ceil()));
}

/// Courbe Catmull-Rom passant par tous les points : rendu doux, sans dépasser l'axe du bas.
List<Offset> courbeLisse(List<Offset> points, {int sousPas = 8, double? yMax}) {
  final n = points.length;
  if (n < 3) return List.of(points);
  final sortie = <Offset>[];
  for (var i = 0; i < n - 1; i++) {
    final p0 = i > 0 ? points[i - 1] : points[i];
    final p1 = points[i], p2 = points[i + 1];
    final p3 = i + 2 < n ? points[i + 2] : points[i + 1];
    for (var k = 0; k < sousPas; k++) {
      final t = k / sousPas, t2 = t * t, t3 = t2 * t;
      double c(double a0, double a1, double a2, double a3) =>
          0.5 * ((2 * a1) + (-a0 + a2) * t + (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 + (-a0 + 3 * a1 - 3 * a2 + a3) * t3);
      final x = c(p0.dx, p1.dx, p2.dx, p3.dx);
      var y = c(p0.dy, p1.dy, p2.dy, p3.dy);
      if (yMax != null && y > yMax) y = yMax;
      sortie.add(Offset(x, y));
    }
  }
  sortie.add(points.last);
  return sortie;
}

/// Comme « .title() » de Python : majuscule à chaque début de mot, le reste en minuscules.
String titreCase(String texte) {
  final b = StringBuffer();
  var debutMot = true;
  for (final c in texte.split('')) {
    final estLettre = c.toLowerCase() != c.toUpperCase();
    if (estLettre) {
      b.write(debutMot ? c.toUpperCase() : c.toLowerCase());
      debutMot = false;
    } else {
      b.write(c);
      debutMot = true;
    }
  }
  return b.toString();
}

/// Mélange deux couleurs (t = 0 → a, t = 1 → b) : sert aux fonds de courbes.
Color melanger(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Comme « {x:,.1f} » de Python : 1234.5 -> « 1,234.5 » (virgule pour les milliers).
String milliersAnglais(num valeur, [int decimales = 0]) {
  final s = valeur.toDouble().toStringAsFixed(decimales);
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  final ent = neg ? parts[0].substring(1) : parts[0];
  final b = StringBuffer();
  for (var i = 0; i < ent.length; i++) {
    if (i > 0 && (ent.length - i) % 3 == 0) b.write(',');
    b.write(ent[i]);
  }
  return '${neg ? '-' : ''}$b${decimales > 0 ? '.${parts[1]}' : ''}';
}

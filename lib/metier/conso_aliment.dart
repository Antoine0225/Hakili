import 'dart:math' as math;

/// Consommation d'aliment regroupée par période (semaine ou mois) à partir de valeurs jour par jour.
class ConsoPeriode {
  final String label;
  final double jours, kgJour, gOiseauJour, kgPeriode, sacs, cout;
  const ConsoPeriode(this.label, this.jours, this.kgJour, this.gOiseauJour, this.kgPeriode, this.sacs, this.cout);
}

/// [kgJour], [coutJour] et [oiseauxJour] ont une valeur par jour. [joursParPeriode] : 7 pour une semaine, 30.4 pour un mois.
List<ConsoPeriode> consoParPeriode(List<double> kgJour, List<double> coutJour, List<double> oiseauxJour,
    {required double joursParPeriode, required String Function(int) label}) {
  final total = kgJour.length;
  final res = <ConsoPeriode>[];
  var rang = 1;
  var debut = 0.0;
  while (debut < total - 0.0001) {
    final fin = math.min(total.toDouble(), debut + joursParPeriode);
    var kg = 0.0, cout = 0.0, ois = 0.0, nb = 0.0;
    for (var d = debut.floor(); d < fin.ceil() && d < total; d++) {
      // part du jour d qui tombe dans la période (les bords peuvent être partiels)
      final part = math.min(fin, d + 1.0) - math.max(debut, d.toDouble());
      if (part <= 0) continue;
      kg += kgJour[d] * part;
      cout += coutJour[d] * part;
      ois += oiseauxJour[d] * part;
      nb += part;
    }
    if (nb > 0) {
      final kgJ = kg / nb;
      final oMoy = ois / nb;
      res.add(ConsoPeriode(label(rang), nb, kgJ, oMoy > 0 ? kgJ / oMoy * 1000 : 0.0, kg, kg / 50, cout));
    }
    rang++;
    debut = fin;
  }
  return res;
}

/// Transforme des valeurs par semaine en valeurs par jour (chaque semaine est répartie sur 7 jours).
List<double> parJour(List<double> parSemaine) => [for (final v in parSemaine) for (var i = 0; i < 7; i++) v / 7];

const _moisCourtsB = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// « Semaine 3 · 12 mars » (ou « Semaine 3 » sans date d'arrivée).
String libelleSemaine(DateTime? debut, int rang) {
  if (debut == null) return 'Semaine $rang';
  final d = DateTime(debut.year, debut.month, debut.day + (rang - 1) * 7);
  return 'Semaine $rang · ${d.day} ${_moisCourtsB[d.month - 1]}';
}

/// « Mois 2 » ou « Mois 2 · mars 2027 » : le mois 1 commence à l'arrivée des poussins.
String libelleMoisConso(DateTime? debut, int rang) {
  if (debut == null) return 'Mois $rang';
  final d = DateTime(debut.year, debut.month, debut.day + ((rang - 1) * 30.4).round());
  return 'Mois $rang · ${_moisCourtsB[d.month - 1]} ${d.year}';
}

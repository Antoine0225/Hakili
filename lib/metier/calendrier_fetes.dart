/// Une fête, avec sa date (approximative pour les fêtes musulmanes : elles dépendent de la lune, ±1 jour).
class Occasion {
  final String nom;
  final DateTime date;
  final bool approximative;
  const Occasion(this.nom, this.date, this.approximative);
}

/// Les grandes fêtes où la demande de poulets et d'œufs monte. Les dates musulmanes sont calculées avec le calendrier
/// hégirien « arithmétique » : elles peuvent différer d'un jour de l'annonce officielle, l'utilisateur peut donc les corriger.
class CalendrierFetes {
  CalendrierFetes._();

  /// Jour grégorien d'une date hégirienne (an, mois, jour).
  static DateTime _hegire(int an, int mois, int jour) {
    final jd = jour + (29.5 * (mois - 1)).ceil() + (an - 1) * 354 + ((3 + 11 * an) / 30).floor() + 1948439.5 - 1;
    final jours = (jd - 2440587.5).round();
    final d = DateTime.utc(1970, 1, 1).add(Duration(days: jours));
    return DateTime(d.year, d.month, d.day);
  }

  /// Les prochaines fêtes à partir de [depuis], classées par date (environ 2 ans).
  static List<Occasion> prochaines(DateTime depuis) {
    final debut = DateTime(depuis.year, depuis.month, depuis.day);
    final limite = debut.add(const Duration(days: 800));
    final toutes = <Occasion>[];
    // an hégirien courant approximatif : (année grégorienne − 622) × 1,0307
    final anH = ((depuis.year - 622) * 1.0307).floor();
    for (var h = anH - 1; h <= anH + 3; h++) {
      toutes.add(Occasion('Début du Ramadan', _hegire(h, 9, 1), true));
      toutes.add(Occasion('Korité (fin du Ramadan)', _hegire(h, 10, 1), true));
      toutes.add(Occasion('Tabaski', _hegire(h, 12, 10), true));
      toutes.add(Occasion('Maouloud', _hegire(h, 3, 12), true));
    }
    for (var a = depuis.year; a <= depuis.year + 3; a++) {
      toutes.add(Occasion('Noël', DateTime(a, 12, 25), false));
      toutes.add(Occasion('Nouvel An', DateTime(a, 1, 1), false));
    }
    final vues = <String>{};
    final sortie = <Occasion>[];
    toutes.sort((x, y) => x.date.compareTo(y.date));
    for (final o in toutes) {
      if (o.date.isBefore(debut) || o.date.isAfter(limite)) continue;
      if (!vues.add('${o.nom}${o.date.year}')) continue;
      sortie.add(o);
    }
    return sortie;
  }

  /// Nombre de jours entre deux dates (calendaires, sans l'heure).
  static int jours(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

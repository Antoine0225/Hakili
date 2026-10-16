import 'dart:math' as math;

enum NiveauChaleur { aucun, vigilance, forte, extreme }

/// Alerte chaleur : on regarde la température maximale prévue aujourd'hui, demain et après-demain.
/// Seuils : 35 °C vigilance, 38 °C chaleur forte, 41 °C chaleur extrême.
class AlerteChaleur {
  final NiveauChaleur niveau;
  final double tMax;
  final int dansJours; // 0 = aujourd'hui, 1 = demain, 2 = après-demain
  final List<double> previsions;
  const AlerteChaleur(this.niveau, this.tMax, this.dansJours, this.previsions);

  static NiveauChaleur niveauPour(double t) {
    if (t >= 41) return NiveauChaleur.extreme;
    if (t >= 38) return NiveauChaleur.forte;
    if (t >= 35) return NiveauChaleur.vigilance;
    return NiveauChaleur.aucun;
  }

  /// [maxPrevus] : maxima prévus (aujourd'hui en premier) ; [actuelle] : température mesurée en ce moment.
  static AlerteChaleur evaluer(List<double> maxPrevus, double actuelle) {
    final liste = <double>[...maxPrevus.take(3)];
    if (liste.isEmpty) liste.add(actuelle);
    liste[0] = math.max(liste[0], actuelle); // la température du moment peut dépasser la prévision du jour
    var pire = 0;
    for (var i = 1; i < liste.length; i++) {
      if (liste[i] > liste[pire]) pire = i;
    }
    return AlerteChaleur(niveauPour(liste[pire]), liste[pire], pire, liste);
  }

  bool get active => niveau != NiveauChaleur.aucun;

  String get quand => dansJours == 0 ? "aujourd'hui" : (dansJours == 1 ? 'demain' : 'après-demain');

  String get nomNiveau => switch (niveau) {
        NiveauChaleur.extreme => 'CHALEUR EXTRÊME',
        NiveauChaleur.forte => 'CHALEUR FORTE',
        _ => 'CHALEUR À SURVEILLER',
      };

  String get titre => '☀️ $nomNiveau — $quand jusqu\'à ${tMax.toStringAsFixed(0)} °C';

  /// Résumé des 3 jours : « Auj. 38° · Dem. 41° · J+2 39° ».
  String get resume {
    const noms = ['Auj.', 'Dem.', 'J+2'];
    return [for (var i = 0; i < previsions.length; i++) '${noms[i]} ${previsions[i].toStringAsFixed(0)}°'].join('  ·  ');
  }

  /// Baisse de ponte possible (estimation indicative, pas une mesure).
  String get baissePonte => switch (niveau) {
        NiveauChaleur.extreme => '15 à 25 %',
        NiveauChaleur.forte => '8 à 12 %',
        _ => '3 à 5 %',
      };

  /// Les conseils, du plus important au moins important. [chair] : élevage de chair (sinon ponte / reproducteurs).
  List<String> conseils({required bool chair}) {
    final l = <String>[
      "Eau fraîche et propre à volonté, abreuvoirs à l'ombre (changez l'eau plusieurs fois par jour).",
      "Donnez l'aliment tôt le matin et en fin de journée, pas entre 11 h et 16 h.",
    ];
    if (niveau != NiveauChaleur.vigilance) {
      l.addAll([
        "Ajoutez des électrolytes ou de la vitamine C dans l'eau (antistress).",
        'Ouvrez au maximum la ventilation ; arroser le toit et le sol autour du bâtiment aide à rafraîchir.',
        'Évitez de manipuler, vacciner ou transporter les volailles entre 11 h et 16 h.',
      ]);
    }
    if (niveau == NiveauChaleur.extreme) {
      l.addAll([
        'Surveillez les volailles toutes les 2 heures : bec ouvert, ailes écartées et halètement sont des signes de coup de chaleur.',
        "Gardez de l'eau en réserve : une coupure d'eau par cette chaleur peut tuer vite.",
        chair
            ? "N'ajoutez pas de nouveaux poussins dans un bâtiment surchargé, et vendez en priorité les sujets déjà prêts."
            : "Ne mettez pas de nouvelle bande dans un bâtiment surchargé : moins de volailles par mètre carré, c'est moins de pertes.",
      ]);
    }
    if (!chair) {
      l.add('Ramassez les œufs plus souvent (3 à 4 fois par jour) : la chaleur les abîme vite.');
      l.add('Donnez du calcium (coquilles broyées) en fin de journée pour garder des coquilles solides.');
    }
    l.add('Si vous constatez une mortalité inhabituelle, appelez votre vétérinaire sans attendre.');
    return l;
  }
}

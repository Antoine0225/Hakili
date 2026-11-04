import 'dart:convert';
import 'dart:math' as math;

import '../data/parametres.dart';

/// Bibliothèque des formules d'aliment (poulet de chair, pondeuses, reproducteurs) avec contrôle nutritionnel.
/// Les formules d'origine respectent les besoins publiés par les sélectionneurs (Cobb, Ross, ISA, Lohmann, Hy-Line)
/// avec des ingrédients courants. Elles restent des points de départ : à faire valider par votre fournisseur de prémix
/// ou un nutritionniste, car la qualité réelle des ingrédients (humidité, aflatoxines…) change les résultats.

/// Un ingrédient et sa composition (par kilo tel que distribué). Ordre fixe : voir [ingredients].
class IngredientDef {
  final String cle, nom;
  final double em, pb, lys, met, ca, pd, na; // énergie (kcal/kg), protéine, lysine, méthionine, calcium, phosphore disponible, sodium (%)
  final bool nouveau; // ingrédient ajouté à ceux de l'onglet Prévisions (son prix est gardé ici)
  const IngredientDef(this.cle, this.nom, this.em, this.pb, this.lys, this.met, this.ca, this.pd, this.na, {this.nouveau = false});
}

const ingredients = <IngredientDef>[
  IngredientDef('mais', 'Maïs', 3350.0, 8.5, 0.25, 0.18, 0.02, 0.08, 0.02),
  IngredientDef('soja', 'Soja torréfié (tourteau)', 2400.0, 44.0, 2.7, 0.62, 0.3, 0.2, 0.02),
  IngredientDef('son', 'Son de blé', 1500.0, 15.0, 0.6, 0.22, 0.12, 0.3, 0.03),
  IngredientDef('poisson', 'Farine de poisson', 2800.0, 60.0, 4.4, 1.6, 5.0, 2.9, 1.0),
  IngredientDef('coquille', 'Coquilles broyées', 0.0, 0.0, 0.0, 0.0, 38.0, 0.0, 0.0),
  IngredientDef('premix', 'Prémix chair (concentré)', 0.0, 8.0, 6.0, 8.0, 18.0, 9.0, 2.0),
  IngredientDef('sel', 'Sel', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 39.0),
  IngredientDef('huile', 'Huile (palme ou soja)', 8800.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, nouveau: true),
  IngredientDef('premixPonte', 'Prémix ponte (concentré)', 0.0, 5.0, 3.0, 6.0, 22.0, 8.0, 2.0, nouveau: true),
  // Ingrédients supplémentaires, proposés quand on modifie une formule (valeurs moyennes ; à vérifier avec vos analyses).
  IngredientDef('sorgho', 'Sorgho', 3200.0, 9.5, 0.22, 0.15, 0.03, 0.09, 0.01, nouveau: true),
  IngredientDef('mil', 'Mil', 3100.0, 11.0, 0.3, 0.22, 0.03, 0.1, 0.02, nouveau: true),
  IngredientDef('coton', 'Tourteau de coton', 2300.0, 40.0, 1.6, 0.55, 0.2, 0.3, 0.04, nouveau: true),
  IngredientDef('arachide', 'Tourteau d\'arachide', 2600.0, 45.0, 1.5, 0.45, 0.15, 0.2, 0.05, nouveau: true),
  IngredientDef('sesame', 'Tourteau de sésame', 2200.0, 42.0, 1.2, 1.2, 1.9, 0.3, 0.05, nouveau: true),
  IngredientDef('sonRiz', 'Son de riz', 2400.0, 13.0, 0.55, 0.25, 0.08, 0.2, 0.03, nouveau: true),
  IngredientDef('poudreOs', 'Poudre d\'os', 0.0, 0.0, 0.0, 0.0, 30.0, 13.0, 0.0, nouveau: true),
  IngredientDef('phosphate', 'Phosphate bicalcique', 0.0, 0.0, 0.0, 0.0, 22.0, 18.0, 0.0, nouveau: true),
  IngredientDef('lysine', 'L-lysine', 0.0, 95.0, 78.0, 0.0, 0.0, 0.0, 0.0, nouveau: true),
  IngredientDef('methionine', 'DL-méthionine', 0.0, 58.7, 0.0, 99.0, 0.0, 0.0, 0.0, nouveau: true),
];

class Plage {
  final double min, max;
  const Plage(this.min, this.max);
}

/// Ce qu'une étape demande à l'aliment.
class BesoinFormule {
  final Plage em, pb, ca, pd, na;
  final double lysMin, metMin;
  const BesoinFormule(this.em, this.pb, this.lysMin, this.metMin, this.ca, this.pd, this.na);
}

class FormuleDef {
  final String id, groupe, etape, quand;
  final BesoinFormule besoin;
  final List<double> defaut; // pourcentages, dans l'ordre de [ingredients]
  const FormuleDef(this.id, this.groupe, this.etape, this.quand, this.besoin, this.defaut);

  /// 'chair' (poulet de chair et croissance lente), 'repro' (reproducteurs) ou 'pond' (pondeuses d'œufs de table).
  String get race => id.startsWith('pond_') ? 'pond' : (id.startsWith('rc_') || id.startsWith('rp_')) ? 'repro' : 'chair';

  /// Vrai si cette formule utilise le prémix ponte (sinon le prémix chair).
  bool get premixPonte => id.startsWith('pond_') || id.startsWith('rp_');

  /// Clé du prémix utilisé par cette formule.
  String get clePremix => premixPonte ? 'premixPonte' : 'premix';
}

final formules = <FormuleDef>[
  FormuleDef('chair_dem', 'Poulet de chair (Cobb, Ross, Hubbard…)', 'Démarrage', 'Jours 1 à 10',
      const BesoinFormule(Plage(2950.0, 3100.0), Plage(21.5, 23.0), 1.3, 0.52, Plage(0.9, 1.05), Plage(0.42, 0.5), Plage(0.15, 0.22)),
      [54.37, 33.38, 3.0, 3.13, 0.33, 3.0, 0.15, 2.64, 0.0]),
  FormuleDef('chair_cro', 'Poulet de chair (Cobb, Ross, Hubbard…)', 'Croissance', 'Jours 11 à 24',
      const BesoinFormule(Plage(3050.0, 3200.0), Plage(19.5, 21.0), 1.15, 0.47, Plage(0.85, 0.95), Plage(0.38, 0.45), Plage(0.15, 0.21)),
      [57.74, 30.25, 3.0, 1.61, 0.39, 3.0, 0.18, 3.83, 0.0]),
  FormuleDef('chair_fin', 'Poulet de chair (Cobb, Ross, Hubbard…)', 'Finition', 'À partir du jour 25',
      const BesoinFormule(Plage(3150.0, 3280.0), Plage(18.0, 19.5), 1.0, 0.42, Plage(0.75, 0.9), Plage(0.33, 0.4), Plage(0.14, 0.2)),
      [60.13, 28.3, 3.0, 0.08, 0.36, 3.0, 0.19, 4.94, 0.0]),
  FormuleDef('lent_dem', 'Poulet à croissance lente ou local amélioré', 'Démarrage', 'Jours 1 à 10',
      const BesoinFormule(Plage(2900.0, 3050.0), Plage(20.0, 21.5), 1.15, 0.46, Plage(0.9, 1.0), Plage(0.4, 0.48), Plage(0.15, 0.22)),
      [60.17, 29.66, 3.0, 2.54, 0.4, 3.0, 0.16, 1.07, 0.0]),
  FormuleDef('lent_cro', 'Poulet à croissance lente ou local amélioré', 'Croissance', 'Jours 11 à 24',
      const BesoinFormule(Plage(2950.0, 3100.0), Plage(18.5, 20.0), 1.0, 0.42, Plage(0.85, 0.95), Plage(0.36, 0.43), Plage(0.15, 0.21)),
      [62.88, 27.89, 3.0, 0.95, 0.49, 3.0, 0.2, 1.59, 0.0]),
  FormuleDef('lent_fin', 'Poulet à croissance lente ou local amélioré', 'Finition', 'À partir du jour 25',
      const BesoinFormule(Plage(3000.0, 3150.0), Plage(16.5, 18.0), 0.88, 0.38, Plage(0.75, 0.9), Plage(0.32, 0.38), Plage(0.14, 0.2)),
      [70.4, 22.34, 3.0, 0.0, 0.4, 3.0, 0.16, 0.7, 0.0]),
  FormuleDef('pond_dem', 'Pondeuses d\'œufs de table', 'Démarrage', '0 à 6 semaines',
      const BesoinFormule(Plage(2850.0, 2980.0), Plage(19.0, 20.5), 1.0, 0.42, Plage(0.95, 1.05), Plage(0.45, 0.5), Plage(0.15, 0.2)),
      [65.66, 23.45, 3.0, 4.8, 0.0, 0.0, 0.09, 0.0, 3.0]),
  FormuleDef('pond_cro', 'Pondeuses d\'œufs de table', 'Croissance', '7 à 12 semaines',
      const BesoinFormule(Plage(2800.0, 2920.0), Plage(17.0, 18.5), 0.86, 0.36, Plage(0.85, 1.0), Plage(0.38, 0.45), Plage(0.15, 0.2)),
      [66.24, 20.2, 7.48, 2.64, 0.23, 0.0, 0.21, 0.0, 3.0]),
  FormuleDef('pond_dev', 'Pondeuses d\'œufs de table', 'Développement', '13 à 17 semaines',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(15.0, 16.5), 0.72, 0.32, Plage(0.85, 1.0), Plage(0.35, 0.42), Plage(0.15, 0.2)),
      [67.25, 15.53, 12.15, 1.42, 0.41, 0.0, 0.24, 0.0, 3.0]),
  FormuleDef('pond_pre', 'Pondeuses d\'œufs de table', 'Pré-ponte', 'De 18 semaines jusqu\'à 2 % de ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(16.5, 18.0), 0.8, 0.36, Plage(2.0, 2.6), Plage(0.42, 0.48), Plage(0.15, 0.2)),
      [66.47, 19.53, 4.52, 3.0, 3.31, 0.0, 0.14, 0.0, 3.03]),
  FormuleDef('pond_p1', 'Pondeuses d\'œufs de table', 'Ponte phase 1', 'Du début de la ponte à environ 46 semaines d\'âge',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(16.5, 18.0), 0.82, 0.38, Plage(3.8, 4.3), Plage(0.38, 0.45), Plage(0.15, 0.2)),
      [60.34, 20.94, 3.0, 3.22, 7.96, 0.0, 0.14, 1.4, 3.0]),
  FormuleDef('pond_p2', 'Pondeuses d\'œufs de table', 'Ponte phase 2', 'Après environ 46 semaines d\'âge',
      const BesoinFormule(Plage(2700.0, 2850.0), Plage(15.5, 17.0), 0.76, 0.35, Plage(4.0, 4.6), Plage(0.33, 0.4), Plage(0.15, 0.2)),
      [61.91, 20.76, 3.0, 1.46, 8.79, 0.0, 0.18, 0.9, 3.0]),
  FormuleDef('rc_dem', 'Reproducteurs chair (parentaux Cobb, Ross…)', 'Démarrage', '0 à 6 semaines',
      const BesoinFormule(Plage(2900.0, 3050.0), Plage(19.0, 20.5), 1.0, 0.42, Plage(0.95, 1.05), Plage(0.44, 0.5), Plage(0.15, 0.2)),
      [64.34, 25.13, 3.0, 3.6, 0.43, 3.0, 0.12, 0.38, 0.0]),
  FormuleDef('rc_cro', 'Reproducteurs chair (parentaux Cobb, Ross…)', 'Croissance', '7 à 12 semaines',
      const BesoinFormule(Plage(2750.0, 2870.0), Plage(15.0, 16.5), 0.72, 0.32, Plage(0.85, 1.0), Plage(0.38, 0.44), Plage(0.15, 0.2)),
      [67.17, 15.77, 11.87, 1.18, 0.76, 3.0, 0.25, 0.0, 0.0]),
  FormuleDef('rc_dev', 'Reproducteurs chair (parentaux Cobb, Ross…)', 'Développement', '13 semaines jusqu\'à 2 semaines avant la ponte',
      const BesoinFormule(Plage(2700.0, 2850.0), Plage(14.0, 15.5), 0.65, 0.3, Plage(0.85, 1.0), Plage(0.35, 0.42), Plage(0.15, 0.2)),
      [67.38, 13.85, 14.34, 0.27, 0.89, 3.0, 0.27, 0.0, 0.0]),
  FormuleDef('rc_pre', 'Reproducteurs chair (parentaux Cobb, Ross…)', 'Pré-ponte', 'Les 2 semaines avant la ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(15.0, 16.5), 0.72, 0.33, Plage(2.0, 2.6), Plage(0.4, 0.46), Plage(0.15, 0.2)),
      [69.49, 16.03, 4.18, 2.58, 4.51, 3.0, 0.21, 0.0, 0.0]),
  FormuleDef('rc_ponte', 'Reproducteurs chair (parentaux Cobb, Ross…)', 'Reproduction', 'Pendant la ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(15.5, 17.0), 0.76, 0.36, Plage(3.0, 3.4), Plage(0.36, 0.42), Plage(0.15, 0.2)),
      [65.94, 20.23, 3.0, 1.13, 6.38, 3.0, 0.19, 0.13, 0.0]),
  FormuleDef('rp_dem', 'Reproducteurs pondeuse (parentaux ISA, Lohmann…)', 'Démarrage', '0 à 6 semaines',
      const BesoinFormule(Plage(2850.0, 2980.0), Plage(19.0, 20.5), 1.0, 0.42, Plage(0.95, 1.05), Plage(0.45, 0.5), Plage(0.15, 0.2)),
      [65.66, 23.45, 3.0, 4.8, 0.0, 0.0, 0.09, 0.0, 3.0]),
  FormuleDef('rp_cro', 'Reproducteurs pondeuse (parentaux ISA, Lohmann…)', 'Croissance', '7 à 12 semaines',
      const BesoinFormule(Plage(2800.0, 2920.0), Plage(16.5, 18.0), 0.84, 0.35, Plage(0.85, 1.0), Plage(0.38, 0.45), Plage(0.15, 0.2)),
      [67.0, 18.64, 8.26, 2.65, 0.24, 0.0, 0.21, 0.0, 3.0]),
  FormuleDef('rp_dev', 'Reproducteurs pondeuse (parentaux ISA, Lohmann…)', 'Développement', '13 semaines jusqu\'à 2 semaines avant la ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(15.0, 16.5), 0.72, 0.32, Plage(0.85, 1.0), Plage(0.35, 0.42), Plage(0.15, 0.2)),
      [67.25, 15.53, 12.15, 1.42, 0.41, 0.0, 0.24, 0.0, 3.0]),
  FormuleDef('rp_pre', 'Reproducteurs pondeuse (parentaux ISA, Lohmann…)', 'Pré-ponte', 'Les 2 semaines avant la ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(16.0, 17.5), 0.78, 0.35, Plage(2.0, 2.6), Plage(0.42, 0.48), Plage(0.15, 0.2)),
      [67.22, 17.99, 5.3, 3.0, 3.32, 0.0, 0.14, 0.0, 3.03]),
  FormuleDef('rp_ponte', 'Reproducteurs pondeuse (parentaux ISA, Lohmann…)', 'Reproduction', 'Pendant la ponte',
      const BesoinFormule(Plage(2750.0, 2880.0), Plage(16.0, 17.5), 0.8, 0.37, Plage(3.3, 3.7), Plage(0.38, 0.44), Plage(0.15, 0.2)),
      [64.67, 19.33, 3.0, 2.95, 6.63, 0.0, 0.14, 0.28, 3.0]),
];

enum StatutNut { ok, proche, hors }

class Nutriments {
  final double em, pb, lys, met, ca, pd, na;
  const Nutriments(this.em, this.pb, this.lys, this.met, this.ca, this.pd, this.na);
}

class FormulesAliment {
  FormulesAliment._();

  static final Map<String, List<double>> _perso = {};
  /// Prix (F/kg) des ingrédients qui ne sont pas dans l'onglet Prévisions.
  static final Map<String, double> prixNouveaux = {'huile': 1000, 'premixPonte': 1300, 'sorgho': 130, 'mil': 150, 'coton': 300, 'arachide': 450, 'sesame': 450, 'sonRiz': 100, 'poudreOs': 400, 'phosphate': 600, 'lysine': 2500, 'methionine': 6000};
  static bool _charge = false;
  /// Boost (0 à 100 %) réglé par la barre de la page Prévisions : formules renforcées dans tous les simulateurs.
  static double boost = 0;

  static FormuleDef def(String id) => formules.firstWhere((f) => f.id == id);

  static Future<void> charger({bool force = false}) async {
    if (_charge && !force) return;
    for (final f in formules) {
      try {
        final t = await Parametres.lire('formule_aliment_${f.id}');
        if (t.isEmpty) continue;
        final l = [for (final e in jsonDecode(t) as List) (e as num).toDouble()];
        if (l.length <= ingredients.length) _perso[f.id] = _pad(l);
      } catch (_) {}
    }
    for (final k in prixNouveaux.keys.toList()) {
      try {
        final v = double.tryParse(await Parametres.lire('prix_ing_$k'));
        if (v != null) prixNouveaux[k] = v;
      } catch (_) {}
    }
    try {
      boost = (double.tryParse(await Parametres.lire('boost_formules')) ?? 0).clamp(0.0, 100.0).toDouble();
    } catch (_) {}
    _charge = true;
  }

  static List<double> _pad(List<double> l) => [...l, for (var i = l.length; i < ingredients.length; i++) 0.0];

  static List<double> pourcentages(String id) => _perso[id] ?? _pad(def(id).defaut);

  /// Applique le « boost » (0 à 100 %) à une formule : un peu plus de soja et d'huile, un peu moins de maïs.
  /// À 100 % : +3 kg de soja, +1 kg d'huile, -4 kg de maïs pour 100 kg d'aliment. Le total reste à 100 kg.
  static List<double> avecBoost(List<double> p, double boostPct) {
    final b = (boostPct / 100).clamp(0.0, 1.0);
    if (b <= 0 || p.length < 8) return p;
    final r = List<double>.of(p);
    final retire = math.min(4 * b, r[0]);
    final f = retire / 4;
    r[0] -= retire;
    r[1] += 3 * f;
    r[7] += 1 * f;
    return r;
  }
  static bool modifiee(String id) => _perso.containsKey(id);

  static Future<void> enregistrer(String id, List<double> p) async {
    _perso[id] = List<double>.of(p);
    await Parametres.ecrire('formule_aliment_$id', jsonEncode(p));
  }

  static Future<void> restaurer(String id) async {
    _perso.remove(id);
    await Parametres.ecrire('formule_aliment_$id', '');
  }

  static Future<void> restaurerTout() async {
    for (final f in formules) {
      await restaurer(f.id);
    }
  }

  static Future<void> enregistrerPrix(String cle, double v) async {
    prixNouveaux[cle] = v;
    await Parametres.ecrire('prix_ing_$cle', v.toString());
  }

  static Future<void> enregistrerBoost(double v) async {
    boost = v;
    await Parametres.ecrire('boost_formules', v.toStringAsFixed(0));
  }

  static double prixDe(String cle) => prixNouveaux[cle] ?? 0;

  static double total(List<double> p) => p.fold<double>(0, (a, b) => a + b);

  /// Composition de l'aliment pour une liste de pourcentages (ordre de [ingredients]).
  static Nutriments nutriments(List<double> p) {
    var em = 0.0, pb = 0.0, lys = 0.0, met = 0.0, ca = 0.0, pd = 0.0, na = 0.0;
    for (var i = 0; i < ingredients.length && i < p.length; i++) {
      final g = ingredients[i], x = p[i] / 100;
      em += g.em * x;
      pb += g.pb * x;
      lys += g.lys * x;
      met += g.met * x;
      ca += g.ca * x;
      pd += g.pd * x;
      na += g.na * x;
    }
    return Nutriments(em, pb, lys, met, ca, pd, na);
  }

  /// Vert si dans la plage, orange si un peu à côté (tolérance [tol] en proportion), rouge sinon.
  static StatutNut statutPlage(double v, Plage pl, double tol) {
    if (v >= pl.min && v <= pl.max) return StatutNut.ok;
    final marge = (pl.min + pl.max) / 2 * tol;
    if (v >= pl.min - marge && v <= pl.max + marge) return StatutNut.proche;
    return StatutNut.hors;
  }

  static StatutNut statutMin(double v, double min, double tol) {
    if (v >= min) return StatutNut.ok;
    if (v >= min * (1 - tol)) return StatutNut.proche;
    return StatutNut.hors;
  }

  /// Coût d'un kilo d'aliment pour des pourcentages donnés ; [prix] donne le prix au kilo d'un ingrédient (par sa clé).
  static double coutKg(List<double> p, double Function(String) prix) {
    var t = 0.0;
    for (var i = 0; i < ingredients.length && i < p.length; i++) {
      t += p[i] * prix(ingredients[i].cle) / 100;
    }
    return t;
  }

  static double coutKgId(String id, double Function(String) prix) => coutKg(pourcentages(id), prix);

  /// Coût moyen d'un kilo quand l'étape de la simulation mélange plusieurs formules (poids = durées).
  static double coutKgMoyen(List<(String, double)> parts, double Function(String) prix, {double boost = 0}) {
    var s = 0.0, w = 0.0;
    for (final (id, poids) in parts) {
      if (poids <= 0) continue;
      s += coutKg(avecBoost(pourcentages(id), boost), prix) * poids;
      w += poids;
    }
    return w > 0 ? s / w : 0.0;
  }
}

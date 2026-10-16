import '../utilitaires/formats.dart';

/// Moteur comptable « Blindage » des bandes de PONDEUSES ADULTES (déjà en production).
/// Traduction fidèle de compta_ponte.py : aucune base de données, aucun écran, uniquement du calcul.
///
///  • BLINDAGE N°1 : le coût d'achat du cheptel est amorti sur 420 jours (60 semaines de ponte).
///  • BLINDAGE N°2 : l'aliment est celui que les poules mangent réellement chaque jour (120 g / poule / jour).
///  • Prix de revient d'une alvéole = coût réel du jour ÷ alvéoles ramassées ce jour-là.

const int joursProductionPonte = 420;
const int consoAlimentGParPondeuseJour = 120;
const double poidsSacPonteKg = 50;
const int moisAvantReforme = 12;
const int joursAvantReforme = 365;
const double prixRevientAlveoleStabilisation = 2600.0;
const String msgStabilisation = 'Stabilisation du cycle en cours...';

const String typePondeuses = 'Poules Pondeuses';
const String stadeAdulte = 'Déjà en Production (Adulte)';

double _flottant(Object? v, [double defaut = 0.0]) {
  if (v == null || v == '') return defaut;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? defaut;
}

DateTime? lireJour(Object? texte) {
  final t = '${texte ?? ''}'.trim();
  final d = lireJma(t.length >= 10 ? t.substring(0, 10) : t);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String jourEnTexteCp(DateTime j) => jourEnTexte(j);

/// Vrai pour une bande de pondeuses adulte, avec investissement, créée sous le nouveau mode.
bool estBandeLissee(Map<String, Object?> bande) {
  return bande['type_elevage'] == typePondeuses &&
      bande['stade_biologique'] == stadeAdulte &&
      _flottant(bande['cout_investissement_initial']) > 0 &&
      ('${bande['date_derniere_imputation'] ?? ''}').trim().isNotEmpty;
}

// ---------------------------------------------------------------- BLINDAGE N°1
double amortissementJournalier(Object? coutAchatTotal) =>
    (_flottant(coutAchatTotal) < 0 ? 0.0 : _flottant(coutAchatTotal)) / joursProductionPonte;

int jourDeProduction(Map<String, Object?> bande, DateTime jour) {
  final debut = lireJour(bande['date_creation']) ?? lireJour(bande['date_arrivee']) ?? jour;
  return DateTime.utc(jour.year, jour.month, jour.day).difference(DateTime.utc(debut.year, debut.month, debut.day)).inDays + 1;
}

double amortissementDuJour(Map<String, Object?> bande, DateTime jour) {
  final numero = jourDeProduction(bande, jour);
  if (numero < 1 || numero > joursProductionPonte) return 0.0;
  return amortissementJournalier(bande['cout_investissement_initial']);
}

// ---------------------------------------------------------------- BLINDAGE N°2
double quantiteConsommeeKgJour(int? nombreSujetsVivants) =>
    ((nombreSujetsVivants ?? 0) < 0 ? 0 : (nombreSujetsVivants ?? 0)) * consoAlimentGParPondeuseJour / 1000.0;

double coutAlimentJournalier(int? nombreSujetsVivants, Object? prixMoyenDuSac, [double poidsSacKg = poidsSacPonteKg]) {
  final prix = _flottant(prixMoyenDuSac);
  return (quantiteConsommeeKgJour(nombreSujetsVivants) / poidsSacKg) * (prix < 0 ? 0.0 : prix);
}

// ---------------------------------------------------------------- imputation des journées
class DetailJour {
  final DateTime jour;
  final int vivants;
  final double consoKg, prixKg, aliment, amortissement;
  final bool saisi;
  const DetailJour(this.jour, this.vivants, this.consoKg, this.prixKg, this.aliment, this.amortissement, this.saisi);
}

class Imputation {
  int jours = 0, joursSansSaisie = 0;
  double aliment = 0, amortissement = 0, annexes = 0, coutJour = 0, consoKg = 0;
  final List<DetailJour> detailJours = [];
}

/// Calcule (sans rien modifier) les charges de toutes les journées pas encore comptabilisées, jusqu'à `jour` inclus.
Imputation imputerCharges(Map<String, Object?> bande, DateTime jour, int effectifVeille, int effectifJour, Object? prixKgAliment) {
  final prixKg = _flottant(prixKgAliment) < 0 ? 0.0 : _flottant(prixKgAliment);
  final prixMoyenDuSac = prixKg * poidsSacPonteKg;
  var derniere = lireJour(bande['date_derniere_imputation']);
  if (derniere == null) {
    final debut = lireJour(bande['date_creation']) ?? lireJour(bande['date_arrivee']) ?? jour;
    derniere = debut.subtract(const Duration(days: 1));
  }
  final annexes0 = _flottant(bande['frais_annexes_en_attente']);
  final annexes = annexes0 < 0 ? 0.0 : annexes0;
  final res = Imputation()..annexes = annexes;

  if (!jour.isAfter(derniere)) {
    res.coutJour = coutAlimentJournalier(effectifJour, prixMoyenDuSac) + amortissementDuJour(bande, jour) + annexes;
    res.consoKg = quantiteConsommeeKgJour(effectifJour);
    return res;
  }

  var coutDuJour = 0.0;
  var courant = derniere.add(const Duration(days: 1));
  while (!courant.isAfter(jour)) {
    final vivants = courant == jour ? effectifJour : effectifVeille;
    final aliment = coutAlimentJournalier(vivants, prixMoyenDuSac);
    final amort = amortissementDuJour(bande, courant);
    res.aliment += aliment;
    res.amortissement += amort;
    res.consoKg += quantiteConsommeeKgJour(vivants);
    res.detailJours.add(DetailJour(courant, vivants, quantiteConsommeeKgJour(vivants), prixKg, aliment, amort, courant == jour));
    res.jours++;
    if (courant == jour) coutDuJour = aliment + amort;
    courant = courant.add(const Duration(days: 1));
  }
  res.joursSansSaisie = res.jours - 1 < 0 ? 0 : res.jours - 1;
  res.coutJour = coutDuJour + annexes;
  return res;
}

/// Inscrit dans la bande le résultat d'imputerCharges (à appeler UNE fois par saisie, avant la sauvegarde).
void appliquerImputation(Map<String, Object?> bande, DateTime jour, Imputation imp) {
  if (imp.jours > 0) {
    bande['cout_aliment'] = _flottant(bande['cout_aliment']) + imp.aliment;
    bande['conso_aliment_kg_cumulee'] = _flottant(bande['conso_aliment_kg_cumulee']) + imp.consoKg;
    bande['cout_amortissement_cumule'] = _flottant(bande['cout_amortissement_cumule']) + imp.amortissement;
    bande['cout_direct_cumule_ponte'] = _flottant(bande['cout_direct_cumule_ponte']) + imp.aliment + imp.amortissement;
    bande['date_derniere_imputation'] = jourEnTexte(jour);
  }
  // Les frais annexes sont déjà entrés dans le cumul à la saisie : on les « consomme » pour ne plus les recompter.
  bande['frais_annexes_en_attente'] = 0.0;
}

// ---------------------------------------------------------------- prix de revient
class PrixRevient {
  final double prix;
  final bool stabilisation;
  final String message;
  const PrixRevient(this.prix, this.stabilisation, this.message);
}

/// Coût réel ÷ alvéoles ramassées. Aucune alvéole : constante de stabilisation + message (jamais d'erreur).
PrixRevient prixRevientAlveole(Object? coutReelExploitation, Object? nbAlveoles) {
  final alveoles = _flottant(nbAlveoles);
  if (alveoles <= 1e-9) return const PrixRevient(prixRevientAlveoleStabilisation, true, msgStabilisation);
  final cout = _flottant(coutReelExploitation);
  return PrixRevient((cout < 0 ? 0.0 : cout) / alveoles, false, '');
}

PrixRevient prixRevientCumule(Map<String, Object?> bande) =>
    prixRevientAlveole(bande['cout_direct_cumule_ponte'], bande['alveoles_cumulees']);

Map<String, Object?> champsInitiauxBandeLissee(DateTime jourCreation, Object? prixKgAliment) {
  final prix = _flottant(prixKgAliment);
  return {
    'date_derniere_imputation': jourEnTexte(jourCreation.subtract(const Duration(days: 1))),
    'cout_amortissement_cumule': 0.0,
    'frais_annexes_en_attente': 0.0,
    'prix_kg_aliment': prix < 0 ? 0.0 : prix,
    'conso_aliment_kg_cumulee': 0.0,
    'date_reforme': '',
  };
}

// ---------------------------------------------------------------- RÉFORME (après 12 mois de ponte)
bool estReformee(Map<String, Object?> bande) => ('${bande['date_reforme'] ?? ''}').trim().isNotEmpty;

int joursDePonte(Map<String, Object?> bande, DateTime jour) {
  final n = jourDeProduction(bande, jour);
  return n < 0 ? 0 : n;
}

bool reformePossible(Map<String, Object?> bande, DateTime jour) =>
    estBandeLissee(bande) && !estReformee(bande) && joursDePonte(bande, jour) >= joursAvantReforme;

/// Part de l'investissement pas encore amortie : la valeur comptable des poules au moment de la réforme.
double valeurResiduelleCheptel(Map<String, Object?> bande) {
  final v = _flottant(bande['cout_investissement_initial']) - _flottant(bande['cout_amortissement_cumule']);
  return v < 0 ? 0.0 : v;
}

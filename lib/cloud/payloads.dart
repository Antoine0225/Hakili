/// Les « colis » envoyés au Cloud : mêmes champs que cloud_sync.py.
/// Chaque fonction reçoit la licence (e-mail) du client en paramètre.
class PayloadsCloud {
  PayloadsCloud._();

  static double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);
  static int _i(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
  static bool _b(Object? v) => v == true || v == 1 || v == '1';
  static String _s(Object? v, [String defaut = '']) {
    final t = v?.toString() ?? '';
    return t.isEmpty ? defaut : t;
  }

  static Map<String, Object?> vente(Map<String, Object?> v, String uid, String licence,
      {bool supprime = false}) =>
      {
        'uid': uid,
        'licence': licence,
        'date': _s(v['date']),
        'type': _s(v['type']),
        'qte': _d(v['qte']),
        'pu': _d(v['pu']),
        'total': _d(v['total']),
        'reglement': _s(v['reglement'], 'Espèces'),
        'client': _s(v['client']),
        'statut': _s(v['statut'], 'Actif'),
        'montant_regle': _d(v['montant_regle']),
        'cout_achat': _d(v['cout_achat']),
        'supprime': supprime,
      };

  static Map<String, Object?> bande(Map<String, Object?> b, String licence, {bool supprime = false}) => {
        'uid': b['uid'],
        'licence': licence,
        'nom': _s(b['nom']),
        'batiment': _s(b['batiment']),
        'type_elevage': _s(b['type_elevage']),
        'stade_biologique': _s(b['stade_biologique']),
        'bascule_effectuee': _b(b['bascule_effectuee']),
        'date_creation': _s(b['date_creation']),
        'date_arrivee': _s(b['date_arrivee']),
        'effectif_initial': _i(b['effectif_initial']),
        'effectif_actuel': _i(b['effectif_actuel']),
        'morts_cumulees': _i(b['morts_cumulees']),
        'oeufs_cumules': _i(b['oeufs_cumules']),
        'alveoles_cumulees': _d(b['alveoles_cumulees']),
        'cout_investissement_initial': _d(b['cout_investissement_initial']),
        'cout_initial_poussins': _d(b['cout_initial_poussins']),
        'cout_direct_cumule': _d(b['cout_direct_cumule']),
        'cout_direct_cumule_ponte': _d(b['cout_direct_cumule_ponte']),
        'cout_aliment': _d(b['cout_aliment']),
        'date_derniere_imputation': _s(b['date_derniere_imputation']),
        'cout_amortissement_cumule': _d(b['cout_amortissement_cumule']),
        'frais_annexes_en_attente': _d(b['frais_annexes_en_attente']),
        'prix_kg_aliment': _d(b['prix_kg_aliment']),
        'conso_aliment_kg_cumulee': _d(b['conso_aliment_kg_cumulee']),
        'date_reforme': _s(b['date_reforme']),
        'statut': _s(b['statut'], 'En élevage'),
        'date_maturite_commerciale': _s(b['date_maturite_commerciale']),
        'date_mise_en_vente': _s(b['date_mise_en_vente']),
        'date_epuisement': _s(b['date_epuisement']),
        'cout_unitaire_fige': _d(b['cout_unitaire_fige']),
        'produit_stock_nom': _s(b['produit_stock_nom']),
        'supprime': supprime,
      };

  static Map<String, Object?> rappel(Map<String, Object?> r, String licence) => {
        'uid': r['uid'],
        'licence': licence,
        'bande_uid': _s(r['bande_uid']),
        'date_prevue': _s(r['date_prevue']),
        'tache': _s(r['tache']),
        'recurrent': _s(r['recurrent']),
        'statut': _s(r['statut'], 'À faire'),
        'fait_le': _s(r['fait_le']),
        'fait_par': _s(r['fait_par']),
      };

  static Map<String, Object?> journalBande(Map<String, Object?> e, String licence) => {
        'uid': e['uid'],
        'licence': licence,
        'bande_uid': _s(e['bande_uid']),
        'date': _s(e['date']),
        'morts': _i(e['morts']),
        'oeufs': _i(e['oeufs']),
        'alveoles': _d(e['alveoles']),
        'taux_ponte': _d(e['taux_ponte']),
        'note': _s(e['note']),
      };

  static Map<String, Object?> arrivage(Map<String, Object?> a, String licence) => {
        'uid': a['uid'],
        'licence': licence,
        'date': _s(a['date']),
        'produit': a['produit'],
        'unite': a['unite'],
        'quantite_saisie': _d(a['quantite_saisie']),
        'poids_sac': _d(a['poids_sac']),
        'prix_achat_total': _d(a['prix_achat_total']),
        'cout_unitaire': _d(a['cout_unitaire']),
        'quantite_ajoutee': _d(a['quantite_ajoutee']),
        'reglement': _s(a['reglement'], 'Espèces'),
        'fournisseur': _s(a['fournisseur']),
        'alveoles_bonus': _d(a['alveoles_bonus']),
        'montant_regle': _d(a['montant_regle']),
        'statut': _s(a['statut'], 'Actif'),
      };
}

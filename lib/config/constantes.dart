/// Les « règles du jeu » de Hakili : valeurs partagées par tous les fichiers.
/// Reprises de config_systeme.py. Si une valeur change un jour, on la change ICI seulement.
library;

const String versionLogiciel = '1.0';

// --- Mises à jour (table configuration_systeme de Supabase, lignes cle / valeur)
const String majCleVersion = 'derniere_version';       // ex : 1.0.1
const String majCleUrl = 'url_telechargement_exe';     // lien de l'installateur ; la colonne sha256_exe de cette ligne est facultative
const int majIntervalleHeures = 3;                      // le logiciel regarde s'il y a du nouveau toutes les 3 heures

// --- Supabase (la clé « publishable » est publique par nature : la vraie protection est le jeton de licence)
const String supabaseUrl = 'https://rsdtcsqrzbbcbwidkqyt.supabase.co';
const String supabaseCle = 'sb_publishable_EAjYNTMh59r239rst4S0cw_ixCO-zam';
const String iaEdgeFunctionUrl = '$supabaseUrl/functions/v1/expert-ia-proxy';

// --- Base SQLite
// Pendant la reconstruction on travaille sur un fichier d'ESSAI, pour ne jamais risquer
// la vraie base de vos données. On passera à la vraie base tout à la fin.
const String nomBaseEssai = 'donnees_hakili_essai.db';
const String nomBaseReelle = 'donnies_antoine.db';

// --- Rôles
const String rolePatron = 'Patron';
const String roleOuvrier = 'Ouvrier';

// --- Licence
const String licenceEdgeFunctionUrl = '$supabaseUrl/functions/v1/licence-gateway';
const int licenceJoursMaxHorsLigne = 5;        // jours autorisés sans Internet
const int licenceDelaiReseauSec = 12;          // attente maximale d'une réponse du serveur
const int otpNombreChiffres = 6;
const int otpDureeValiditeSec = 10 * 60;       // compte à rebours du code reçu par e-mail

// --- Synchronisation Cloud (Supabase)
const bool jetonObligatoire = true;            // sans badge de licence valide, la synchro attend
const int cloudIntervalleSec = 3600;           // cycle complet toutes les heures (et tout de suite après une saisie)
const int cloudDelaiSec = 8;
const int cloudTaillePage = 1000;
const int cloudTailleLot = 200;
const int cloudChevauchement = 500;
const int cloudMaxTentatives = 5;
const Map<String, String> cloudConflits = {
  'ventes': 'uid',
  'stocks_arrivages': 'uid',
  'catalogue_produits': 'licence,nom',
  'bandes_elevage': 'uid',
  'rappels_veterinaires': 'uid',
  'journal_bande_evenements': 'uid',
};
const Map<String, String> cloudRpc = {
  'stock_delta': 'ajuster_stock',
  'stock_init': 'initialiser_stock',
};
const List<String> cloudTablesIncrementales = [
  'ventes', 'stocks_arrivages', 'bandes_elevage', 'rappels_veterinaires'
];

// --- Divers
/// Pendant les essais, le logiciel travaille sur un fichier d'essai. Mettez true UNIQUEMENT quand vous êtes prêt
/// à utiliser votre vraie base (donnies_antoine.db) : c'est la bascule finale.
const bool utiliserBaseReelle = true;
const int licenceBattementMinutes = 30;
/// Après ce nombre de minutes sans activité, le code PIN est redemandé (verrouillage automatique).
const int verrouInactiviteMinutes = 45;

import 'config/constantes.dart';
import 'data/parametres.dart';

/// Qui est connecté en ce moment ? (remplace self.role_utilisateur, self.nom_ferme... de Python)
class Session {
  Session._();

  static String _role = roleOuvrier;
  static String get role => _role;

  /// Changer de session mémorise aussi « qui travaille » pour le journal des modifications.
  static set role(String valeur) {
    _role = valeur;
    try {
      Parametres.ecrire('ctx_session', valeur).catchError((_) {});
    } catch (_) {}
  }
  static String nomFerme = 'ANTOINE SOFTWARE';

  /// Le Patron peut donner à l'Ouvrier l'accès au module Élevage (réglage « acces_module3_ouvrier »).
  static bool accesModule3Ouvrier = false;

  /// Réglages de session (non enregistrés dans la base, comme dans la version Python).
  static String typeElevage = 'chair';
  static DateTime dateReceptionPoussins = DateTime.now();

  /// Stock d'aliment en sacs (réglage « stock_aliment_sacs », 5 par défaut).
  static int sacsAlimentEnStock = 5;

  static bool get estPatron => role == rolePatron;

  /// Le Patron voit toujours Élevage ; l'Ouvrier seulement si le Patron le lui a autorisé.
  static bool get peutVoirModule3 => estPatron || accesModule3Ouvrier;

  static void fermer() => role = roleOuvrier;
}

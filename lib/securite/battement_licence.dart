import 'dart:async';

import '../cloud/service_cloud.dart';
import '../config/constantes.dart';
import 'jeton_cloud.dart';
import 'licence_locale.dart';
import 'licence_serveur.dart';

/// 💓 Toutes les 30 minutes, le serveur reçoit des nouvelles de ce PC : si la licence a été retirée ou
/// suspendue pendant l'utilisation, le logiciel se verrouille (ou revient à l'écran de connexion).
class BattementLicence {
  BattementLicence._();

  static Timer? _horloge;
  static DateTime _dernier = DateTime.now();
  static bool _occupe = false;

  static void demarrer({required void Function(String) onVerrou, required void Function(String) onDeconnexion}) {
    arreter();
    _dernier = DateTime.now();
    _horloge = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_occupe || DateTime.now().difference(_dernier).inMinutes < licenceBattementMinutes) return;
      _occupe = true;
      _dernier = DateTime.now();
      try {
        await _traiter(onVerrou, onDeconnexion);
      } catch (_) {
      } finally {
        _occupe = false;
      }
    });
  }

  static void arreter() {
    _horloge?.cancel();
    _horloge = null;
  }

  static Future<void> _traiter(void Function(String) onVerrou, void Function(String) onDeconnexion) async {
    final email = await Licence.lireEmail();
    if (email.isEmpty) return;
    var res = await LicenceServeur.transaction(email, await Licence.pcId(), mode: 'battement');
    if (!res.reseau) return; // pas d'Internet : on réessaiera, rien ne bouge
    if (res.autorise && res.code == 'ok') {
      await Licence.enregistrerCache(res.expiration ?? '');
      return;
    }
    if (res.code == 'absent') {
      // ce PC n'est plus enregistré : on tente de le ré-inscrire par un contrôle complet
      res = await LicenceServeur.transaction(email, await Licence.pcId());
      if (!res.reseau) return;
      if (res.autorise) {
        await Licence.enregistrerCache(res.expiration ?? '');
        return;
      }
    }
    final message = res.message.isNotEmpty ? res.message : "⛔ L'adresse $email n'est plus autorisée sur le serveur.";
    arreter();
    ServiceCloud.arreter();
    if (res.code == 'inconnu') {
      await Licence.activerVerrou(email, message, code: res.code);
      await Licence.marquerSession(false);
      JetonCloud.oublier();
      onVerrou(message);
    } else {
      await Licence.marquerSession(false);
      await Licence.effacerCache();
      JetonCloud.oublier();
      onDeconnexion(message);
    }
  }
}

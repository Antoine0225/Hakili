import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../data/parametres.dart';
import '../securite/licence_locale.dart';
import '../securite/pin.dart';
import '../session.dart';
import '../theme/palette.dart';

/// Affiché une seule fois dans la vie du logiciel : nom de la ferme + codes PIN Patron et Ouvrier.
class AssistantConfiguration extends StatefulWidget {
  final VoidCallback onTermine;
  /// Appelé quand le client reprend une ferme déjà utilisée sur ce PC (le logiciel recharge alors ses réglages).
  final VoidCallback onFermeReprise;
  const AssistantConfiguration({super.key, required this.onTermine, required this.onFermeReprise});

  @override
  State<AssistantConfiguration> createState() => _AssistantConfigurationState();
}

class _AssistantConfigurationState extends State<AssistantConfiguration> {
  final _nom = TextEditingController();
  final _pinPatron = TextEditingController();
  final _pinOuvrier = TextEditingController();
  bool _masquer = true;
  bool _enCours = false;
  String _erreur = '';
  List<(String, String, DateTime)> _fermes = [];

  @override
  void initState() {
    super.initState();
    BaseLocale.fermesDejaSurCePc().then((l) {
      if (mounted) setState(() => _fermes = l);
    });
  }

  /// Reprend une ferme déjà utilisée sur ce PC : ses données et ses codes PIN sont retrouvés tels quels.
  Future<void> _reprendre(String chemin, String nom) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprendre cette ferme ?'),
        content: Text('Vous allez continuer avec la ferme « $nom » : ses données et ses codes PIN seront retrouvés.\n\n'
            'Rien n\'est supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reprendre')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _erreur = '';
      _enCours = true;
    });
    final email = await Licence.lireEmail();
    final expiration = Licence.expiration;
    ServiceCloud.arreter();
    final reussi = await BaseLocale.reprendreFerme(chemin);
    if (!reussi) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = "Impossible d'ouvrir cette ferme. Vos données ne sont pas effacées : relancez le logiciel.";
        });
      }
      return;
    }
    // La licence de ce PC est réinscrite dans la ferme retrouvée.
    if (email.isNotEmpty) {
      await Licence.enregistrerEmail(email);
      await Parametres.ecrire('proprietaire_licence', email);
    }
    if (expiration.isNotEmpty) await Licence.enregistrerCache(expiration);
    await Licence.marquerSession(true);
    await Licence.leverVerrou();
    if (mounted) widget.onFermeReprise();
  }

  @override
  void dispose() {
    _nom.dispose();
    _pinPatron.dispose();
    _pinOuvrier.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final nom = _nom.text.trim();
    final pp = _pinPatron.text.trim();
    final po = _pinOuvrier.text.trim();

    String? erreur;
    if (nom.isEmpty) {
      erreur = 'Veuillez indiquer le nom de votre ferme.';
    } else if (pp.length < 4) {
      erreur = 'Le code PIN Patron doit contenir au moins 4 caractères.';
    } else if (po.length < 4) {
      erreur = 'Le code PIN Ouvrier doit contenir au moins 4 caractères.';
    } else if (pp == po) {
      erreur = "Les deux codes doivent être différents l'un de l'autre.";
    }
    if (erreur != null) {
      setState(() => _erreur = erreur!);
      return;
    }

    setState(() {
      _erreur = '';
      _enCours = true;
    });
    await Parametres.ecrire('nom_ferme', nom);
    await Pin.definir(rolePatron, pp);
    await Pin.definir(roleOuvrier, po);
    await Parametres.ecrire('configuration_terminee', '1');
    Session.nomFerme = nom;
    if (mounted) widget.onTermine();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 32, 36, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('◆', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, color: p.accent)),
                    const SizedBox(height: 6),
                    Text('BIENVENUE', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                    const SizedBox(height: 6),
                    Text('C O N F I G U R A T I O N   I N I T I A L E', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.txtGris)),
                    const SizedBox(height: 4),
                    Text('Ces informations ne vous seront demandées qu\'une seule fois.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.txtDoux)),
                    const SizedBox(height: 26),
                    if (_fermes.isNotEmpty) ...[
                      _titreSection('VOUS AVEZ DÉJÀ UTILISÉ CE PC ?', p),
                      for (final f in _fermes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed: _enCours ? null : () => _reprendre(f.$1, f.$2),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                            child: Text('📂 Continuer avec la ferme « ${f.$2} »'),
                          ),
                        ),
                      Text('Ou créez une nouvelle ferme ci-dessous.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtGris)),
                      const SizedBox(height: 22),
                    ],
                    _titreSection('01   IDENTITÉ DE L\'EXPLOITATION', p),
                    TextField(
                      controller: _nom,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                          labelText: 'Nom de la ferme',
                          hintText: 'Ex : Ferme Avicole de Moribabougou'),
                    ),
                    const SizedBox(height: 22),
                    _titreSection('02   CODES D\'ACCÈS SÉCURISÉS', p),
                    TextField(
                      controller: _pinPatron,
                      obscureText: _masquer,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                          labelText: 'Code PIN Patron — accès total'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pinOuvrier,
                      obscureText: _masquer,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _valider(),
                      decoration: const InputDecoration(
                          labelText: 'Code PIN Ouvrier — caisse uniquement'),
                    ),
                    Align(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _masquer = !_masquer),
                        icon: Icon(_masquer ? Icons.visibility : Icons.visibility_off, size: 18),
                        label: Text(_masquer ? 'Afficher les codes' : 'Masquer les codes'),
                        style: TextButton.styleFrom(foregroundColor: p.txtGris),
                      ),
                    ),
                    Text('Minimum 4 caractères. Les deux codes doivent être différents.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtGris)),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _erreur.isEmpty
                          ? const SizedBox(height: 18)
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text('⚠️  $_erreur', textAlign: TextAlign.center,
                                  style: TextStyle(color: p.danger, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    FilledButton(
                      onPressed: _enCours ? null : _valider,
                      child: _enCours
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Text('Terminer la configuration'),
                    ),
                    const SizedBox(height: 14),
                    Text('© Antoine Software', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: p.txtGris)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titreSection(String texte, Palette p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texte, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
      );
}

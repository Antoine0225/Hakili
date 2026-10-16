import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/service_cloud.dart';
import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../data/parametres.dart';
import '../securite/licence_locale.dart';
import '../securite/licence_serveur.dart';
import '../theme/palette.dart';
import '../widgets/achat_licence.dart';
import '../widgets/choix_ferme.dart';

/// Activation de la licence : 1) on saisit l'e-mail  2) on recopie le code à 6 chiffres reçu par e-mail.
/// Le serveur décide de tout : ce logiciel ne connaît jamais le code attendu.
class EcranLicence extends StatefulWidget {
  final String emailInitial;
  final String messageInfo;
  final VoidCallback onActive;
  const EcranLicence({
    super.key,
    this.emailInitial = '',
    this.messageInfo = '',
    required this.onActive,
  });

  @override
  State<EcranLicence> createState() => _EcranLicenceState();
}

enum _Phase { email, otp, termine }

class _EcranLicenceState extends State<EcranLicence> {
  late final TextEditingController _email = TextEditingController(text: widget.emailInitial);
  final _otp = TextEditingController();
  _Phase _phase = _Phase.email;
  String _emailGele = '';
  bool _enCours = false;
  String _message = '';
  Color? _couleurMessage; // null = couleur « accent »
  int _secondes = otpDureeValiditeSec;
  Timer? _chrono;

  @override
  void initState() {
    super.initState();
    _message = widget.messageInfo;
  }

  @override
  void dispose() {
    _chrono?.cancel();
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _dire(String texte, [Color? couleur]) => setState(() {
        _message = texte;
        _couleurMessage = couleur;
      });

  // ------------------------------------------------------------------ étape 1 : demander le code
  Future<void> _demanderCode() async {
    if (_phase != _Phase.email || _enCours) return;
    final p = Palette.de(context);
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      _dire('⚠️  Adresse e-mail invalide.', p.danger);
      return;
    }
    setState(() => _enCours = true);
    _dire('⏳ Génération du code de sécurité en cours...');

    final res = await LicenceServeur.demanderCode(email);
    if (!mounted) return;
    setState(() => _enCours = false);

    if (!res.reseau) {
      _dire('📡  Serveur injoignable. Activez le partage de connexion\nde votre téléphone puis réessayez.',
          p.alerte);
      return;
    }
    if (!res.succes) {
      _dire(res.message.isNotEmpty ? res.message : '⛔  Impossible de générer un code pour cette adresse.',
          p.danger);
      return;
    }
    _emailGele = email;
    _demarrerChrono();
    setState(() => _phase = _Phase.otp);
    _dire('📧  Un code à $otpNombreChiffres chiffres a été envoyé à $email.');
  }

  void _demarrerChrono() {
    _chrono?.cancel();
    _secondes = otpDureeValiditeSec;
    _chrono = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondes <= 1) {
        t.cancel();
        _otp.clear();
        setState(() => _phase = _Phase.email);
        _dire('⌛ Le code a expiré. Demandez-en un nouveau.', Palette.de(context).alerte);
      } else {
        setState(() => _secondes--);
      }
    });
  }

  String get _chronoTexte {
    final m = (_secondes ~/ 60).toString().padLeft(2, '0');
    final s = (_secondes % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ------------------------------------------------------------------ étape 2 : confirmer le code
  Future<void> _confirmerCode() async {
    if (_phase != _Phase.otp || _enCours) return;
    final p = Palette.de(context);
    final code = _otp.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != otpNombreChiffres) {
      _dire('⚠️ Saisissez les $otpNombreChiffres chiffres du code reçu par e-mail.', p.danger);
      return;
    }
    setState(() => _enCours = true);
    _dire('⏳ Vérification du code de sécurité...');

    final res = await LicenceServeur.verifierCode(_emailGele, code, await Licence.pcId());
    if (!mounted) return;
    setState(() => _enCours = false);

    if (!res.reseau) {
      _dire('📡  Serveur injoignable. Vérifiez votre connexion puis réessayez.', p.alerte);
      return;
    }
    if (!res.succes) {
      _otp.clear();
      if ((res.code == 'pleine' || res.code == 'conflit') && res.message.isNotEmpty) {
        _dire(res.message, p.danger);
      } else {
        _dire('⛔ Code incorrect ou expiré. Vérifiez votre boîte mail.', p.danger);
      }
      return;
    }

    // 🏡 Une autre ferme est déjà sur ce PC ? Le client choisit : garder, retrouver la sienne, ou repartir à neuf.
    final proprietaire = await Licence.lireProprietaireFerme();
    if (proprietaire.isNotEmpty && proprietaire != _emailGele && await Licence.baseContientDesDonnees()) {
      if (!mounted) return;
      final choix = await proposerChoixFerme(context, proprietaire, _emailGele);
      if (choix == null) {
        if (mounted) _dire('Connexion annulée : choisissez une ferme pour continuer.', p.alerte);
        return;
      }
      if (choix != 'garder') {
        ServiceCloud.arreter();
        final ok = await BaseLocale.basculerFerme(proprietaire, _emailGele, retrouver: choix == 'retrouver');
        if (!ok) {
          if (mounted) _dire("⛔ Impossible d'ouvrir la ferme choisie. Vos données ne sont pas effacées : relancez le logiciel.", p.danger);
          return;
        }
      }
    }

    // ✅ Licence validée par le serveur : on enregistre tout, puis on lève un éventuel gel local.
    _chrono?.cancel();
    final exp = res.expiration ?? '';
    await Licence.enregistrerEmail(_emailGele);
    await Parametres.ecrire('proprietaire_licence', _emailGele);
    await Licence.enregistrerCache(exp);
    await Licence.marquerSession(true);
    await Licence.leverVerrou();
    Licence.expiration = exp;
    if (!mounted) return;

    final occ = res.occupation ?? [1, 1];
    setState(() => _phase = _Phase.termine);
    _dire('✅ Accès accordé jusqu\'au $exp.\n🖥️ Formule ${occ[1]} PC — ${occ[0]}/${occ[1]} PC enregistré(s).',
        p.succes);
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) widget.onActive();
  }

  // ------------------------------------------------------------------ affichage
  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final enOtp = _phase == _Phase.otp;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 34, 36, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 34, color: p.accent),
                    const SizedBox(height: 10),
                    Text('Hakili', textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: policeTitre, fontSize: 30,
                            fontWeight: FontWeight.bold, color: p.txtPrinc)),
                    const SizedBox(height: 4),
                    Text('ACTIVATION DE LA LICENCE', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, letterSpacing: 2.2,
                            fontWeight: FontWeight.bold, color: p.txtGris)),
                    const SizedBox(height: 26),
                    if (!enOtp) ...[
                      TextField(
                        controller: _email,
                        enabled: !_enCours && _phase == _Phase.email,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => _demanderCode(),
                        decoration: const InputDecoration(
                            labelText: 'Votre adresse e-mail', hintText: 'exemple@gmail.com'),
                      ),
                    ] else ...[
                      Text(_emailGele, textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, color: p.txtPrinc)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _otp,
                        enabled: !_enCours,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: otpNombreChiffres,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                        onSubmitted: (_) => _confirmerCode(),
                        decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                      ),
                      const SizedBox(height: 8),
                      Text('Le code expire dans $_chronoTexte', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: p.txtDoux)),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _message.isEmpty
                          ? const SizedBox(height: 22)
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(_message, textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold,
                                      color: _couleurMessage ?? p.accent)),
                            ),
                    ),
                    if (_phase != _Phase.termine)
                      FilledButton(
                        onPressed: _enCours ? null : (enOtp ? _confirmerCode : _demanderCode),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: enOtp ? p.succes : p.cuivre),
                        child: _enCours
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(enOtp ? '🔒 CONFIRMER LE CODE DE SÉCURITÉ' : 'ACTIVER MA LICENCE'),
                      ),
                    if (_phase != _Phase.termine)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          height: 42,
                          child: FilledButton(
                            onPressed: () => ouvrirAchatLicence(context, (_emailGele.isNotEmpty ? _emailGele : _email.text).trim()),
                            style: FilledButton.styleFrom(backgroundColor: p.neutre, foregroundColor: p.txtPrinc,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Text('🛒  ACHAT DE LICENCE', style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    if (enOtp)
                      TextButton(
                        onPressed: _enCours
                            ? null
                            : () {
                                _chrono?.cancel();
                                _otp.clear();
                                setState(() => _phase = _Phase.email);
                                _dire('');
                              },
                        child: const Text("Changer d'adresse e-mail"),
                      ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => exit(0),
                      style: TextButton.styleFrom(foregroundColor: p.txtGris),
                      child: const Text('Quitter le logiciel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

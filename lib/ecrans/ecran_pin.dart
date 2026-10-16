import 'package:flutter/material.dart';

import '../securite/pin.dart';
import '../data/journal_repo.dart';
import '../session.dart';
import '../theme/palette.dart';

/// Écran de connexion : le code PIN décide si on entre en Patron ou en Ouvrier.
class EcranPin extends StatefulWidget {
  final VoidCallback onOuvert;
  const EcranPin({super.key, required this.onOuvert});

  @override
  State<EcranPin> createState() => _EcranPinState();
}

class _EcranPinState extends State<EcranPin> {
  final _champ = TextEditingController();
  final _focus = FocusNode();
  bool _enCours = false;
  String _erreur = '';

  @override
  void dispose() {
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    final code = _champ.text.trim();
    if (code.isEmpty || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = '';
    });

    final role = await Pin.identifierRole(code);
    if (!mounted) return;

    if (role == null) {
      JournalRepo.noter('Sécurité', 'ÉCHEC', "Code PIN incorrect à l'ouverture du logiciel");
      _champ.clear();
      setState(() {
        _enCours = false;
        _erreur = 'Code PIN incorrect. Veuillez réessayer.';
      });
      _focus.requestFocus();
      return;
    }
    Session.role = role;
    JournalRepo.noter('Sécurité', 'CONNEXION', 'Ouverture de la session $role');
    widget.onOuvert();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 34, 36, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 34, color: p.accent),
                    const SizedBox(height: 10),
                    Text(Session.nomFerme, textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: policeTitre, fontSize: 22,
                            fontWeight: FontWeight.bold, color: p.txtPrinc)),
                    const SizedBox(height: 4),
                    Text('ACCÈS SÉCURISÉ', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, letterSpacing: 2.4,
                            fontWeight: FontWeight.bold, color: p.txtGris)),
                    const SizedBox(height: 26),
                    TextField(
                      controller: _champ,
                      focusNode: _focus,
                      autofocus: true,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4),
                      onSubmitted: (_) => _ouvrir(),
                      decoration: const InputDecoration(hintText: 'Votre code PIN'),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _erreur.isEmpty
                          ? const SizedBox(height: 22)
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text('⚠️  $_erreur', textAlign: TextAlign.center,
                                  style: TextStyle(color: p.danger, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    FilledButton(
                      onPressed: _enCours ? null : _ouvrir,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: _enCours
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Text("DÉVERROUILLER L'ACCÈS"),
                    ),
                    const SizedBox(height: 14),
                    Text('Accès strictement réservé au personnel autorisé',
                        textAlign: TextAlign.center,
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
}

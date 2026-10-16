import 'dart:io';

import 'package:flutter/material.dart';

/// Écran rouge hermétique : les données restent intactes sur le PC, seul l'ACCÈS est gelé.
/// Sorties possibles : fermer le logiciel, ou essayer une AUTRE adresse e-mail dont la licence est valide.
class EcranVerrou extends StatelessWidget {
  final String message;
  final VoidCallback onAutreAdresse;
  const EcranVerrou({super.key, required this.message, required this.onAutreAdresse});

  static const _rouge = Color(0xFF932C21);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rouge,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚨', style: TextStyle(fontSize: 60)),
                const SizedBox(height: 16),
                const Text(
                  "SÉCURITÉ : Votre licence a été suspendue par l'administrateur.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),
                const Text('Accès aux données gelé. Veuillez contacter le support.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFFFECACA))),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(message, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFECACA))),
                ],
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: onAutreAdresse,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: _rouge,
                      minimumSize: const Size(280, 46)),
                  child: const Text('🔑 Utiliser une autre adresse e-mail'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => exit(0),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white, side: const BorderSide(color: Colors.white, width: 2),
                      minimumSize: const Size(280, 46)),
                  child: const Text('Fermer le logiciel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

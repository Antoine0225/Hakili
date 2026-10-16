import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Petit message de confirmation en bas de l'écran (afficher_confirmation_rapide de Python) :
/// il apparaît en fondu, reste 1,8 s puis disparaît. Un nouveau message remplace l'ancien.
class Toast {
  Toast._();

  static OverlayEntry? _entree;
  static Timer? _minuteur;

  static void afficher(BuildContext context, String message, {Color? couleur, int dureeMs = 1800}) {
    final p = Palette.de(context);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _retirer();
    final fond = couleur ?? p.succes;
    _entree = OverlayEntry(
      builder: (_) => Positioned(
        left: 0, right: 0, bottom: 28,
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              builder: (_, v, enfant) =>
                  Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: enfant)),
              child: Material(
                color: fond,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  child: Text(message,
                      style: const TextStyle(
                          fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entree!);
    _minuteur = Timer(Duration(milliseconds: dureeMs), _retirer);
  }

  static void _retirer() {
    _minuteur?.cancel();
    _entree?.remove();
    _entree = null;
  }
}

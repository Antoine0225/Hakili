import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/palette.dart';
import 'dialogues.dart';

const numeroWhatsappVendeur = '22360511046';

const _debutMessage = "Bonjour Antoine Software, je souhaite acheter une licence d'accès de ";
const _finMessage = ' pour mon logiciel de gestion avicole. Voici mon adresse e-mail : ';

class _Offre {
  final String libelle, message;
  final Color fond;
  const _Offre(this.libelle, this.message, this.fond);
}

const _offres = [
  _Offre('🥇 Licence Premium — 1 AN\n💻 1 PC (1 utilisateur) — 40,000 fcfa',
      '${_debutMessage}1 AN pour 1 PC (formule 1 utilisateur)$_finMessage', Color(0xFFBC6B2D)),
  _Offre('🥇 Licence Premium — 1 AN\n💻💻 2 PC (2 utilisateurs) — 60,000 fcfa',
      '${_debutMessage}1 AN pour 2 PC (formule 2 utilisateurs)$_finMessage', Color(0xFF2F7D4F)),
  _Offre('💎 Licence Business — 2 ANS\n💻 1 PC (1 utilisateur) — 65,000 fcfa',
      '${_debutMessage}2 ANS pour 1 PC (formule 1 utilisateur)$_finMessage', Color(0xFF123229)),
  _Offre('💎 Licence Business — 2 ANS\n💻💻 2 PC (2 utilisateurs) — 90,000 fcfa',
      '${_debutMessage}2 ANS pour 2 PC (formule 2 utilisateurs)$_finMessage', Color(0xFFB98A1E)),
];

String _lienWhatsapp(String message, String email) =>
    'https://wa.me/$numeroWhatsappVendeur?text=${Uri.encodeComponent(message + email.trim())}';

Future<void> _ouvrirLien(BuildContext context, String lien) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    Dialogues.avertissement(context, 'WhatsApp indisponible',
        "Impossible d'ouvrir WhatsApp automatiquement.\nÉcrivez directement au +$numeroWhatsappVendeur.");
  }
}

/// 🛒 « CHOISISSEZ VOTRE FORMULE » : le client voit les tarifs AVANT de lancer sa commande.
Future<void> ouvrirAchatLicence(BuildContext context, String emailSaisi) {
  final p = Palette.de(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(30, 22, 30, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('🛒', textAlign: TextAlign.center, style: TextStyle(fontSize: 26)),
            const SizedBox(height: 2),
            Text('CHOISISSEZ VOTRE FORMULE', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            Text('Votre commande sera envoyée par WhatsApp', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: p.txtDoux)),
            const SizedBox(height: 14),
            for (final o in _offres)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: SizedBox(
                  height: 62,
                  child: FilledButton(
                    onPressed: () => _ouvrirQr(ctx, _lienWhatsapp(o.message, emailSaisi), o.libelle),
                    style: FilledButton.styleFrom(backgroundColor: o.fond, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(o.libelle, textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text('Votre licence est activée dès réception du paiement.', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: p.txtDoux)),
            const SizedBox(height: 10),
            SizedBox(height: 32, child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc),
              child: const Text('Retour', style: TextStyle(fontSize: 11)),
            )),
          ]),
        ),
      ),
    ),
  );
}

Future<void> _ouvrirQr(BuildContext context, String lien, String libelle) {
  final p = Palette.de(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(30, 22, 30, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('SCANNEZ POUR COMMANDER',
                style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 4),
            Text(libelle, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.accent)),
            const SizedBox(height: 4),
            Text("📸 Sortez votre téléphone, ouvrez l'appareil photo et scannez ce code : WhatsApp s'ouvre avec votre commande déjà écrite.",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.txtDoux)),
            const SizedBox(height: 12),
            Container(
              color: Colors.white, padding: const EdgeInsets.all(10),
              child: QrImageView(data: lien, size: 280, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            Text('Ou écrivez-nous au  +$numeroWhatsappVendeur',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtGris)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity, height: 42,
              child: FilledButton(
                onPressed: () => _ouvrirLien(context, lien),
                style: FilledButton.styleFrom(backgroundColor: p.neutre, foregroundColor: p.txtPrinc),
                child: const Text('🌐  Ouvrir quand même sur ce PC', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: p.txtGris), child: const Text('Fermer')),
          ]),
        ),
      ),
    ),
  );
}

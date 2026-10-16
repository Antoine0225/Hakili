import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/constantes.dart';
import '../securite/jeton_cloud.dart';
import '../securite/licence_locale.dart';
import '../theme/palette.dart';
import '../widgets/mise_en_page_module.dart';

/// 🐓 Expert IA Aviculture : chat autonome (conseils vétérinaires et zootechniques).
/// La clé Gemini ne vit JAMAIS dans ce logiciel : la question part vers l'Edge Function « expert-ia-proxy »,
/// qui n'accepte que les appels portant le badge de licence délivré par le serveur de licences.
class EcranExpertIa extends StatefulWidget {
  const EcranExpertIa({super.key});

  /// La conversation survit à la navigation entre pages (comme dans la version Python).
  static final List<(String, String)> historique = [];

  @override
  State<EcranExpertIa> createState() => _EcranExpertIaState();
}

class _EcranExpertIaState extends State<EcranExpertIa> {
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  final _focus = FocusNode();
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    if (EcranExpertIa.historique.isEmpty) {
      EcranExpertIa.historique.add(('🐓 Antoine IA',
          "Bonjour ! Je suis Antoine IA, votre ingénieur agronome et vétérinaire expert en aviculture au Mali. "
          "Posez-moi une question sur vos formules d'aliment, une maladie ou un traitement."));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _descendre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.animateTo(_defilement.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  void _nouvelleConversation() {
    setState(() {
      EcranExpertIa.historique.clear();
      EcranExpertIa.historique.add(('🐓 Antoine IA',
          "Bonjour ! Je suis Antoine IA, votre ingénieur agronome et vétérinaire expert en aviculture au Mali. "
          "Posez-moi une question sur vos formules d'aliment, une maladie ou un traitement."));
    });
  }

  Future<void> _envoyer() async {
    final question = _saisie.text.trim();
    if (question.isEmpty || _enCours) return;
    _saisie.clear();
    setState(() {
      EcranExpertIa.historique.add(('👤 Vous', question));
      _enCours = true;
    });
    _descendre();
    final reponse = await _interroger(question);
    if (!mounted) return;
    setState(() {
      EcranExpertIa.historique.add(('🐓 Antoine IA', reponse));
      _enCours = false;
    });
    _descendre();
    _focus.requestFocus();
  }

  Future<String> _interroger(String question) async {
    try {
      final licence = (await Licence.lireEmail()).trim().toLowerCase();
      final jeton = JetonCloud.lire(licence);
      if (jeton.isEmpty) {
        return "⚠️ Votre licence n'a pas encore été confirmée en ligne. Vérifiez votre connexion Internet "
            'puis relancez le logiciel (ou réessayez dans quelques minutes).';
      }
      final r = await http
          .post(
            Uri.parse(iaEdgeFunctionUrl),
            headers: {'Content-Type': 'application/json', 'apikey': supabaseCle, 'Authorization': 'Bearer $jeton'},
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 25));
      if (r.statusCode == 401) {
        return '⚠️ Licence non reconnue par le service IA. Relancez le logiciel avec Internet pour renouveler votre accès.';
      }
      if (r.statusCode == 429) return '⏳ Vous avez atteint la limite de questions pour le moment. Réessayez un peu plus tard.';
      final corps = utf8.decode(r.bodyBytes);
      if (r.statusCode != 200) {
        return '⚠️ Erreur du service IA (${r.statusCode}) : ${corps.length > 200 ? corps.substring(0, 200) : corps}';
      }
      final d = jsonDecode(corps);
      final texte = (d is Map ? '${d['reponse'] ?? ''}' : '').trim();
      return texte.isEmpty ? '⚠️ Réponse vide reçue de l\'IA.' : texte;
    } catch (e) {
      return '⚠️ Impossible de contacter l\'IA pour le moment : $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return MiseEnPageModule(
      papierDirect: true,
      gauche: Align(
        alignment: Alignment.topCenter,
        child: Container(
          decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.bordure)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🐓 VOTRE INGÉNIEUR AGRONOME PERSONNEL',
                  style: TextStyle(fontFamily: policeTitre, fontSize: 15, fontWeight: FontWeight.bold, color: p.accent)),
              const SizedBox(height: 15),
              Text(
                  "Posez vos questions sur les formules d'aliment, les maladies (Newcastle, Gumboro, Coccidiose…), "
                  'les traitements et le climat sahélien de Bamako. Les réponses sont générées par une IA — vérifiez '
                  'toujours les cas graves avec un vétérinaire.',
                  style: TextStyle(fontSize: 11, color: p.txtDoux)),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity, height: 34,
                child: FilledButton(
                  onPressed: _nouvelleConversation,
                  style: FilledButton.styleFrom(backgroundColor: p.panneau2, foregroundColor: p.txtPrinc,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('🧹 Nouvelle conversation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      ),
      droite: Builder(builder: (context) {
        final p = Palette.de(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
                child: ListView(
                  controller: _defilement,
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final (auteur, texte) in EcranExpertIa.historique)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SelectableText.rich(TextSpan(children: [
                          TextSpan(text: '$auteur :\n', style: TextStyle(fontWeight: FontWeight.bold, color: auteur.contains('Vous') ? p.accent : p.succes)),
                          TextSpan(text: texte),
                        ]), style: TextStyle(fontFamily: policeTexte, fontSize: 12, height: 1.35, color: p.txtPrinc)),
                      ),
                    if (_enCours)
                      Text('🐓 Antoine IA :\n⏳ Réflexion en cours…', style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtGris)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _saisie, focusNode: _focus, onSubmitted: (_) => _envoyer(),
                    decoration: const InputDecoration(hintText: 'Écrivez votre question ici…'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100, height: 42,
                child: FilledButton(
                  onPressed: _enCours ? null : _envoyer,
                  style: FilledButton.styleFrom(backgroundColor: p.cuivre, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text(_enCours ? '…' : '➤ Envoyer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        );
      }),
    );
  }
}

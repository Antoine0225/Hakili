import 'package:flutter/material.dart';

import '../metier/previsions.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogues.dart';

/// Ingrédients proposés dans la liste (l'utilisateur peut aussi taper n'importe quel autre nom).
const ingredientsDeDepart = [
  'Maïs grain',
  'Sorgho',
  'Mil',
  'Tourteau de soja',
  'Tourteau de coton',
  "Tourteau d'arachide",
  'Tourteau de sésame',
  'Son de blé',
  'Son de riz',
  'Farine de poisson',
  'Drêche',
  'Prémix',
  'Coquilles broyées (calcium)',
  "Poudre d'os",
  'Sel',
  'Huile de palme',
  'Lysine',
  'Méthionine',
];

/// Ouvre la fenêtre « Ma formule » pour une étape. Renvoie true si la formule a été enregistrée ou remise à l'origine.
Future<bool> editerFormulePerso(BuildContext context, String etape, String titreEtape) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogueFormule(etape: etape, titreEtape: titreEtape),
  );
  return r ?? false;
}

class _Ligne {
  final TextEditingController nom, pct, prix;
  _Ligne(String n, double p, double c)
      : nom = TextEditingController(text: n),
        pct = TextEditingController(text: p > 0 ? nombreCourt(p) : ''),
        prix = TextEditingController(text: c > 0 ? nombreCourt(c) : '');

  void liberer() {
    nom.dispose();
    pct.dispose();
    prix.dispose();
  }
}

double? _nombre(String t) => double.tryParse(t.trim().replaceAll(' ', '').replaceAll(',', '.'));

class _DialogueFormule extends StatefulWidget {
  final String etape, titreEtape;
  const _DialogueFormule({required this.etape, required this.titreEtape});

  @override
  State<_DialogueFormule> createState() => _DialogueFormuleState();
}

class _DialogueFormuleState extends State<_DialogueFormule> {
  final List<_Ligne> _lignes = [];
  String _erreur = '';
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // Point de départ : la formule actuelle de l'étape (la personnalisée si elle existe, sinon celle d'origine).
    final d = Previsions.formule(widget.etape);
    for (final l in d.lignes) {
      _lignes.add(_Ligne(l.nom, l.kg, l.kg > 0 ? l.cout / l.kg : 0));
    }
  }

  @override
  void dispose() {
    for (final l in _lignes) {
      l.liberer();
    }
    super.dispose();
  }

  double get _totalPct => _lignes.fold(0.0, (s, l) => s + (_nombre(l.pct.text) ?? 0));
  double get _coutSac => _lignes.fold(0.0, (s, l) => s + (_nombre(l.pct.text) ?? 0) * (_nombre(l.prix.text) ?? 0));

  void _ajouter() => setState(() => _lignes.add(_Ligne('', 0, 0)));

  void _retirer(int i) {
    final l = _lignes.removeAt(i);
    setState(() {});
    // on attend la fin de l'image en cours avant de libérer les champs
    Future.delayed(const Duration(milliseconds: 300), l.liberer);
  }

  Future<void> _enregistrer() async {
    if (_enCours) return;
    final noms = <String>{};
    final sortie = <IngredientPerso>[];
    String? probleme;
    for (final l in _lignes) {
      final nom = l.nom.text.trim();
      if (nom.isEmpty && l.pct.text.trim().isEmpty && l.prix.text.trim().isEmpty) continue; // ligne vide : ignorée
      final pct = _nombre(l.pct.text);
      final prix = _nombre(l.prix.text);
      if (nom.isEmpty) {
        probleme = '⚠️ Donnez un nom à chaque ingrédient.';
      } else if (!noms.add(nom.toLowerCase())) {
        probleme = '⚠️ « $nom » apparaît deux fois : regroupez-les sur une seule ligne.';
      } else if (pct == null || pct <= 0) {
        probleme = '⚠️ Indiquez la part (%) de « $nom ».';
      } else if (prix == null || prix <= 0) {
        probleme = '⚠️ Indiquez le prix au kilo de « $nom ».';
      } else {
        sortie.add(IngredientPerso(nom, pct, prix));
      }
      if (probleme != null) break;
    }
    if (probleme == null && sortie.isEmpty) probleme = '⚠️ Ajoutez au moins un ingrédient.';
    if (probleme == null) {
      final total = sortie.fold(0.0, (s, i) => s + i.pct);
      if ((total - 100).abs() > 0.05) {
        probleme = total < 100
            ? '⚠️ Le total fait ${nombreCourt(total)} % : il manque ${nombreCourt(100 - total)} % pour arriver à 100 %.'
            : '⚠️ Le total fait ${nombreCourt(total)} % : il y a ${nombreCourt(total - 100)} % de trop (il faut 100 %).';
      }
    }
    if (probleme != null) {
      setState(() => _erreur = probleme!);
      return;
    }
    setState(() => _enCours = true);
    await Previsions.enregistrerPerso(widget.etape, sortie);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _revenirOrigine() async {
    final ok = await Dialogues.confirmer(
      context,
      "Formule d'origine",
      "Voulez-vous supprimer votre formule et revenir à la formule d'origine de Hakili ?\n\nVotre formule personnelle sera effacée.",
      oui: 'Revenir', non: 'Garder la mienne',
    );
    if (!ok || !mounted) return;
    await Previsions.retirerPerso(widget.etape);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _entete(Palette p, String t, {TextAlign a = TextAlign.left}) => Text(t,
      textAlign: a, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.txtGris));

  InputDecoration _deco(String indice, {Widget? fin}) => InputDecoration(
        hintText: indice, isDense: true, suffixIcon: fin,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      );

  Widget _ligne(Palette p, int i) {
    final l = _lignes[i];
    final pct = _nombre(l.pct.text) ?? 0, prix = _nombre(l.prix.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: l.nom,
            style: const TextStyle(fontSize: 13),
            decoration: _deco(
              'Nom de l\'ingrédient',
              fin: PopupMenuButton<String>(
                tooltip: 'Choisir dans la liste',
                icon: Icon(Icons.arrow_drop_down, color: p.txtDoux),
                onSelected: (v) => setState(() => l.nom.text = v),
                itemBuilder: (_) => [
                  for (final n in ingredientsDeDepart) PopupMenuItem(value: n, height: 36, child: Text(n, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 84,
          child: TextField(
            controller: l.pct,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13),
            decoration: _deco('%'),
            onChanged: (_) => setState(() => _erreur = ''),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: TextField(
            controller: l.prix,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13),
            decoration: _deco('F / kg'),
            onChanged: (_) => setState(() => _erreur = ''),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(pct > 0 && prix > 0 ? fmtF(pct * prix) : '—',
              textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ),
        IconButton(
          tooltip: 'Retirer cet ingrédient',
          onPressed: _lignes.length <= 1 ? null : () => _retirer(i),
          icon: Icon(Icons.delete_outline, size: 20, color: p.danger),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final total = _totalPct;
    final juste = (total - 100).abs() <= 0.05;
    final cout = _coutSac;
    final etat = juste
        ? '✅ Total : ${nombreCourt(total)} %'
        : (total < 100
            ? '⚠️ Total : ${nombreCourt(total)} %  (il manque ${nombreCourt(100 - total)} %)'
            : '⚠️ Total : ${nombreCourt(total)} %  (${nombreCourt(total - 100)} % de trop)');
    return Dialog(
      backgroundColor: p.panneau,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('✏️  MA FORMULE D\'ALIMENT',
                style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 2),
            Text(widget.titreEtape, style: TextStyle(fontSize: 12, color: p.txtDoux)),
            const SizedBox(height: 4),
            Text('Pour 100 kg de mélange. Les parts (%) doivent faire 100 % au total. Choisissez un ingrédient dans la liste ▾ ou tapez le vôtre.',
                style: TextStyle(fontSize: 11, color: p.txtGris)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(flex: 5, child: _entete(p, 'INGRÉDIENT')),
              const SizedBox(width: 8),
              SizedBox(width: 84, child: _entete(p, 'PART (%)')),
              const SizedBox(width: 8),
              SizedBox(width: 104, child: _entete(p, 'PRIX / KG')),
              const SizedBox(width: 8),
              SizedBox(width: 92, child: _entete(p, 'COÛT', a: TextAlign.right)),
              const SizedBox(width: 48),
            ]),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [for (var i = 0; i < _lignes.length; i++) _ligne(p, i)]),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _ajouter,
                child: const Text('➕ Ajouter un ingrédient', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const Divider(height: 18),
            Row(children: [
              Text(etat, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: juste ? p.succes : p.alerte)),
              const Spacer(),
              Text('Coût : ${(cout / 100).toStringAsFixed(1)} F / kg   ·   Sac de 100 kg : ${fmtF(cout)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ]),
            if (_erreur.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_erreur, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.danger)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              if (Previsions.aPerso(widget.etape))
                TextButton(
                  onPressed: _enCours ? null : _revenirOrigine,
                  style: TextButton.styleFrom(foregroundColor: p.txtDoux),
                  child: const Text("↩️ Revenir à la formule d'origine"),
                ),
              const Spacer(),
              TextButton(
                onPressed: _enCours ? null : () => Navigator.pop(context, false),
                style: TextButton.styleFrom(foregroundColor: p.txtGris),
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _enCours ? null : _enregistrer,
                child: const Text('Enregistrer ma formule', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

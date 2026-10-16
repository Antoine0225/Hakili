import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/parametres.dart';

/// Le logo de la ferme : choisi dans Paramètres, gardé dans la base de ce PC,
/// et placé UNIQUEMENT en haut des documents PDF (jamais affiché ailleurs dans le logiciel).
class LogoPdf {
  LogoPdf._();

  static const _cle = 'logo_ferme_png';
  static Uint8List? _cache;
  static bool _lu = false;

  /// Les octets de l'image (PNG réduit) ou null s'il n'y a pas de logo.
  static Future<Uint8List?> octets() async {
    if (_lu) return _cache;
    try {
      final t = await Parametres.lire(_cle);
      _cache = t.isEmpty ? null : base64Decode(t);
    } catch (_) {
      _cache = null;
    }
    _lu = true;
    return _cache;
  }

  static Future<bool> existe() async => (await octets()) != null;

  /// Le logo prêt à poser en haut d'un PDF (null s'il n'y en a pas). [alignement] : gauche par défaut.
  static Future<pw.Widget?> widget({double hauteur = 46, bool centre = false}) async {
    final o = await octets();
    if (o == null) return null;
    try {
      final img = pw.Image(pw.MemoryImage(o), height: hauteur, fit: pw.BoxFit.contain);
      return pw.Align(alignment: centre ? pw.Alignment.center : pw.Alignment.centerLeft, child: img);
    } catch (_) {
      return null; // image illisible : le PDF se fait quand même, sans logo
    }
  }

  /// Fait choisir une image (PNG ou JPG), la réduit, puis l'enregistre. Renvoie true si c'est fait,
  /// false si le client a annulé, et lance une erreur si l'image est illisible.
  static Future<bool> choisirEtEnregistrer() async {
    final fichier = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
    ]);
    if (fichier == null) return false;
    final brut = await fichier.readAsBytes();
    // réduction : 240 pixels de haut suffisent largement pour un PDF net et léger
    final codec = await ui.instantiateImageCodec(brut, targetHeight: 240);
    final image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw Exception('image illisible');
    final octetsPng = png.buffer.asUint8List();
    await Parametres.ecrire(_cle, base64Encode(octetsPng));
    _cache = octetsPng;
    _lu = true;
    return true;
  }

  static Future<void> retirer() async {
    await Parametres.ecrire(_cle, '');
    _cache = null;
    _lu = true;
  }
}

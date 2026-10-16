/// Les PDF de Hakili utilisent une police simple, sans accents ni emojis : ce petit outil nettoie
/// les textes qui viennent de la base (noms de clients, de produits, détails du journal...).
String sansAccents(String t) {
  const de = 'àâäçéèêëîïôöùûüÿñÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸÑ';
  const vers = 'aaaceeeeiioouuuynAAACEEEEIIOOUUUYN';
  final sb = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    if (i >= 0) {
      sb.write(vers[i]);
    } else if (r == 0x153) {
      sb.write('oe');
    } else if (r == 0x152) {
      sb.write('OE');
    } else if (r == 0x2019) {
      sb.write("'");
    } else if (r == 0x2013 || r == 0x2014 || r == 0x2212) {
      sb.write('-');
    } else if (r == 0xD7) {
      sb.write('x');
    } else if (r == 0xA0 || r == 0x202F || r == 0x2009) {
      sb.write(' ');
    } else if (r == 0xB7 || r == 0x2022) {
      sb.write('-');
    } else if (r == 0x2192) {
      sb.write('->');
    } else if (r >= 32 && r < 127) {
      sb.write(c);
    }
  }
  return sb.toString().trim();
}

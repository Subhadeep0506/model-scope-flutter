/// Formats a byte count the way every size label in the mockups is drawn.
///
/// Hugging Face reports sizes in decimal units, and the mockups follow suit —
/// `1.10 GB` next to a quant chip is 1.10 × 10⁹ bytes, not a gibibyte. Keeping
/// one helper means the catalog chips, the installed-model rows, the
/// `Models · 8.06 GB` heading and the Storage card can never disagree.
String formatBytes(int bytes) {
  const int mb = 1000 * 1000;
  const int gb = 1000 * mb;
  const int kb = 1000;

  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes B';
}

/// Abbreviates a download count, matching `182k downloads` in the mockup.
String formatCount(int count) {
  if (count >= 1000000) {
    final millions = count / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }
  if (count >= 1000) {
    final thousands = count / 1000;
    return '${thousands.toStringAsFixed(thousands >= 100 ? 0 : 1)}k';
  }
  return '$count';
}

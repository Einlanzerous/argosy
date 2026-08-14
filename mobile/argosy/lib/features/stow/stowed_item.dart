import '../browse/media_card.dart';

/// A subtitle track that came down with a stowed item, already converted to
/// WebVTT and sitting next to the video file.
class StowedSubtitle {
  const StowedSubtitle({
    required this.id,
    required this.label,
    required this.language,
    required this.fileName,
  });

  final String id;
  final String label;
  final String language;

  /// File name (not a full path) inside the item's stow directory. Paths are
  /// stored relative because iOS moves the application container between
  /// launches — an absolute path recorded today is wrong after the next update.
  final String fileName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'language': language,
    'fileName': fileName,
  };

  static StowedSubtitle fromJson(Map<String, dynamic> json) => StowedSubtitle(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    language: json['language'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
  );
}

/// One item packed away on this device, as recorded in the on-device index.
///
/// This carries everything the Stowed screen and the offline player need to work
/// with no server reachable: enough catalog metadata to render a row, the file
/// to play, and the tracks to play alongside it. Anything not stored here is
/// simply unavailable offline, which is why the list is a little wider than it
/// first looks.
class StowedItem {
  const StowedItem({
    required this.itemId,
    required this.title,
    required this.fileName,
    required this.bytes,
    required this.stowedAt,
    this.subtitleLine,
    this.durationSeconds = 0,
    this.posterUrl,
    this.kind = MediaKind.movie,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.subtitles = const [],
    this.incomplete = false,
  });

  final String itemId;
  final String title;

  /// Secondary line — the year for a film, "S1 · E3" and the episode title for
  /// an episode. Rendered offline, so it is stored rather than re-derived.
  final String? subtitleLine;

  /// Video file name inside the item's stow directory.
  final String fileName;
  final int bytes;
  final double durationSeconds;
  final DateTime stowedAt;

  /// Absolute poster URL. Artwork is served unauthenticated and cached by the
  /// image layer; offline it simply fails to load and the row falls back to its
  /// gradient, which is a better trade than bundling artwork into every package.
  final String? posterUrl;

  final MediaKind kind;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final List<StowedSubtitle> subtitles;

  /// True while the download is unfinished — the entry exists so the bytes on
  /// disk are visible, countable and deletable, but there is no playable file
  /// behind it yet.
  ///
  /// Recorded up front rather than only on success: a stow that fails partway
  /// deliberately keeps its `.part` so a retry resumes, and without a row for it
  /// those bytes would be invisible to the storage view, absent from the list,
  /// and unreachable by delete — several gigabytes with no way to see or
  /// reclaim them.
  final bool incomplete;

  /// Size of the finished file, or of the bytes downloaded so far while
  /// [incomplete].
  int get sizeOnDisk => bytes;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'title': title,
    'subtitleLine': subtitleLine,
    'fileName': fileName,
    'bytes': bytes,
    'durationSeconds': durationSeconds,
    'stowedAt': stowedAt.toIso8601String(),
    'posterUrl': posterUrl,
    'kind': kind.name,
    'seriesId': seriesId,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'subtitles': subtitles.map((s) => s.toJson()).toList(),
    'incomplete': incomplete,
  };

  StowedItem copyWith({
    int? bytes,
    bool? incomplete,
    List<StowedSubtitle>? subtitles,
  }) => StowedItem(
    itemId: itemId,
    title: title,
    fileName: fileName,
    bytes: bytes ?? this.bytes,
    stowedAt: stowedAt,
    subtitleLine: subtitleLine,
    durationSeconds: durationSeconds,
    posterUrl: posterUrl,
    kind: kind,
    seriesId: seriesId,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    subtitles: subtitles ?? this.subtitles,
    incomplete: incomplete ?? this.incomplete,
  );

  static StowedItem fromJson(Map<String, dynamic> json) => StowedItem(
    itemId: json['itemId'] as String,
    title: json['title'] as String? ?? 'Untitled',
    subtitleLine: json['subtitleLine'] as String?,
    fileName: json['fileName'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
    stowedAt:
        DateTime.tryParse(json['stowedAt'] as String? ?? '') ?? DateTime.now(),
    posterUrl: json['posterUrl'] as String?,
    kind: json['kind'] == MediaKind.series.name
        ? MediaKind.series
        : MediaKind.movie,
    seriesId: json['seriesId'] as String?,
    seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
    episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
    subtitles: (json['subtitles'] as List<dynamic>? ?? const [])
        .map((s) => StowedSubtitle.fromJson(s as Map<String, dynamic>))
        .toList(),
    incomplete: json['incomplete'] as bool? ?? false,
  );
}

/// What a stow is currently doing, for the button and the Stowed list.
enum StowPhase {
  /// Not stowed, nothing in flight.
  none,

  /// The server is deciding, or queueing the encode.
  requesting,

  /// The server is re-encoding this item into an offline package.
  packaging,

  /// Bytes are coming down.
  downloading,

  /// On the device and playable offline.
  stowed,

  failed,
}

/// Live status for one item's stow, held in memory by the controller. The
/// [StowedItem] index on disk only records finished stows; this is the part that
/// changes second to second.
class StowStatus {
  const StowStatus({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.packagedSeconds = 0,
    this.durationSeconds = 0,
    this.message,
  });

  const StowStatus.none() : this(phase: StowPhase.none);

  final StowPhase phase;
  final int receivedBytes;
  final int totalBytes;

  /// How far the server-side encode has reached, when packaging.
  final double packagedSeconds;
  final double durationSeconds;

  /// Reason text while deciding/packaging, or the failure when [phase] is
  /// [StowPhase.failed].
  final String? message;

  bool get isBusy =>
      phase == StowPhase.requesting ||
      phase == StowPhase.packaging ||
      phase == StowPhase.downloading;

  /// 0..1 for the active phase, or null when there is nothing to measure yet
  /// (the caller shows an indeterminate spinner).
  double? get fraction {
    switch (phase) {
      case StowPhase.downloading:
        if (totalBytes <= 0) return null;
        return (receivedBytes / totalBytes).clamp(0.0, 1.0);
      case StowPhase.packaging:
        if (durationSeconds <= 0) return null;
        return (packagedSeconds / durationSeconds).clamp(0.0, 1.0);
      default:
        return null;
    }
  }

  /// Short label for the button/row while work is in flight.
  String get label {
    switch (phase) {
      case StowPhase.none:
        return 'Stow';
      case StowPhase.requesting:
        return 'Preparing…';
      case StowPhase.packaging:
        final f = fraction;
        return f == null ? 'Packaging…' : 'Packaging ${(f * 100).round()}%';
      case StowPhase.downloading:
        final f = fraction;
        return f == null ? 'Downloading…' : 'Downloading ${(f * 100).round()}%';
      case StowPhase.stowed:
        return 'Stowed';
      case StowPhase.failed:
        return 'Retry';
    }
  }
}

import 'package:flutter/foundation.dart';

/// The words the scanner shows or says: its buttons, for screen readers, and
/// what the web, Windows and Linux page writes when the camera will not start.
///
/// English by default. [ScannerLabels.french], [ScannerLabels.dutch] and
/// [ScannerLabels.german] are ready to use, and any of them can be changed
/// piece by piece with [copyWith]. The native scanners of Android, iOS and
/// macOS draw their own words, except for `ScannerBar.cancelLabel`.
@immutable
class ScannerLabels {
  /// English, or the words given.
  const ScannerLabels({
    this.close = 'Close',
    this.torch = 'Torch',
    this.pause = 'Pause',
    this.resume = 'Resume',
    this.flipHorizontal = 'Flip horizontally',
    this.flipVertical = 'Flip vertically',
    this.switchCamera = 'Switch camera',
    this.cameraBlocked = 'Camera blocked',
    this.cameraBlockedWeb =
        'The page needs permission to use the camera. Allow it in the '
        'address bar, then reload.',
    this.cameraBlockedDesktop =
        'Allow this application to use the camera in the system settings, '
        'then open the scanner again.',
    this.noCamera = 'No camera found',
    this.noCameraWeb =
        'This device has no camera the browser can open. Try it on a phone.',
    this.noCameraDesktop = 'This computer has no camera the scanner can open.',
    this.cameraBusy = 'Camera busy',
    this.cameraBusyWeb =
        'Another application is using it. Close that one and reload.',
    this.cameraBusyDesktop =
        'Another application is using it. Close that one and open the '
        'scanner again.',
    this.insecureOrigin = 'Not a secure origin',
    this.insecureOriginDetail =
        'A browser only opens the camera over HTTPS or on localhost.',
    this.cameraFailed = 'The camera did not start',
    this.noReason = 'No reason was given.',
    this.decoderFailed = 'The scanner did not load',
    this.decoderFailedDetail = 'The decoder could not be started.',
  });

  /// English, the default.
  static const ScannerLabels english = ScannerLabels();

  /// French.
  static const ScannerLabels french = ScannerLabels(
    close: 'Fermer',
    torch: 'Lampe',
    resume: 'Reprendre',
    flipHorizontal: 'Retourner horizontalement',
    flipVertical: 'Retourner verticalement',
    switchCamera: 'Changer de caméra',
    cameraBlocked: 'Caméra bloquée',
    cameraBlockedWeb:
        "La page a besoin de l'autorisation d'utiliser la caméra. "
        "Autorisez-la dans la barre d'adresse, puis rechargez.",
    cameraBlockedDesktop:
        "Autorisez cette application à utiliser la caméra dans les "
        'paramètres du système, puis rouvrez le scanner.',
    noCamera: 'Aucune caméra trouvée',
    noCameraWeb:
        "Cet appareil n'a pas de caméra que le navigateur peut ouvrir. "
        'Essayez sur un téléphone.',
    noCameraDesktop:
        "Cet ordinateur n'a pas de caméra que le scanner peut ouvrir.",
    cameraBusy: 'Caméra occupée',
    cameraBusyWeb:
        "Une autre application l'utilise. Fermez-la, puis rechargez.",
    cameraBusyDesktop:
        "Une autre application l'utilise. Fermez-la, puis rouvrez le "
        'scanner.',
    insecureOrigin: 'Origine non sécurisée',
    insecureOriginDetail:
        "Un navigateur n'ouvre la caméra qu'en HTTPS ou sur localhost.",
    cameraFailed: "La caméra n'a pas démarré",
    noReason: "Aucune raison n'a été donnée.",
    decoderFailed: "Le scanner ne s'est pas chargé",
    decoderFailedDetail: "Le décodeur n'a pas pu démarrer.",
  );

  /// Dutch.
  static const ScannerLabels dutch = ScannerLabels(
    close: 'Sluiten',
    torch: 'Zaklamp',
    pause: 'Pauzeren',
    resume: 'Hervatten',
    flipHorizontal: 'Horizontaal spiegelen',
    flipVertical: 'Verticaal spiegelen',
    switchCamera: 'Andere camera',
    cameraBlocked: 'Camera geblokkeerd',
    cameraBlockedWeb:
        'De pagina heeft toestemming nodig om de camera te gebruiken. Sta '
        'die toe in de adresbalk en laad de pagina opnieuw.',
    cameraBlockedDesktop:
        'Sta deze toepassing toe de camera te gebruiken in de '
        'systeeminstellingen en open de scanner opnieuw.',
    noCamera: 'Geen camera gevonden',
    noCameraWeb:
        'Dit apparaat heeft geen camera die de browser kan openen. Probeer '
        'het op een telefoon.',
    noCameraDesktop:
        'Deze computer heeft geen camera die de scanner kan openen.',
    cameraBusy: 'Camera bezet',
    cameraBusyWeb:
        'Een andere toepassing gebruikt hem. Sluit die en laad de pagina '
        'opnieuw.',
    cameraBusyDesktop:
        'Een andere toepassing gebruikt hem. Sluit die en open de scanner '
        'opnieuw.',
    insecureOrigin: 'Geen beveiligde oorsprong',
    insecureOriginDetail:
        'Een browser opent de camera alleen via HTTPS of op localhost.',
    cameraFailed: 'De camera is niet gestart',
    noReason: 'Er is geen reden opgegeven.',
    decoderFailed: 'De scanner is niet geladen',
    decoderFailedDetail: 'De decoder kon niet starten.',
  );

  /// German.
  static const ScannerLabels german = ScannerLabels(
    close: 'Schließen',
    torch: 'Taschenlampe',
    pause: 'Pausieren',
    resume: 'Fortsetzen',
    flipHorizontal: 'Horizontal spiegeln',
    flipVertical: 'Vertikal spiegeln',
    switchCamera: 'Kamera wechseln',
    cameraBlocked: 'Kamera blockiert',
    cameraBlockedWeb:
        'Die Seite braucht die Erlaubnis, die Kamera zu verwenden. Erlauben '
        'Sie sie in der Adressleiste und laden Sie die Seite neu.',
    cameraBlockedDesktop:
        'Erlauben Sie dieser Anwendung in den Systemeinstellungen, die '
        'Kamera zu verwenden, und öffnen Sie den Scanner erneut.',
    noCamera: 'Keine Kamera gefunden',
    noCameraWeb:
        'Dieses Gerät hat keine Kamera, die der Browser öffnen kann. '
        'Versuchen Sie es auf einem Telefon.',
    noCameraDesktop:
        'Dieser Computer hat keine Kamera, die der Scanner öffnen kann.',
    cameraBusy: 'Kamera belegt',
    cameraBusyWeb:
        'Eine andere Anwendung verwendet sie. Schließen Sie diese und laden '
        'Sie die Seite neu.',
    cameraBusyDesktop:
        'Eine andere Anwendung verwendet sie. Schließen Sie diese und öffnen '
        'Sie den Scanner erneut.',
    insecureOrigin: 'Kein sicherer Ursprung',
    insecureOriginDetail:
        'Ein Browser öffnet die Kamera nur über HTTPS oder auf localhost.',
    cameraFailed: 'Die Kamera ist nicht gestartet',
    noReason: 'Es wurde kein Grund angegeben.',
    decoderFailed: 'Der Scanner wurde nicht geladen',
    decoderFailedDetail: 'Der Decoder konnte nicht starten.',
  );

  /// The close button over the camera, when there is no bar.
  final String close;

  /// The buttons over the camera.
  final String torch;
  final String pause;
  final String resume;
  final String flipHorizontal;
  final String flipVertical;
  final String switchCamera;

  /// The camera refused: the title, then what to do in a browser and in a
  /// desktop application.
  final String cameraBlocked;
  final String cameraBlockedWeb;
  final String cameraBlockedDesktop;

  /// No camera at all.
  final String noCamera;
  final String noCameraWeb;
  final String noCameraDesktop;

  /// The camera held by another application.
  final String cameraBusy;
  final String cameraBusyWeb;
  final String cameraBusyDesktop;

  /// A page served over plain HTTP, where a browser opens no camera.
  final String insecureOrigin;
  final String insecureOriginDetail;

  /// Any other failure, and what is said when the browser gave no reason.
  final String cameraFailed;
  final String noReason;

  /// The decoder could not be loaded.
  final String decoderFailed;
  final String decoderFailedDetail;

  /// These labels with the ones given changed.
  ScannerLabels copyWith({
    String? close,
    String? torch,
    String? pause,
    String? resume,
    String? flipHorizontal,
    String? flipVertical,
    String? switchCamera,
    String? cameraBlocked,
    String? cameraBlockedWeb,
    String? cameraBlockedDesktop,
    String? noCamera,
    String? noCameraWeb,
    String? noCameraDesktop,
    String? cameraBusy,
    String? cameraBusyWeb,
    String? cameraBusyDesktop,
    String? insecureOrigin,
    String? insecureOriginDetail,
    String? cameraFailed,
    String? noReason,
    String? decoderFailed,
    String? decoderFailedDetail,
  }) => ScannerLabels(
    close: close ?? this.close,
    torch: torch ?? this.torch,
    pause: pause ?? this.pause,
    resume: resume ?? this.resume,
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    switchCamera: switchCamera ?? this.switchCamera,
    cameraBlocked: cameraBlocked ?? this.cameraBlocked,
    cameraBlockedWeb: cameraBlockedWeb ?? this.cameraBlockedWeb,
    cameraBlockedDesktop: cameraBlockedDesktop ?? this.cameraBlockedDesktop,
    noCamera: noCamera ?? this.noCamera,
    noCameraWeb: noCameraWeb ?? this.noCameraWeb,
    noCameraDesktop: noCameraDesktop ?? this.noCameraDesktop,
    cameraBusy: cameraBusy ?? this.cameraBusy,
    cameraBusyWeb: cameraBusyWeb ?? this.cameraBusyWeb,
    cameraBusyDesktop: cameraBusyDesktop ?? this.cameraBusyDesktop,
    insecureOrigin: insecureOrigin ?? this.insecureOrigin,
    insecureOriginDetail: insecureOriginDetail ?? this.insecureOriginDetail,
    cameraFailed: cameraFailed ?? this.cameraFailed,
    noReason: noReason ?? this.noReason,
    decoderFailed: decoderFailed ?? this.decoderFailed,
    decoderFailedDetail: decoderFailedDetail ?? this.decoderFailedDetail,
  );

  /// What the bundled page writes, for a page run by [host], `web` or
  /// `desktop`: each failure's title and what to do about it.
  Map<String, List<String>> toPage({required String host}) {
    final bool desktop = host == 'desktop';
    return <String, List<String>>{
      'blocked': <String>[
        cameraBlocked,
        if (desktop) cameraBlockedDesktop else cameraBlockedWeb,
      ],
      'missing': <String>[
        noCamera,
        if (desktop) noCameraDesktop else noCameraWeb,
      ],
      'busy': <String>[
        cameraBusy,
        if (desktop) cameraBusyDesktop else cameraBusyWeb,
      ],
      'insecure': <String>[insecureOrigin, insecureOriginDetail],
      'failed': <String>[cameraFailed, noReason],
      'decoder': <String>[decoderFailed, decoderFailedDetail],
    };
  }
}

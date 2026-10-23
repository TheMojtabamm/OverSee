import "dart:async";

import "package:flutter/foundation.dart" show ValueNotifier;

import "package:google_mobile_ads/google_mobile_ads.dart";

import "../core/log.dart";

/// Interstitial ad shown right after a successful connect, built to stay inside
/// Google Play / AdMob policy:
///
///  * Consent first. The Google UMP form is shown where required (EEA/UK/…) and no
///    ad is requested until [ConsentInformation.canRequestAds] is true.
///  * Natural break only: after the user tapped Connect and the tunnel is up.
///    Never on launch, on exit, on disconnect, or while connecting.
///  * Capped: at most one per [minGap], and none on the user's very first connect.
///  * Content rated PG at most.
///  * Test units unless a real `AD_INTERSTITIAL_ID` is injected at build time, so
///    development and unconfigured builds never serve (or self-click) live ads.
class AdService {
  static const String _testInterstitial =
      "ca-app-pub-3940256099942544/1033173712";
  static const String _unitId = String.fromEnvironment("AD_INTERSTITIAL_ID",
      defaultValue: _testInterstitial);

  static const Duration minGap = Duration(minutes: 5);

  static const String _testBanner = "ca-app-pub-3940256099942544/9214589741";
  static const String bannerUnitId =
      String.fromEnvironment("AD_BANNER_ID", defaultValue: _testBanner);

  /// True once consent allows ad requests and the SDK is started; the banner widget
  /// listens to this so it appears as soon as consent is given.
  static final ValueNotifier<bool> adsReady = ValueNotifier(false);

  static InterstitialAd? _ready;
  static bool _loading = false;
  static bool _sdkStarted = false;
  static DateTime? _lastShown;

  /// Gather consent, then start the SDK. Safe to call more than once.
  static Future<void> init() async {
    await _gatherConsent();
    await _startSdkIfAllowed();
  }

  static Future<void> _gatherConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((FormError? e) {
          if (e != null) Log.d("consent form: ${e.errorCode}");
          if (!done.isCompleted) done.complete();
        });
      },
      (FormError e) {
        Log.d("consent update failed: ${e.errorCode}");
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  static Future<void> _startSdkIfAllowed() async {
    if (_sdkStarted) return;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
    );
    await MobileAds.instance.initialize();
    _sdkStarted = true;
    adsReady.value = true;
    preload();
  }

  /// Settings entry point ("Ad privacy options"), required by UMP for some regions.
  static Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false; // no ads plugin (tests, desktop) or consent not initialised
    }
  }

  static Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await _startSdkIfAllowed();
  }

  static void preload() {
    if (!_sdkStarted || _ready != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ready = ad;
          _loading = false;
        },
        onAdFailedToLoad: (e) {
          _loading = false;
          Log.d("ad load failed: ${e.code}");
        },
      ),
    );
  }

  /// Decides whether an ad may be shown now (pure; unit-tested).
  static bool mayShow({
    required bool firstEverConnect,
    required DateTime? lastShown,
    required DateTime now,
    Duration gap = minGap,
  }) {
    if (firstEverConnect) return false;
    if (lastShown != null && now.difference(lastShown) < gap) return false;
    return true;
  }

  /// Call after the tunnel is up. Never blocks or delays the connection; a
  /// missing ad is silently skipped. [stillConnected] is re-checked right before
  /// showing so an ad can't appear after the user already disconnected.
  static void showAfterConnect({
    required bool firstEverConnect,
    required bool Function() stillConnected,
  }) {
    final now = DateTime.now();
    if (!mayShow(
        firstEverConnect: firstEverConnect, lastShown: _lastShown, now: now)) {
      return;
    }
    final ad = _ready;
    if (ad == null) {
      preload();
      return;
    }
    if (!stillConnected()) return;
    _ready = null;
    _lastShown = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        preload();
      },
    );
    ad.show();
  }
}

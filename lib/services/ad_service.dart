import "package:flutter/foundation.dart";
import "package:google_mobile_ads/google_mobile_ads.dart";

/// Shows one interstitial ad right after the user connects. The unit ID comes
/// from `--dart-define=AD_INTERSTITIAL_ID=...` in release builds; without it the
/// Google *test* unit is used, so debug and unconfigured builds never serve real
/// ads (and never risk account flags from self-clicks).
class AdService {
  static const String _testInterstitial =
      "ca-app-pub-3940256099942544/1033173712";
  static const String _unitId =
      String.fromEnvironment("AD_INTERSTITIAL_ID", defaultValue: _testInterstitial);

  static InterstitialAd? _ready;
  static bool _loading = false;

  static Future<void> init() async {
    await MobileAds.instance.initialize();
    preload();
  }

  /// Load the next ad in the background so it is ready when a connect succeeds.
  static void preload() {
    if (_ready != null || _loading) return;
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
          debugPrint("ad load failed: ${e.code}");
        },
      ),
    );
  }

  /// Call after the tunnel is up. No-op (silently) if no ad is ready, so a
  /// missing ad never blocks or delays the connection.
  static void showAfterConnect() {
    final ad = _ready;
    if (ad == null) {
      preload();
      return;
    }
    _ready = null;
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

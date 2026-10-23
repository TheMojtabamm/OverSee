import "package:flutter/material.dart";
import "package:google_mobile_ads/google_mobile_ads.dart";

import "../../core/log.dart";
import "../../data/ad_service.dart";

/// One anchored adaptive AdMob banner, shown under the config list.
///
/// Policy-wise: it is placed away from the config buttons (a margin separates it
/// from tappable rows), it appears only after consent allows ad requests, and it
/// takes no space at all until an ad has actually loaded.
class BannerAdBox extends StatefulWidget {
  const BannerAdBox({super.key});
  @override
  State<BannerAdBox> createState() => _BannerAdBoxState();
}

class _BannerAdBoxState extends State<BannerAdBox> {
  BannerAd? _ad;
  bool _loaded = false;
  int _width = 0;

  @override
  void initState() {
    super.initState();
    AdService.adsReady.addListener(_maybeLoad);
  }

  @override
  void dispose() {
    AdService.adsReady.removeListener(_maybeLoad);
    _ad?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = MediaQuery.sizeOf(context).width.truncate();
    if (w != _width) {
      _width = w;
      _maybeLoad();
    }
  }

  Future<void> _maybeLoad() async {
    if (!AdService.adsReady.value || _width == 0 || !mounted) return;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(_width);
    if (size == null || !mounted) return;
    _ad?.dispose();
    setState(() => _loaded = false);
    final ad = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, e) {
          Log.d("banner failed: ${e.code}");
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}

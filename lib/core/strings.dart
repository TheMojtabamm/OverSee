import "package:flutter/material.dart";

/// Minimal fa/en string table. Persian is the primary audience, so every key
/// must exist in both languages (enforced by a unit test).
class S {
  final Locale locale;
  const S(this.locale);

  static const supportedLocales = [Locale("fa"), Locale("en")];
  static const LocalizationsDelegate<S> delegate = _SDelegate();

  static S of(BuildContext context) => Localizations.of<S>(context, S)!;

  String t(String key) =>
      (table[locale.languageCode] ?? table["en"]!)[key] ??
      table["en"]![key] ??
      key;

  static const Map<String, Map<String, String>> table = {
    "en": {
      "tab_configs": "Configs",
      "tab_add": "Add",
      "configs_title": "Configs",
      "empty_title": "No configs yet.",
      "empty_hint":
          "Open the Add tab to paste a config or import a locked file.",
      "locked": "Locked",
      "connect_ok": "Connected",
      "channel": "Channel",
      "open_channel": "Open Channel",
      "cancel": "Cancel",
      "continue": "Continue",
      "add_title": "Add config",
      "add_hint": "vless:// vmess:// trojan:// ss://  …",
      "paste": "Paste",
      "add": "Add",
      "import_locked": "Import locked file (.ovsea)",
      "clipboard_empty": "Clipboard is empty.",
      "no_xray":
          "No supported Xray config found (VLESS / VMess / Trojan / Shadowsocks).",
      "no_key": "This build cannot open locked files.",
      "share": "Share",
      "copy": "Copy",
      "copied": "Config copied",
      "qr": "QR code",
      "hide_qr": "Hide QR",
      "lock_title": "Lock (export as protected file)",
      "lock_sub": "Only Oversea can open it. Shared as a file.",
      "ad_text": "Ad text (shown to whoever opens it)",
      "tg_url": "Telegram channel URL",
      "lock_share": "Lock & share file",
      "settings": "Settings",
      "sponsored": "Sponsored",
      "sponsored_note":
          "Message from the owner of this config. Not from Oversea.",
      "status_disconnected": "Disconnected",
      "status_connecting": "Connecting…",
      "status_connected": "Connected",
      "status_blocked": "Blocked — connection lost",
      "status_error": "Connection failed",
      "disconnect": "Disconnect",
      "vpn_denied": "VPN permission was not granted.",
      "unsupported": "This config type is not supported.",
      "connect_failed": "Could not connect.",
      "invalid_tg": "Channel link must be an https://t.me/… link.",
      "disclosure_title": "VPN connection",
      "disclosure_body":
          "Oversea uses Android's VPN service to route your device's internet traffic through the server in the config you choose. Your traffic is encrypted between your phone and that server.\n\nOversea does not record, store or sell your browsing activity. The server you pick is run by the config's owner, so only connect to servers you trust.\n\nThe app shows ads (Google AdMob), which may use your advertising ID if you consent.",
      "agree": "Agree & continue",
      "dns": "Private DNS (DoH)",
      "dns_hint": "Lookups are sent through the tunnel.",
      "fragment": "TLS fragmentation",
      "fragment_hint": "Helps on networks that filter by SNI.",
      "ipv6": "IPv6",
      "ipv6_hint": "Off: IPv6 is blocked inside the tunnel (no leaks).",
      "bypass_lan": "Bypass local network",
      "kill_switch": "Kill switch",
      "kill_switch_hint":
          "If the connection drops, block traffic instead of leaking.",
      "system_vpn": "System VPN settings (Always-on)",
      "split": "Per-app VPN",
      "split_all": "All apps",
      "split_allow": "Only selected",
      "split_deny": "Except selected",
      "choose_apps": "Choose apps",
      "search": "Search",
      "privacy_policy": "Privacy policy",
      "ad_privacy": "Ad privacy options",
      "no_policy": "No policy URL configured in this build.",
      "creator_verified": "Verified creator",
      "creator_unknown": "Creator (not trusted)",
      "creator_unsigned": "Unsigned file — creator unknown",
      "trust": "Trust",
      "untrust": "Remove trust",
      "your_creator_id": "Your creator ID",
      "your_creator_hint":
          "Publish this in your channel so followers can recognise your official files.",
      "test_all": "Test all",
      "ms": "ms",
      "failed": "failed",
    },
    "fa": {
      "tab_configs": "کانفیگ‌ها",
      "tab_add": "افزودن",
      "configs_title": "کانفیگ‌ها",
      "empty_title": "هنوز کانفیگی نیست.",
      "empty_hint":
          "از تب «افزودن» کانفیگ را پیست کنید یا فایل قفل‌شده وارد کنید.",
      "locked": "قفل‌شده",
      "connect_ok": "متصل شد",
      "channel": "کانال",
      "open_channel": "باز کردن کانال",
      "cancel": "انصراف",
      "continue": "ادامه",
      "add_title": "افزودن کانفیگ",
      "add_hint": "vless:// vmess:// trojan:// ss://  …",
      "paste": "پیست",
      "add": "افزودن",
      "import_locked": "وارد کردن فایل قفل‌شده (.ovsea)",
      "clipboard_empty": "کلیپ‌بورد خالی است.",
      "no_xray":
          "کانفیگ Xray پشتیبانی‌شده‌ای پیدا نشد (VLESS / VMess / Trojan / Shadowsocks).",
      "no_key": "این نسخه نمی‌تواند فایل قفل‌شده را باز کند.",
      "share": "اشتراک‌گذاری",
      "copy": "کپی",
      "copied": "کانفیگ کپی شد",
      "qr": "کد QR",
      "hide_qr": "پنهان کردن QR",
      "lock_title": "قفل (خروجی به‌صورت فایل محافظت‌شده)",
      "lock_sub":
          "فقط Oversea می‌تواند آن را باز کند. به‌صورت فایل ارسال می‌شود.",
      "ad_text": "متن تبلیغ (به هر کسی که باز کند نمایش داده می‌شود)",
      "tg_url": "لینک کانال تلگرام",
      "lock_share": "قفل و ارسال فایل",
      "settings": "تنظیمات",
      "sponsored": "حمایت‌شده",
      "sponsored_note": "پیام از طرف صاحب این کانفیگ است، نه Oversea.",
      "status_disconnected": "قطع",
      "status_connecting": "در حال اتصال…",
      "status_connected": "متصل",
      "status_blocked": "مسدود — اتصال قطع شد",
      "status_error": "اتصال ناموفق بود",
      "disconnect": "قطع اتصال",
      "vpn_denied": "مجوز VPN داده نشد.",
      "unsupported": "این نوع کانفیگ پشتیبانی نمی‌شود.",
      "connect_failed": "اتصال برقرار نشد.",
      "invalid_tg": "لینک کانال باید به شکل https://t.me/… باشد.",
      "disclosure_title": "اتصال VPN",
      "disclosure_body":
          "Oversea از سرویس VPN اندروید استفاده می‌کند تا ترافیک اینترنت دستگاه شما را از طریق سرور کانفیگ انتخابی عبور دهد. ترافیک شما بین گوشی و آن سرور رمزگذاری می‌شود.\n\nOversea فعالیت وب‌گردی شما را ثبت، ذخیره یا فروش نمی‌کند. سرور انتخابی متعلق به صاحب کانفیگ است؛ فقط به سرورهایی که به آن‌ها اعتماد دارید وصل شوید.\n\nاپ تبلیغ (Google AdMob) نشان می‌دهد که در صورت رضایت شما ممکن است از شناسه‌ی تبلیغاتی استفاده کند.",
      "agree": "موافقم و ادامه",
      "dns": "DNS خصوصی (DoH)",
      "dns_hint": "درخواست‌های DNS از داخل تونل ارسال می‌شوند.",
      "fragment": "قطعه‌قطعه‌سازی TLS",
      "fragment_hint": "روی شبکه‌هایی که با SNI فیلتر می‌کنند کمک می‌کند.",
      "ipv6": "IPv6",
      "ipv6_hint": "خاموش: IPv6 داخل تونل مسدود می‌شود (بدون نشت).",
      "bypass_lan": "عبور مستقیم شبکه‌ی محلی",
      "kill_switch": "کلید قطع (Kill switch)",
      "kill_switch_hint": "اگر اتصال قطع شد، به‌جای نشت، ترافیک مسدود شود.",
      "system_vpn": "تنظیمات VPN سیستم (Always-on)",
      "split": "VPN به‌ازای هر برنامه",
      "split_all": "همه‌ی برنامه‌ها",
      "split_allow": "فقط انتخاب‌شده‌ها",
      "split_deny": "به‌جز انتخاب‌شده‌ها",
      "choose_apps": "انتخاب برنامه‌ها",
      "search": "جستجو",
      "privacy_policy": "سیاست حفظ حریم خصوصی",
      "ad_privacy": "گزینه‌های حریم خصوصی تبلیغات",
      "no_policy": "در این نسخه نشانی سیاست حریم خصوصی تنظیم نشده است.",
      "creator_verified": "سازنده‌ی تأییدشده",
      "creator_unknown": "سازنده (مورد اعتماد نیست)",
      "creator_unsigned": "فایل بدون امضا — سازنده نامشخص",
      "trust": "اعتماد",
      "untrust": "حذف اعتماد",
      "your_creator_id": "شناسه‌ی سازنده‌ی شما",
      "your_creator_hint":
          "این را در کانالتان منتشر کنید تا دنبال‌کنندگان فایل‌های رسمی شما را تشخیص دهند.",
      "test_all": "تست همه",
      "ms": "ms",
      "failed": "ناموفق",
    },
  };
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();
  @override
  bool isSupported(Locale locale) =>
      S.supportedLocales.any((l) => l.languageCode == locale.languageCode);
  @override
  Future<S> load(Locale locale) async => S(locale);
  @override
  bool shouldReload(covariant LocalizationsDelegate<S> old) => false;
}

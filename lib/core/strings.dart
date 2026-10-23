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

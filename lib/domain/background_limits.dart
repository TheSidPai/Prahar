/// Phone makers that keep an autostart gate of their own, on top of Android's
/// battery optimisation.
///
/// This is the most likely reason a student says reminders stopped. The
/// battery exemption tells stock Android not to freeze the process; it says
/// nothing to MIUI, ColorOS, Funtouch or One UI, each of which keeps a
/// separate list of apps allowed to start on their own, and each of which
/// defaults a newly installed app to "not allowed". The alarm stays
/// registered, `dumpsys alarm` still lists it, and nothing ever wakes to post
/// it.
///
/// No API reports the state of any of these lists. The app can know it is on a
/// phone that has the gate; it cannot know whether it is being blocked. That
/// asymmetry is the whole design of the notice this drives: it is advice
/// offered once, not a warning that claims to have checked.
///
/// Pure by the rule in CLAUDE.md — no Flutter, no channels — so the mapping is
/// testable without a device, which matters because the device it is about is
/// one nobody here owns.
class BackgroundGate {
  /// The maker's name as a person would write it.
  final String vendor;

  /// What that maker calls the setting. Getting this wrong is worse than
  /// saying nothing: it sends someone hunting for a switch that is not there
  /// under that name.
  final String settingName;

  /// True when the phone has an autostart screen but the maker is not one this
  /// app knows by name, so the copy has to stop naming things.
  final bool isGeneric;

  const BackgroundGate({
    required this.vendor,
    required this.settingName,
    this.isGeneric = false,
  });

  /// For a device that has a vendor autostart screen under a maker this app
  /// does not recognise.
  ///
  /// Better than saying nothing, because the screen demonstrably exists and
  /// the deep link will open it. Better than guessing a name, because a
  /// confidently wrong setting name sends someone hunting for a switch that is
  /// not called that.
  static const generic = BackgroundGate(
    vendor: 'this phone',
    settingName: 'autostart',
    isGeneric: true,
  );

  /// What the card on Today calls itself.
  String get noticeTitle => 'One more setting on $vendor';

  /// What the permanent Settings row calls itself. The generic gate has no
  /// name worth putting in a title, so it gets a plain one.
  String get rowTitle =>
      isGeneric ? 'Background autostart' : '$settingName on $vendor';

  /// The sentence explaining what to do. Capitalised at the front, so the
  /// generic "this phone" reads as a sentence rather than a fragment.
  String get explanation => isGeneric
      ? 'This phone keeps its own list of apps allowed to start on their '
            'own. Find Prahar in the list and allow it, so reminders keep '
            'arriving.'
      : '$vendor keeps its own list of apps allowed to start on their own. '
            'Turn on $settingName for Prahar so reminders keep arriving.';

  /// Picks the gate for a device, given its maker and whether a vendor
  /// autostart screen actually resolved on it.
  ///
  /// **`hasScreen` decides whether there is a gate at all**, because it is the
  /// only honest evidence available: it means an autostart activity was really
  /// found on this device. The maker string only chooses the wording. Doing it
  /// the other way round, which is how this shipped first, is wrong twice
  /// over — a maker not in the table gets no notice even though its phone
  /// gates background starts, and a maker in the table gets a card promising a
  /// screen that may not be installed.
  static BackgroundGate? resolve({
    required String manufacturer,
    required bool hasScreen,
  }) {
    if (!hasScreen) return null;
    return forManufacturer(manufacturer) ?? generic;
  }

  /// Maps `Build.MANUFACTURER`, lowercased, to how that maker's gate should be
  /// described. Null means the maker is not known by name, not that the phone
  /// has no gate — see [resolve].
  ///
  /// Google, Motorola, Nothing and Sony are absent deliberately: they ship
  /// stock Android with no autostart list, so nothing resolves on them anyway
  /// and they never reach this.
  static BackgroundGate? forManufacturer(String raw) {
    final m = raw.trim().toLowerCase();
    if (m.isEmpty) return null;

    return switch (m) {
      // Redmi and Poco ship MIUI/HyperOS and report themselves separately.
      'xiaomi' || 'redmi' || 'poco' => const BackgroundGate(
        vendor: 'Xiaomi',
        settingName: 'Autostart',
      ),
      'oppo' => const BackgroundGate(
        vendor: 'Oppo',
        settingName: 'Startup manager',
      ),
      'realme' => const BackgroundGate(
        vendor: 'Realme',
        settingName: 'Auto-launch',
      ),
      // Newer OnePlus builds are ColorOS underneath and share the setting.
      'oneplus' => const BackgroundGate(
        vendor: 'OnePlus',
        settingName: 'Auto-launch',
      ),
      'vivo' ||
      'iqoo' => const BackgroundGate(vendor: 'Vivo', settingName: 'Auto start'),
      'huawei' => const BackgroundGate(
        vendor: 'Huawei',
        settingName: 'App launch',
      ),
      'honor' => const BackgroundGate(
        vendor: 'Honor',
        settingName: 'App launch',
      ),
      // One UI has no autostart list; the equivalent is keeping the app out of
      // the sleeping-apps list, which is where the deep link lands.
      'samsung' => const BackgroundGate(
        vendor: 'Samsung',
        settingName: 'Never sleeping apps',
      ),
      'asus' => const BackgroundGate(
        vendor: 'Asus',
        settingName: 'Auto-start manager',
      ),
      'meizu' => const BackgroundGate(
        vendor: 'Meizu',
        settingName: 'Autostart',
      ),
      'letv' ||
      'leeco' => const BackgroundGate(vendor: 'Letv', settingName: 'Autostart'),
      // Transsion brands, which are common in India and kill aggressively.
      // Named separately: telling an Infinix owner they are on a Tecno is the
      // fastest way to make the whole notice look like it is guessing.
      'tecno' => const BackgroundGate(
        vendor: 'Tecno',
        settingName: 'Autostart',
      ),
      'infinix' => const BackgroundGate(
        vendor: 'Infinix',
        settingName: 'Autostart',
      ),
      'itel' => const BackgroundGate(vendor: 'Itel', settingName: 'Autostart'),
      _ => null,
    };
  }
}

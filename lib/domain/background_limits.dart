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

  const BackgroundGate({required this.vendor, required this.settingName});

  /// Maps `Build.MANUFACTURER`, lowercased, to the gate that phone has.
  ///
  /// Returns null for Pixel, Motorola, Nothing and anything unrecognised: no
  /// gate, so no notice. An unknown maker is treated as clean rather than
  /// warned about, because a notice nobody can act on is just noise.
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

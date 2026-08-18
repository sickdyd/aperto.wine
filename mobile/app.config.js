// Three build variants share one config, keyed off APP_VARIANT (set per EAS
// profile in eas.json). They carry distinct bundle identifiers so a tester can
// hold development, staging and production on one device without one upgrade
// silently replacing another.
const VARIANT = process.env.APP_VARIANT ?? "development";

const VARIANTS = {
  development: { suffix: ".dev", name: "aperto (dev)" },
  staging: { suffix: ".staging", name: "aperto (staging)" },
  production: { suffix: "", name: "aperto.wine" },
};

const { suffix, name } = VARIANTS[VARIANT] ?? VARIANTS.development;
const bundleIdentifier = `wine.aperto.app${suffix}`;

// The domain the app claims for universal links. Staging builds claim the
// staging host, so scanning a staging QR on a device holding both builds opens
// the staging app rather than production.
const LINK_DOMAIN =
  VARIANT === "production" ? "aperto.wine" : "staging.aperto.wine";

module.exports = {
  expo: {
    name,
    slug: "aperto-wine",
    version: "1.0.0",
    orientation: "portrait",
    scheme: "apertowine",
    userInterfaceStyle: "light", // the ledger is warm paper; there is no dark stock
    newArchEnabled: true,
    icon: "./assets/images/icon.png",
    splash: {
      image: "./assets/images/splash-icon.png",
      resizeMode: "contain",
      backgroundColor: "#F6F2E9", // paper, not white
    },

    web: {
      favicon: "./assets/images/favicon.png",
    },

    ios: {
      supportsTablet: false,
      bundleIdentifier,
      // The other half of the QR handoff. With this claim in place and a
      // matching apple-app-site-association served from the Rails app, scanning
      // a table QR opens the app when it is installed and Safari when it is
      // not — with no branching logic of our own, and with the QR still
      // encoding a plain https:// URL so already-printed table tents keep
      // working forever.
      associatedDomains: [`applinks:${LINK_DOMAIN}`],
      infoPlist: {
        ITSAppUsesNonExemptEncryption: false,
      },
    },

    android: {
      package: bundleIdentifier,
      edgeToEdgeEnabled: true,
      adaptiveIcon: {
        foregroundImage: "./assets/images/android-icon-foreground.png",
        // Android 13+ themed icons: the same mark as one flat colour on
        // transparency, which the launcher re-tints from the wallpaper. Without
        // it a themed home screen falls back to shrinking the full-colour icon
        // into a grey circle.
        monochromeImage: "./assets/images/android-icon-monochrome.png",
        // A flat token rather than a background PNG: the ground is one colour,
        // and `backgroundImage` would only be a 1024² image of it.
        backgroundColor: "#F6F2E9",
      },
      // Android's App Links, the counterpart to iOS associatedDomains.
      // autoVerify makes the OS check /.well-known/assetlinks.json at install
      // time; without it the user gets a disambiguation dialog instead of a
      // direct open.
      intentFilters: [
        {
          action: "VIEW",
          autoVerify: true,
          data: [{ scheme: "https", host: LINK_DOMAIN, pathPrefix: "/t/" }],
          category: ["BROWSABLE", "DEFAULT"],
        },
      ],
    },

    plugins: [
      "expo-router",
      "expo-localization",
      "expo-secure-store",
      "expo-font",
      [
        "expo-camera",
        {
          // Scanning is how a returning diner reaches a table without leaving
          // the app. First-time diners never see this — they arrive through the
          // QR itself, via the universal link above.
          cameraPermission:
            "aperto.wine uses the camera to scan the QR code on your table so it can show you that restaurant's wine list.",
          // The plugin requests RECORD_AUDIO by default, for video capture we
          // never do. Asking a diner for the microphone in order to read a QR
          // code is the kind of over-permission that sinks an App Store review
          // and, fairly, spooks users.
          recordAudioAndroid: false,
        },
      ],
      [
        "expo-notifications",
        {
          // Android reads nothing but the alpha channel of this file, so it is
          // the mark as a 96x96 white-on-transparent silhouette, not the app
          // icon. Pointing this at the full-colour icon is what renders the
          // notorious solid white square on the status bar.
          icon: "./assets/images/notification-icon.png",
          color: "#6E1F2A",
        },
      ],
    ],

    extra: {
      router: {},
      variant: VARIANT,
      // eas.projectId is filled in by `eas init` on first build.
    },

    experiments: {
      typedRoutes: true,
    },
  },
};

import { useState } from "react";
import { View, Text, Pressable, Linking } from "react-native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { useRouter } from "expo-router";
import { useTranslation } from "react-i18next";
import { SafeAreaView } from "react-native-safe-area-context";

import { extractTableToken } from "@/services/table-links";

/**
 * In-app QR scanning, for a returning diner who opens the app before reaching
 * for the table tent. A first-time diner never lands here — they scan with the
 * system camera and arrive through the universal link at t/[token].
 *
 * Anything that is not one of our table URLs is ignored rather than routed, so
 * a supermarket barcode cannot push a junk token into the app. See
 * services/table-links.
 */
export default function ScanScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [handled, setHandled] = useState(false);

  // `permission` is null until the hook has read the current status. Rendering
  // the request screen during that beat makes the button flash up and vanish on
  // every visit for a user who already granted access.
  if (!permission) {
    return <Gate title={t("common.loading")} />;
  }

  if (!permission.granted) {
    // canAskAgain is the whole distinction. Once a user has denied the camera,
    // iOS will not show the system dialog again for the life of the install, so
    // requestPermission() resolves to "denied" without presenting anything —
    // the button would look live and do nothing. That case has to route to
    // Settings instead, which is the only place the decision can be reversed.
    return permission.canAskAgain ? (
      <Gate
        title={t("table.permissionTitle")}
        body={t("table.permissionBody")}
        actionLabel={t("table.permissionGrant")}
        onAction={requestPermission}
        onDismiss={() => router.back()}
        dismissLabel={t("common.back")}
      />
    ) : (
      <Gate
        title={t("table.permissionTitle")}
        body={t("table.permissionDeniedBody")}
        actionLabel={t("table.permissionOpenSettings")}
        onAction={() => Linking.openSettings()}
        onDismiss={() => router.back()}
        dismissLabel={t("common.back")}
      />
    );
  }

  return (
    <View className="flex-1 bg-ox-1">
      <CameraView
        style={{ flex: 1 }}
        barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
        onBarcodeScanned={({ data }) => {
          // The camera fires continuously while a code is in frame; without
          // this guard one tent produces a stack of identical navigations.
          if (handled) return;

          const token = extractTableToken(data);
          if (!token) return;

          setHandled(true);
          router.replace(`/t/${token}`);
        }}
      />

      <SafeAreaView className="absolute inset-x-0 top-0">
        <Pressable
          accessibilityRole="button"
          onPress={() => router.back()}
          className="self-start px-6 py-4"
        >
          <Text className="font-mono text-xs tracking-widest text-on-deep uppercase">
            {t("common.back")}
          </Text>
        </Pressable>
      </SafeAreaView>

      <SafeAreaView className="absolute inset-x-0 bottom-0">
        <Text className="font-mono text-xs tracking-widest text-on-deep uppercase text-center pb-8">
          {t("table.scanning")}
        </Text>
      </SafeAreaView>
    </View>
  );
}

/** The non-camera states: loading, permission wanted, permission refused. */
function Gate({
  title,
  body,
  actionLabel,
  onAction,
  dismissLabel,
  onDismiss,
}: {
  title: string;
  body?: string;
  actionLabel?: string;
  onAction?: () => void;
  dismissLabel?: string;
  onDismiss?: () => void;
}) {
  return (
    <SafeAreaView className="flex-1 bg-paper">
      <View className="flex-1 px-6 justify-center">
        <Text className="font-display text-3xl text-ox-2">{title}</Text>

        {body ? <Text className="font-body text-lg text-ink-soft mt-4">{body}</Text> : null}

        {actionLabel && onAction ? (
          <Pressable
            accessibilityRole="button"
            onPress={onAction}
            className="mt-8 bg-ox-2 px-6 py-4 active:bg-ox-1"
          >
            <Text className="font-mono text-sm tracking-widest text-paper uppercase text-center">
              {actionLabel}
            </Text>
          </Pressable>
        ) : null}

        {dismissLabel && onDismiss ? (
          <Pressable accessibilityRole="button" onPress={onDismiss} className="mt-4 px-6 py-3">
            <Text className="font-mono text-xs tracking-widest text-ox-3 uppercase text-center">
              {dismissLabel}
            </Text>
          </Pressable>
        ) : null}
      </View>
    </SafeAreaView>
  );
}

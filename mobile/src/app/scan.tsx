import { useState } from "react";
import { View, Text, Pressable } from "react-native";
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

  if (!permission?.granted) {
    return (
      <SafeAreaView className="flex-1 bg-paper">
        <View className="flex-1 px-6 justify-center">
          <Text className="font-body text-lg text-ink">{t("table.scanning")}</Text>
          <Pressable
            accessibilityRole="button"
            onPress={requestPermission}
            className="mt-8 bg-ox-2 px-6 py-4"
          >
            <Text className="font-mono text-sm tracking-widest text-paper uppercase text-center">
              {t("home.scan")}
            </Text>
          </Pressable>
        </View>
      </SafeAreaView>
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
      <SafeAreaView className="absolute inset-x-0 bottom-0">
        <Text className="font-mono text-xs tracking-widest text-on-deep uppercase text-center pb-8">
          {t("table.scanning")}
        </Text>
      </SafeAreaView>
    </View>
  );
}

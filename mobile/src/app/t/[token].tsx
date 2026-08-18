import { View, Text } from "react-native";
import { useLocalSearchParams } from "expo-router";
import { useTranslation } from "react-i18next";
import { SafeAreaView } from "react-native-safe-area-context";

/**
 * The universal-link landing screen.
 *
 * This path deliberately mirrors the Rails route exactly —
 * `get "t/:table_token", to: "menus#show"` — because the QR encodes a plain
 * https://aperto.wine/t/TOKEN URL and iOS/Android hand that same path to us
 * when the app is installed. Renaming this route without re-issuing the
 * apple-app-site-association (and shipping an App Store update, since iOS
 * caches the AASA at install time) breaks every printed table tent silently.
 */
export default function TableScreen() {
  const { token } = useLocalSearchParams<{ token: string }>();
  const { t } = useTranslation();

  return (
    <SafeAreaView className="flex-1 bg-paper">
      <View className="flex-1 px-6 justify-center">
        <Text className="font-mono text-xs tracking-widest text-ox-3 uppercase">
          {t("table.title")}
        </Text>
        <Text className="font-display text-4xl text-ox-2 mt-4">
          {t("table.openingList")}
        </Text>
        <Text className="font-mono text-sm text-quiet mt-6" accessibilityLabel="table token">
          {token}
        </Text>
      </View>
    </SafeAreaView>
  );
}

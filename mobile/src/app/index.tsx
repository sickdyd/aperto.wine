import { View, Text, Pressable } from "react-native";
import { useRouter } from "expo-router";
import { useTranslation } from "react-i18next";
import { SafeAreaView } from "react-native-safe-area-context";

import { Rule } from "@/components/rule";

export default function HomeScreen() {
  const { t } = useTranslation();
  const router = useRouter();

  return (
    <SafeAreaView className="flex-1 bg-paper">
      <View className="flex-1 px-6 justify-center">
        <Text className="font-mono text-xs tracking-widest text-ox-3 uppercase">
          {t("common.appName")}
        </Text>

        <Rule weight="heavy" className="mt-3" />

        <Text className="font-display text-5xl text-ox-2 mt-8 leading-tight">
          {t("home.title")}
        </Text>

        <Text className="font-body text-lg text-ink-soft mt-4">
          {t("home.subtitle")}
        </Text>

        <Pressable
          accessibilityRole="button"
          onPress={() => router.push("/scan")}
          className="mt-10 bg-ox-2 px-6 py-4 active:bg-ox-1"
        >
          <Text className="font-mono text-sm tracking-widest text-paper uppercase text-center">
            {t("home.scan")}
          </Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

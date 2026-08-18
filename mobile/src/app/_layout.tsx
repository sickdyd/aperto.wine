import "../../global.css";

import { useEffect } from "react";
import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { StatusBar } from "expo-status-bar";
import { QueryClient } from "@tanstack/react-query";
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useFonts } from "expo-font";
import { InstrumentSerif_400Regular } from "@expo-google-fonts/instrument-serif";
import { EBGaramond_400Regular, EBGaramond_500Medium } from "@expo-google-fonts/eb-garamond";
import { JetBrainsMono_400Regular } from "@expo-google-fonts/jetbrains-mono";

import "@/i18n";
import { useAuthStore } from "@/stores/auth-store";

SplashScreen.preventAutoHideAsync();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // A restaurant's wine list changes across a service, not across a
      // scroll. Five minutes keeps a re-entered screen instant without
      // showing yesterday's list.
      staleTime: 5 * 60 * 1000,
      retry: 2,
    },
  },
});

// Restaurant wifi is unreliable and a diner who has already loaded a list
// should keep seeing it through a dead spot. The cache is plain AsyncStorage,
// never SecureStore — it holds menus, not credentials.
const persister = createAsyncStoragePersister({ storage: AsyncStorage });

export default function RootLayout() {
  const hydrate = useAuthStore((s) => s.hydrate);
  const hydrated = useAuthStore((s) => s.hydrated);

  const [fontsLoaded, fontError] = useFonts({
    InstrumentSerif_400Regular,
    EBGaramond_400Regular,
    EBGaramond_500Medium,
    JetBrainsMono_400Regular,
  });

  useEffect(() => {
    hydrate();
  }, [hydrate]);

  useEffect(() => {
    // fontError still hides the splash: falling back to system serif is far
    // better than holding a user on the splash screen forever because a
    // typeface failed to decode.
    if ((fontsLoaded || fontError) && hydrated) SplashScreen.hideAsync();
  }, [fontsLoaded, fontError, hydrated]);

  if (!fontsLoaded && !fontError) return null;

  return (
    <PersistQueryClientProvider client={queryClient} persistOptions={{ persister }}>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: "#F6F2E9" },
        }}
      />
    </PersistQueryClientProvider>
  );
}

import { View } from "react-native";

/**
 * Rules replace boxes — the ledger's core structural device. Three weights,
 * matching the web's `--color-rule-*` tokens: hairline divides rows, medium
 * divides subsections, heavy breaks sections.
 */
export type RuleWeight = "hair" | "medium" | "heavy";

const WEIGHTS: Record<RuleWeight, string> = {
  hair: "h-px bg-ox-4",
  medium: "h-[2px] bg-ox-3",
  heavy: "h-[3px] bg-ox-1",
};

export function Rule({
  weight = "hair",
  className = "",
}: {
  weight?: RuleWeight;
  className?: string;
}) {
  return <View accessibilityRole="none" className={`${WEIGHTS[weight]} ${className}`} />;
}

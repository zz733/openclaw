import type { ModelDefinitionConfig } from "openclaw/plugin-sdk/provider-model-shared";

export const DEEPSEEK_BASE_URL = "https://api.deepseek.com";

// DeepSeek V3.2 API pricing (per 1M tokens)
// https://api-docs.deepseek.com/quick_start/pricing
const DEEPSEEK_V3_2_COST = {
  input: 0.28,
  output: 0.42,
  cacheRead: 0.028,
  cacheWrite: 0,
};

// DeepSeek V4 Flash pricing (per 1M tokens)
const DEEPSEEK_V4_FLASH_COST = {
  input: 0.14,
  output: 0.28,
  cacheRead: 0.028,
  cacheWrite: 0,
};

export const DEEPSEEK_MODEL_CATALOG: ModelDefinitionConfig[] = [
  {
    id: "deepseek-v4-flash",
    name: "DeepSeek V4 Flash",
    reasoning: true,
    input: ["text"],
    contextWindow: 1000000,
    maxTokens: 384000,
    cost: DEEPSEEK_V4_FLASH_COST,
    compat: {
      supportsUsageInStreaming: true,
      supportsReasoningEffort: true,
      maxTokensField: "max_tokens",
    },
  },
  {
    id: "deepseek-chat",
    name: "DeepSeek Chat",
    reasoning: false,
    input: ["text"],
    contextWindow: 131072,
    maxTokens: 8192,
    cost: DEEPSEEK_V3_2_COST,
    compat: {
      supportsUsageInStreaming: true,
      maxTokensField: "max_tokens",
    },
  },
  {
    id: "deepseek-reasoner",
    name: "DeepSeek Reasoner",
    reasoning: true,
    input: ["text"],
    contextWindow: 131072,
    maxTokens: 65536,
    cost: DEEPSEEK_V3_2_COST,
    compat: {
      supportsUsageInStreaming: true,
      supportsReasoningEffort: false,
      maxTokensField: "max_tokens",
    },
  },
];

export function buildDeepSeekModelDefinition(
  model: (typeof DEEPSEEK_MODEL_CATALOG)[number],
): ModelDefinitionConfig {
  return {
    ...model,
    api: "openai-completions",
  };
}

const DEEPSEEK_V4_MODEL_IDS = new Set(["deepseek-v4-flash"]);

export function isDeepSeekV4ModelId(modelId: string): boolean {
  return DEEPSEEK_V4_MODEL_IDS.has(modelId.toLowerCase());
}

export function isDeepSeekV4ModelRef(model: { provider?: string; id?: unknown }): boolean {
  return (
    model.provider === "deepseek" && typeof model.id === "string" && isDeepSeekV4ModelId(model.id)
  );
}

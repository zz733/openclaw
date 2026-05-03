import type { StreamFn } from "@mariozechner/pi-agent-core";
import { streamSimple } from "@mariozechner/pi-ai";
import { streamWithPayloadPatch } from "../agents/pi-embedded-runner/stream-payload-utils.js";
import type { ProviderWrapStreamFnContext } from "./plugin-entry.js";

export type ProviderStreamWrapperFactory =
  | ((streamFn: StreamFn | undefined) => StreamFn | undefined)
  | null
  | undefined
  | false;

export function composeProviderStreamWrappers(
  baseStreamFn: StreamFn | undefined,
  ...wrappers: ProviderStreamWrapperFactory[]
): StreamFn | undefined {
  return wrappers.reduce(
    (streamFn, wrapper) => (wrapper ? wrapper(streamFn) : streamFn),
    baseStreamFn,
  );
}

const HTML_ENTITY_RE = /&(?:amp|lt|gt|quot|apos|#39|#x[0-9a-f]+|#\d+);/i;

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(Number.parseInt(hex, 16)))
    .replace(/&#(\d+);/gi, (_, dec) => String.fromCodePoint(Number.parseInt(dec, 10)));
}

export function decodeHtmlEntitiesInObject(value: unknown): unknown {
  if (typeof value === "string") {
    return HTML_ENTITY_RE.test(value) ? decodeHtmlEntities(value) : value;
  }
  if (Array.isArray(value)) {
    return value.map(decodeHtmlEntitiesInObject);
  }
  if (value && typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      result[key] = decodeHtmlEntitiesInObject(entry);
    }
    return result;
  }
  return value;
}

function decodeToolCallArgumentsHtmlEntitiesInMessage(message: unknown): void {
  if (!message || typeof message !== "object") {
    return;
  }
  const content = (message as { content?: unknown }).content;
  if (!Array.isArray(content)) {
    return;
  }
  for (const block of content) {
    if (!block || typeof block !== "object") {
      continue;
    }
    const typedBlock = block as { type?: unknown; arguments?: unknown };
    if (typedBlock.type !== "toolCall" || !typedBlock.arguments) {
      continue;
    }
    if (typeof typedBlock.arguments === "object") {
      typedBlock.arguments = decodeHtmlEntitiesInObject(typedBlock.arguments);
    }
  }
}

function wrapStreamDecodeToolCallArgumentHtmlEntities(
  stream: ReturnType<typeof streamSimple>,
): ReturnType<typeof streamSimple> {
  const originalResult = stream.result.bind(stream);
  stream.result = async () => {
    const message = await originalResult();
    decodeToolCallArgumentsHtmlEntitiesInMessage(message);
    return message;
  };

  const originalAsyncIterator = stream[Symbol.asyncIterator].bind(stream);
  (stream as { [Symbol.asyncIterator]: typeof originalAsyncIterator })[Symbol.asyncIterator] =
    function () {
      const iterator = originalAsyncIterator();
      return {
        async next() {
          const result = await iterator.next();
          if (!result.done && result.value && typeof result.value === "object") {
            const event = result.value as { partial?: unknown; message?: unknown };
            decodeToolCallArgumentsHtmlEntitiesInMessage(event.partial);
            decodeToolCallArgumentsHtmlEntitiesInMessage(event.message);
          }
          return result;
        },
        async return(value?: unknown) {
          return iterator.return?.(value) ?? { done: true as const, value: undefined };
        },
        async throw(error?: unknown) {
          return iterator.throw?.(error) ?? { done: true as const, value: undefined };
        },
      };
    };
  return stream;
}

export function createHtmlEntityToolCallArgumentDecodingWrapper(
  baseStreamFn: StreamFn | undefined,
): StreamFn {
  const underlying = baseStreamFn ?? streamSimple;
  return (model, context, options) => {
    const maybeStream = underlying(model, context, options);
    if (maybeStream && typeof maybeStream === "object" && "then" in maybeStream) {
      return Promise.resolve(maybeStream).then((stream) =>
        wrapStreamDecodeToolCallArgumentHtmlEntities(stream),
      );
    }
    return wrapStreamDecodeToolCallArgumentHtmlEntities(maybeStream);
  };
}

export {
  applyAnthropicPayloadPolicyToParams,
  resolveAnthropicPayloadPolicy,
} from "../agents/anthropic-payload-policy.js";
export {
  buildCopilotDynamicHeaders,
  hasCopilotVisionInput,
} from "../agents/copilot-dynamic-headers.js";
export { applyAnthropicEphemeralCacheControlMarkers } from "../agents/pi-embedded-runner/anthropic-cache-control-payload.js";
export {
  createBedrockNoCacheWrapper,
  isAnthropicBedrockModel,
} from "../agents/pi-embedded-runner/bedrock-stream-wrappers.js";
export {
  createMoonshotThinkingWrapper,
  resolveMoonshotThinkingType,
} from "../agents/pi-embedded-runner/moonshot-thinking-stream-wrappers.js";
export { streamWithPayloadPatch } from "../agents/pi-embedded-runner/stream-payload-utils.js";
export {
  createToolStreamWrapper,
  createZaiToolStreamWrapper,
} from "../agents/pi-embedded-runner/zai-stream-wrappers.js";

// ─── DeepSeek V4 Thinking Support ────────────────────────────────────────────

export type DeepSeekV4ThinkingLevel = ProviderWrapStreamFnContext["thinkingLevel"];

function isDisabledDeepSeekV4ThinkingLevel(thinkingLevel: DeepSeekV4ThinkingLevel): boolean {
  const normalized = typeof thinkingLevel === "string" ? thinkingLevel.toLowerCase() : "";
  return normalized === "off" || normalized === "none";
}

function resolveDeepSeekV4ReasoningEffort(thinkingLevel: DeepSeekV4ThinkingLevel): "high" {
  void thinkingLevel; // v4.11 has no "max" level, always use "high"
  return "high";
}

function stripDeepSeekV4ReasoningContent(payload: Record<string, unknown>): void {
  if (!Array.isArray(payload.messages)) {
    return;
  }
  for (const message of payload.messages) {
    if (!message || typeof message !== "object") {
      continue;
    }
    delete (message as Record<string, unknown>).reasoning_content;
  }
}

function ensureDeepSeekV4AssistantReasoningContent(payload: Record<string, unknown>): void {
  if (!Array.isArray(payload.messages)) {
    return;
  }
  for (const message of payload.messages) {
    if (!message || typeof message !== "object") {
      continue;
    }
    const record = message as Record<string, unknown>;
    if (record.role !== "assistant") {
      continue;
    }
    if (!("reasoning_content" in record)) {
      record.reasoning_content = "";
    }
  }
}

export function createDeepSeekV4OpenAICompatibleThinkingWrapper(params: {
  baseStreamFn: StreamFn | undefined;
  thinkingLevel: DeepSeekV4ThinkingLevel;
  shouldPatchModel: (model: Parameters<StreamFn>[0]) => boolean;
}): StreamFn | undefined {
  if (!params.baseStreamFn) {
    return undefined;
  }
  const underlying = params.baseStreamFn;
  return (model, context, options) => {
    if (!params.shouldPatchModel(model)) {
      return underlying(model, context, options);
    }

    return streamWithPayloadPatch(underlying, model, context, options, (payload) => {
      if (isDisabledDeepSeekV4ThinkingLevel(params.thinkingLevel)) {
        payload.thinking = { type: "disabled" };
        delete payload.reasoning_effort;
        delete payload.reasoning;
        stripDeepSeekV4ReasoningContent(payload);
        return;
      }

      payload.thinking = { type: "enabled" };
      payload.reasoning_effort = resolveDeepSeekV4ReasoningEffort(params.thinkingLevel);
      ensureDeepSeekV4AssistantReasoningContent(payload);
    });
  };
}

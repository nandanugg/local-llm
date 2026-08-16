MODEL := $(QWEN38_27B_Q4_MTP_GGUF)
MODEL_ALIAS := unsloth/Qwen3.8-27B

# CTX_SIZE := 262144 # full ctx
# OUTPUT_TOKENS := 32768 # full ouput
# Context window: maximum total number of tokens the model can keep in its active context.
# This includes the prompt/history AND newly generated tokens.
#
# Higher = allows longer conversations/files and more history to remain available,
#          but uses more KV-cache VRAM and can make generation slower at long context.
# Lower  = uses less VRAM and generally keeps long-context generation faster,
#          but older/input tokens must be truncated sooner.
#
# Example with CTX_SIZE=131072 and OUTPUT_TOKENS=16384:
#   roughly up to ~114688 tokens can be input/history if the full 16384-token
#   generation budget needs to remain available.
#
# Note: actual usable input is slightly lower because system prompts,
# chat templates, special tokens, etc. also consume context.
CTX_SIZE := 131072

# Maximum number of new tokens the model is allowed to generate for one request.
# This is only a limit; the model may stop earlier when it reaches EOS/end-of-answer.
#
# Higher = allows longer answers/reasoning, but gives the model permission to spend
#          more time generating and requires enough remaining context capacity.
# Lower  = caps responses sooner, finishes earlier, and reserves less context for output.
#
# OUTPUT_TOKENS does not pre-allocate all of those tokens in advance;
# it simply sets the maximum generation budget.
OUTPUT_TOKENS := 16384

# Unsloth-recommended thinking-mode sampling
TEMPERATURE := 1.0
TOP_P := 0.95
TOP_K := 20
MIN_P := 0.0
PRESENCE_PENALTY := 0.0
REPEAT_PENALTY := 1.0

# Force full model offload. If this OOMs, change back to auto.
GPU_LAYERS := all

# Prompt ingestion: maximum number of input tokens handled as one logical batch.
# Higher = can improve prompt/prefill throughput, but uses more memory and has diminishing returns.
# Lower  = uses less memory, but may make prompt processing slower due to more batching iterations.
# Mostly affects prompt/prefill speed, not single-stream generation TPS.
BATCH_SIZE := 2048

# Physical compute batch: maximum number of tokens actually processed together by the backend/GPU.
# A logical BATCH_SIZE may be split into multiple UBATCH_SIZE-sized compute chunks.
#
# Example: BATCH_SIZE=2048, UBATCH_SIZE=512
#   logical batch: [2048 tokens]
#   compute chunks: [512] [512] [512] [512]
#
# Higher = larger GPU compute chunks, potentially faster prefill/better GPU utilization,
#          but requires more VRAM and may OOM if set too high.
# Lower  = smaller compute chunks and lower VRAM usage, but potentially slower prefill
#          because the same logical batch requires more physical compute chunks.
# Mostly affects prompt/prefill speed; usually has little effect on single-stream generation TPS.
UBATCH_SIZE := 512

# KV cache stores attention information for tokens already processed,
# so the model does not need to recompute the entire context for every new token.
# The KV cache grows as context length grows, so it can consume a lot of VRAM
# at large context sizes such as 128K+.
#
# K = "Key" cache used by attention to determine which previous tokens are relevant.
# V = "Value" cache containing the information retrieved from those previous tokens.
#
# Lower precision (q4_0):
#   + Much lower KV-cache VRAM usage
#   + Allows much longer context to fit in VRAM
#   - Some precision/quality loss
#   - Not necessarily faster; performance depends on model/backend/kernel support
#
# Higher precision (q8_0 / f16):
#   + More accurate KV representation
#   + Potentially better quality, especially at long context
#   - Uses substantially more VRAM
#   - May reduce the maximum context that fits on the GPU
#
# llama.cpp default is f16; q4_0 is chosen here primarily to save VRAM
# so a large context can fit on the 24 GB RTX 3090.
CACHE_TYPE_K := q4_0
CACHE_TYPE_V := q4_0

CACHE_RAM := 29696

# MTP speculative decoding: predicts multiple future tokens with a cheap MTP head,
# then the main model verifies those predictions together.
# Works especially well when output is predictable, e.g. code refactoring,
# unchanged/repeated code, boilerplate, structured text, etc.
#
# Maximum number of future tokens MTP is allowed to draft before verification.
# Higher = potentially more generation speed when predictions are accurate,
#          but more wasted computation when drafts are rejected.
# Lower  = less speculative work and less waste, but smaller possible speedup.
# Best value depends on model/workload; benchmark actual generation TPS.
MTP_DRAFT_TOKENS := 16

# Minimum draft-token probability/confidence required to continue drafting.
# Higher = more conservative: stops drafting earlier, usually higher acceptance rate,
#          but may miss opportunities for longer speculative runs.
# Lower  = more aggressive: drafts further even when less confident,
#          potentially more speed if accepted, but more rejected/wasted draft tokens.
#
# With n-max=16 and p-min=0.8, MTP can draft far ahead when highly confident,
# while stopping early when the prediction becomes uncertain.
MTP_DRAFT_P_MIN := 0.8

# Thinking + coding focused: reasoning stays on, xhigh effort, kept across turns
REASONING := on
REASONING_EFFORT := xhigh
PRESERVE_THINKING := true

REQUIRED_FLAGS := \
	--spec-type \
	--spec-draft-n-max \
	--spec-draft-p-min \
	--spec-draft-type-k \
	--spec-draft-type-v \
	--chat-template-kwargs \
	--cache-type-k \
	--cache-ram

PROFILE_ARGS := \
	--ctx-size "$(CTX_SIZE)" \
	--n-predict "$(OUTPUT_TOKENS)" \
	--batch-size "$(BATCH_SIZE)" \
	--ubatch-size "$(UBATCH_SIZE)" \
	--gpu-layers "$(GPU_LAYERS)" \
	--temp "$(TEMPERATURE)" \
	--top-p "$(TOP_P)" \
	--top-k "$(TOP_K)" \
	--min-p "$(MIN_P)" \
	--presence-penalty "$(PRESENCE_PENALTY)" \
	--repeat-penalty "$(REPEAT_PENALTY)" \
	--flash-attn on \
	--cache-type-k "$(CACHE_TYPE_K)" \
	--cache-type-v "$(CACHE_TYPE_V)" \
	--spec-type draft-mtp \
	--spec-draft-n-max "$(MTP_DRAFT_TOKENS)" \
	--spec-draft-p-min "$(MTP_DRAFT_P_MIN)" \
	--spec-draft-type-k q4_0 \
	--spec-draft-type-v q4_0 \
	--parallel 1 \
	--no-mmproj \
	--chat-template-kwargs '{"preserve_thinking":$(PRESERVE_THINKING),"reasoning_effort":"$(REASONING_EFFORT)"}' \
	--jinja \
	--kv-unified \
	--cache-ram "$(CACHE_RAM)" \
	--cache-idle-slots \
	--reasoning $(REASONING)

MODEL := $(QWEN38_27B_Q4_MTP_GGUF)
MODEL_ALIAS := unsloth/Qwen3.8-27B

# CTX_SIZE := 262144 # full ctx
# OUTPUT_TOKENS := 32768 # full ouput
CTX_SIZE := 131072
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
# GPU_LAYERS := auto

# Prompt ingestion
BATCH_SIZE := 2048
UBATCH_SIZE := 512
# BATCH_SIZE := 4096
# UBATCH_SIZE := 1024

# KV Settings
CACHE_TYPE_K := q4_0
CACHE_TYPE_V := q4_0
# CACHE_TYPE_K := q8_0
# CACHE_TYPE_V := q8_0

CACHE_RAM := 29696

# MTP Settings
MTP_DRAFT_TOKENS := 16
MTP_DRAFT_P_MIN := 0.8

# Thinking + coding focused: reasoning stays on, high effort, kept across turns
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

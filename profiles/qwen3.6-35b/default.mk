MODEL := $(HOME)/Downloads/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
MODEL_ALIAS := unsloth/Qwen3.6-35B-A3B

CTX_SIZE := 262144
OUTPUT_TOKENS := 32768
TEMPERATURE := 1.0
TOP_P := 0.95
TOP_K := 20
MIN_P := 0.0
PRESENCE_PENALTY := 0.0
REPEAT_PENALTY := 1.0
GPU_LAYERS := auto
BATCH_SIZE := 2048
UBATCH_SIZE := 512

CACHE_TYPE_K := bf16
CACHE_TYPE_V := bf16
PRESERVE_THINKING := true
MTP_DRAFT_TOKENS := 2
REQUIRED_FLAGS := --spec-type --spec-draft-n-max --chat-template-kwargs --cache-type-k

PROFILE_ARGS := \
	--flash-attn auto \
	--cache-type-k "$(CACHE_TYPE_K)" \
	--cache-type-v "$(CACHE_TYPE_V)" \
	--spec-type draft-mtp \
	--spec-draft-n-max "$(MTP_DRAFT_TOKENS)" \
	--chat-template-kwargs '{"preserve_thinking":$(PRESERVE_THINKING)}'

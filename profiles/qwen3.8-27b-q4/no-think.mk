MODEL := $(QWEN38_27B_Q4_MTP_GGUF)
MODEL_ALIAS := unsloth/Qwen3.8-27B

CTX_SIZE := 262144
OUTPUT_TOKENS := 32768
TEMPERATURE := 0.7
TOP_P := 0.8
TOP_K := 20
MIN_P := 0.0
PRESENCE_PENALTY := 1.5
REPEAT_PENALTY := 1.0
GPU_LAYERS := auto
BATCH_SIZE := 2048
UBATCH_SIZE := 512

CACHE_TYPE_K := bf16
CACHE_TYPE_V := bf16
MTP_DRAFT_TOKENS := 2
REQUIRED_FLAGS := --spec-type --spec-draft-n-max --chat-template-kwargs --cache-type-k

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
	--flash-attn auto \
	--cache-type-k "$(CACHE_TYPE_K)" \
	--cache-type-v "$(CACHE_TYPE_V)" \
	--spec-type draft-mtp \
	--spec-draft-n-max "$(MTP_DRAFT_TOKENS)" \
	--chat-template-kwargs '{"enable_thinking":false}'

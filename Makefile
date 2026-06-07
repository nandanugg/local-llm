SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

MODEL ?= $(HOME)/Downloads/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
MODEL_ALIAS ?= unsloth/Qwen3.6-35B-A3B

LLAMA_REPO ?= https://github.com/ggml-org/llama.cpp.git
LLAMA_REF ?= master
LLAMA_DIR ?= $(CURDIR)/.llama.cpp

BACKEND ?= auto
ifeq ($(BACKEND),auto)
  ifneq ($(shell command -v nvcc 2>/dev/null),)
    RESOLVED_BACKEND := cuda
  else ifneq ($(wildcard /usr/include/vulkan/vulkan.h),)
    RESOLVED_BACKEND := vulkan
  else
    RESOLVED_BACKEND := cpu
  endif
else
  RESOLVED_BACKEND := $(BACKEND)
endif

BUILD_DIR ?= $(LLAMA_DIR)/build-$(RESOLVED_BACKEND)
JOBS ?= $(shell nproc)
THREADS ?= $(shell lscpu -p=CORE 2>/dev/null | sed '/^\#/d' | sort -u | wc -l)

SYSTEM_LLAMA_CLI := $(shell command -v llama-cli 2>/dev/null || true)
SYSTEM_LLAMA_SERVER := $(shell command -v llama-server 2>/dev/null || true)
LLAMA_CLI ?= $(if $(SYSTEM_LLAMA_CLI),$(SYSTEM_LLAMA_CLI),$(BUILD_DIR)/bin/llama-cli)
LLAMA_SERVER ?= $(if $(SYSTEM_LLAMA_SERVER),$(SYSTEM_LLAMA_SERVER),$(BUILD_DIR)/bin/llama-server)

CTX_SIZE ?= 262144
OUTPUT_TOKENS ?= 32768
TEMPERATURE ?= 1.0
TOP_P ?= 0.95
TOP_K ?= 20
MIN_P ?= 0.0
PRESENCE_PENALTY ?= 0.0
REPEAT_PENALTY ?= 1.0
CACHE_TYPE_K ?= bf16
CACHE_TYPE_V ?= bf16
GPU_LAYERS ?= auto
PRESERVE_THINKING ?= true
MTP_DRAFT_TOKENS ?= 2
BATCH_SIZE ?= 2048
UBATCH_SIZE ?= 512

HOST ?= 127.0.0.1
PORT ?= 8001
PARALLEL ?= 1
EXTRA_ARGS ?=

COMMON_ARGS = \
	--model "$(MODEL)" \
	--ctx-size "$(CTX_SIZE)" \
	--n-predict "$(OUTPUT_TOKENS)" \
	--batch-size "$(BATCH_SIZE)" \
	--ubatch-size "$(UBATCH_SIZE)" \
	--threads "$(THREADS)" \
	--gpu-layers "$(GPU_LAYERS)" \
	--flash-attn auto \
	--cache-type-k "$(CACHE_TYPE_K)" \
	--cache-type-v "$(CACHE_TYPE_V)" \
	--temp "$(TEMPERATURE)" \
	--top-p "$(TOP_P)" \
	--top-k "$(TOP_K)" \
	--min-p "$(MIN_P)" \
	--presence-penalty "$(PRESENCE_PENALTY)" \
	--repeat-penalty "$(REPEAT_PENALTY)" \
	--spec-type draft-mtp \
	--spec-draft-n-max "$(MTP_DRAFT_TOKENS)" \
	--chat-template-kwargs '{"preserve_thinking":$(PRESERVE_THINKING)}'

ifeq ($(RESOLVED_BACKEND),cuda)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=ON -DGGML_VULKAN=OFF
else ifeq ($(RESOLVED_BACKEND),vulkan)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=OFF -DGGML_VULKAN=ON
else ifeq ($(RESOLVED_BACKEND),cpu)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=OFF -DGGML_VULKAN=OFF
else
  $(error BACKEND must be auto, cuda, vulkan, or cpu)
endif

.PHONY: help setup run run-code run-no-think server server-code server-no-think server-codex
.PHONY: build update clean-build check check-model check-cli check-server
.PHONY: ensure-cli ensure-server print-config

help:
	@printf '%s\n' \
		'Qwen3.6 llama.cpp runner' \
		'' \
		'  make run              Interactive thinking mode for general tasks (temp 1.0)' \
		'  make run-code         Interactive thinking mode for precise coding (temp 0.6)' \
		'  make run-no-think     Interactive non-thinking mode' \
		'  make server           API server on http://$(HOST):$(PORT)' \
		'  make server-code      API server with coding temperature (0.6)' \
		'  make server-no-think  API server with thinking disabled' \
		'  make server-codex     API server tuned for Codex agent workloads' \
		'  make setup            Install CUDA build dependencies and expose nvcc' \
		'  make build            Build llama-cli and llama-server locally' \
		'  make check            Validate the model, binary, and required flags' \
		'  make print-config     Show the effective configuration' \
		'' \
		'Useful overrides:' \
		'  MODEL=/path/model.gguf  CTX_SIZE=32768  OUTPUT_TOKENS=4096' \
		'  CACHE_TYPE_K=f16 CACHE_TYPE_V=f16  GPU_LAYERS=auto' \
		'  BACKEND=cpu|cuda|vulkan  EXTRA_ARGS="..."'

setup:
	@pm=''; \
	packages=''; \
	if command -v pacman >/dev/null 2>&1; then \
		pm='pacman'; \
		packages='base-devel cmake git ripgrep cuda'; \
		printf 'Installing build dependencies with pacman...\n'; \
		sudo pacman -S --needed $$packages; \
	elif command -v apt-get >/dev/null 2>&1; then \
		pm='apt-get'; \
		packages='build-essential cmake git ripgrep nvidia-cuda-toolkit'; \
		printf 'Installing build dependencies with apt-get...\n'; \
		sudo apt-get update; \
		sudo apt-get install -y $$packages; \
	elif command -v dnf >/dev/null 2>&1; then \
		pm='dnf'; \
		packages='gcc gcc-c++ make cmake git ripgrep cuda-toolkit'; \
		printf 'Installing build dependencies with dnf...\n'; \
		sudo dnf install -y $$packages; \
	elif command -v zypper >/dev/null 2>&1; then \
		pm='zypper'; \
		packages='gcc gcc-c++ make cmake git ripgrep cuda-toolkit'; \
		printf 'Installing build dependencies with zypper...\n'; \
		sudo zypper install -y $$packages; \
	else \
		printf 'Unsupported package manager. Install these manually: C++ build tools, cmake, git, ripgrep, CUDA toolkit.\n' >&2; \
		exit 1; \
	fi; \
	case "$${SHELL##*/}" in \
		fish) \
			config="$$HOME/.config/fish/config.fish"; \
			mkdir -p "$$(dirname "$$config")"; \
			if ! grep -qsF '/opt/cuda/bin' "$$config"; then \
				printf '\n# Added by local-llm setup: CUDA compiler\nfish_add_path /opt/cuda/bin\n' >> "$$config"; \
			fi; \
			;; \
		zsh) \
			config="$$HOME/.zshrc"; \
			if ! grep -qsF '/opt/cuda/bin' "$$config"; then \
				printf '\n# Added by local-llm setup: CUDA compiler\nexport PATH="/opt/cuda/bin:$$PATH"\n' >> "$$config"; \
			fi; \
			;; \
		bash) \
			config="$$HOME/.bashrc"; \
			if ! grep -qsF '/opt/cuda/bin' "$$config"; then \
				printf '\n# Added by local-llm setup: CUDA compiler\nexport PATH="/opt/cuda/bin:$$PATH"\n' >> "$$config"; \
			fi; \
			;; \
		*) \
			config="$$HOME/.profile"; \
			if ! grep -qsF '/opt/cuda/bin' "$$config"; then \
				printf '\n# Added by local-llm setup: CUDA compiler\nexport PATH="/opt/cuda/bin:$$PATH"\n' >> "$$config"; \
			fi; \
			;; \
	esac; \
	printf 'Installed packages with %s and updated %s.\n' "$$pm" "$$config"; \
	export PATH="/opt/cuda/bin:$$PATH"; \
	if ! command -v nvcc >/dev/null 2>&1; then \
		printf 'nvcc is still not available. Open a new shell or verify that the CUDA toolkit installed correctly.\n' >&2; \
		exit 1; \
	fi; \
	nvcc --version

run: check-cli check-model
	@exec "$(LLAMA_CLI)" $(COMMON_ARGS) --conversation --multiline-input $(EXTRA_ARGS)

run-code:
	@$(MAKE) --no-print-directory run TEMPERATURE=0.6

run-no-think:
	@$(MAKE) --no-print-directory run PRESERVE_THINKING=false EXTRA_ARGS='--reasoning off $(EXTRA_ARGS)'

server: check-server check-model
	@exec "$(LLAMA_SERVER)" $(COMMON_ARGS) \
		--alias "$(MODEL_ALIAS)" \
		--host "$(HOST)" \
		--port "$(PORT)" \
		--parallel "$(PARALLEL)" \
		$(EXTRA_ARGS)

server-code:
	@$(MAKE) --no-print-directory server TEMPERATURE=0.6

server-no-think:
	@$(MAKE) --no-print-directory server PRESERVE_THINKING=false EXTRA_ARGS='--reasoning off $(EXTRA_ARGS)'

server-codex:
	@$(MAKE) --no-print-directory server \
		TEMPERATURE=0.6 \
		CACHE_TYPE_K=q8_0 \
		CACHE_TYPE_V=q8_0 \
		BATCH_SIZE=4096 \
		UBATCH_SIZE=1024 \
		PRESERVE_THINKING=false \
		EXTRA_ARGS='--jinja --kv-unified --reasoning off $(EXTRA_ARGS)'

ensure-cli:
	@if [[ ! -x "$(LLAMA_CLI)" ]]; then \
		$(MAKE) --no-print-directory build; \
	fi

ensure-server:
	@if [[ ! -x "$(LLAMA_SERVER)" ]]; then \
		$(MAKE) --no-print-directory build; \
	fi

check: check-cli check-server check-model
	@printf 'Configuration is valid.\n'

check-model:
	@test -f "$(MODEL)" || { \
		printf 'Model not found: %s\nOverride it with: make run MODEL=/path/to/model.gguf\n' "$(MODEL)" >&2; \
		exit 1; \
	}

check-cli: ensure-cli
	@help_output="$$("$(LLAMA_CLI)" --help 2>&1)"; \
	for flag in --spec-type --spec-draft-n-max --chat-template-kwargs --cache-type-k; do \
		rg -q --fixed-strings -- "$$flag" <<<"$$help_output" || { \
			printf '%s is too old; missing required option %s\n' "$(LLAMA_CLI)" "$$flag" >&2; \
			exit 1; \
		}; \
	done

check-server: ensure-server
	@help_output="$$("$(LLAMA_SERVER)" --help 2>&1)"; \
	for flag in --spec-type --spec-draft-n-max --chat-template-kwargs --cache-type-k; do \
		rg -q --fixed-strings -- "$$flag" <<<"$$help_output" || { \
			printf '%s is too old; missing required option %s\n' "$(LLAMA_SERVER)" "$$flag" >&2; \
			exit 1; \
		}; \
	done

build: $(BUILD_DIR)/CMakeCache.txt
	@cmake --build "$(BUILD_DIR)" --config Release -j "$(JOBS)" \
		--target llama-cli llama-server

$(LLAMA_DIR)/.git:
	@git clone --depth 1 --branch "$(LLAMA_REF)" "$(LLAMA_REPO)" "$(LLAMA_DIR)"

$(BUILD_DIR)/CMakeCache.txt: $(LLAMA_DIR)/.git
	@cmake -S "$(LLAMA_DIR)" -B "$(BUILD_DIR)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		-DLLAMA_CURL=OFF \
		$(CMAKE_BACKEND_ARGS)

update: $(LLAMA_DIR)/.git
	@git -C "$(LLAMA_DIR)" pull --ff-only
	@cmake -S "$(LLAMA_DIR)" -B "$(BUILD_DIR)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		-DLLAMA_CURL=OFF \
		$(CMAKE_BACKEND_ARGS)
	@$(MAKE) --no-print-directory build

clean-build:
	@cmake -E remove_directory "$(BUILD_DIR)"

print-config:
	@printf '%-20s %s\n' \
		'MODEL' "$(MODEL)" \
		'LLAMA_CLI' "$(LLAMA_CLI)" \
		'LLAMA_SERVER' "$(LLAMA_SERVER)" \
		'BACKEND' "$(RESOLVED_BACKEND)" \
		'CTX_SIZE' "$(CTX_SIZE)" \
		'OUTPUT_TOKENS' "$(OUTPUT_TOKENS)" \
		'TEMPERATURE' "$(TEMPERATURE)" \
		'CACHE K/V' "$(CACHE_TYPE_K)/$(CACHE_TYPE_V)" \
		'BATCH/UBATCH' "$(BATCH_SIZE)/$(UBATCH_SIZE)" \
		'THREADS' "$(THREADS)" \
		'GPU_LAYERS' "$(GPU_LAYERS)" \
		'PARALLEL' "$(PARALLEL)" \
		'PRESERVE_THINKING' "$(PRESERVE_THINKING)"

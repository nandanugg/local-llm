SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
dq := "

model ?= qwen3.6-35b
profile ?= default

PROFILES_DIR ?= $(CURDIR)/profiles
PROFILE_FILE := $(PROFILES_DIR)/$(model)/$(profile).mk
PROFILE_FILES := $(sort $(wildcard $(PROFILES_DIR)/*/*.mk))

-include $(PROFILE_FILE)

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

SYSTEM_LLAMA_SERVER := $(shell command -v llama-server 2>/dev/null || true)
LLAMA_SERVER ?= $(if $(SYSTEM_LLAMA_SERVER),$(SYSTEM_LLAMA_SERVER),$(BUILD_DIR)/bin/llama-server)

MODEL ?=
MODEL_ALIAS ?= $(model)

CTX_SIZE ?= 32768
OUTPUT_TOKENS ?= 4096
TEMPERATURE ?= 1.0
TOP_P ?= 0.95
TOP_K ?= 20
MIN_P ?= 0.0
PRESENCE_PENALTY ?= 0.0
REPEAT_PENALTY ?= 1.0
GPU_LAYERS ?= auto
BATCH_SIZE ?= 2048
UBATCH_SIZE ?= 512
PROFILE_ARGS ?=
REQUIRED_FLAGS ?=

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
	--temp "$(TEMPERATURE)" \
	--top-p "$(TOP_P)" \
	--top-k "$(TOP_K)" \
	--min-p "$(MIN_P)" \
	--presence-penalty "$(PRESENCE_PENALTY)" \
	--repeat-penalty "$(REPEAT_PENALTY)" \
	$(PROFILE_ARGS)

ifeq ($(RESOLVED_BACKEND),cuda)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=ON -DGGML_VULKAN=OFF
else ifeq ($(RESOLVED_BACKEND),vulkan)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=OFF -DGGML_VULKAN=ON
else ifeq ($(RESOLVED_BACKEND),cpu)
  CMAKE_BACKEND_ARGS := -DGGML_CUDA=OFF -DGGML_VULKAN=OFF
else
  $(error BACKEND must be auto, cuda, vulkan, or cpu)
endif

.PHONY: help setup list-profiles server server-code server-no-think server-codex
.PHONY: build update clean-build check check-profile check-model check-server
.PHONY: ensure-server print-config

help:
	@printf '%s\n' \
		'local llama.cpp runner' \
		'' \
		'  make server           API server on http://$(HOST):$(PORT)' \
		'  make server-code      API server using profile=code' \
		'  make server-no-think  API server using profile=no-think' \
		'  make server-codex     API server using profile=codex' \
		'  make setup            Install CUDA build dependencies and expose nvcc' \
		'  make list-profiles    Show configured model/profile pairs' \
		'  make build            Build llama-server locally' \
		'  make check            Validate the model, server binary, and required flags' \
		'  make print-config     Show the effective configuration' \
		'' \
		'Useful overrides:' \
		'  model=qwen3.6-35b profile=codex  MODEL=/path/model.gguf' \
		'  CTX_SIZE=32768 OUTPUT_TOKENS=4096 GPU_LAYERS=auto' \
		'  BACKEND=cpu|cuda|vulkan EXTRA_ARGS="..."'

list-profiles:
	@if [[ -z "$(PROFILE_FILES)" ]]; then \
		printf 'No profiles found under %s\n' "$(PROFILES_DIR)"; \
	else \
		printf 'Available profiles:\n'; \
		for file in $(PROFILE_FILES); do \
			rel="$${file#$(PROFILES_DIR)/}"; \
			model_name="$${rel%/*}"; \
			profile_name="$${rel##*/}"; \
			profile_name="$${profile_name%.mk}"; \
			printf '  make server model=%s profile=%s\n' "$$model_name" "$$profile_name"; \
		done; \
	fi

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
server: check-profile check-server check-model
	@exec "$(LLAMA_SERVER)" $(COMMON_ARGS) \
		--alias "$(MODEL_ALIAS)" \
		--host "$(HOST)" \
		--port "$(PORT)" \
		--parallel "$(PARALLEL)" \
		$(EXTRA_ARGS)

server-code:
	@$(MAKE) --no-print-directory server profile=code

server-no-think:
	@$(MAKE) --no-print-directory server profile=no-think

server-codex:
	@$(MAKE) --no-print-directory server profile=codex
ensure-server:
	@if [[ ! -x "$(LLAMA_SERVER)" ]]; then \
		$(MAKE) --no-print-directory build; \
	fi

check: check-profile check-server check-model
	@printf 'Configuration is valid.\n'

check-profile:
	@test -f "$(PROFILE_FILE)" || { \
		printf 'Profile not found: %s\n' "$(PROFILE_FILE)" >&2; \
		$(MAKE) --no-print-directory list-profiles >&2; \
		exit 1; \
	}

check-model:
	@test -f "$(MODEL)" || { \
		printf 'Model not found: %s\nOverride it with: make server model=%s profile=%s MODEL=/path/to/model.gguf\n' "$(MODEL)" "$(model)" "$(profile)" >&2; \
		exit 1; \
	}

check-server: ensure-server
	@if [[ -n "$(REQUIRED_FLAGS)" ]]; then \
		help_output="$$("$(LLAMA_SERVER)" --help 2>&1)"; \
		for flag in $(REQUIRED_FLAGS); do \
			rg -q --fixed-strings -- "$$flag" <<<"$$help_output" || { \
				printf '%s is too old; missing required option %s\n' "$(LLAMA_SERVER)" "$$flag" >&2; \
				exit 1; \
			}; \
		done; \
	fi

build: $(BUILD_DIR)/CMakeCache.txt
	@cmake --build "$(BUILD_DIR)" --config Release -j "$(JOBS)" \
		--target llama-server

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

print-config: check-profile
	@printf '%-20s %s\n' \
		'model/profile' "$(model)/$(profile)" \
		'PROFILE_FILE' "$(PROFILE_FILE)" \
		'MODEL' "$(MODEL)" \
		'MODEL_ALIAS' "$(MODEL_ALIAS)" \
		'LLAMA_SERVER' "$(LLAMA_SERVER)" \
		'BACKEND' "$(RESOLVED_BACKEND)" \
		'CTX_SIZE' "$(CTX_SIZE)" \
		'OUTPUT_TOKENS' "$(OUTPUT_TOKENS)" \
		'TEMPERATURE' "$(TEMPERATURE)" \
		'BATCH/UBATCH' "$(BATCH_SIZE)/$(UBATCH_SIZE)" \
		'THREADS' "$(THREADS)" \
		'GPU_LAYERS' "$(GPU_LAYERS)" \
		'PARALLEL' "$(PARALLEL)" \
		'REQUIRED_FLAGS' "$(REQUIRED_FLAGS)" \
		'PROFILE_ARGS' "$(subst $(dq),\$(dq),$(PROFILE_ARGS))" \
		'EXTRA_ARGS' "$(subst $(dq),\$(dq),$(EXTRA_ARGS))"

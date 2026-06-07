# local-llm

Run Qwen3.6 locally with llama.cpp using settings recommended by Unsloth.

## Requirements

- GNU Make
- Git
- CMake and a C++ build toolchain
- `rg` for capability checks
- A local GGUF model

The default model path is:

```text
~/Downloads/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
```

Override it when needed:

```bash
make run MODEL=/path/to/model.gguf
```

## Usage

```bash
# Build llama.cpp locally using the detected backend
make build

# Interactive general-purpose mode
make run

# Interactive coding mode
make run-code

# Start the API server on port 8001
make server

# Start the server with Codex/OpenCode agent settings
make server-codex

# Validate the model and llama.cpp binaries
make check

# Show the effective configuration
make print-config
```

Override settings through Make variables:

```bash
make server-codex \
  MODEL=/path/to/model.gguf \
  BACKEND=cuda \
  CTX_SIZE=131072
```

Supported backends are `cpu`, `cuda`, and `vulkan`. With `BACKEND=auto`,
the Makefile selects CUDA when `nvcc` is available, Vulkan when its headers
are installed, and CPU otherwise.

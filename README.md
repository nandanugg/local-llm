# local-llm

Run local GGUF models through the llama.cpp HTTP server using configurable model profiles.

## Requirements

- GNU Make
- Git
- CMake and a C++ build toolchain
- `rg` for capability checks
- A local GGUF model

The default profile uses this model path:

```text
~/Downloads/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
```

Override it when needed:

```bash
make server MODEL=/path/to/model.gguf
```

## Profiles

Profiles live under `profiles/<model>/<profile>.mk` and set the GGUF path,
model alias, sampling settings, and model-specific llama.cpp arguments.

List available profiles:

```bash
make list-profiles
```

Run a selected model/profile pair:

```bash
make server model=qwen3.6-35b profile=codex
```

Command-line overrides still work:

```bash
make server model=qwen3.6-35b profile=codex \
  MODEL=/path/to/model.gguf \
  CTX_SIZE=32768
```

## Usage

```bash
# Build llama-server locally using the detected backend
make build

# Start the API server on port 8001
make server

# Start the server with Codex/OpenCode agent settings
make server-codex

# Validate the model and llama-server binary
make check

# Show the effective configuration
make print-config
```

Override settings through Make variables:

```bash
make server-codex \
  model=qwen3.6-35b \
  MODEL=/path/to/model.gguf \
  BACKEND=cuda \
  CTX_SIZE=131072
```

Supported backends are `cpu`, `cuda`, and `vulkan`. With `BACKEND=auto`,
the Makefile selects CUDA when `nvcc` is available, Vulkan when its headers
are installed, and CPU otherwise.

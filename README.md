# local-llm

Run local GGUF models through the llama.cpp HTTP server using configurable model profiles.

## Requirements

- GNU Make
- Git
- CMake and a C++ build toolchain
- `rg` for capability checks
- `fuser` from `psmisc` for stopping the server
- A local GGUF model

The profiles use the Qwen3.8 27B MTP GGUF (Q4_K_XL) configured in `.envrc`:

```bash
export QWEN38_27B_Q4_MTP_GGUF=/path/to/Qwen3.8-27B-UD-Q4_K_XL.gguf
```

Load `.envrc` with `direnv allow` or `source .envrc` before invoking Make.

Override it when needed:

```bash
make server MODEL=/path/to/model.gguf
```

## Profiles

Profiles live under `profiles/<model>/<profile>.mk` and set the GGUF path,
model alias, sampling settings, and model-specific llama.cpp arguments.

The Qwen3.8 27B profiles all enable MTP and use Unsloth's recommended
sampling settings:

- `default`: thinking + coding focused (`temperature=1.0`, reasoning on,
  `reasoning_effort=high`, reduced 131,072-token context for a lower
  VRAM/RAM footprint)
- `general`: general thinking tasks (`temperature=1.0`, full 262,144-token
  context)
- `no-think`: general instruct mode (`temperature=0.7`, `top_p=0.8`, thinking
  disabled, full 262,144-token context)

List available profiles:

```bash
make list-profiles
```

Run a selected model/profile pair:

```bash
make server model=qwen3.8-27b-q4 profile=general
```

Command-line overrides still work:

```bash
make server model=qwen3.8-27b-q4 profile=general \
  MODEL=/path/to/model.gguf \
  CTX_SIZE=32768
```

## Usage

```bash
# Compile llama-server locally using the detected backend
make compile

# Start the coding/OpenAI-compatible default profile on port 8001
make server

# Start the general thinking profile
make server profile=general

# Start the non-thinking instruct profile
make server profile=no-think

# Stop the process listening on the configured server port
make kill-server

# Validate the model and llama-server binary
make check

# Show the effective configuration
make print-config
```

Override settings through Make variables:

```bash
make server \
  model=qwen3.8-27b-q4 \
  MODEL=/path/to/model.gguf \
  BACKEND=cuda \
  CTX_SIZE=131072
```

Supported backends are `cpu`, `cuda`, and `vulkan`. With `BACKEND=auto`,
the Makefile selects CUDA when `nvcc` is available, Vulkan when its headers
are installed, and CPU otherwise.

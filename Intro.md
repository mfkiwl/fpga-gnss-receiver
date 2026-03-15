I’d use GSD-2 as a **project manager and verification driver** for HDL work, not as the HDL toolchain itself.

GSD-2’s public docs show the pieces that matter for RTL work: it can run in step or auto mode, keeps project state in `.gsd/` files, supports long-running background shell processes, and has LSP integration for diagnostics, definitions, references, rename, hover, symbols, and code actions. Its built-in verification model is “static checks → command execution → behavioral testing → human review,” which maps surprisingly well to HDL if you wire it to your simulators, linters, and synth tools. ([GitHub][1])

My recommendation is to organize your flow like this:

## 1) Let GSD own the **spec and task decomposition**

Use GSD for:

* turning feature requests into milestones/slices/tasks
* tracking architectural decisions
* keeping a living project description
* generating test and verification checklists

That fits its native workflow exactly, since it maintains `PROJECT.md`, `DECISIONS.md`, roadmap/context/research files, per-task plans, and UAT scripts inside `.gsd/`. ([GitHub][1])

For HDL, that means each milestone should be something like:

* add AXI-Lite register block
* add CDC-safe RX FIFO
* add SV/UVM smoke test for framing
* add VHDL package for shared types
* close lint on top-level and testbench
* prove timing/synthesis sanity for module X

## 2) Keep the HDL intelligence in external tools

For VHDL, GHDL is a solid fit because it is explicitly a VHDL analyzer/compiler/simulator and its normal flow is analysis, elaboration, and run. ([ghdl.github.io][2])

For SystemVerilog, I’d separate two jobs:

* **lint / language checking:** `slang`, which is built for parsing, type checking, elaboration, and lint-style checking of SystemVerilog projects. ([GitHub][3])
* **simulation / compile flow:** `verilator`, which supports Verilog/SystemVerilog and has a `--lint-only` mode for fast checks. ([GitHub][4])

So the right mental model is:

**GSD-2 = planner / orchestrator / editor / shell driver**
**GHDL / slang / Verilator / vendor tools = actual HDL compilers, linters, simulators, synthesis engines**

## 3) Build a repo layout GSD can reason about

A simple layout helps the agent a lot:

```text
rtl/
  vhdl/
  sv/
tb/
  vhdl/
  sv/
sim/
  scripts/
lint/
  scripts/
constraints/
docs/
```

Then add a tiny “how to verify” document in the repo root, for example `docs/hdl-workflow.md`, that states:

* where source files live
* how compile order is handled
* top modules/entities
* testbench names
* which command is the source of truth for lint
* which command is the source of truth for sim
* what “done” means for this project

That gives GSD stable grounding so it does not invent flows.

## 4) Give GSD **mechanical verification commands**

This is the biggest thing. GSD’s verification ladder is strongest when every task can end in a command that returns pass/fail. ([GitHub][1])

Create scripts like:

```bash
./lint/lint_vhdl.sh
./lint/lint_sv.sh
./sim/run_smoke.sh
./sim/run_regression.sh
./synth/check_synth.sh
```

Examples of what they might do:

### VHDL

```bash
ghdl -a --std=08 rtl/vhdl/pkg_types.vhd rtl/vhdl/fifo.vhd tb/vhdl/fifo_tb.vhd
ghdl -e --std=08 fifo_tb
ghdl -r --std=08 fifo_tb --stop-time=10us
```

GHDL documents exactly that analyze/elaborate/run model. ([ghdl.github.io][5])

### SystemVerilog

```bash
slang --single-unit rtl/sv/top.sv tb/sv/top_tb.sv
verilator --lint-only -Wall rtl/sv/top.sv tb/sv/top_tb.sv
```

`slang` is intended for parsing / type checking / elaboration of SystemVerilog, and Verilator’s `--lint-only` mode is expressly for lint checks without generating a simulation build. ([sv-lang.com][6])

Once those exist, tell GSD that every code-editing task must end by running the relevant script.

## 5) Use LSP only after you install HDL language servers

GSD-2 has LSP support, but it does not ship HDL semantics by itself; the value comes from whichever language server you install and configure. Its docs only promise generic LSP operations, not built-in VHDL/SV knowledge. ([GitHub][1])

So I’d treat LSP as:

* fast symbol lookup
* rename
* references
* hover
* diagnostics from your HDL server

That is especially useful for:

* package/type renames in VHDL
* tracing signal/module usage in SV
* navigating large register maps and interface packages

## 6) Prefer **step mode** for architecture, **auto mode** for bounded edits

GSD supports both `/gsd` step mode and `/gsd auto` autonomous mode, and even recommends a two-terminal workflow where one terminal runs auto and another is used to steer with `/gsd discuss`, `/gsd status`, and `/gsd queue`. ([GitHub][1])

For HDL I would use:

### Step mode for:

* CDC architecture choices
* reset strategy
* clocking/interface definitions
* changing handshake semantics
* any task that could silently alter timing or protocol behavior

### Auto mode for:

* adding assertions
* propagating naming cleanup
* testbench boilerplate
* docs / comments / packages
* lint-fix loops
* adding mechanical checks and scripts

That split reduces the risk of the agent making plausible-but-wrong RTL decisions.

## 7) Define “done” in HDL terms, not software terms

For each GSD slice, I’d write must-haves like:

* entity/module compiles with no fatal diagnostics
* linter returns zero errors
* smoke testbench runs to completion
* waveform artifact is generated
* no new warnings of class X/Y/Z
* synthesis elaboration completes for target top
* interface timing/latency contract documented

That lines up with GSD’s “truths, artifacts, key links” verification structure. ([GitHub][1])

## 8) Feed it prompts that constrain HDL risk

Good GSD prompts for HDL are very explicit. For example:

**Good**

> Add a parameterized SystemVerilog async FIFO in `rtl/sv/async_fifo.sv`. Use Gray-coded pointers, two-flop synchronizers, no mixed blocking/nonblocking style, and preserve existing interface conventions. Verification must pass `./lint/lint_sv.sh` and `./sim/run_smoke.sh`. Do not modify unrelated modules.

**Better**

> First inspect existing reset, clock, and naming conventions. Create a short plan. Then implement only slice 1: module skeleton + package/types + lint-clean compile. Do not add testbench changes yet.

**Best**

> Treat the compile scripts as source of truth. If the tool output conflicts with your assumptions, follow the tool output. Do not “fix” warnings by suppressing them unless the warning is intentional and documented.

That kind of constraint is where GSD-style systems tend to shine.

## 9) Make compile order and filelists explicit

HDL projects break AI agents when compile order is implicit.

I would add:

* `vhdl.files`
* `sv.f`
* `tops.mk` or a `Makefile`

Then point GSD to those files and tell it never to infer source ordering from directory traversal unless the filelist is missing. This matters more for VHDL than most software languages because package/entity order is part of correctness.

## 10) Use it to generate and maintain verification collateral

A very good use of GSD is producing the “boring but high-value” stuff:

* assertion plans
* directed test lists
* module interface docs
* register maps
* reset/clock domain inventories
* bring-up checklists
* waveform inspection steps
* synthesis signoff checklist

Its roadmap/research/context/task-summary system is naturally good at this kind of persistent engineering memory. ([GitHub][1])

## 11) Where I would not trust it without close supervision

I would be careful with:

* CDC logic
* async resets and reset release
* inferred RAM/FIFO behavior across vendors
* timing exception generation
* multi-clock testbenches
* vendor IP integration
* anything involving subtle nonblocking/blocking or delta-cycle semantics
* changes that “compile fine” but alter latency or protocol timing

In those areas, use GSD for planning and diff generation, but keep a human in the loop for acceptance.

## A concrete setup I’d use

### For a mixed VHDL + SystemVerilog project

* GSD-2 for planning, edits, tracking, and task execution
* GHDL for VHDL compile/sim ([ghdl.github.io][2])
* slang for SystemVerilog semantic checking ([GitHub][3])
* Verilator for fast SV lint / sim-oriented checks ([GitHub][4])
* vendor synthesis tool or Yosys flow behind a shell script
* filelists and Make targets as the canonical interface

### Suggested commands to teach GSD

```bash
make lint-vhdl
make lint-sv
make sim-smoke
make sim-regress
make synth-check
make waves
```

### Suggested policy to tell GSD

```text
Always run lint before simulation.
Never change compile order files unless the task requires it.
Treat warnings related to latches, multiple drivers, width mismatch, and uninitialized signals as high priority.
For VHDL package/interface changes, update all dependent units and rerun full compile.
For SystemVerilog, do not replace always_ff / always_comb with plain always.
```

## My bottom-line recommendation

Use GSD-2 for HDL when you want:

* persistent planning across many RTL tasks
* structured decomposition of features into safe slices
* command-driven verification loops
* long-running agent help on large codebases

Do **not** use it as your “HDL brain” by itself. Make your HDL tools the authority, and make GSD the system that repeatedly edits code until those tools pass. That plays directly to what the repo publicly documents: autonomous/step execution, LSP, background shell, project-state artifacts, and verification-driven task completion. ([GitHub][1])

I can turn this into a concrete starter kit for you next: a `.gsd/preferences.md`, a repo layout, and `Makefile` targets for either a VHDL-only flow or a mixed VHDL/SystemVerilog flow.

[1]: https://github.com/gsd-build/gsd-2 "GitHub - gsd-build/gsd-2: A powerful meta-prompting, context engineering and spec-driven development system that enables agents to work for long periods of time autonomously without losing track of the big picture · GitHub"
[2]: https://ghdl.github.io/ghdl/about.html?utm_source=chatgpt.com "About - 7.0.0-dev"
[3]: https://github.com/MikePopoloski/slang?utm_source=chatgpt.com "slang - SystemVerilog Language Services"
[4]: https://github.com/verilator/verilator?utm_source=chatgpt.com "Verilator open-source SystemVerilog simulator and lint ..."
[5]: https://ghdl.github.io/ghdl/quick_start/simulation/index.html?utm_source=chatgpt.com "Simulation - 6.0.0-dev"
[6]: https://sv-lang.com/user-manual.html?utm_source=chatgpt.com "User Manual | slang C++ docs"

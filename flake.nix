# Is this just about macOS and Linux? Or is it about Windows too?                     Impervious to Decay   
#  ____  _             _       _         ____       _                                     ___________          .--.
# |  _ \(_)_ __  _   _| | __ _| |_ ___  |  _ \ _ __(_)_ __ ___   ___     ,--./,-.     C  |     |  Nix|  Free  |o_o |
# | |_) | | '_ \| | | | |/ _` | __/ _ \ | |_) | '__| | '_ ` _ \ / _ \   / #      \    l  |     |     |        |:_/ |
# |  __/| | |_) | |_| | | (_| | ||  __/ |  __/| |  | | | | | | |  __/  |          |   o  |_____|_____|  O    //   \ \
# |_|   |_| .__/ \__,_|_|\__,_|\__\___| |_|   |_|  |_|_| |_| |_|\___|   \        /    s  |macOS|     |  p   (|     | )           
#         |_|                                                            `._,._,'     e  |Windows/WSL|  e  /'\_   _/`\           
#             Welcome to Pipulate Prime IaC, a multi-platform app;                    d  |_____|_____|  n  \___)=(___/           
#             Your intro to your "Write once run anywhere" future!                                                                                           
#             Built on a *very good* "No Problem" framework (NPvg)                    HW Decays Over Time 
#
# ==============================================================================
# PIPULATE PRIME NIX FLAKE - "MAGIC COOKIE" AUTO-UPDATING SYSTEM
# ==============================================================================
# 
# This flake is the second half of the "magic cookie" installation system.
# It works together with the assets/installer/install.sh script (hosted at pipulate.com) to:
#
# 1. Transform a non-git directory into a proper git repository
# 2. Enable forever-forward git-pull auto-updates
# 3. Provide a consistent development environment across macOS, Windows (WSL2) and Linux
#
# === THE "MAGIC COOKIE" CONCEPT ===
# The "magic cookie" approach solves a bootstrapping problem:
# - Nix flakes require a git repository to function properly
# - We can't rely on git being available on all systems during initial install
# - We want a simple one-line curl|sh installation that works everywhere
#
# The solution:
# 1. assets/installer/install.sh downloads a ZIP archive (no git required)
# 2. assets/installer/install.sh extracts the ZIP and adds a ROT13-encoded SSH key
# 3. assets/installer/install.sh runs `nix develop` to activate this flake
# 4. THIS FLAKE detects non-git directories and transforms them into git repos
# 5. Auto-updates are enabled through git pulls in future nix develop sessions
#
# === CURRENT IMPLEMENTATION ===
# The flake now fully implements the "magic cookie" functionality:
# - Detects non-git directories and transforms them into git repositories
# - Preserves critical files during transformation:
#   * whitelabel.txt (maintains app identity)
#   * .ssh directory (preserves credentials)
#   * .venv directory (preserves virtual environment)
# - Creates backups before transformation
# - Performs automatic git pulls to keep the installation up to date
# - Switches to SSH-based git operations when SSH keys are available
#
# === REPOSITORY AWARENESS ===
# This flake is part of the target pipulate project repo at:
# /home/mike/repos/pipulate/flake.nix
#
# This is different from the installer script which lives at:
# /home/mike/repos/Pipulate.com/assets/installer/install.sh
#
# When a user runs:
#
#     curl -fsSL https://pipulate.com/install.sh | bash
#
# The installer downloads this flake as part of the ZIP archive.
# Most modern development is done on Linux, but Macs are Unix. If you think Homebrew and Docker
# are the solution, you're wrong. Welcome to the world of Nix Flakes! This file defines a complete,
# reproducible development environment. It's like a recipe for your perfect workspace, ensuring
# everyone on your team has the exact same setup, every time. As a bonus, you can use Nix flakes on
# Windows under WSL. Plus, whatever you make will be deployable to the cloud.
{
  # This description helps others understand the purpose of this Flake
  description = "A flake that reports the OS using separate scripts with optional CUDA support and unfree packages allowed.";
  # Inputs are the dependencies for our Flake
  # They're pinned to specific versions to ensure reproducibility
  inputs = {
    # nixpkgs is the main repository of Nix packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # flake-utils provides helpful functions for working with Flakes
    flake-utils.url = "github:numtide/flake-utils";
  };
  # Outputs define what our Flake produces
  # In this case, it's a development shell that works across different systems
      outputs = { self, nixpkgs, flake-utils }:
      let
        # TRUE SINGLE SOURCE OF TRUTH: Read version and description directly from __init__.py
        # No manual editing of this file needed - everything comes from __init__.py
        initPyContent = builtins.readFile ./__init__.py;
        # Extract __version__ from __init__.py
        versionMatch = builtins.match ".*__version__[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*" initPyContent;
        versionNumber = if versionMatch != null then builtins.head versionMatch else "unknown";
        # Extract __version_description__ from __init__.py  
        # DOUBLE-QUOTE ONLY (2026-08-04, first-contact convicted on macOS). The
        # character class excluded the apostrophe from the CAPTURE, so a
        # description containing one was silently TRUNCATED at it: So'wI' chu'
        # became So, and the banner read `Version: 2.04 (So)` on every shell
        # entry -- a wrong-but-plausible label that reads as a deliberately terse
        # description. THE LAST-INCH RULE with a regex as the last inch: every
        # mechanism upstream was correct and only the string nobody audits was
        # damaged. __init__.py always writes this value in double quotes, so
        # match double quotes only and let apostrophes through. __version__ above
        # is left alone on purpose -- a version number cannot contain a quote, so
        # its looser class has no failure mode to fix, and a second edit there
        # would be change without a conviction behind it.
        descMatch = builtins.match ".*__version_description__[[:space:]]*=[[:space:]]*\"([^\"]+)\".*" initPyContent;
        versionDesc = if descMatch != null then builtins.head descMatch else null;
        # Combine version and description
        version = if versionDesc != null then "${versionNumber} (${versionDesc})" else versionNumber;
      in
    flake-utils.lib.eachDefaultSystem (system:
      let
        # We're creating a custom instance of nixpkgs
        # This allows us to enable unfree packages like CUDA
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;  # This is necessary for CUDA support
          };
        };
        # These helpers let us adjust our setup based on the OS
        isDarwin = pkgs.stdenv.isDarwin;
        isLinux = pkgs.stdenv.isLinux;
        # Define a static workspace name to prevent random file generation
        jupyterWorkspaceName = "pipulate-main";

 		# Define the default notebook for JupyterLab to open on startup
 		jupyterStartupNotebook = "Notebooks/Onboarding.ipynb";

        # --- 🌐 BROWSER TAB CONFIGURATION ---
        autoOpenJupyter = "true";
        autoOpenFastHTML = "false";
        fastHtmlOpenDelay = "0";  # Seconds to delay FastHTML tab if both are true

        # --- CORRECTED: Declarative list for notebooks to copy ---
        notebookFilesToCopy = [
          {
            source = "assets/nbs/imports/core_sauce.py";
            dest = "Notebooks/imports/core_sauce.py";
            desc = "the unified core workflow engine";
          }
          {
            source = "assets/nbs/imports/onboard_sauce.py";
            dest = "Notebooks/imports/onboard_sauce.py";
            desc = "a local 'onboard_sauce.py' source of secret sauce";
          }
          {
            source = "assets/nbs/imports/url_inspect_sauce.py";
            dest = "Notebooks/imports/url_inspect_sauce.py";
            desc = "a local 'url_inspect_sauce.py' source of secret sauce";
          }
          {
            source = "assets/nbs/imports/faq_writer_sauce.py";
            dest = "Notebooks/imports/faq_writer_sauce.py";
            desc = "a local 'faq_writer_sauce.py' source of secret sauce";
          }
          {
            source = "assets/nbs/imports/gap_analyzer_sauce.py";
            dest = "Notebooks/imports/gap_analyzer_sauce.py";
            desc = "a local 'gap_analyzer_sauce.py' source of secret sauce";
          }
          {
            source = "assets/nbs/imports/videditor_sauce.py";
            dest = "Notebooks/imports/videditor_sauce.py";
            desc = "a local 'videditor_sauce.py' source of secret sauce";
          }
          {
            source = "assets/nbs/Onboarding.ipynb";
            dest = "Notebooks/Onboarding.ipynb";
            desc = "the Pipulate initiation rite and setup guide";
          }
          {
            source = "assets/nbs/Advanced_Notebooks/01_URLinspector.ipynb";
            dest = "Notebooks/Advanced_Notebooks/01_URLinspector.ipynb";
            desc = "a local 'URL-by-URL auditor.' derived from FAQuilizer";
          }
          {
            source = "assets/nbs/Advanced_Notebooks/02_FAQuilizer.ipynb";
            dest = "Notebooks/Advanced_Notebooks/02_FAQuilizer.ipynb";
            desc = "a local 'FAQuilizer' simple workflow";
          }
          {
            source = "assets/nbs/Advanced_Notebooks/03_GAPalyzer.ipynb";
            dest = "Notebooks/Advanced_Notebooks/03_GAPalyzer.ipynb";
            desc = "a local 'Competitor Gap Analyzer.' advanced workflow";
          }
          {
            source = "assets/nbs/Advanced_Notebooks/04_VIDeditor.ipynb";
            dest = "Notebooks/Advanced_Notebooks/04_VIDeditor.ipynb";
            desc = "a local 'NoGooey Video Editor.'";
          }
          {
            source = "assets/nbs/Educational_Notebooks/Truth_Actually.ipynb";
            dest = "Notebooks/Educational_Notebooks/Truth_Actually.ipynb";
            desc = "the Player Piano Test, an interactive actuator-literacy lesson";
          }
        ];

        # Convert the Nix list to a string that Bash can loop over
        notebookFilesString = pkgs.lib.concatStringsSep "\n" (
          map (file: "${file.source};${file.dest};${file.desc}") notebookFilesToCopy
        );

        # Real commands, not shell functions, so Python-spawned `!` commands in
        # adhoc.txt inherit them through PATH just like interactive Bash does.
        postsCommand = pkgs.writeShellScriptBin "posts" ''
          set -euo pipefail
          root="''${PIPULATE_ROOT:-$PWD}"
          python_bin="$root/.venv/bin/python"
          if [ ! -x "$python_bin" ]; then
            echo "posts: missing $python_bin; enter the Pipulate Nix shell first." >&2
            exit 1
          fi
          cd "$root/scripts/articles"
          # Default to target 1 ONLY when the caller supplies no -t of its
          # own, so rgx/rgxc can retarget without lsa.py seeing two -t flags.
          case " $* " in
            *" -t "*|*" --target"*) exec "$python_bin" lsa.py "$@" ;;
            *) exec "$python_bin" lsa.py -t 1 "$@" ;;
          esac
        '';

        # THE `c`-TWIN OF `posts` (mirrors rgx -> rgxc, same suffix grammar).
        # Same corpus, same selection flags, plus each article's holographic
        # shard (keywords + summary) read from _context/<stem>.json.
        #
        # WHY THIS IS THE ONLY LENS THAT FITS: a single recent article can run
        # 180k+ tokens, so `posts 20` names ~1.5M tokens of work you cannot
        # load. Twenty shards is ~1.6k. The shard is the article's own lossy
        # compression, and this command is the only way to read three weeks of
        # work in one context window.
        #
        # A COMMAND, NOT A FUNCTION, for the same reason `posts` is one: a `!`
        # chisel-strike in adhoc.txt spawns a non-interactive child that
        # inherits PATH and never inherits functions, so `! postsc 5` resolves
        # and `! posts2 5` cannot. Forwarding is total, so `-t`, `--reverse`,
        # `--match`, `--slugs` and the bare-N positional all still work, and
        # `posts` still owns the -t default so lsa.py never sees two of them.
        #
        # SILENT DEGRADATION, NAMED HERE SO IT IS NEVER DIAGNOSED TWICE:
        # print_shard_header returns quietly when the shard file is missing, so
        # a listing with no kw/sum lines means contextualizer.py has not run for
        # those articles -- NOT that this flag is broken.
        # SECOND SILENT MODE, OBSERVED 2026-08-06: --fmt dated-slugs (and any
        # non-full format) does not render shards at all, so `postsc --fmt
        # dated-slugs N` prints EXACTLY what a shard-less corpus prints. Two
        # causes, one printout -- THE DISCRIMINATION QUESTION fails on that
        # command, and the wrong diagnosis (contextualizer never ran) is the
        # one a reader reaches for first. Diagnose missing shards in FULL
        # format only.
        postscCommand = pkgs.writeShellScriptBin "postsc" ''
          set -euo pipefail
          exec ${postsCommand}/bin/posts --shards "$@"
        '';
        rgxCommand = pkgs.writeShellScriptBin "rgx" ''
          set -euo pipefail

          # Target selection: -t KEY (first args only) resolves the corpus
          # path from blogs.json at RUNTIME — never baked into the Nix store —
          # so adding a blog in blogs.nix needs no rebuild of this command.
          target="1"
          if [ "''${1:-}" = "-t" ] && [ "$#" -ge 2 ]; then
            target="$2"
            shift 2
          fi

          # -v: THE ART WALK. Open the matches in the editor instead of
          # printing them. Newest article lands in buffer 1 so :bn walks
          # backward in time through each article's ASCII art.
          vim_mode=0
          if [ "''${1:-}" = "-v" ]; then
            vim_mode=1
            shift
          fi

          last_args=()
          capn=8
          lastn=""
          if [[ "''${1:-}" =~ ^[0-9]+$ ]]; then
            last_args=(--last "$1")
            lastn="$1"
            if [ "$1" -lt "$capn" ]; then
              capn="$1"
            fi
            shift
          fi
          if [ "$#" -eq 0 ]; then
            echo "Usage: rgx [-t KEY] [-v] [N] TERM [TERM...]   (leading N = only the N most recent matches; -v opens them in vim, newest first)" >&2
            exit 1
          fi

          terms=("$@")
          blogs_json="$HOME/.config/pipulate/blogs.json"
          posts_dir="$(${pkgs.jq}/bin/jq -r --arg t "$target" '.[$t].path // empty' "$blogs_json" 2>/dev/null || true)"
          if [ -z "$posts_dir" ]; then
            posts_dir="$HOME/repos/trimnoir/_posts"
          fi
          if [ ! -d "$posts_dir" ]; then
            echo "rgx: posts dir for target $target not found: $posts_dir" >&2
            exit 1
          fi
          matches="$(${pkgs.ripgrep}/bin/rg -il -- "''${terms[0]}" "$posts_dir" || true)"
          for term in "''${terms[@]:1}"; do
            [ -z "$matches" ] && break
            matches="$(printf '%s\n' "$matches" | ${pkgs.findutils}/bin/xargs -r ${pkgs.ripgrep}/bin/rg -il -- "$term" || true)"
          done
          if [ -z "$matches" ]; then
            echo "No matching articles." >&2
            exit 0
          fi

          sorted_matches="$(printf '%s\n' "$matches" | ${pkgs.coreutils}/bin/sort)"

          # THE ART WALK exit: sorted_matches is oldest-first (date-prefixed
          # filenames), so the optional leading N takes the tail (the N most
          # recent) and tac flips it newest-first before exec'ing the editor.
          # The vim alias is interactive-only, so resolve nvim explicitly;
          # the exported VIMINIT still loads the repo's init.lua.
          if [ "$vim_mode" -eq 1 ]; then
            vim_list="$sorted_matches"
            if [ -n "$lastn" ]; then
              vim_list="$(printf '%s\n' "$vim_list" | ${pkgs.coreutils}/bin/tail -n "$lastn")"
            fi
            vim_list="$(printf '%s\n' "$vim_list" | ${pkgs.coreutils}/bin/tac)"
            editor="$(command -v nvim || command -v vim || true)"
            if [ -z "$editor" ]; then
              echo "rgx: no nvim or vim found on PATH" >&2
              exit 1
            fi
            mapfile -t vim_files < <(printf '%s\n' "$vim_list")
            exec "$editor" "''${vim_files[@]}"
          fi

          # Drop --fmt paths so each match carries its Tokens/Bytes annotation
          # (the same per-article numbers `posts` shows) for context budgeting.
          # Deliberately NOT --shards/--around: that shard + hit-region noise is
          # rgxc's job. rgx stays the quiet, token-annotated match list.
          printf '%s\n' "$sorted_matches" \
            | ${postsCommand}/bin/posts -t "$target" --stdin "''${last_args[@]}"

          # Clipboard is an interactive-only side effect. Under prompt_foo's
          # captured pipe, the forked xclip daemon inherits and holds the fd
          # open forever, deadlocking communicate(). Gate on a real tty and
          # detach xclip's own stdout so no capture pipe can be held hostage.
          if [ -t 1 ] && command -v xclip >/dev/null 2>&1; then
            if printf '%s\n' "$sorted_matches" \
              | ${postsCommand}/bin/posts -t "$target" --stdin --last "$capn" --fmt slugs \
              | { echo "[[[TODO_SLUGS]]]"; cat; echo "[[[END_SLUGS]]]"; } \
              | xclip -selection clipboard >/dev/null 2>&1; then
              echo "📋 TODO_SLUGS block (≤$capn newest) → clipboard (type xp to compile)" >&2
            fi
          fi
        '';

        rgxcCommand = pkgs.writeShellScriptBin "rgxc" ''
          set -euo pipefail

          # Same runtime target resolution as rgx: -t KEY (first args only)
          # reads blogs.json when the command RUNS, so the Nix store carries
          # the mechanism, never the data.
          target="1"
          if [ "''${1:-}" = "-t" ] && [ "$#" -ge 2 ]; then
            target="$2"
            shift 2
          fi

          # -v: THE ART WALK (mirrored from rgx). Open the matches in the
          # editor instead of printing shards. Newest article lands in
          # buffer 1 so :bn walks backward in time through the ASCII art.
          vim_mode=0
          if [ "''${1:-}" = "-v" ]; then
            vim_mode=1
            shift
          fi

          last_args=()
          capn=8
          lastn=""
          if [[ "''${1:-}" =~ ^[0-9]+$ ]]; then
            last_args=(--last "$1")
            lastn="$1"
            if [ "$1" -lt "$capn" ]; then
              capn="$1"
            fi
            shift
          fi
          if [ "$#" -eq 0 ]; then
            echo "Usage: rgxc [-t KEY] [-v] [N] TERM [TERM...]   (leading N = only the N most recent matches; -v opens them in vim, newest first)" >&2
            exit 1
          fi

          terms=("$@")
          blogs_json="$HOME/.config/pipulate/blogs.json"
          posts_dir="$(${pkgs.jq}/bin/jq -r --arg t "$target" '.[$t].path // empty' "$blogs_json" 2>/dev/null || true)"
          if [ -z "$posts_dir" ]; then
            posts_dir="$HOME/repos/trimnoir/_posts"
          fi
          if [ ! -d "$posts_dir" ]; then
            echo "rgxc: posts dir for target $target not found: $posts_dir" >&2
            exit 1
          fi
          matches="$(${pkgs.ripgrep}/bin/rg -il -- "''${terms[0]}" "$posts_dir" || true)"
          for term in "''${terms[@]:1}"; do
            [ -z "$matches" ] && break
            matches="$(printf '%s\n' "$matches" | ${pkgs.findutils}/bin/xargs -r ${pkgs.ripgrep}/bin/rg -il -- "$term" || true)"
          done
          if [ -z "$matches" ]; then
            echo "No matching articles." >&2
            exit 0
          fi

          sorted_matches="$(printf '%s\n' "$matches" | ${pkgs.coreutils}/bin/sort)"

          # THE ART WALK exit (mirrored from rgx): tail takes the N most
          # recent, tac flips newest-first, nvim resolved explicitly since
          # the vim alias is interactive-only; VIMINIT loads init.lua.
          if [ "$vim_mode" -eq 1 ]; then
            vim_list="$sorted_matches"
            if [ -n "$lastn" ]; then
              vim_list="$(printf '%s\n' "$vim_list" | ${pkgs.coreutils}/bin/tail -n "$lastn")"
            fi
            vim_list="$(printf '%s\n' "$vim_list" | ${pkgs.coreutils}/bin/tac)"
            editor="$(command -v nvim || command -v vim || true)"
            if [ -z "$editor" ]; then
              echo "rgxc: no nvim or vim found on PATH" >&2
              exit 1
            fi
            mapfile -t vim_files < <(printf '%s\n' "$vim_list")
            exec "$editor" "''${vim_files[@]}"
          fi

          printf '%s\n' "$sorted_matches" \
            | ${postsCommand}/bin/posts -t "$target" --stdin --shards "''${last_args[@]}" --around 2 --terms "''${terms[@]}"

          # Same tty gate as rgx: never let a forked xclip daemon hold a
          # captured pipe open. Interactive use keeps the clipboard magic;
          # prompt_foo's ! executor gets clean EOF and no deadlock.
          if [ -t 1 ] && command -v xclip >/dev/null 2>&1; then
            if printf '%s\n' "$sorted_matches" \
              | ${postsCommand}/bin/posts -t "$target" --stdin --last "$capn" --fmt slugs \
              | { echo "[[[TODO_SLUGS]]]"; cat; echo "[[[END_SLUGS]]]"; } \
              | xclip -selection clipboard >/dev/null 2>&1; then
              echo "📋 TODO_SLUGS block (≤$capn newest) → clipboard (type xp to compile)" >&2
            fi
          fi
        '';

        # ai-commit: init.lua's \g mapping shells out to this NAME. On Pipulate
        # Prime a system-level copy also exists (/run/current-system/sw/bin via
        # the nixos repo); this shim makes the name resolve inside ANY Pipulate
        # dev shell (macOS, WSL, vanilla Linux) so \g never silently downgrades
        # to the "Update <file>" fallback on machines without the system copy.
        aiCommitCommand = pkgs.writeShellScriptBin "ai-commit" ''
          set -euo pipefail
          root="''${PIPULATE_ROOT:-$PWD}"
          python_bin="$root/.venv/bin/python"
          if [ ! -x "$python_bin" ]; then
            echo "ai-commit: missing $python_bin; enter the Pipulate Nix shell first." >&2
            exit 1
          fi
          exec "$python_bin" "$root/scripts/ai.py" "$@"
        '';

        # THE DEED KEEPER (2026-09-06). Rotation prunes to the newest twenty,
        # which at this compile rate makes a snapshot's name durable for about
        # a day -- fine for a discussion, useless for a ticket. This promotes
        # ONE snapshot out of rotation so its name still resolves months from
        # now, and the choice of which one is deliberately the human's: no
        # retention policy can know which compile mattered.
        #
        # A PACKAGED COMMAND, NOT A SHELL FUNCTION, and the reason is receipts.
        # Only a human types this, which by THE THREE-TIER AMENDMENT would
        # ordinarily make a function correct -- but a function is invisible to
        # the `!` executor, so its only possible witness is a source census
        # proving text landed in this file, which proves nothing about whether
        # the command runs. A writeShellScriptBin resolves through PATH in a
        # child shell and can therefore be probed. Given two working spellings,
        # take the one that can be measured.
        #
        # FOUR THINGS IT MUST NEVER DO:
        #   1. RENAME. The name carries eight hex of the archive's own SHA-256,
        #      so the egress footer's verify line and every ticket reference
        #      quote it verbatim. Same name in the keep directory, or nothing.
        #   2. REBUILD. Copy bytes. Regenerating a cartridge to refresh it
        #      destroys the only property that makes it evidence.
        #   3. KEEP AN UNVERIFIED FILE. The copy is verified after landing and
        #      REMOVED on refusal -- a kept deed that does not verify is worse
        #      than no deed, because it looks like one.
        #   4. LIVE INSIDE THE REPO. The keep directory sits outside the
        #      worktree so pruning structurally cannot reach it and no forced
        #      git sweep can either. Payloads may carry client data, and
        #      structural absence beats exclusion policy.
        deedCommand = pkgs.writeShellScriptBin "deed" ''
          set -euo pipefail
          root="''${PIPULATE_ROOT:-$PWD}"
          keep="''${PIPULATE_DEEDS_DIR:-$HOME/.local/state/pipulate/deeds}"
          if [ "$#" -eq 0 ]; then
            newest=$(ls -t "$root"/foo-*.zip 2>/dev/null | head -1 || true)
            if [ -z "$newest" ]; then
              echo "deed: no rotated snapshot in $root -- compile once first." >&2
              exit 1
            fi
            echo "newest   $(basename "$newest")"
            kept=$(ls -1 "$keep"/foo-*.zip 2>/dev/null | wc -l || true)
            echo "kept     $kept in $keep"
            exit 0
          fi
          name=$(basename "$1")
          src="$root/$name"
          if [ ! -f "$src" ]; then
            echo "deed: $name is not in $root -- it may already have been pruned." >&2
            exit 1
          fi
          if [ -f "$keep/$name" ]; then
            echo "deed: already kept -- $keep/$name"
            exit 0
          fi
          mkdir -p "$keep"
          cp -p "$src" "$keep/$name"
          if ! "$root/.venv/bin/python" "$root/scripts/foo_cartridge.py" "$keep/$name"; then
            rm -f "$keep/$name"
            echo "deed: REFUSED -- the copy did not verify; nothing kept." >&2
            exit 1
          fi
          echo "deed: kept $keep/$name"
        '';
        # Common packages that we want available in our environment
        # regardless of the operating system
        commonPackages = with pkgs; [
          postsCommand                 # Article corpus formatter usable by child shells
          postscCommand                # posts plus holographic shards (the c-twin)
          rgxCommand                   # Bounded AND-search over article files
          rgxcCommand                  # rgx plus holographic shards and hit context
          aiCommitCommand              # \g's commit generator resolves in-shell on every platform
          deedCommand                  # Promote one cartridge snapshot out of rotation, verified
          uv                           # Fast Python package installer and resolver
          sqlite                       # Ensures correct SQLite library is linked on macOS
          ruff                         # Fast Python linter (native Nix binary)
          (python312.withPackages (ps: with ps; [
            nbstripout
          ]))
          nbstripout
          figlet                       # For creating ASCII art welcome messages
          tmux                         # Terminal multiplexer for managing sessions
          zlib                         # Compression library for data compression
          git                          # Version control system for tracking changes
          git-filter-repo              # Surgical git history rewriting (scrub strings/paths across all commits)
          curl                         # Command-line tool for transferring data with URLs
          wget                         # Utility for non-interactive download of files from the web
          cmake                        # Cross-platform build system generator
          htop                         # Interactive process viewer for Unix systems
          plantuml
          graphviz
          eza                          # A tree directory visualizer that uses .gitignore
          ripgrep		               # Like find and grep but honors .gitignore
          xclip
          jq
          dig
          whois
          ffmpeg
        ] ++ (with pkgs; pkgs.lib.optionals isLinux [
          # PLATFORM GATE (macOS-convicted 2026-08-04, first-contact receipt):
          # nixpkgs marks alsa-utils *-linux ONLY, so an unconditional entry in
          # commonPackages made `nix develop` REFUSE TO EVALUATE on
          # aarch64-darwin. The flake therefore died BEFORE the shellHook, which
          # means gitUpdateLogic never ran, which means the magic-cookie
          # transformation never happened and a fresh Mac install could not
          # complete at all -- an eval-time refusal is strictly worse than a
          # runtime failure, because nothing downstream of it gets a chance to
          # report. xhost rides here for the same reason (X11 is a Linux
          # concern) and its bare name also clears the `xorg.xhost` deprecation
          # warning that the same install printed one line above the error.
          # NOTE: xclip, dig, and whois all evaluated CLEAN on aarch64-darwin in
          # that receipt -- they sit above alsa-utils in the list and Nix forces
          # buildInputs in order -- so they deliberately stay unconditional.
          xhost                        # X access grants for cold-start / multi-user rides
          alsa-utils                   # ALSA sound tooling
          espeak-ng                    # Text-to-speech, Linux only
          sox                          # Sound processing, Linux only
          virtualenv
          gcc                          # GNU Compiler Collection for compiling C/C++ code
          stdenv.cc.cc.lib             # Standard C library for Linux systems
          chromium                     # Chromium browser for Selenium automation
          undetected-chromedriver
        ]);
        # This script sets up our Python environment and project
runScript = pkgs.writeShellScriptBin "run-script" ''
          #!/usr/bin/env bash
          # Activate the virtual environment
          source .venv/bin/activate
          # SILENT-AFTER-BANNER (2026-08-04, first-contact convicted): this loop
          # printed TWO lines per file -- twenty-four lines of INFO on a fresh
          # install, wedged between the package count and the boot menu, at the
          # one moment a newcomer has no way to tell signal from noise. It was
          # also chatter about the ORDINARY case: on every entry after the first,
          # all twelve destinations already exist and the loop is silent, so the
          # only time it ever spoke was the time its speech was least readable.
          # A COUNTER, NOT A GAG. THE DISCRIMINATION QUESTION applies to silence
          # too -- what does this print in the world where the copy loop is
          # broken? -- so one summary line survives whenever anything was
          # actually staged, and nothing prints when nothing was. Same shape as
          # the "packages ready" line below: meaningful silence, never silence
          # that is indistinguishable from a dead loop. The counter increments in
          # the CURRENT shell because a heredoc-fed while loop forks no subshell;
          # a pipe here would zero it and report success for a loop that ran.
          copy_notebook_if_needed() {
            local staged=0
            while IFS=';' read -r source dest desc; do
              if [ -f "$source" ] && [ ! -f "$dest" ]; then
                mkdir -p "$(dirname "$dest")"
                cp "$source" "$dest"
                staged=$((staged + 1))
              fi
            done <<EOF
          ${notebookFilesString}
          EOF
            if [ "$staged" -gt 0 ]; then
              echo "📓 $staged starter file(s) copied into Notebooks/ -- yours to edit."
            fi
          }
          # Set up the personal playground
          if [ ! -f "Notebooks/Playground/WELCOME.md" ]; then
            # The mkdir moved to miscSetupLogic 2026-08-07 so .#quiet gets the
            # folder too. This heredoc STAYS: runScript is a standalone
            # writeShellScriptBin, never interpolated, which is the one place a
            # heredoc is safe -- and the body below carries triple-backtick
            # fences that would become command substitution inside a
            # double-quoted printf. Moving the document is a content decision,
            # not this move.
            cat << 'PLAYGROUND_EOF' > "Notebooks/Playground/WELCOME.md"
          # 🎢 Welcome to the Playground!
          
          This folder is your personal sandbox. It is intentionally **ignored** by Pipulate's main version control.
          
          ## Why does this exist?
          As a practitioner readying clients for the agentic web, you need a place to write fast, messy, disposable Python scripts to solve immediate client problems. You shouldn't have to worry about breaking the main Pipulate architecture or accidentally committing client data to a public repository.
          
          ## How it works:
          1. **Full Access:** Scripts here use the same `.venv` Python environment as Pipulate. You have access to `pandas`, `httpx`, `lxml`, and the Pipulate `wand` without installing anything.
          2. **The Sausage Factory:** Write your ad hoc "tracer bullet" scripts here. If they prove valuable across multiple clients, you can graduate them up to `Notebooks/imports/` as reusable "sauce" modules.
          3. **Protect Your Work:** Because Pipulate ignores this folder, we highly recommend turning it into your own private repository:
          
          ```bash
          cd Notebooks/Playground
          git init
          # Then link it to a private GitHub repository to back up your work!
          ```
          
          ## What this folder becomes (coming soon — not active yet)

          Right now this Playground is a **solo** sandbox: just you, your throwaway
          scripts, and the shared `.venv`. None of the team features below are wired
          up yet — this is a map of where things are headed, kept here so the intent
          stays visible from inside the code instead of buried in notes.

          Nothing you put here is ever shared. When you want to hand something to a
          teammate, drag it into `Notebooks/Shared/` and put it in a folder named
          after you — one folder per person, so two people can never collide.

          ```text
          Notebooks/
          ├── Advanced_Notebooks/     copied in for you; your edits stay
          ├── Educational_Notebooks/  copied in for you
          ├── imports/                copied in for you
          ├── Playground/   ◀── THIS  private. NOTHING here is ever shared.
          ├── Client_Work/            private
          ├── Deliverables/           private
          └── Shared/<your-name>/     drag work here to hand it to a teammate
          ```

          That is the whole map. Everything except `Shared/` is either yours alone or
          handed to you; `Shared/` is the one place you deliberately give work away.

          Happy hacking. Throw some paint around.
          PLAYGROUND_EOF
          fi
          # Create a fancy welcome message
          if [ ! -f whitelabel.txt ]; then
            APP_NAME=$(basename "$PWD")
            if [[ "$APP_NAME" == *"botify"* ]]; then
              APP_NAME="$APP_NAME"
            else
              APP_NAME="Pipulate"
            fi
            echo "$APP_NAME" > whitelabel.txt
          fi
          # MAGIC COOKIE COMPONENT: This section reads the whitelabel.txt that should be 
          # preserved if/when the directory is transformed into a git repo
          APP_NAME=$(cat whitelabel.txt)
          PROPER_APP_NAME=$(echo "$APP_NAME" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
          # THE BANNER MOVED TO DOOR 1 (2026-08-25). The figlet printed HERE,
          # ABOVE the threshold, so the human who was one keypress away from
          # saying "do not start the app" got a full-width ASCII assertion of
          # that app's identity first. The banner is the curtain going up on
          # the app; it belongs on the path where the app actually starts, and
          # it now renders just below the BOOT_CHOICE exit. PROPER_APP_NAME
          # stays computed here -- it is the figlet's only consumer and both
          # live in this one process, so the move strands nothing.
          #
          # WHAT REPLACES IT IS A READING, NEVER A BOOLEAN. "nix present: True"
          # names a state nothing observed; `nix --version` is an observation,
          # and it discriminates Determinate Nix from generic Nix for free --
          # exactly the fact a first-contact reader needs and cannot get from a
          # boolean. Every field is read at this moment from a named source:
          # nix from the binary, python from the activated venv, the version
          # from __init__.py at flake eval, the path from the shell.
          #
          # ITS SILENCE IS ALSO A READING. runScript is invoked by the LAST
          # line of each shellHook, so ANY output from it witnesses that the
          # whole hook parsed -- the HALF-EXECUTED HOOK failure prints nothing
          # here at all. That witness used to be the figlet's job; it did not
          # disappear, it changed hands.
          #
          # LD_LIBRARY_PATH="" IS LOAD-BEARING (THE UNEXPORTED-SHIM RULE): the
          # nix() rpath shim is a shell FUNCTION defined in miscSetupLogic, and
          # this script is a CHILD PROCESS, so it inherits the polluted path
          # and not the shim. The inline clear is the prescribed spelling and
          # is a no-op on a clean shell.
          # 89 CHARS ON ITS FIRST FLIGHT, MEASURED (2026-08-25). Two cuts, in
          # the order that matters: BOUND THE UNBOUNDED FIELD FIRST, then
          # remove redundancy, and never truncate a reading.
          #   $PWD is the only field that can grow without limit -- 25 here,
          #     but a stranger with ~/Documents/code/pipulate pushes this line
          #     past 100. Tilde-shortening saves 9 AND bounds it structurally.
          #   The leading "nix " is redundant with the parenthetical right
          #     after it, and that parenthetical is the whole discriminator:
          #     "(Nix) 2.25.0..." is generic, "(Determinate Nix 3.x) 2.x" is
          #     DetSys. Saves 4 and destroys nothing.
          # 89 - 9 - 4 = 76, with headroom. Truncating the prerelease build
          # string was REFUSED: that is the LAST-INCH failure -- a correct
          # reading destroyed by the transformation nearest the reader.
          #
          # THE FIRST ATTEMPT AT THIS COMMENT WAS REFUSED BY THE NIX AIRLOCK,
          # for containing the exact sequence it warned about. A bash comment
          # DOES NOT EXIST at Nix parse time: the whole indented string is one
          # value, and a dollar immediately followed by an open brace starts
          # interpolation ANYWHERE inside it, comment or not. The warning was
          # the hazard. So: say "dollar-brace" in words and never type it. A
          # bare dollar followed by a letter is literal and safe, which is why
          # $PWD and $HOME below reach bash intact. Two adjacent single quotes
          # are the other structural hazard and appear nowhere here.
          NIX_READING=$(LD_LIBRARY_PATH="" nix --version 2>/dev/null | tail -1 | sed 's/^nix //')
          if [ -z "$NIX_READING" ]; then NIX_READING="nix: no reading"; fi
          PY_READING=$(python -V 2>&1)
          if [ -z "$PY_READING" ]; then PY_READING="python: no reading"; fi
          PWD_READING=$(printf '%s' "$PWD" | sed "s|^$HOME|~|")
          if [ -z "$PWD_READING" ]; then PWD_READING="$PWD"; fi
          printf '%s · %s · v%s · %s\n' "$NIX_READING" "$PY_READING" "${versionNumber}" "$PWD_READING"
          # --- JupyterLab Local Configuration ---
          export JUPYTER_CONFIG_DIR="$(pwd)/.jupyter"
          # Install Python packages from requirements.txt
          FRESH_ENV=false
          if [ ! -d .venv/lib/python*/site-packages ] || [ $(find .venv/lib/python*/site-packages -name "*.dist-info" 2>/dev/null | wc -l) -lt 10 ]; then
            FRESH_ENV=true
            echo "🔧 Fresh install detected — packages downloading..."
          fi
          # --- Pip Install Verbosity Toggle ---
          PIP_VERBOSE="false"
          PIP_QUIET_FLAG="--quiet"
          if [ "$PIP_VERBOSE" = "true" ]; then
            PIP_QUIET_FLAG=""
          fi
          if uv pip install -r requirements.txt $PIP_QUIET_FLAG && \
            uv pip install -e . --no-deps $PIP_QUIET_FLAG; then
            true
          else
            false
          fi
          if [ $? -ne 0 ]; then
              echo "⚠️  Warning: pip setup encountered an error."
          elif [ "$FRESH_ENV" = true ]; then
              package_count=$(pip list --format=freeze | wc -l)
              echo "✅ $package_count packages ready."
          fi
          # Check if numpy is properly installed
          if ! python -c "import numpy" 2>/dev/null; then
            echo "❌ Error: numpy could not be imported. Check your installation."
          fi
          # Add convenience scripts to PATH
          export PATH="$VIRTUAL_ENV/bin:$PATH"
          # OUTSIDE THE THRESHOLD BY DESIGN -- these three run on BOTH sides:
          #   copy_notebook_if_needed -- notebooks on disk are a deliverable of
          #     the flake, not of the server. Idempotent, cheap, and a door-2
          #     user who later runs `python server.py` should find them there.
          #   pkill -- entering `nix develop` has ALWAYS killed a running
          #     server. Door 2 keeps that promise instead of inventing a new
          #     one, so a later `python server.py` finds :5001 free.
          #   git pull -- the `dev` shell skips gitUpdateLogic entirely, so
          #     this bare pull is dev's ONLY update path. Inside the branch, a
          #     habitual door-2 user would silently drift from upstream and
          #     the magic cookie's forever-forward promise would rot.
          copy_notebook_if_needed
          # ONE WORKSHOP AT A TIME, SAID OUT LOUD (2026-08-04). This kill has
          # always been unconditional and silent, and it is PATTERN-based, so
          # entering ANY whitelabeled workshop stops the server running in EVERY
          # other one -- ports 5001 and 8888 are global. That means the
          # one-at-a-time rule is already enforced as PHYSICS and needs no policy
          # added to it. What was missing was the RECEIPT: a newcomer with two
          # workshops watched one window's server die for no stated reason, which
          # is indistinguishable from a crash. Speak only when there WAS a kill,
          # so a single-workshop user never sees this line at all.
          if pkill -f "python server.py"; then
            echo "🛑 Stopped a Pipulate server that was already running (ports 5001/8888 are shared -- one workshop at a time)."
          fi
          git pull --quiet
          # THE THRESHOLD: two doors, asked BEFORE anything starts.
          #
          # boot_menu.py speaks ONLY through its exit code -- 0 start the
          # app, 10 stay in the shell. Nothing here parses its stdout, so no
          # capture pipe can ever be held open by it (the rgx/xclip deadlock
          # is the conviction). That also makes the renderer swappable: a
          # Textual boot_menu.py can replace the stdlib/Rich one and this
          # branch never learns the difference.
          #
          # FALL-THROUGH GUARANTEE: if scripts/boot_menu.py is absent -- an
          # older checkout, a partial clone, a hand-deleted file -- the flake
          # behaves EXACTLY as it did before the menu existed. The flake must
          # never depend on a file that might not have landed.
          BOOT_CHOICE=0
          if [ -f scripts/boot_menu.py ]; then
            python scripts/boot_menu.py
            BOOT_CHOICE=$?
          fi
          if [ "$BOOT_CHOICE" -eq 10 ]; then
            # DOOR 2 -- nothing starts. runScript is EXECUTED (named on its
            # own line in each shellHook), never sourced, so exiting here
            # ends this child process and drops the parent into its
            # interactive prompt. That is the same path door 2 already took
            # under the tail placement, witnessed 2026-07-23 landing at
            # `(nix) pipulate $`. Exiting BEFORE the JupyterLab launch is
            # what makes the quiet workshop quiet: no tmux session, no TTS
            # greeting, no 30-second readiness poll, and -- the visible bug
            # this fixes -- no backgrounded browser subshell spraying dots
            # over the prompt and then announcing that a server nobody
            # authorized failed to start.
            exit 0
          fi
          # DOOR 3 -- the Pipulate tab (2026-09-03). Same servers as door 1,
          # opposite tab. It assigns the two names the runtime tab shadows
          # below already read, so the shadows need no new branch and the
          # .onboarded gate is simply not consulted on this path. A typed
          # env var loses to a pressed key here, on purpose: the door is
          # the explicit choice. If boot_menu.py predates door 3 it never
          # returns 11, and this block is inert.
          if [ "$BOOT_CHOICE" -eq 11 ]; then
            PIPULATE_OPEN_JUPYTER=false
            PIPULATE_OPEN_FASTHTML=true
          fi
          # DOOR 1 ONLY: the banner, moved down from above the threshold on
          # 2026-08-25. Everything below this line runs only when the human
          # chose to start the app -- or when boot_menu.py is absent and the
          # FALL-THROUGH GUARANTEE puts us on the pre-menu path, where the
          # banner printed unconditionally anyway. The full version string
          # with its description rides here rather than in the readings line
          # above, because this is the one surface whose entire job is to name
          # the thing that is starting.
          figlet "$PROPER_APP_NAME"
          echo "Version: ${version}"
          # THE TAB KNOBS MOVE TO RUNTIME (2026-09-03, smallest possible step
          # toward swappable front tabs). autoOpenJupyter / autoOpenFastHTML
          # stay in Nix as the DEFAULTS; an env var typed at the prompt
          # shadows them for one entry, so "Pipulate tab only" is
          #   PIPULATE_OPEN_JUPYTER=false PIPULATE_OPEN_FASTHTML=true nix develop
          # with no flake edit and no new door. Nothing else changes: both
          # servers still start, and with no env vars set the readings are
          # byte-identical to before. A future door 3/4 sets these two
          # variables and nothing below needs to learn about it.
          OPEN_JUPYTER="''${PIPULATE_OPEN_JUPYTER:-${autoOpenJupyter}}"
          OPEN_FASTHTML="''${PIPULATE_OPEN_FASTHTML:-${autoOpenFastHTML}}"
          JUPYTER_BROWSER_FLAG=""
          if [ "$OPEN_JUPYTER" != "true" ]; then JUPYTER_BROWSER_FLAG="--no-browser"; fi
          # Automatically start JupyterLab in background and server in foreground
          # Start JupyterLab in a tmux session
          # NOTE: kill and launch stay PAIRED inside the branch. Splitting
          # them (kill outside, launch inside) would murder another
          # terminal's JupyterLab every time someone picked door 2.
          tmux kill-session -t jupyter 2>/dev/null || true
          # Start JupyterLab with error logging
          tmux new-session -d -s jupyter "source .venv/bin/activate && jupyter lab ${jupyterStartupNotebook} $JUPYTER_BROWSER_FLAG --workspace=\$JUPYTER_WORKSPACE_NAME --NotebookApp.token=\"\" --NotebookApp.password=\"\" --NotebookApp.disable_check_xsrf=True 2>&1 | tee /tmp/jupyter-startup.log"
          sleep 2

          # 🗣️ THE UNIFIED VOICE TRIGGER (Context-Aware)
          if [ -f Notebooks/data/.onboarded ]; then
            python -c "import logging; logging.getLogger('piper').setLevel(logging.ERROR); from imports.voice_synthesis import chip_voice_system as cvs; cvs.speak_text('Welcome back to the workshop. JupyterLab will be waiting in the first tab.')" > /dev/null 2>&1 &
          else
            if [[ "$(uname -s)" == "Darwin" ]]; then
              CLOSE_CMD="Command W"
            else
              CLOSE_CMD="clicking the X"
            fi
            TTS_DIR_NAME=$(basename "$PWD")
            TTS_MSG="Pipulate is installed. Starting JupyterLab and the server. To quit when you are done, forcibly close this terminal window using $CLOSE_CMD. To run it again later, open a new terminal, type C, D, space, $TTS_DIR_NAME, hit enter, then type nix develop. JupyterLab will appear first. Completing the onboarding will unlock the main application tab. Get ready to hit Shift Enter all the way down."
            python -c "import logging; logging.getLogger('piper').setLevel(logging.ERROR); from imports.voice_synthesis import chip_voice_system as cvs; cvs.speak_text('$TTS_MSG')" > /dev/null 2>&1 &
          fi

          JUPYTER_STARTED=false
          for i in {1..30}; do
            if curl -s http://localhost:8888 > /dev/null 2>&1; then
              JUPYTER_STARTED=true
              echo ""
              echo "✅ JupyterLab is ready:"
              echo "   http://localhost:8888/lab/tree/Notebooks/Onboarding.ipynb"
              echo ""
              echo "   Run the notebook top-to-bottom with Shift+Enter."
              echo "   Completing onboarding unlocks the Pipulate app:"
              echo "   http://localhost:5001"
              echo ""
              break
            fi
            sleep 1
          done
          if [ "$JUPYTER_STARTED" = false ]; then
            echo "❌ JupyterLab failed to start within 30 seconds."
            if [ -f /tmp/jupyter-startup.log ]; then
              tail -20 /tmp/jupyter-startup.log | sed 's/^/    /'
            fi
            echo "   tmux attach -t jupyter  # to see full logs"
            echo
          fi
          # Open FastHTML in the browser
          (
            # Wait for server to be ready before opening browser
            echo "Waiting for $APP_NAME server to start (checking http://localhost:5001)..."
            SERVER_STARTED=false
            for i in {1..30}; do
              if curl -s http://localhost:5001 > /dev/null 2>&1; then
                echo "✅ $APP_NAME server is ready at http://localhost:5001!"
                SERVER_STARTED=true
                break
              fi
              sleep 1
              echo -n "."
            done
            if [ "$SERVER_STARTED" = true ]; then
              # EXPLICIT-FALSE WINS (2026-09-11): PIPULATE_OPEN_FASTHTML=false
              # used to lose to the onboarded-marker fallback below, so an
              # already-onboarded caller (autognome.py, every run) could never
              # actually suppress this auto-open -- the marker file exists
              # after the first successful onboarding and stays forever.
              # Checking for the explicit "false" first lets a caller that
              # wants to own the browser-open decision itself (see
              # autognome.py's single-actor browser-open block) actually do so.
              if [ "$OPEN_FASTHTML" = "false" ]; then
                echo
                echo "✅ Pipulate server is running at http://localhost:5001 (auto-open suppressed)"
              elif [ "$OPEN_FASTHTML" = "true" ] || [ -f Notebooks/data/.onboarded ]; then
                if [ "${fastHtmlOpenDelay}" -gt 0 ]; then
                  echo "Delaying FastHTML tab by ${fastHtmlOpenDelay} seconds..."
                  sleep ${fastHtmlOpenDelay}
                fi
                if command -v xdg-open >/dev/null 2>&1; then
                  xdg-open http://localhost:5001 >/dev/null 2>&1 &
                elif command -v open >/dev/null 2>&1; then
                  open http://localhost:5001 >/dev/null 2>&1 &
                fi
              else
                echo
                echo "✅ Pipulate server is running at http://localhost:5001"
                echo "   Finish the Onboarding notebook to unlock it automatically next time."
              fi
            else
              echo
              echo "⚠️  Server didn't start within 30 seconds, but continuing..."
            fi
          ) &
          # Run server in foreground
          python server.py
        '';
        # Logic for installing all Python packages
        pythonInstallLogic = ''
          # Activate the virtual environment to ensure commands run in the correct context
          source .venv/bin/activate
          # Install all dependencies from requirements.txt
          uv pip install -r requirements.txt --quiet
          # Install the local project in editable mode so it's importable
          uv pip install -e . --no-deps --quiet
        '';
        # --- REFACTORED SHELL LOGIC ---
        # Logic for setting up Python venv, PATH, etc.
        pythonSetupLogic = ''
          # Set up the Python virtual environment with explicit Python 3.12 isolation
          test -d .venv || ${pkgs.python312}/bin/python -m venv .venv --clear
          export VIRTUAL_ENV="$(pwd)/.venv"
          export PATH="$VIRTUAL_ENV/bin:$PATH"
          # Purge wheel-installed ruff binary so native pkgs.ruff on PATH is used on NixOS
          rm -f .venv/bin/ruff 2>/dev/null || true
          # Prioritize Python 3.12 libraries first to avoid version conflicts
          export LD_LIBRARY_PATH=${pkgs.python312}/lib:${pkgs.lib.makeLibraryPath commonPackages}:$LD_LIBRARY_PATH
          unset PYTHONPATH
          # --- JupyterLab Local Configuration ---
          export JUPYTER_CONFIG_DIR="$(pwd)/.jupyter"
          export JUPYTER_WORKSPACE_NAME="${jupyterWorkspaceName}"
        '';
        # Logic for the "Magic Cookie" git transformation and auto-updates
        gitUpdateLogic = ''
          # MAGIC COOKIE TRANSFORMATION
          if [ ! -d .git ]; then
            # QUIET TRANSFORM (2026-09-14, the first Mac install from npvg.org).
            # This branch printed four announcements and git clone printed
            # seven progress lines, and none of the eleven discriminated
            # anything: a clone that fails prints its own fatal, and the one
            # verdict line at the end says what happened and where the
            # pre-transform files went. The failure branch is untouched.
            TEMP_DIR=$(mktemp -d)
            if git clone --quiet --depth=1 https://github.com/pipulate/pipulate.git "$TEMP_DIR"; then
              if [ -f whitelabel.txt ]; then cp whitelabel.txt "$TEMP_DIR/"; fi
              if [ -d .ssh ]; then
                mkdir -p "$TEMP_DIR/.ssh"
                cp -r .ssh/* "$TEMP_DIR/.ssh/"
                chmod 600 "$TEMP_DIR/.ssh/rot" 2>/dev/null || true
              fi
              if [ -d .venv ]; then
                cp -r .venv "$TEMP_DIR/"
              fi
              BACKUP_DIR=$(mktemp -d)
              cp -r . "$BACKUP_DIR/"
              find . -maxdepth 1 -not -path "./.*" -exec rm -rf {} \; 2>/dev/null || true
              cp -r "$TEMP_DIR/." .
              rm -rf "$TEMP_DIR"
              echo "✅ Transformed into a git repository (pre-transform files backed up to $BACKUP_DIR)."
            else
              echo "❌ Error: Failed to clone repository."
            fi
          fi
          # Auto-update with the EXACT-OBJECT STASH CONTRACT (banked 2026-07-18).
          # THREE STATE CLASSES:
          #   1. Upstream substrate — tracked files, replaceable only by ff-pull.
          #   2. User overlay — .jupyter/lab/user-settings/ rides the exact-stash
          #      lane below; durable user state (~/.config/pipulate, Playground,
          #      .env, whitelabel.txt, .ssh) lives outside the substrate and is
          #      never touched by this block.
          #   3. Disposable workspace — gitignored caches/artifacts; ignored here.
          if [ -d .git ]; then
            # THE ANNOUNCEMENT IS NOT A READING (2026-09-05, first car of the
            # quieting ride). The echo that stood here printed one identical
            # line in every world -- fetch about to succeed, fetch about to
            # fail, tree about to be found dirty -- so it discriminated
            # nothing. The verdicts below already do: "Already up to date."
            # and "Updates found" are readings of LOCAL against REMOTE, and a
            # failed fetch prints its own fatal. Cut the announcement, keep
            # the verdicts.
            # THE STAT-CACHE REFRESH (2026-08-04, first-contact convicted on two
            # consecutive Darwin installs). git diff-index decides from the
            # index's CACHED STAT DATA -- dev, inode, mtime, size -- and the
            # magic cookie's `cp -r "$TEMP_DIR/." .` above hands every tracked
            # file a new inode, a new device, and a new mtime while carrying the
            # clone's index along untouched. A tree byte-identical to HEAD
            # therefore reports dirty, so this gate fired seconds after
            # "Successfully transformed into git repository", telling a newcomer
            # to commit or stash work they had not done.
            # ELIMINATION, NOT GUESSWORK: `git status --porcelain` on that same
            # Mac tree printed `?? .ssh/` and nothing else, which kills content
            # drift, mode drift and symlink drift (all three survive a refresh)
            # and kills the nbstripout theory twice over -- every .gitattributes
            # line is commented out, and filter.nbstripout.clean is not
            # configured until miscSetupLogic, which runs AFTER this block.
            # Stale stat data is the only survivor, and status refreshes the
            # index as a side effect, which is why the false positive had always
            # healed by the time a human could look at it.
            # --refresh re-stats and clears ONLY the stale entries: a genuinely
            # modified file still reports dirty, so halt-don't-destroy is
            # unchanged. -q continues instead of erroring when paths need
            # updating, and the redirect makes a corrupt .git fail OPEN to the
            # exact pre-refresh behavior. A warning firing on every first
            # contact is the RETIRE-THE-CANARY failure: it teaches the reader to
            # skip warnings before they have ever read a true one.
            git update-index -q --refresh 2>/dev/null || true
            # THE HALT-DON'T-DESTROY GATE: tracked local modifications formerly
            # met `git reset --hard HEAD` before anything was preserved. Now a
            # dirty tree (outside the Jupyter overlay path) PAUSES the automatic
            # update. A dirty tree costs a skipped update, never user work.
            if ! git diff-index --quiet HEAD -- . ':!.jupyter/lab/user-settings'; then
              echo "⚠️  Local modifications detected. Skipping automatic update to protect your work."
              echo "   Commit, stash, or revert them, then re-enter nix develop to update."
            else
              # NO ANNOUNCEMENT BEFORE THE PUSH (2026-09-05, discharging the
              # 2026-08-04 TODO): the push below may stash nothing, and a line
              # naming an act no code performed fails the ATTRIBUTED-VOICE
              # mechanical test at the top of every first-contact transcript.
              # The restore branch below already speaks, and only when a stash
              # actually happened.
              # EXACT-OBJECT CAPTURE: compare refs/stash before and after the
              # push so we only ever act on the stash THIS run created. A no-op
              # push leaves PIPULATE_STASH empty; pre-existing stashes are
              # never applied, never dropped.
              PRE_STASH=$(git rev-parse -q --verify refs/stash || true)
              git stash push --quiet --include-untracked --message "Auto-stash JupyterLab settings" -- .jupyter/lab/user-settings/ 2>/dev/null || true
              POST_STASH=$(git rev-parse -q --verify refs/stash || true)
              PIPULATE_STASH=""
              if [ -n "$POST_STASH" ] && [ "$POST_STASH" != "$PRE_STASH" ]; then
                PIPULATE_STASH="$POST_STASH"
              fi
              # --quiet: the fetch summary (the From line and the branch
              # arrow) narrated the ordinary case to stderr on every entry.
              # It silences the summary and never the failure: a dead network
              # still prints its fatal. The Rule of Silence, applied to a
              # subprocess rather than to our own echo.
              git fetch --quiet origin main
              LOCAL=$(git rev-parse HEAD)
              REMOTE=$(git rev-parse origin/main)
              CURRENT_BRANCH=$(git branch --show-current)
              if [ "$LOCAL" != "$REMOTE" ]; then
                if [ "$CURRENT_BRANCH" = "main" ]; then
                  echo "Updates found. Pulling latest changes..."
                  git pull --ff-only origin main
                  echo "Update complete!"
                else
                  echo "Updates available on main branch."
                fi
              else
                echo "Already up to date."
              fi
              # EXACT-OBJECT RESTORATION: apply and drop ONLY the SHA captured
              # above. On conflict the stash is KEPT and its SHA printed —
              # there is no destruction path in this branch.
              if [ -n "$PIPULATE_STASH" ]; then
                echo "Restoring local JupyterLab settings..."
                if ! git stash apply --quiet "$PIPULATE_STASH" 2>/dev/null; then
                  echo "⚠️ WARNING: Your local JupyterLab settings conflicted with an update."
                  echo "   They are preserved in stash $PIPULATE_STASH — recover with:"
                  echo "   git stash apply $PIPULATE_STASH"
                  git checkout HEAD -- .jupyter/lab/user-settings/ 2>/dev/null || true
                else
                  PIPULATE_STASH_NAME=$(git stash list --format='%H %gd' | awk -v sha="$PIPULATE_STASH" '$1==sha{print $2; exit}')
                  if [ -n "$PIPULATE_STASH_NAME" ]; then
                    git stash drop --quiet "$PIPULATE_STASH_NAME" 2>/dev/null || true
                  fi
                fi
              fi
            fi
          fi
        '';
        # Miscellaneous setup logic for aliases, CUDA, SSH, etc.
        miscSetupLogic = ''
          export PIPULATE_ROOT="$(pwd)" # Capture the absolute path to the project root
          # THE VAULT: where `warm` parks paste-kind secrets -- 0600, beside the
          # wallet, outside the repo, outside git. Sourced FIRST so the per-install
          # repo .env below still wins: global vault, then local specifics.
          # CONVICTED 2026-07-23: warm wrote SLACK_USER_TOKEN here, the offline
          # scoreboard read the file back and reported `filled`, and every
          # connector's os.getenv saw nothing -- because NOTHING sourced it. Two
          # boards, one wallet, opposite answers. The path honors PIPULATE_DOTENV
          # exactly as wallet.py does, so the writer and the reader can never
          # drift onto different files.
          VAULT_ENV="''${PIPULATE_DOTENV:-$HOME/.config/pipulate/.env}"
          if [ -f "$VAULT_ENV" ]; then
            set -a
            source "$VAULT_ENV"
            set +a
          fi
          # Auto-load .env if present (keeps secrets out of the shell hook itself)
          if [ -f "$PIPULATE_ROOT/.env" ]; then
            set -a
            source "$PIPULATE_ROOT/.env"
            set +a
          fi
          # THE WALLET HYDRATOR: export non-secret defaults from the wallet
          # (~/.config/pipulate/connectors.json). Names/paths/defaults only —
          # never secret values. Precedence preserved: anything already set
          # (real env or the .env block above) is NEVER overwritten; only
          # genuinely unset vars hydrate from each connector's defaults block.
          WALLET_FILE="$HOME/.config/pipulate/connectors.json"
          if [ -f "$WALLET_FILE" ] && command -v jq >/dev/null 2>&1; then
            while IFS='=' read -r wallet_key wallet_val; do
              [ -n "$wallet_key" ] || continue
              if ! printenv "$wallet_key" >/dev/null 2>&1; then
                export "$wallet_key=$wallet_val"
              fi
            done < <(jq -r 'to_entries[] | select(.value|type=="object") | (.value.defaults // {}) | to_entries[] | "\(.key)=\(.value)"' "$WALLET_FILE" 2>/dev/null)
          fi
          # THE ACETATE OVERLAY: Force Neovim to use the embedded cognitive blueprint
          export VIMINIT="luafile $PIPULATE_ROOT/init.lua"
          # Set up nbstripout git filter
          if [ ! -f .gitattributes ]; then
            echo "*.ipynb filter=nbstripout" > .gitattributes
          fi
          # THE .git GUARD IS FIRST-CONTACT HYGIENE, not defensiveness. A
          # magic-cookie install is deliberately NOT a git repository yet -- the
          # transformation fires on the first plain `nix develop` -- so this
          # line printed a red "fatal: --local can only be used inside a git
          # repository" in the middle of a stranger's very first install,
          # witnessed 2026-08-01 in the install-only lane. Harmless (the
          # shellHook does not set -e) and therefore worse than a real error:
          # it is noise that looks like failure at the exact moment the reader
          # has no way to judge. The pre-commit install below was already
          # guarded; this line was missed.
          if [ -d .git ]; then
            git config --local filter.nbstripout.clean "nbstripout"
          fi
          # THE COMMIT AIRLOCK: install the client-identity denylist guard.
          # Hook logic is versioned in scripts/git_hooks/pre-commit; patterns
          # live OUTSIDE the repo (~/.config/pipulate/commit_denylist.txt) so
          # the denylist itself can never leak. No denylist file = no-op.
          if [ -d .git ] && [ -f "$PIPULATE_ROOT/scripts/git_hooks/pre-commit" ]; then
            mkdir -p .git/hooks
            cp "$PIPULATE_ROOT/scripts/git_hooks/pre-commit" .git/hooks/pre-commit
            chmod +x .git/hooks/pre-commit
          fi
          # Set EFFECTIVE_OS for browser automation scripts
          if [[ "$(uname -s)" == "Darwin" ]]; then export EFFECTIVE_OS="darwin"; else export EFFECTIVE_OS="linux"; fi
          # ── THE THREE BUCKETS (flat siblings under Notebooks/) ───────
          # Named ONCE, here. Every other mention of these folders in this
          # repo defers to this block; if one of them disagrees, this one is
          # right and the other one is a bug.
          #
          #   canon     Advanced_Notebooks/  Educational_Notebooks/  imports/
          #             delivered by runScript's copy-if-absent loop: your
          #             edits survive, and upstream updates do not arrive.
          #   personal  Playground/  Client_Work/  Deliverables/
          #             gitignored. NOTHING here is ever shared.
          #   shared    Shared/
          #             gitignored. Drag work here to hand it to a teammate.
          #             One folder per person -- Shared/<name>/ -- so two
          #             writers can never collide and nobody needs git.
          #
          # WHY "Shared" AND NOT "Share": the naming test is spoken, not
          # written. "Go to the shared folder." "Which one?" "The one called
          # Shared." Share/, Collaborators/, and a nested Workshop/ all lose
          # that test. This is a chiral choice, not a converged one -- both
          # spellings work and the cost is being locked out of the twin.
          # It is locked now. Do not re-litigate it; rename it if it hurts.
          #
          # CREATED HERE, in miscSetupLogic, because this is the only logic
          # that runs in ALL THREE shells. runScript -- which writes
          # Playground's WELCOME.md -- is skipped entirely by .#quiet, so a
          # folder created there is invisible to the one lane that agents and
          # scripts actually live in. That is SHELL-LANE FINDING (a) applied
          # instead of merely noted.
          #
          # PLAYGROUND'S mkdir MOVED HERE 2026-08-07. It was born in runScript,
          # so under .#quiet the folder did not exist at all -- the exact defect
          # the paragraph above describes, sitting one directory over from the
          # fix that names it. Two authorities for one tier, one of them blind
          # to the lane agents and scripts actually live in.
          # THE FILESYSTEM CANNOT WITNESS THIS on a machine that has ever
          # entered the default shell: the folder is already there, so `test -d`
          # prints the same answer in both worlds. The straddle reads the
          # GENERATED HOOK TEXT instead (nix eval on devShells.<sys>.quiet).
          mkdir -p "$PIPULATE_ROOT/Notebooks/Playground"
          mkdir -p "$PIPULATE_ROOT/Notebooks/Shared"
          # ONE printf, NEVER a heredoc. A cat-heredoc here broke nix develop on
          # main for every user on 2026-08-05: this logic is interpolated into
          # shellHook, the terminator lost its column-0 alignment, and bash
          # swallowed the remaining ~790 lines. printf has no terminator to lose.
          # TWO EDITING HAZARDS, both structural: two adjacent single quotes end
          # the Nix indented string, and a dollar-brace starts an interpolation.
          # Neither appears below. A lone backslash passes through literally --
          # same as the PS1 line beneath this block -- so bash printf does the
          # newline work.
          if [ ! -f "$PIPULATE_ROOT/Notebooks/Shared/README.md" ]; then
            printf "%s\n" "# Shared" "" "This is the one folder you use on purpose to hand work to someone else." "Everything else under Notebooks/ is either yours alone or delivered to you." "Nothing here is private: assume a teammate will read it." "" "Make a folder with your own name, and work inside it:" "" "    mkdir -p Notebooks/Shared/yourname" "" "One folder per person means two people can drop work at the same moment and" "never collide, so there is nothing to merge and no git to learn." "" "Pipulate git ignores this whole folder. To back yours up, put your own git" "repository inside your own subfolder; it will not fight with anything above." > "$PIPULATE_ROOT/Notebooks/Shared/README.md"
          fi
          # Clean up the prompt to remove Nix's redundant prefixes and Mac's long hostname
          export PS1="\[\033[1;32m\](nix)\[\033[0m\] \[\033[1;34m\]\W\[\033[0m\] $ "
          # Shadow the nix CLI for two reasons, both only relevant *inside* an
          # active dev shell (this function simply does not exist out in (sys),
          # so its mere presence proves we are already in the room):
          #
          # 1. rpath fix: the shell's LD_LIBRARY_PATH front-loads
          #    python312/commonPackages libs that the nix binary itself can't
          #    load. Clearing it for just this call restores nix's own rpath
          #    without touching the shell env.
          # 2. Gentle anti-nesting nudge: a *bare* `nix develop` typed in here is
          #    almost always a newcomer reflexively trying to "restart" after
          #    Ctrl+C'ing the server. They do not need a nested room — they need
          #    `python server.py`. Redirect them kindly. Any nix call WITH args
          #    (e.g. `nix develop .#quiet`, `nix flake check`) still passes
          #    straight through with the rpath fix, so power use is untouched.
          nix() {
            if [ "$1" = "develop" ] && [ "$#" -eq 1 ]; then
              echo "🟢 You are already inside the Pipulate Nix shell — no need to run 'nix develop' again."
              echo "   • Restart the server after Ctrl+C:  python server.py"
              echo "   • Leave this environment entirely:  exit"
              return 0
            fi
            LD_LIBRARY_PATH="" command nix "$@"
          }
          # Add aliases
          # d(): READ-ONLY, always -- a probe that mutates the index is not
          # a probe. The diff shows tracked changes; untracked files are
          # STRUCTURALLY INVISIBLE to git diff, so a WRITE_FILE car would
          # land a new file and `d` printed nothing at all -- output
          # identical to "no change landed," which is the discrimination
          # question failing in the daily driver. List them by name instead
          # and stage nothing.
          d() {
            git --no-pager diff
            local untracked
            untracked=$(git ls-files --others --exclude-standard)
            if [ -n "$untracked" ]; then
              echo ""
              echo "--- UNTRACKED (invisible to the diff above; m will stage these) ---"
              printf '%s\n' "$untracked" | sed 's/^/  + /'
            fi
          }
          alias gdiff='git --no-pager diff --no-textconv'
          alias nixops='(cd "$PIPULATE_ROOT" && ./nixops.sh)'
          alias gitops='(cd ~/repos/trimnoir && git commit --allow-empty -m "retry" && git push)'
          alias force='(cd ~/repos/trimnoir && git commit --allow-empty -m "retry" && git push)'
          alias isnix="if [ -n \"$IN_NIX_SHELL\" ]; then echo \"✓ In Nix shell v${version}\"; else echo \"✗ Not in Nix shell\"; fi"
          # THE SECOND DOOR, SPLIT IN TWO (2026-08-25). One word was doing two
          # unrelated jobs and nothing about the word said so: bare `mcp`
          # listed CONNECTORS that pull material IN, while `mcp <tool>`
          # dispatched a REGISTRY TOOL. Worse, `mcp` is the NAME OF A FILE --
          # scripts/connectors/mcp.py, the one thing here that genuinely IS
          # MCP -- and that file could not be reached by its own name because
          # the roster had taken it. Three words now, each of whose bare and
          # argument forms are about the same thing:
          #
          #   sources        the sources you can name (the roster)
          #   tools          the registry tools you can call
          #   tools <name>   call one
          #   mcp <server>   the real Streamable-HTTP client (aliased below)
          #
          # Discharges the CONNECTOR ALIAS TRANSITION earmark, whose text asked
          # only that the roster be renamed so `mcp` came free. `sources` beats
          # that earmark's own `connect` / `pipe` / `warp` for one reason: it
          # names the OUTPUT CLASS rather than an action the command does not
          # perform. The roster connects nothing; `warm` does.
          #
          # FALL-THROUGH GUARANTEE, and it now REFUSES instead of substituting:
          # if the roster file has not landed, say so in one line. The old
          # spelling fell through to `cli.py call` with no arguments, which
          # answered a DIFFERENT QUESTION with an argparse error. A shell must
          # never depend on a file that might not be there, and it must never
          # quietly answer something else when that file is missing.
          #
          # FUNCTIONS, NOT ALIASES (THE THREE-TIER AMENDMENT): `tools` needs a
          # branch, and both are typed by a human and never echoed as a `!`
          # probe, so neither needs to be a packaged derivation.
          sources() {
            if [ -f "$PIPULATE_ROOT/scripts/sources_menu.py" ]; then
              "$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/sources_menu.py"
            else
              echo "sources: scripts/sources_menu.py has not landed in this checkout."
            fi
          }
          tools() {
            if [ "$#" -eq 0 ]; then
              (cd "$PIPULATE_ROOT" && .venv/bin/python cli.py mcp-discover)
            else
              (cd "$PIPULATE_ROOT" && .venv/bin/python cli.py call "$@")
            fi
          }
          # THE RECALL WORD. The door-two list prints ONCE, at the moment of
          # choice, and then scrolls away under whatever the human does next.
          # `menu` prints it again from the SAME tuple (DOOR_TWO_WORDS in
          # boot_menu.py), so the reminder can never drift from the original.
          #
          # A DISPLAY, NEVER A SECOND THRESHOLD, and the exit code is the whole
          # argument. boot_menu.py FAILS OPEN by design: no tty,
          # PIPULATE_BOOT_MENU=0, or any unexpected exception all return 0,
          # which means START THE APP. That polarity is correct at the
          # threshold, where blocking would strand an unattended nix develop.
          # At a PROMPT it inverts: a menu that branched on exit 0 would start
          # a server every time it ran without a tty -- including inside
          # prompt_foo's `!` executor, where stdout is a pipe, and `pu` would
          # then pkill the running server, start a new one in the foreground,
          # and hold the compile until the 180s process-group kill. So nothing
          # here reads the exit status, and --recall returns before the isatty
          # gate is ever reached. Door 1 already has a word here: `pu`.
          #
          # A FUNCTION, not writeShellScriptBin (THE THREE-TIER AMENDMENT):
          # only a human types this, and no child shell needs to resolve it.
          # That also makes it structurally invisible to the `!` executor, so
          # `type menu` can only ever be witnessed by a human at a real
          # prompt; the straddle reads the generated hook text instead.
          menu() {
            if [ -f "$PIPULATE_ROOT/scripts/boot_menu.py" ]; then
              "$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/boot_menu.py" --recall
            else
              echo "menu: scripts/boot_menu.py has not landed in this checkout."
            fi
          }
          # THE THIRD DOOR: `pu` starts the server door 2 declined to start.
          # Kill-then-start, so it doubles as a restart and never collides on
          # :5001 -- the same pkill runScript has always run on shell entry.
          pu() {
            (
              cd "$PIPULATE_ROOT" || exit 1
              pkill -f "python server.py" || true
              python server.py
            )
          }
          # Bare `pipulate` is the long form of `pu`. WITH arguments it hands
          # off to the real PyPI console script -- `command` bypasses this
          # function -- so `pipulate install`, `pipulate run`, and
          # `pipulate mcp-discover` keep working inside the shell instead of
          # being silently shadowed.
          pipulate() {
            if [ "$#" -eq 0 ]; then
              pu
            else
              command pipulate "$@"
            fi
          }
          # THE CONNECTOR GRAMMAR (idea #7 made literal): tiny Unix commands,
          # one per API, each a self-contained file in scripts/connectors/.
          # Args pass through: `botify org/project`, `confluence ENG`,
          # `gmail <thread_id>`. Interactive-shell only — adhoc.txt `!` lines
          # keep the full `python scripts/connectors/...` spelling because
          # child shells never inherit aliases.
          alias gmail='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/gmail.py"'
          # `email` is the New-B-facing name for the same connector. `gmail`
          # stays, because the filename and the muscle memory both say gmail.
          alias email='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/gmail.py"'
          alias botify='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/botify.py"'
          alias confluence='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/confluence.py"'
          alias gsc='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/gsc.py"'
          alias sheets='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/sheets.py"'
          alias jira='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/jira.py"'
          alias slack='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/slack.py"'
          # `mcp` NOW MEANS THE CLIENT, which is what the file has always been
          # named. Freed 2026-08-25 when the roster became `sources`, and
          # claimed in the SAME car so the word is never a hole. An ALIAS, not
          # a function: nothing branches here, because mcp.py's own bare mode is
          # the branch -- and a bare `mcp` that argparse-exited 2 would have
          # been a worse first keypress than the roster it replaced.
          alias mcp='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/mcp.py"'
          # weblogin <apex-domain>: pop up a visible Chrome on the house
          # persistent profile (data/uc_profiles/default) so persistent
          # scrapes inherit the login. Log in, close the window, done.
          alias weblogin='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/weblogin.py"'
          # mothercat [trail] [--dry-narrate]: ride a validated trail (Car B).
          # Bare rides walk.DEFAULT_TRAIL -- since 2026-08-01 the zero-auth
          # public_walk softball, so the SHORTEST invocation is now the SAFEST.
          # Expert trail, named rather than implied:
          #   mothercat assets/trails/first_context.yaml   (Jira/Botify/Gmail)
          # A path rides that trail; --dry-narrate
          # speaks each stop and opens no browser. A human types it, so an alias
          # is correct (ALIAS-DISPATCH RULE); it does NOT inherit into `!` child
          # shells, exactly like the connector aliases above.
          alias mothercat='"$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/mother_cat.py"'
          # walk [trail]: the SHORT spelling of the ride above. Five rungs, one
          # implementation, so the short form can never be weaker than the long:
          #   bash assets/installer/mck.sh public_walk   implementation-revealing
          #   bash walk public_walk                      repository-facing
          #   bash walk                                  the default is the launcher's
          #   walk public_walk                           this line
          #   walk                                       the teaching surface
          # AN ALIAS, per THE ALIAS-DISPATCH RULE and the mothercat precedent
          # directly above: pure prefix dispatch, no branch, typed only by a
          # human. Nothing invokes it on anyone's behalf, and it is never echoed
          # as a probe -- a bare walk runs a ninety-second spoken rehearsal and
          # then blocks on a terminal, which is an actuator, not a reading.
          # THE ROOT WRAPPER IS THE ONE DELEGATOR. This points at the repo-root
          # walk file rather than at the launcher directly, so rungs 4 and 5 run
          # byte-identical code to rungs 2 and 3 and the launcher path lives in
          # exactly one place. It also means `bash walk` still works for
          # anything that cannot see a shell alias, including a child process --
          # the file covers the tier an alias structurally cannot.
          # NOT scripts/walk.py, which is the non-actuating dry-run PLANNER and
          # shares nothing with this word but four letters.
          alias walk='bash "$PIPULATE_ROOT/walk"'
          # THE CREDENTIAL GAME: bare `warm` is the LIVE red/green board — one
          # bounded API call per enrolled wallet slot, GOLD when every row is
          # green. `warm <slot>` is the fixer for that one credential, and a
          # browser_session slot's fixer IS weblogin.py, so nothing was lost
          # when this word stopped meaning weblogin directly. `weblogin <apex>`
          # is unchanged for anyone who wants the browser and nothing else.
          #
          # A FUNCTION, not an alias: THE ALIAS-DISPATCH RULE says nothing can
          # invoke an alias on a human's behalf, and sources_menu.py's roster
          # names this word to a reader who may reasonably expect it to be
          # reachable.
          warm() {
            if [ "$#" -eq 0 ]; then
              "$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/wallet.py" check
            else
              "$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/connectors/wallet.py" warm "$@"
            fi
          }
          alias vim='nvim'
          alias lsp='ls -d -1 "$PWD"/*'
          alias p='cd "$PIPULATE_ROOT"'
          alias foo='(cd "$PIPULATE_ROOT" && python prompt_foo.py --no-tree)'
          alias fu='(cd "$PIPULATE_ROOT" && python prompt_foo.py)'
          alias default='(cd "$PIPULATE_ROOT" && python prompt_foo.py --chop DEFAULT_CHOP --no-tree)'
          # `u`-twin convention (mirrors foo -> fu): same CHOP, tree + UML
          # restored by dropping --no-tree. Functions (not aliases) so
          # --profile/--reason pass straight through, e.g.
          #   defaultu --profile trusted --reason "Confluence enterprise"
          defaultu() { (cd "$PIPULATE_ROOT" && python prompt_foo.py --chop DEFAULT_CHOP "$@"); }
          ahc() { (cd "$PIPULATE_ROOT" && python prompt_foo.py --chop ADHOC_CHOP --no-tree "$@"); }
          ahcu() { (cd "$PIPULATE_ROOT" && python prompt_foo.py --chop ADHOC_CHOP "$@"); }
          # THE WALK-ROUTER TWIN. Chapter VIII-b says to keep an alternate
          # router selection LOCAL to the compiler invocation and never in the
          # parent shell. That was prose beside a mechanism with nothing
          # gating it, which THE PUBLISH-ROSTER RULE convicts: prose beside a
          # mechanism does not gate the mechanism. Here the selection is local
          # BY CONSTRUCTION, because the assignment prefixes an EXTERNAL
          # command inside a subshell, so no bash mode can leak it upward the
          # way a prefix on a shell function can.
          # WHY IT MATTERS: parse_file_list_from_config exits 1 with ROUTER
          # REFUSED when PIPULATE_ADHOC_FILE is set and the named file is
          # missing or carries no active lines. One stray export therefore
          # breaks every ADHOC_CHOP compile in that shell, ahc and sniff and
          # scrub included, and the walk router does not exist until a walk
          # completes. The refusal is correct and the export is the defect.
          # A FUNCTION, not an alias, per the release conviction of
          # 2026-08-01: an alias body ending in a paren reports a syntax error
          # at the trailing argument the operator typed.
          ahcw() { (cd "$PIPULATE_ROOT" && PIPULATE_ADHOC_FILE="$PIPULATE_ROOT/adhocwalk.txt" python prompt_foo.py --chop ADHOC_CHOP --no-tree "$@"); }
          # THE IDEATION DOOR: `idea` compiles IDEATION_CHOP (the constitution's
          # two forcing-function rules) primed for a 30-and-3 / axis-forcing
          # fan-out turn. A function, not an alias, so --profile/--reason pass
          # straight through, mirroring defaultu/ahc.
          idea() { (cd "$PIPULATE_ROOT" && python prompt_foo.py --chop IDEATION_CHOP --no-tree "$@"); }
          # THE FORGETTING DOOR: `forget` compiles COMPACT_CHOP with its baked
          # COMPACT_PROMPT -- dedupe, fade, graduate, one car per verb -- so
          # "the router feels heavy" is one word at the prompt, the way `brief`
          # and `idea` already are. A function, not an alias, so --profile and
          # --reason pass straight through, mirroring idea/ahc. Typed by a
          # human only: the compile lane witnesses it through the generated
          # hook text, never through `type`.
          forget() { (cd "$PIPULATE_ROOT" && python prompt_foo.py @COMPACT_PROMPT --chop COMPACT_CHOP --no-tree "$@"); }
          alias ahe='(cd "$PIPULATE_ROOT" && nvim "''${PIPULATE_ADHOC_FILE:-adhoc.txt}" foo_files.py)'
          # THE SNIFF DOOR: one word at the prompt puts a wire-truth lens into
          # the next compile. Appends a sigil line to the adhoc overlay, then
          # fires ahc. A FUNCTION because it must call ahc(), itself a function
          # -- ALIAS-DISPATCH RULE. Note this is a DIFFERENT reachability
          # problem from the one postsCommand/rgxCommand solve: those are
          # writeShellScriptBin because CHILD shells must resolve them through
          # PATH. sniff is only ever typed by a human in this shell, so a
          # function is correct -- and a function is also invisible to the `!`
          # executor, which is why nothing here is ever echoed as a probe.
          #
          # Default sigil is % (distill the CACHED ledger). -f writes ! instead
          # (a fresh flight, which RECORDS the ledger). % on a cold cache is a
          # documented miss, not a bug: prompt_foo prints the ledger-miss line
          # and names the ! scrape. So: sniff -f once, sniff freely after.
          #
          # Lines ACCUMULATE on purpose. adhoc.txt is a scratchpad, `ahe` is
          # the pruner, and every sigil line re-fires on every later compile.
          # This function only appends, and prints exactly what it wrote.
          sniff() {
            if [ -z "$PIPULATE_ROOT" ]; then
              echo "sniff: PIPULATE_ROOT is unset -- enter the Pipulate Nix shell first." >&2
              return 1
            fi
            local sigil="%"
            if [ "''${1:-}" = "-f" ]; then
              sigil="!"
              shift
            elif [ "''${1:-}" = "-a" ]; then
              sigil="?"
              shift
            fi
            if [ "$#" -eq 0 ]; then
              echo "Usage: sniff [-f|-a] <domain-or-url>   (% distills the cached ledger; -f flies fresh anonymous; -a flies fresh on weblogin's warmed profile)" >&2
              return 1
            fi
            local url="$1"
            case "$url" in
              http://*|https://*) ;;
              *) url="https://$url" ;;
            esac
            local adhoc="''${PIPULATE_ADHOC_FILE:-$PIPULATE_ROOT/adhoc.txt}"
            # Seam guard: appending to a file whose last byte is not a newline
            # fuses the sigil onto the previous line, and the compiler parses
            # the fusion as one unrunnable path.
            if [ -s "$adhoc" ] && [ -n "$(tail -c 1 "$adhoc")" ]; then
              printf '\n' >> "$adhoc"
            fi
            printf '%s%s\n' "$sigil" "$url" >> "$adhoc"
            echo "sniff: $adhoc <- $sigil$url"
            ahc
          }
          # SNIFF COMPLETION -- INTERACTIVE-ONLY, STRUCTURALLY, AND UNPROBEABLE.
          # A compspec lives in the shell process and has no export form (there
          # is no `export -C`), while the `!` executor spawns a NON-interactive
          # /bin/sh via Popen(shell=True). Any `!` probe of this spec returns
          # the SAME answer whether the spec exists or not -- a false receipt in
          # both directions -- so it is deliberately never echoed into
          # adhoc.txt. The only honest witness is a human pressing Tab.
          #
          # Bare domains only, no scheme: COMP_WORDBREAKS contains ':', so
          # typing "https://exa<TAB>" splits the word and completion cannot see
          # the prefix. sniff() prepends https:// anyway, so bare is both the
          # shorter path and the working one.
          _sniff() {
            local cur cache d domains
            cur="''${COMP_WORDS[COMP_CWORD]}"
            cache="$PIPULATE_ROOT/browser_cache"
            [ -d "$cache" ] || return 0
            domains=""
            for d in "$cache"/*/; do
              [ -d "$d" ] || continue
              d="''${d%/}"
              d="''${d##*/}"
              case "$d" in
                looking_at|automation_recipes|test_rotation_data) continue ;;
              esac
              domains="$domains $d"
            done
            mapfile -t COMPREPLY < <(compgen -W "$domains" -- "$cur")
          }
          complete -F _sniff sniff
          # THE SCRUB DOOR: publish-time twin of sniff. When a compile is
          # BLOCKED because a denylisted client name survived the PII scrub,
          # the compliant fix and the bypass must cost the same keystrokes --
          # otherwise the bypass wins every time, which is exactly how
          # SECRET_TRIPWIRES ended up as [].
          #
          #   scrub                      list the substitutions in force
          #   scrub samplebrand                samplebrand === CLIENT_1  (auto-numbered)
          #   scrub samplebrand SAMPLE_BRAND   samplebrand === SAMPLE_BRAND
          #
          # THIS IS NOT THE DRAFTING LEVER. While writing, you want the real
          # names visible in the payload: `ahc --profile trusted --reason "..."`
          # already does that and always did. scrub is for the ONE compile you
          # publish from.
          #
          # BARE TOKEN, not \b...\b: a bare token neutralises the name whether
          # the left-hand side is treated as a regex or as a literal, and the
          # boundary form only works under one of those. The compiler's block
          # message reports DENYLIST patterns in regex form; no substitution
          # rule has ever been read in a payload, so the safer spelling wins.
          # If a name overmatches, add boundaries by hand to that one line.
          # A FUNCTION, per ALIAS-DISPATCH RULE: it must call ahc(), and like
          # sniff it is therefore invisible to the `!` executor and is never
          # echoed as a probe.
          scrub() {
            if [ -z "$PIPULATE_ROOT" ]; then
              echo "scrub: PIPULATE_ROOT is unset -- enter the Pipulate Nix shell first." >&2
              return 1
            fi
            local subs="''${PIPULATE_PII_FILE:-$HOME/.config/pipulate/pii_substitutions.txt}"
            mkdir -p "$(dirname "$subs")"
            [ -f "$subs" ] || : > "$subs"
            if [ "$#" -eq 0 ]; then
              echo "scrub: $subs"
              grep -v '^[[:space:]]*#' "$subs" | grep -v '^[[:space:]]*$'
              return 0
            fi
            local token="$1"
            if grep -qF "$token ===" "$subs"; then
              echo "scrub: already present -- $token"
            else
              local repl="$2"
              if [ -z "$repl" ]; then
                local n
                n=$(grep -c ' === ' "$subs" 2>/dev/null || true)
                repl="CLIENT_$((n + 1))"
              fi
              # Seam guard, same as sniff: appending to a file whose last byte
              # is not a newline fuses two rules into one unparseable line.
              if [ -s "$subs" ] && [ -n "$(tail -c 1 "$subs")" ]; then
                printf '\n' >> "$subs"
              fi
              printf '%s === %s\n' "$token" "$repl" >> "$subs"
              echo "scrub: $subs <- $token === $repl"
            fi
            ahc
          }
          alias pins='(cd "$PIPULATE_ROOT" && python prompt_foo.py --chop PINNED_CHOP --no-tree)'
          # THE FIRST WISH, RENAMED (2026-08-25). `learn` failed the
          # ATTRIBUTED-VOICE mechanical test: it named an act no code in this
          # pipeline performs. Nobody learns anything -- a payload compiles and
          # a clipboard fills. `brief` names an artifact the command ACTUALLY
          # PRODUCES, which is the whole difference. The obvious objection --
          # that "brief" read bare sounds like "brief me" -- is survivable and
          # `learn` was not: the recipient is under-specified by one word and
          # the card supplies it, whereas "teach me" is wholly false and no
          # card copy repairs it.
          # THE ARTIFACT KEEPS ITS NAME. The command is `brief`; the thing it
          # produces is still The First Wish, which is what INSTALL_CHOP and
          # the seed lane call it. Renaming the artifact too would drag `seed`
          # and SEED_PROMPT into a car that has no business touching them.
          # NO COMPATIBILITY ALIAS: two words for one job is the sibling-.md
          # failure, and `command not found` is a loud wound, not a quiet lie.
          # Compiles the INSTALL_CHOP onboarding context into the clipboard with a
          # self-contained prompt, then tells the human where to paste it.
          brief() {
            (cd "$PIPULATE_ROOT" && python prompt_foo.py \
              "You are Yen Sid-ton, the onboarding wizard for Pipulate. A newcomer wants to install Pipulate for the first time. Your FIRST reply must be short and do four things in order: (1) confirm in one line that you hold the full install map (installer, flake, both Pipulate.com pages); (2) show the one-line install command immediately, since it is identical on every OS; (3) ask exactly one question, which OS they are on, noting it changes only the caveats, never the command; (4) add one line noting the command assumes Nix is already installed, and that a nix command not found response means install Nix first and reopen the terminal. From then on: one step per turn, one question maximum per turn, and every step ends with a visible success checkpoint describing what they should literally see (the one-line environment readings, the three-door menu where they press 1, the figlet banner once the app starts, the JupyterLab URL, the spoken voice greeting) plus the single most likely failure symptom at that step and its fix. Deliver the macOS --impure exception and the reopen-your-terminal-after-installing-Nix requirement at the moment each can bite, never as an upfront lecture. Offer the magic cookie internals (ZIP + ROT13 key, then git transformation and auto-updates inside nix develop) as an optional aside when relevant or when asked, not as mandatory explanation. When both the server and JupyterLab are confirmed running, declare the install banked and teach the re-entry incantation: cd into the install folder, then nix develop. High signal, low noise. Ask them what they see; never assume." \
              --chop INSTALL_CHOP --no-tree --quiet)
            echo ""
            echo "🧞 The First Wish is compiled and sitting in your clipboard."
            echo "   1. Open an AI web chat: Claude, ChatGPT, or Gemini."
            echo "   2. Paste it (Ctrl+V / Cmd+V) and send."
            echo "   3. Tell it your OS. It has the whole install map — ask it anything."
          }
          # THE BOOK SEED: compile the distributable First Wish (SEED_PROMPT +
          # SEED_CHOP) for a stranger WITHOUT the environment. Bare `seed`
          # compiles clipboard + cartridge; `seed -o` also renders
          # first_wish.md for no-execution surfaces. Per the COVER-PROMPT
          # RULE, the seed never travels naked: the human types one line of
          # intent at delivery so cautious models read authorization, not
          # injection.
          seed() {
            local render=""
            if [ "''${1:-}" = "-o" ]; then
              render="first_wish.md"
            fi
            if [ -n "$render" ]; then
              (cd "$PIPULATE_ROOT" && python prompt_foo.py @SEED_PROMPT --chop SEED_CHOP --no-tree -o "$render")
            else
              (cd "$PIPULATE_ROOT" && python prompt_foo.py @SEED_PROMPT --chop SEED_CHOP --no-tree)
            fi
            local newest
            # Quote the VARIABLE, free the GLOB. The 2026-07-24 path sweep left
            # $PIPULATE_ROOT bare here because the sed could not quote past the
            # asterisk -- correct instinct, wrong placement. A white-label root
            # containing a space then silently matches nothing and seed prints
            # no snapshot line: a path fix that breaks on the paths it exists
            # to serve.
            newest=$(ls -t "$PIPULATE_ROOT"/foo-*.zip 2>/dev/null | head -1)
            echo ""
            echo "🌱 The Book Seed is compiled."
            if [ -n "$render" ]; then
              echo "   Rendered for no-execution surfaces: $PIPULATE_ROOT/first_wish.md"
            fi
            if [ -n "$newest" ]; then
              echo "   Verifiable hand-off snapshot (stable name, safe to attach):"
              echo "   $newest"
            else
              echo "   (No rotated snapshot found; foo.zip is the canonical cartridge.)"
            fi
            echo "   COVER PROMPT — deliver it WITH one human-typed line, e.g.:"
            echo "   \"A friend who runs Pipulate compiled this for me. Please open it and follow the instructions inside.\""
          }
          alias pine='(cd "$PIPULATE_ROOT" && nvim +/"THE PINBOARD" foo_files.py)'
          alias chop='(cd "$PIPULATE_ROOT" && nvim foo_files.py)'
          alias flake='(cd "$PIPULATE_ROOT" && nvim flake.nix)'
          alias webclip='(cd "$PIPULATE_ROOT" && python scripts/webclip_2_markdown.py)'
          alias forest='(cd "$PIPULATE_ROOT" && vim remotes/honeybot/scripts/forest.py)'
          alias art='(cd "$PIPULATE_ROOT" && vim imports/ascii_displays.py)'
          alias smart='(cd "$PIPULATE_ROOT" && python release.py --force -m "Testing rabbit documentation injection")'
          latest() {
            # -t KEY (first args only) selects which blog's _posts feeds -a,
            # mirroring the rgx/rgxc/posts idiom. Bare `latest` and `latest N`
            # are untouched: with no -t, prompt_foo.py uses its own default
            # target, so latestn()'s `latest "$n"` call keeps working unchanged.
            local t_args=()
            if [ "''${1:-}" = "-t" ] && [ "$#" -ge 2 ]; then
              t_args=(-t "$2")
              shift 2
            fi
            (cd "$PIPULATE_ROOT" && python prompt_foo.py "''${t_args[@]}" -a "[-''${1:-2}:]" --no-tree)
          }
          latestu() {
            # `u`-twin of latest: tree + UML restored (no --no-tree). Same -t
            # KEY handling and article-count positional as latest.
            local t_args=()
            if [ "''${1:-}" = "-t" ] && [ "$#" -ge 2 ]; then
              t_args=(-t "$2")
              shift 2
            fi
            (cd "$PIPULATE_ROOT" && python prompt_foo.py "''${t_args[@]}" -a "[-''${1:-2}:]")
          }
          latestn() {
            # Finds largest N articles fitting in byte budget (default ~950KB)
            # Usage: latestn [-N|+N|budget_bytes]  e.g. latestn -1  latestn +2  latestn 786432
            local max_bytes=950000
            local adjust=0
            case "''${1:-}" in
              -[0-9]*) adjust="''${1}" ;;
              +[0-9]*) adjust="''${1#+}" ;;
               [0-9]*) max_bytes="''${1}" ;;
            esac
            local n=$(python3 -c "
import os, sys, json
root = os.getcwd()
env = 0
try:
    sys.path.insert(0, root)
    import foo_files
    for line in foo_files.AI_PHOOEY_CHOP.strip().splitlines():
        s = line.strip().split('#')[0].strip()
        if s and ('/' in s or '.' in s) and not s.startswith('!'):
            fp = s if os.path.isabs(s) else os.path.join(root, s)
            if os.path.isfile(fp): env += os.path.getsize(fp)
except: env = 200000
env += 145000  # command outputs, wrappers, diff telemetry
pm = os.path.join(root, 'prompt.md')
if os.path.isfile(pm): env += os.path.getsize(pm)
try:
    cfg = os.path.expanduser('~/.config/pipulate/blogs.json')
    posts = os.path.expanduser(json.load(open(cfg))['1']['path']) if os.path.exists(cfg) else os.path.expanduser('~/repos/trimnoir/_posts')
except: posts = os.path.expanduser('~/repos/trimnoir/_posts')
budget = $max_bytes - env
files = sorted([f for f in os.listdir(posts) if f.endswith('.md') and f[:4].isdigit()], reverse=True)
total = 0; n = 0
for f in files:
    sz = os.path.getsize(os.path.join(posts, f))
    if total + sz > budget: break
    total += sz; n += 1
print(max(1, n))
" 2>/dev/null || echo 5)
            n=$((n + adjust))
            [[ $n -lt 1 ]] && n=1
            echo "📐 Auto-sized to $n most recent articles (budget: $max_bytes bytes)"
            latest "$n"
          }
          slugs() { (cd "$PIPULATE_ROOT" && python scripts/articles/lsa.py -t 1 --slugs "$@" --fmt paths); }
          # slugs-ordered preserves input order for narrative control
          sluggo() { for slug in "$@"; do (cd "$PIPULATE_ROOT" && python scripts/articles/lsa.py -t 1 --match "$slug" --fmt paths); done; }
          # `rgx` and `rgxc` are Nix-packaged commands above, not shell
          # functions, so interactive use and adhoc.txt child shells share one implementation.
          # UNNAMED-ROOT RULE conviction: this invoked release.py through the
          # CWD while `smart` invokes the SAME SCRIPT wrapped in
          # cd "$PIPULATE_ROOT" -- one script, two spellings, one anchored.
          # A FUNCTION, not an alias (ALIAS-DISPATCH sibling, convicted
          # 2026-08-01): the alias body ended in ')', so `release "msg"`
          # expanded to a subshell followed by a bare word and bash reported a
          # syntax error AT THE MESSAGE -- a failure that reads as a quoting
          # mistake in the operator's own typing and is not one. release.py has
          # had -m/--message the whole time and no spelling could reach it.
          release() { (cd "$PIPULATE_ROOT" && python release.py --release --force "$@"); }
          # clear -x: repaint the screen but PRESERVE scrollback, exactly as
          # blast() already does. Plain `clear` (ncurses >= 6.0) emits the E3
          # escape and erases the buffer -- convicted 2026-07-23 when a `g`
          # typed between an ignition and its AFTER tap destroyed the receipts
          # the tap existed to produce. A read-only status check must never be
          # able to delete evidence.
          alias g='clear -x && echo "Blast Radius Check to establish bisection Left-hand Causal Boundary. It is a Popper-thing. Science." && git status'
          m() {
            # THE UNTRACKED-FILE DEBT (banked TODO 2026-07-20, discharged
            # 2026-07-31, receipt-gated): a new file is invisible to
            # `git diff HEAD`, to `git commit -am`, AND to ai.py -- whose
            # get_staged_diff() reads `git diff --staged` FIRST and falls
            # back to bare `git diff`, so an untracked-only change produced
            # an empty diff, an empty message, and an aborted commit. That
            # is why every WRITE_FILE car has needed a hand-typed `git add`
            # between `app` and `m`. Staging FIRST fixes all three at once:
            # the hint detector below sees the new path, ai.py's --staged
            # branch sees real content, and commit -am carries what is
            # already in the index.
            # RISK, named rather than hidden: -A sweeps unrelated work in
            # progress into the commit. The .gitignore and the pre-commit
            # denylist hook are the only fences, and they are the same
            # fences `blast` has always relied on.
            git add -A
            local msg
            # THE INTENT PARAMETER (router-churn edition, 2026-07-17): the
            # alias knows WHY this commit exists, so it says so. A diff that
            # is ONLY foo_files.py is the left-hand blast-radius boundary of
            # a sentinel-bounded AI edit — comment lines toggled to curate
            # the next compile's context, not features added or removed.
            # Detection is deterministic (git diff --name-only); only the
            # prose is delegated, and the hint outranks the model's guess.
            local hint=""
            local changed
            changed=$(git diff HEAD --name-only | sort -u)
            if [ "$changed" = "foo_files.py" ]; then
              hint="This diff touches ONLY foo_files.py, the Prompt Fu context-compiler router. Router edits are routine, near-continuous background churn: lines are commented in and out to select which files enter the next compiled context, and this commit exists solely to set the left-hand boundary (the clean BEFORE state) of a sentinel-bounded AI edit. Do NOT interpret comment toggling, token annotation refresh, or paintbox/stats churn as adding or removing features. The correct message is essentially: chore(router): set AI-edit blast boundary (foo_files.py context curation). Deviate only if the diff plainly shows something beyond router line curation."
            elif printf '%s\n' "$changed" | grep -qx 'foo_files.py'; then
              hint="This diff includes foo_files.py, the context-compiler router, whose comment-toggling churn is routine AI-edit boundary noise. The OTHER changed files are the substance of this commit: describe those. Treat the foo_files.py portion as incidental router curation, never as a feature addition or removal."
            fi
            if [ -n "$hint" ]; then
              msg=$(python "$PIPULATE_ROOT/scripts/ai.py" --auto --format plain --hint "$hint" 2>/dev/null | head -1)
            else
              msg=$(python "$PIPULATE_ROOT/scripts/ai.py" --auto --format plain 2>/dev/null | head -1)
            fi
            if [ -z "$msg" ]; then
              echo "❌ ai.py returned empty message, aborting."
              return 1
            fi
            # THE ERROR-AS-MESSAGE GUARD (convicted 2026-09-05 by git log:
            # de37b466's subject is an Ollama read-timeout error). init.lua's
            # \g already refuses a message matching ^Error:; this is parity,
            # and blast() inherits it because blast() calls m().
            case "$msg" in
              Error:*)
                echo "❌ ai.py returned an error as the message, aborting: $msg"
                return 1 ;;
            esac
            echo "📝 Committing: $msg"
            git commit -am "$msg"
          }
          # THE BLAST RADIUS: commit + push + status in one detonation.
          # Three regimes: dirty tree -> m then push (empty message still
          # aborts everything). Clean tree but AHEAD of remote -> push the
          # accumulated commits, because the blast radius includes local
          # work that never left the machine. Clean and level -> nothing
          # to detonate; report calmly. Safe (and now pleasant) to spam.
          blast() {
            if [ -n "$(git status --porcelain)" ]; then
              m || return 1
            fi
            local ahead
            ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
            if [ "$ahead" -gt 0 ]; then
              echo "🚀 Pushing $ahead commit(s) to remote..."
              git push || return 1
            else
              echo "🧘 Nothing to blast: tree clean, remote current."
            fi
            # clear -x: repaint the screen but PRESERVE scrollback, so the
            # before/after probe evidence survives the detonation and can be
            # copied out afterward. Plain `clear` (ncurses >= 6.0) emits the
            # E3 escape and erases scrollback — shredding the receipts.
            clear -x && echo "$ git status" && git status
          }
          # SPLIT VERDICT, and the two halves need OPPOSITE treatment. `cat
          # patch` is CWD-dependent BY DESIGN -- it reads the patch where you
          # stand, matched with `patch` which writes it where you stand, so the
          # pair agrees wherever you are. The script name is not: its location
          # is a HIDDEN ARGUMENT. Hence a root-anchored path and NOT a cd
          # wrapper -- a wrapper would relocate `cat patch` too and silently
          # break the matched pair. General test: cd-wrapper when the whole
          # command belongs to the repo, anchored path when one named file does.
          alias app='cat patch | python "$PIPULATE_ROOT/apply.py"'
          figurate() {
            local name="''${1:-white_rabbit}"
            # UNNAMED-ROOT RULE conviction 2026-07-24: this resolved the venv
            # interpreter through the CWD and therefore worked only from the
            # repo root. Interpreter anchored, body deliberately untouched --
            # if the -c script also reads relative paths that is a second
            # conviction, and it needs the body in a payload first.
            "$PIPULATE_ROOT/.venv/bin/python" -c "
from pipulate import wand
r = wand.figurate('$name')
print('Name:', r.name)
print('Drift:', r.drift)
print('AI:\n', r.ai)
"
          }
          patronus() {
            local target="''${1:-white_rabbit}"
            "$PIPULATE_ROOT/.venv/bin/python" -c "import os, sys; sys.path.insert(0, os.environ.get('PIPULATE_ROOT', os.getcwd())); from imports.ascii_displays import patronus; target = sys.argv[1] if len(sys.argv) > 1 else 'white_rabbit'; patronus(target)" "$target"
          }
          window() {
            local duration="30"
            if [ "$#" -gt 0 ] && [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
              duration="$1"
              shift
            fi
            if [ "$#" -eq 0 ]; then
              echo "Usage: window [duration] command [args...]"
              return 1
            fi
            "$PIPULATE_ROOT/.venv/bin/python" -c "import os, sys; sys.path.insert(0, os.environ.get('PIPULATE_ROOT', os.getcwd())); from imports.ascii_displays import conjure_window; conjure_window(sys.argv[2:], duration=float(sys.argv[1]))" "$duration" "$@"
          }
          conjure_window() {
            window "$@"
          }
          
          # ---------------------------------------------------------
          # THE SUBSHELL ALIASES (Execute safely from anywhere)
          # ---------------------------------------------------------
          # `posts` is a Nix-packaged command so child shells can resolve it.
          posts2() { posts --reverse "$@"; }
          # `postsc` is likewise Nix-packaged; only the reversed twin needs a
          # function, exactly as with posts2. The reversed twins stay
          # interactive-only on purpose -- a `!` line spells the flag out.
          postsc2() { postsc --reverse "$@"; }
          preview() { (cd "$PIPULATE_ROOT/scripts/articles" && python publishizer.py "$@"); }

          # The true 'publish' command (Atomic Cross-Domain Deployment)
          # It requires a commit message as an argument.
          publish() {
            # 80/20 reboot gate: the first non-flag arg is the commit message; the
            # optional --reboot flag opts into the [5/5] stream.py restart (the
            # ~4-hour memory-leak hygiene purge). Without it a routine publish stops
            # after [4/5], leaving the live stream running untouched.
            #
            # THE SWEEP GATE, AND WHY IDEMPOTENT IS NOT THE SAME AS CHEAP
            # (measured 2026-08-31: ~5 minutes). googledocizer.py's freshness
            # check IS free -- it compares an already-fetched Drive timestamp
            # against a local mtime. What is NOT free is the Local Target Title
            # Contract pass that runs BEFORE it, which markdown-renders every
            # one of ~1,400 articles to HTML and then discards 1,312 of them
            # unread. The API was never the cost; the render was, and it is
            # paid whether or not anything uploads.
            # So the default hands the script ONE file. --latest reads the
            # marker articleizer.py wrote for this target and syncs exactly the
            # post this publish is about. --sweep opts back into the whole
            # corpus for the rare deliberate case (a rendering-pipeline change,
            # a hand-edited OLD post), the same shape gobot's --all already
            # uses. A missing marker is non-fatal: googledocizer exits 1, the
            # guard below warns, and the site still ships.
            local REBOOT=0
            local GDOCS_SCOPE="--latest"
            local MSG=""
            for arg in "$@"; do
              if [ "$arg" = "--reboot" ]; then
                REBOOT=1
              elif [ "$arg" = "--sweep" ]; then
                GDOCS_SCOPE=""
              elif [ -z "$MSG" ]; then
                MSG="$arg"
              fi
            done

            if [ -z "$MSG" ]; then
              echo "❌ Error: Please provide a commit message."
              echo "Usage: publish \"Your commit message here\" [--reboot] [--sweep]"
              return 1
            fi
            
            # The Bounded Context of the Payload
            TARGET_REPO="$HOME/repos/trimnoir"
            
            echo "🚀 [1/5] Payload Delivery: Committing and Pushing $TARGET_REPO..."
            # Execute in a subshell to avoid stranding the user's terminal
            (
                cd "$TARGET_REPO" || exit 1
                git add .
                # THE ALWAYS-FIRES GUARANTEE: a clean tree (e.g. an infra/hook-only
                # change made in the pipulate repo, not trimnoir) means `git commit -am`
                # has nothing to commit and silently no-ops, which means no push, which
                # means the post-receive hook on Honeybot never fires. Fall back to an
                # empty commit so `publish` alone is always sufficient to trigger a deploy.
                if ! git commit -am "$MSG"; then
                    echo "ℹ️  Nothing to commit in $TARGET_REPO; creating empty commit to ring the deploy bell."
                    git commit --allow-empty -m "$MSG"
                fi
                git push
            )
            
            # Check if the subshell push succeeded (which triggers the post-receive hook)
            if [ $? -eq 0 ]; then
                # GOOGLE DOCS SYNC rides here, right after the git payload
                # lands, because it depends only on the local article file(s)
                # already on disk -- not on the Honeybot deploy below.
                # SCOPE COMES FROM THE GATE ABOVE, and the echo prints the
                # resolved value rather than a fixed word, so the receipt can
                # never disagree with what actually ran.
                # Non-fatal by design -- a Drive hiccup (expired OAuth token,
                # network blip) must never block the live site from shipping.
                # Retry by hand with:
                #   python scripts/articles/googledocizer.py -t 1 --yes --latest
                # INTERPRETER ANCHORED (UNNAMED-ROOT RULE): the bare name
                # resolved through PATH, which is only correct while the venv
                # is in front of it. The script path was already anchored one
                # argument to its right; this makes both halves of the line
                # agree.
                echo "🚀 [2/5] Google Docs: Syncing to Drive (scope: ''${GDOCS_SCOPE:-full sweep})..."
                if ! "$PIPULATE_ROOT/.venv/bin/python" "$PIPULATE_ROOT/scripts/articles/googledocizer.py" -t 1 --yes $GDOCS_SCOPE; then
                    echo "⚠️  Google Docs sync failed; continuing deployment anyway."
                fi
                echo "🚀 [3/5] Infrastructure: Synchronizing Server Configurations..."
                # Back in the Pipulate root bounded context
                if [ -f "./nixops.sh" ]; then
                    ./nixops.sh
                    echo "🚀 [4/5] The Capstone: Rebuilding Nginx Routes..."
                    ssh -t mike@192.168.10.100 'sudo cp ~/nixos-config-staged/* /etc/nixos/ && sudo nixos-rebuild switch'
                    if [ "$REBOOT" -ne 1 ]; then
                        echo "⏭️  [5/5] Skipped — stream.py left running. Pass --reboot to force the restart now."
                        echo "✅ Atomic Deployment Complete (stream untouched)."
                        return 0
                    fi
                    echo "🚀 [5/5] Stream Refresh: Restarting Honeybot slideshow child..."
                    ssh mike@192.168.10.100 '
                        pattern="/home/mike/www/mikelev[.]in/scripts/stream[.]py"
                        old_pids=$(pgrep -f -- "$pattern" || true)
                        count=$(printf "%s\n" "$old_pids" | sed "/^$/d" | wc -l)

                        if [ "$count" -eq 0 ]; then
                            echo "⚠️ No stream.py child found; watchdog may already be between cycles."
                            exit 0
                        fi

                        if [ "$count" -gt 1 ]; then
                            echo "⚠️ Found $count stream.py children. Terminating all so the singleton lock can arbitrate."
                            pgrep -af -- "$pattern" || true
                        else
                            echo "   old=$old_pids"
                        fi

                        for old in $old_pids; do
                            kill -TERM "$old" || true
                        done

                        # Surgical sweep to flush any orphaned UI drawing children or text tails
                        pkill -f "/home/mike/www/mikelev[.]in/scripts/logs[.]py" || true
                        # THE SUICIDAL PKILL (convicted 2026-08-05, twice in one
                        # transcript). pkill -f matches the FULL command line, and
                        # the remote shell running this script carries the pattern
                        # in its own argv -- so an unescaped pattern kills the
                        # shell that issued it. The two lines above are protected
                        # by the [.] trick: the regex demands a literal dot that
                        # the argv literal does not contain. This one was missed.
                        # CONSEQUENCE: the ssh session died HERE every time, so
                        # sleep 12, the pgrep re-count, and all three verdict
                        # branches below have NEVER EXECUTED -- an unreachable
                        # verification block, and orphaned tails never reaped.
                        pkill -f "tail -f /var/log/nginx/access[.]log" || true

                        sleep 12

                        new_pids=$(pgrep -f -- "$pattern" || true)
                        new_count=$(printf "%s\n" "$new_pids" | sed "/^$/d" | wc -l)

                        echo "   new_count=$new_count"
                        if [ -n "$new_pids" ]; then
                            printf "%s\n" "$new_pids" | sed "s/^/   new=/"
                        fi

                        if [ "$new_count" -eq 1 ]; then
                            echo "✅ Stream watchdog relaunched exactly one stream.py child."
                        elif [ "$new_count" -gt 1 ]; then
                            echo "⚠️ Duplicate stream.py children remain after restart:"
                            pgrep -af -- "$pattern" || true
                        else
                            echo "⚠️ Stream restart requested, but no new PID was confirmed."
                        fi
                    '
                    echo "✅ Atomic Deployment Complete."
                else
                    echo "⚠️ Warning: nixops.sh not found. Server config sync skipped."
                fi
            else
                echo "❌ Error: Target Git push failed. Deployment halted."
            fi
          }
          if [ "$EFFECTIVE_OS" = "darwin" ]; then
            alias xc='pbcopy <'
            alias xcp='pbcopy'
            alias xv='pbpaste >'
            alias prompt='(cd "$PIPULATE_ROOT" && pbpaste >prompt.md)'
            alias patch='pbpaste >patch'
            # Added macOS equivalents for article creation
            # THE BRIDGE PULL: Reach into the Z640 and suck the bridge file into the Mac clipboard
            alias pull='ssh mike@nixos.local "cat /tmp/clipboard_bridge.txt" | pbcopy && echo "✅ Z640 -> Mac Clipboard"'
            # THE BOOKMARK LOOP ON THE MAC (2026-09-10). NixOS gets `bm` and
            # `bms` from configuration.nix's environment.shellAliases; the Mac
            # has no such thing, so its copies live here, the way `pull` does.
            # Same chain, same script: chrome_windows.py is the DIY lane on
            # darwin (quit refuses while Chrome runs, reopen is a reminder), so
            # `bms` on the Mac is Cmd-Q Chrome, bms, reopen by hand. The nixos
            # checkout is expected at ~/repos/nixos; PIPULATE_NIXOS_REPO moves
            # it. FUNCTIONS, NOT ALIASES: both branch on a missing checkout.
            # TWO CHECKOUTS, TWO CLOCKS (Mac first contact, 2026-09-10): these
            # words live in THIS flake's shell -- enter it from the pipulate
            # checkout, never `nix develop` inside the nixos one, which has no
            # flake and says so -- and they reach across into a sibling repo
            # that nothing pulls for you. The first Mac `bms` found a day-stale
            # nixos checkout: bookmarks_sync.py present, the newer
            # chrome_windows.py not, and python3 said "can't open file". The
            # gate below now names both scripts and the pull that fixes it.
            bm() {
              local repo="''${PIPULATE_NIXOS_REPO:-$HOME/repos/nixos}"
              if [ ! -f "$repo/bookmarks.nix" ]; then
                echo "bm: no bookmarks.nix at $repo (set PIPULATE_NIXOS_REPO)" >&2
                return 1
              fi
              (cd "$repo" && "$(command -v nvim || command -v vim)" bookmarks.nix bookmarks_harvest.md)
            }
            bms() {
              local repo="''${PIPULATE_NIXOS_REPO:-$HOME/repos/nixos}"
              if [ ! -f "$repo/scripts/bookmarks_sync.py" ] || [ ! -f "$repo/scripts/chrome_windows.py" ]; then
                echo "bms: scripts/bookmarks_sync.py or scripts/chrome_windows.py is missing at $repo -- git pull in that checkout, or set PIPULATE_NIXOS_REPO" >&2
                return 1
              fi
              (cd "$repo" && python3 scripts/chrome_windows.py quit && { python3 scripts/bookmarks_sync.py; python3 scripts/chrome_windows.py reopen; })
            }
          else
            alias xc='xclip -selection clipboard <'
            alias xcp='xclip -selection clipboard'
            alias xv='xclip -selection clipboard -o >'
            alias xp='(cd "$PIPULATE_ROOT" && python scripts/xp.py)'
            alias prompt='(cd "$PIPULATE_ROOT" && xclip -selection clipboard -o >prompt.md)'
            alias patch='xclip -selection clipboard -o >patch'
            # Linux subshell aliases
            # write_post: unified, data-driven article intake. The privacy lane
            # now lives in blogs.json ('lane' per target); sanitizer.py resolves
            # it from -t, so the flake no longer hardcodes --public/--private.
            write_post() {
              (cd "$PIPULATE_ROOT/scripts/articles" \
                && xclip -selection clipboard -o >article.txt \
                && python sanitizer.py -t "$1" \
                && python articleizer.py -t "$1")
            }
            alias article='write_post 1'
            alias grim='write_post 3'
            alias bot='write_post 4'
            gobot() {
              # Routine runs sync ONLY the article 'bot' just wrote, via the
              # marker articleizer.py records. Pass --all to force a full
              # directory re-sweep (for global template/pipeline changes).
              local SCOPE="--latest"
              local msg=""
              for arg in "$@"; do
                if [ "$arg" = "--all" ]; then
                  SCOPE=""
                elif [ -z "$msg" ]; then
                  msg="$arg"
                fi
              done
              msg="''${msg:-Update work journal}"
              local BOTIFY_REPO="$HOME/repos/botifyml"
              echo "📚 [1/3] Committing source-of-truth (botifyml)..."
              # THE ALWAYS-FIRES GUARANTEE (gobot edition, retry-convicted
              # 2026-07-17): the commit can already be on disk from a prior
              # run whose Confluence step then failed — the MOST common
              # reason to re-run gobot. A clean tree made `git commit -am`
              # exit nonzero and `|| return 1` aborted BEFORE shards and
              # Confluence. Fall through instead: skip the commit, still
              # push (no-op when level), and continue the pipeline.
              (
                cd "$BOTIFY_REPO" || exit 1
                git add .
                if ! git commit -am "$msg"; then
                  echo "ℹ️  Nothing to commit in botifyml; continuing to shards + Confluence."
                fi
                git push
              ) || return 1
              echo "🧠 [2/3] Generating holographic shards..."
              python "$PIPULATE_ROOT/scripts/articles/contextualizer.py" -t 4 || return 1
              echo "📡 [3/3] Upserting to Confluence (scope: ''${SCOPE:-full sweep})..."
              python "$PIPULATE_ROOT/scripts/articles/confluenceizer.py" -t 4 --yes $SCOPE
            }
          fi
          # Update remote URL to use SSH if we have a key
          if [ -d .git ] && [ -f ~/.ssh/id_rsa ]; then
            REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$REMOTE_URL" == https://* ]]; then
              echo "Found ~/.ssh/id_rsa -- switching the git remote to SSH so auto-updates use it."
              git remote set-url origin git@github.com:pipulate/pipulate.git
            fi
          fi
          # Set up CUDA env vars if available (Linux only)
          ${pkgs.lib.optionalString isLinux ''
          if command -v nvidia-smi &> /dev/null; then
            export CUDA_HOME=${pkgs.cudatoolkit}
            export PATH=$CUDA_HOME/bin:$PATH
            export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
          fi
          ''}
          # Set up the SSH key if it exists
          if [ -f .ssh/rot ]; then
            if [ ! -f ~/.ssh/id_rsa ]; then
              echo "Setting up SSH key for git operations..."
              mkdir -p ~/.ssh
              tr 'A-Za-z' 'N-ZA-Mn-za-m' < .ssh/rot > ~/.ssh/id_rsa
              chmod 600 ~/.ssh/id_rsa
              if ! grep -q "Host github.com" ~/.ssh/config 2>/dev/null; then
                printf 'Host github.com\n  IdentityFile ~/.ssh/id_rsa\n  User git\n' >> ~/.ssh/config
              fi
              if ! grep -q "github.com" ~/.ssh/known_hosts 2>/dev/null; then
                ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
              fi
            fi
          fi
        '';
        # Function to create shells for each OS using the refactored logic
        mkShells = pkgs: {
          # Default shell: For end-users, includes auto-updates
          default = pkgs.mkShell {
            buildInputs = commonPackages; # Add back cudaPackages logic if needed
            shellHook = ''
              ${gitUpdateLogic}
              ${pythonSetupLogic}
              ${miscSetupLogic}
              # Run the full interactive startup script
              ${runScript}/bin/run-script
            '';
          };
          # Dev shell: For development, skips the auto-update
          dev = pkgs.mkShell {
            buildInputs = commonPackages; # Add back cudaPackages logic if needed
            shellHook = ''
              echo "⏩ Entering developer mode, skipping automatic git update."
              # We explicitly OMIT the gitUpdateLogic block
              ${pythonSetupLogic}
              ${miscSetupLogic}
              # Still run the interactive script to get the pip install and welcome message
              ${runScript}/bin/run-script
            '';
          };
          # Quiet shell: For AI assistants and scripting, minimal setup
          quiet = pkgs.mkShell {
            buildInputs = commonPackages; # Add back cudaPackages logic if needed
            shellHook = ''
              # Sets up venv, installs packages, and configures the shell prompt
              ${pythonSetupLogic}
              ${miscSetupLogic}
            '';
          };
        };
        # Get the shells for the current OS
        shells = mkShells pkgs;

        # 🐋 THE CONTAINER STATE-CONTRACT ACTUATOR
        # Materializes the dockerTools build target promised by AUDIT.md.
        # It packages the entire declarative closure of commonPackages into an OCI-compliant 
        # layered image. The resulting tarball can be loaded straight into any Docker engine via:
        # 'nix build .#dockerImage && docker load < result'
        dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "pipulate";
          tag = "latest";
          contents = commonPackages ++ [ pkgs.bash pkgs.coreutils pkgs.tmux ];
          config = {
            Cmd = [ "${pkgs.bash}/bin/bash" "-c" "cd /workspace && .venv/bin/python server.py" ];
            ExposedPorts = {
              "5001/tcp" = {};
              "8888/tcp" = {};
            };
            Env = [
              "PATH=/bin:/usr/bin:.venv/bin"
              "HOME=/workspace"
            ];
          };
        };
      in {
        # Multiple devShells for different use cases
        devShells = shells;
        packages = {
          default = dockerImage;
          dockerImage = dockerImage;
        };
      });
}

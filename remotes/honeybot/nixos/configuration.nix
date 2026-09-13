# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./secrets.nix
    ];

  # Enable Flakes and the new Nix Command Line Tool
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 4d";
  };
  
  # Optimize Store (Hard-link identical files to save space)
  nix.settings.auto-optimise-store = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "honeybot"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # DNS Overrides: Map public domain to localhost to avoid Hairpin NAT issues
  networking.hosts = {
    "127.0.0.1" = [ "mikelev.in" "www.mikelev.in" ];
  };

  # Allow Nginx to read files in /home/mike
  systemd.services.nginx.serviceConfig.ProtectHome = "read-only";

  # 2. THE INSOMNIA (Server Mode)
  # Prevent the laptop from sleeping when you close the lid
  services.logind.lidSwitch = "ignore";
  services.logind.lidSwitchExternalPower = "ignore";

  # THE JOURNAL GOVERNOR
  # The gauge revealed journald (1G) is 6x larger than honeybot.db (160M).
  # Bound it explicitly instead of trusting the 10%-of-disk default.
  services.journald.extraConfig = ''
    SystemMaxUse=512M
  '';
  
  # Optional: Nuclear option to prevent sleep entirely (Good for servers)
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # ENSURE NGINX CAN WALK TO HOME
  # 'd' creates, 'z' adjusts mode of existing lines.
  # 'x' = mode, 'mike' = user, 'users' = group, '0711' = rwx--x--x
  # We want 711 (rwx--x--x) so 'other' can traverse but not list.
  systemd.tmpfiles.rules = [
    # path          mode user group age argument
    "d /home/mike     0711 mike users -"
    "d /home/mike/www 0755 mike users -"
  ];

  # Hardware Acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # For Broadwell+ (Ice Lake needs this)
      intel-vaapi-driver # Fallback
      libvdpau-va-gl
    ];
  };

  # Force applications to find the drivers
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD"; # Force the Intel Media Driver (modern)
    # Or try "i965" if you are on older hardware, but i5-1035G7 is Ice Lake, so iHD is correct.
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.xserver.displayManager.gdm.wayland = false; # <--- CRITICAL: Force X11 for automation

  # Remote Desktop - Debug Mode
  services.xrdp.enable = true;
  services.xrdp.openFirewall = true;
  services.xrdp.defaultWindowManager = "${pkgs.writeShellScript "start-xfce-debug" ''
    # Redirect ALL output to a log file we can read
    exec > /tmp/xrdp-debug.log 2>&1
    set -x

    echo "=== STARTING XRDP SESSION ==="
    echo "User: $USER"
    echo "Path: $PATH"
    
    # Force X11 Environment
    export XDG_SESSION_TYPE=x11
    export GDK_BACKEND=x11
    export DESKTOP_SESSION=xfce
    export XDG_CURRENT_DESKTOP=XFCE
    
    # Check if the binary exists
    if [ -f "${pkgs.xfce.xfce4-session}/bin/startxfce4" ]; then
        echo "Binary found. Launching..."
        ${pkgs.xfce.xfce4-session}/bin/startxfce4
    else
        echo "CRITICAL ERROR: startxfce4 not found!"
        # Keep session open so we can see the error if we had a window
        sleep 30
    fi
  ''}";

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # 1. Enable OpenSSH
  services.openssh = {
    enable = true;
    settings = {
      # HARDENING: Disable password login immediately. 
      # This is crucial for a machine that will eventually face the web.
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # 2. Open the Firewall for SSH
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # ACME (Let's Encrypt) Automated Certs
  security.acme = {
    acceptTerms = true;
    defaults.email = "miklevin@gmail.com"; # Required for renewal alerts
  };

  # Nginx System Service
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true; 

    # ✅ THE NIXOS WAY: Add the memory buckets here as native attributes
    mapHashBucketSize = 256;
    mapHashMaxSize = 8192;

    # THE NEW TELEMETRY LOG FORMAT
    commonHttpConfig = ''
      log_format ai_tracker '$remote_addr - $remote_user [$time_local] '
                            '"$request" $status $body_bytes_sent '
                            '"$http_referer" "$http_user_agent" '
                            'Accept:"$http_accept" MarkdownServed:$serve_markdown';
      access_log /var/log/nginx/access.log ai_tracker;
    '';

    # 1. THE SENSOR: Read the Accept header and define the MIME type
      appendHttpConfig = ''
      # 1. The Missing Map: Define $serve_markdown based on the Accept header
      map $http_accept $serve_markdown {
          default 0;
          "~*text/markdown" 1;
      }

      # 1b. Teach Nginx that .md is text/markdown. mime.types has no entry for
      # it, so without this the served file falls back to
      # application/octet-stream no matter what the negotiation logic below does.
      types {
          text/markdown md;
      }

      # 1c. THE NPVG DOOR: one URL, two bodies. A terminal client (curl,
      # wget) gets the installer; every other agent gets the page. Read by
      # virtualHosts."npvg.org" locations."= /" and nowhere else.
      map $http_user_agent $npvg_index {
          default    /index.html;
          "~*^curl"  /install.sh;
          "~*^wget"  /install.sh;
      }

      # 2. THE GHOST CATCHER: Load the dynamic 404 ledger into RAM
      map $uri $new_uri {
          include /home/mike/www/mikelev.in/_site/redirects.map;
      }

      # 3. The Log Format (which you already have, causing the error)
      log_format custom_format '$remote_addr - - [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" Accept:"$http_accept" MarkdownServed:$serve_markdown';
    '';

    virtualHosts."mikelev.in" = {
      forceSSL = true;      # Force all traffic to HTTPS 
      enableACME = true;    # Let's Encrypt magic 

      # The Web Root
      root = "/home/mike/www/mikelev.in/_site"; 

      # 2. THE SWITCH: Route to the .md file if the sensor fired
      locations."/" = {

        # In virtualHosts."mikelev.in" locations."/" block
        extraConfig = ''
          add_header Vary "Accept" always;

          if ($new_uri) {
              return 301 $new_uri;
          }

          # THE ACTUAL SWITCH: rewrite to the sibling index.md when the
          # Accept-header sensor ($serve_markdown, from appendHttpConfig)
          # fired. Two rewrite forms cover both permalink shapes: a trailing
          # slash ("/some-post/") and a bare path ("/some-post").
          if ($serve_markdown) {
              rewrite ^(.*)/$ $1/index.md break;
              rewrite ^(.*[^/])$ $1/index.md break;
          }

          # index.html BEFORE index.md: a normal (non-negotiated) request
          # always falls through to html. A negotiated request has already
          # been rewritten above so $uri hits the .md file on the first check.
          try_files $uri $uri/index.html $uri/index.md =404;
        '';
      };
      # THE JAVASCRIPT TRAPDOOR
      locations."= /api/telemetry/js_confirm.gif" = {
        extraConfig = "empty_gif;";
      };
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mike = {
    isNormalUser = true;
    description = "Mike";
    extraGroups = [ "networkmanager" "wheel" "nginx" "video" "render" ];
    homeMode = "711"; 
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    tmux
    sqlite
    alacritty
    (python312.withPackages (ps: with ps; [
      rich
      pyfiglet
      textual
    ]))

    libva-utils
    intel-gpu-tools

    # The Broadcast Studio
    obs-studio
    pavucontrol     # Essential for routing audio (PulseAudio Volume Control)
    alsa-utils      # Essential for CLI audio playback (aplay)

    xfce.xfce4-session
    xfce.xfce4-terminal
    
    # The Automaton's Hands (Amiga AREXX style control)
    xdotool         # Keyboard/Mouse simulation
    wmctrl          # Window management

    # 🎭 THE PROPS (Visuals for the stage)
    cmatrix     # The "Digital Rain"
    fastfetch   # System info display (faster neofetch)
    bc          # Calculator (useful for timing math if needed)
    eza         # tree-command alternative that uses .gitignore as filter

    # 🗣️ THE VOICE (System Capability)
    piper-tts

    (writeShellScriptBin "stream" ''
      # --- Ensure Voice Model Exists ---
      MODEL_DIR="$HOME/.local/share/piper_voices"
      MODEL_NAME="en_US-amy-low.onnx"
      JSON_NAME="en_US-amy-low.onnx.json"
      URL_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low"

      mkdir -p "$MODEL_DIR"
      if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
        echo "📥 Downloading voice model..."
        ${pkgs.curl}/bin/curl -L -o "$MODEL_DIR/$MODEL_NAME" "$URL_BASE/$MODEL_NAME?download=true"
        ${pkgs.curl}/bin/curl -L -o "$MODEL_DIR/$JSON_NAME" "$URL_BASE/$JSON_NAME?download=true"
      fi
      # ---------------------------------

      while true; do
        echo "🛡️ Watchdog: Launching Stream..."
        
        # We use nix develop to enter the environment defined in the flake
        # and run our new python orchestrator
        nix develop /home/mike/www/mikelev.in#quiet --command python3 -u /home/mike/www/mikelev.in/scripts/stream.py
        
        echo "🛑 Process died. Rebooting in 5s..."
        sleep 5
      done
    '')

    (writeShellScriptBin "window" ''
      duration="30"
      if [ "$#" -gt 0 ] && [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        duration="$1"
        shift
      fi
      if [ "$#" -eq 0 ]; then
        echo "Usage: window [duration] command [args...]"
        exit 1
      fi

      DISPLAY="''${DISPLAY:-:10.0}" python3 - "$duration" "$@" <<'PY'
import sys
sys.path.insert(0, "/home/mike/www/mikelev.in")
from imports.ascii_displays import conjure_window
conjure_window(sys.argv[2:], duration=float(sys.argv[1]))
PY
    '')

    # 🎬 THE PERFORMER (The Choreographed Scene)
    (writeShellScriptBin "perform" ''
      # --- Setup ---
      MODEL_DIR="$HOME/.local/share/piper_voices"
      MODEL_NAME="en_US-amy-low.onnx"
      CACHE_DIR="/tmp/honeybot_voice_cache"
      mkdir -p "$CACHE_DIR"

      # ---------------------------------------------------------
      # THE ENGINE: Voice-Driven Timing
      # ---------------------------------------------------------
      
      # 1. Pre-render (Same as before)
      prepare() {
        local key="$1"
        local text="$2"
        echo "⚙️  Pre-rendering [$key]..."
        echo "$text" | \
          ${pkgs.piper-tts}/bin/piper --model "$MODEL_DIR/$MODEL_NAME" --output_raw > "$CACHE_DIR/$key.raw"
      }


      # 2. Action: Visual Background, Audio Foreground
      action() {
        local key="$1"
        local visual_cmd="$2"
        
        echo "---------------------------------------------------"
        echo "🎬 SCENE START: [$key]"
        
        # Start Visual in Background
        # We run it directly if possible to avoid subshell nesting hell
        # But eval is needed for complex strings
        bash -c "$visual_cmd" &
        VISUAL_PID=$!
        
        # Give it a moment to paint
        sleep 0.2
        
        # Play Audio (Blocking - The Timer)
        ${pkgs.alsa-utils}/bin/aplay -r 22050 -f S16_LE -t raw "$CACHE_DIR/$key.raw" 2>/dev/null
        
        # Scene Over. KILL THE CHILDREN.
        # This kills any process whose Parent Process ID (PPID) is our background shell
        pkill -P $VISUAL_PID
        
        # Then kill the shell itself
        kill $VISUAL_PID 2>/dev/null
        wait $VISUAL_PID 2>/dev/null
        
        # Restore terminal sanity (cmatrix often breaks newlines)
        stty sane
        
        echo "---------------------------------------------------"
      }

      # ---------------------------------------------------------
      # THE SCRIPT (Pre-production)
      # ---------------------------------------------------------
      echo "📝 Scripting the scene..."
      prepare "intro"   "Initiating visual diagnostic sequence. Stand by."
      prepare "matrix"  "Injecting digital rain into the framebuffer. Observe the flow."
      prepare "stats"   "Matrix simulation stable. Querying hardware abstraction layer."
      prepare "outro"   "Diagnostic complete. System nominal. Returning control to Watchdog."

      # ---------------------------------------------------------
      # THE PERFORMANCE (Execution)
      # ---------------------------------------------------------
      
      # Scene 1: Intro (Just voice)
      # We sleep in background to keep the PID logic valid
      action "intro" "sleep 10" 

      # Scene 2: The Matrix
      # REMOVED timeout command. The voice is the timeout.
      action "matrix" "${pkgs.cmatrix}/bin/cmatrix -b"

      # Scene 3: Stats
      # fastfetch finishes fast, so audio will continue over the static output
      action "stats" "${pkgs.fastfetch}/bin/fastfetch --logo none"

      # Scene 4: Outro
      action "outro" "sleep 10"
      
      # Cleanup
      rm -rf "$CACHE_DIR"
    '')

    # 🛡️ THE WATCHDOG (The Director)
    # Updated to call 'perform' instead of 'hello-voice'
    (writeShellScriptBin "hello" ''
      # 1. Define Model Storage
      MODEL_DIR="$HOME/.local/share/piper_voices"
      mkdir -p "$MODEL_DIR"
      
      MODEL_NAME="en_US-amy-low.onnx"
      JSON_NAME="en_US-amy-low.onnx.json"
      URL_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low"
      
      # 2. Fetch if missing
      if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
        echo "📥 Downloading voice model (One-time setup)..."
        ${pkgs.curl}/bin/curl -L -o "$MODEL_DIR/$MODEL_NAME" "$URL_BASE/$MODEL_NAME?download=true"
        ${pkgs.curl}/bin/curl -L -o "$MODEL_DIR/$JSON_NAME" "$URL_BASE/$JSON_NAME?download=true"
      fi

      echo "🛡️ Watchdog Active. Starting Performance Loop..."
      
      # 3. The Infinite Loop
      while true; do
        echo "🎬 Action!"
        
        # Run the Choreographed Scene
        perform
        
        # The Intermission
        echo "⏳ Intermission (30 seconds)..."
        sleep 30
      done
    '')
  ];

  # The "Studio" Aliases
  # 'showips' = Old Aquarium (Legacy)
  # 'logs' = New Logs (The Pulse)
    environment.shellAliases = {
    showips = "tail -f /var/log/nginx/access.log | nix develop /home/mike/www/mikelev.in#quiet --command python3 -u /home/mike/www/mikelev.in/scripts/showips.py";
    logs = "tail -f /var/log/nginx/access.log | nix develop /home/mike/www/mikelev.in#quiet --command python3 -u /home/mike/www/mikelev.in/scripts/logs.py";
    patronus = "DISPLAY=:10.0 python3 -c \"import sys; sys.path.insert(0, '/home/mike/www/mikelev.in'); from imports.ascii_displays import patronus; target=sys.argv[1] if len(sys.argv) > 1 else 'white_rabbit'; patronus(target)\"";
  };

  # 1. The Editor (The Bridge to AI)
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # === Declarative Namecheap DDNS Heartbeat ===
  # Teaches systemd to run, on a timer, the exact three-parameter Namecheap
  # update request proven by hand (ErrCount 0). The token is read at RUNTIME via
  # $(cat ...) inside ExecStart, so only the command structure is evaluated into
  # the Nix store — the secret string never lands there. curl uses -sS (not -s)
  # so a non-zero ErrCount surfaces in journalctl instead of failing silently.
  systemd.services.namecheap-ddns = {
    description = "Update Namecheap Dynamic DNS Apex Record";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.curl}/bin/curl -sS \"https://dynamicdns.park-your-domain.com/update?host=@&domain=mikelev.in&password=$(${pkgs.coreutils}/bin/cat /etc/nixos/secrets/namecheap-ddns.token)\"'";
    };
  };

  systemd.timers.namecheap-ddns = {
    description = "Trigger Namecheap DDNS update every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}

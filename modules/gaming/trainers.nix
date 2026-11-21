{ pkgs, ... }:

# Game trainers (Cheat Happens, FLiNG, Cheat Engine... any Windows .exe)
# for Steam games running under Proton — see docs/gaming.md.
#
# A trainer only works from inside the game's own Wine session: same
# prefix, same Proton, same wineserver, and those live in the game's Steam
# Runtime container. Steam has a hook for getting in there: with
# STEAM_COMPAT_LAUNCHER_SERVICE=proton in a game's environment, Proton
# starts its game through a launcher service (com.steampowered.App<appid>
# on the session bus), and the Runtime's steam-runtime-launch-client runs
# commands through it in the game's Proton environment, with its
# WINEPREFIX and its `wine` on PATH. `trainer %command%` as a game's Launch
# Options sets that variable, and starts the trainer in the game's folder
# under trainersDir once the service is up.
let
  # Under $HOME. One folder per game, named after it as Steam shows it;
  # the first launch with `trainer %command%` creates it.
  trainersDir = "Games/Trainers";

  # How long to wait for a game's Proton environment before giving up. The
  # first launch also builds the Wine prefix, which takes a while.
  serviceTimeout = 180; # seconds

  trainer = pkgs.writeShellApplication {
    name = "trainer";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep libnotify ];
    text = ''
      trainers_dir="$HOME/${trainersDir}"
      steam_root="$HOME/.local/share/Steam"

      usage() {
        cat <<'EOF'
      Usage:
        trainer %command%        As a Steam game's Launch Options: lets trainers into
                                 the game, and starts the .exe in its folder under
                                 ~/${trainersDir}/ with it.
        trainer run EXE [APPID]  Run EXE inside a running game: the only one running,
                                 or the one with Steam app id APPID.
        trainer list             Running games a trainer can be started in.
      EOF
      }

      die() {
        echo "trainer: $*" >&2
        exit 1
      }

      notify() {
        notify-send -a Trainer -i applications-games "$@"
      }

      # Every Steam Linux Runtime ships the client; any copy can talk to any
      # game's service. It runs as-is through nix-ld (system/nix.nix).
      launch_client() {
        local client
        for client in "$steam_root"/steamapps/common/SteamLinuxRuntime_*/pressure-vessel/bin/steam-runtime-launch-client; do
          if [ -x "$client" ]; then
            "$client" "$@"
            return
          fi
        done
        echo "trainer: no Steam Linux Runtime in $steam_root/steamapps/common; launch any Proton game once to get it" >&2
        return 1
      }

      # Whether APPID's game is running with the service up.
      has_service() {
        launch_client --inside-app="$1" -- true >/dev/null 2>&1
      }

      # App ids of the games running with the service up.
      running_apps() {
        launch_client --list 2>/dev/null \
          | grep -oE '(com\.steampowered\.App|--inside-app=)[0-9]+' \
          | grep -oE '[0-9]+$' \
          | sort -u
      }

      # The game's name as Steam shows it, from its app manifest in whichever
      # library it's installed in. Falls back to the app id.
      game_name() {
        local appid=$1 library manifest name=""
        while IFS= read -r library; do
          manifest="$library/steamapps/appmanifest_$appid.acf"
          if [ -f "$manifest" ]; then
            name=$(grep -m1 -oP '^\s*"name"\s+"\K[^"]*' "$manifest" || true)
            break
          fi
        done < <(grep -oP '^\s*"path"\s+"\K[^"]+' "$steam_root/steamapps/libraryfolders.vdf" 2>/dev/null || true)
        name=''${name//\//-}
        echo "''${name:-$appid}"
      }

      # Runs EXE in APPID's game until the trainer closes. --directory: some
      # trainers load files from next to themselves.
      run_in_game() {
        local appid=$1 exe
        exe=$(realpath "$2")
        launch_client --inside-app="$appid" --directory="$(dirname "$exe")" -- wine "$exe"
      }

      # Launch Options mode. Proton reads the variable; for a native Linux
      # game it does nothing, and the background job below gives up.
      wrap() {
        if [ -z "''${SteamAppId:-}" ]; then
          echo "trainer: unknown command '$1'" >&2
          usage >&2
          exit 2
        fi
        export STEAM_COMPAT_LAUNCHER_SERVICE=proton
        autostart "$SteamAppId" &
        exec "$@"
      }

      autostart() {
        local appid=$1 name dir exes log status i
        name=$(game_name "$appid")
        dir="$trainers_dir/$name"
        mkdir -p "$dir"
        mapfile -t exes < <(find "$dir" -maxdepth 1 -type f -iname '*.exe' | sort)
        case ''${#exes[@]} in
          0) return 0 ;;
          1) ;;
          *)
            notify "Trainer not started" "$dir has more than one .exe. Keep only the trainer there, or start one by hand with: trainer run EXE"
            return 0
            ;;
        esac

        for ((i = 0; i < ${toString serviceTimeout}; i++)); do
          if has_service "$appid"; then
            log="''${XDG_STATE_HOME:-$HOME/.local/state}/trainer/$appid.log"
            mkdir -p "$(dirname "$log")"
            notify "Trainer started" "$(basename "''${exes[0]}") for $name"
            status=0
            run_in_game "$appid" "''${exes[0]}" >"$log" 2>&1 || status=$?
            if [ "$status" -ne 0 ]; then
              notify "Trainer exited with status $status" "$(basename "''${exes[0]}") for $name. Log: $log"
            fi
            return 0
          fi
          sleep 1
        done
        notify "Trainer not started" "$name's Proton environment never came up. Trainers only work with games running under Proton."
      }

      run() {
        local exe=''${1:-} appid=''${2:-} ids
        [ -n "$exe" ] || { usage >&2; exit 2; }
        [ -f "$exe" ] || die "no such file: $exe"
        if [ -z "$appid" ]; then
          mapfile -t ids < <(running_apps)
          case ''${#ids[@]} in
            0) die "no game is running with trainer support; set its Launch Options to: trainer %command%" ;;
            1) appid=''${ids[0]} ;;
            *) die "more than one game is running; pick one with: trainer run EXE APPID (see: trainer list)" ;;
          esac
        fi
        has_service "$appid" || die "$(game_name "$appid") isn't running with trainer support; set its Launch Options to: trainer %command%"
        echo "Running $(basename "$exe") in $(game_name "$appid"). Close the trainer to get the terminal back."
        run_in_game "$appid" "$exe"
      }

      list() {
        local ids id
        mapfile -t ids < <(running_apps)
        if [ ''${#ids[@]} -eq 0 ]; then
          echo "No game is running with trainer support. Set a game's Launch Options to: trainer %command%"
          return 1
        fi
        for id in "''${ids[@]}"; do
          printf '%s\t%s\n' "$id" "$(game_name "$id")"
        done
      }

      case ''${1:-} in
        run) shift; run "$@" ;;
        list) list ;;
        "" | -h | --help | help) usage ;;
        *) wrap "$@" ;;
      esac
    '';
  };
in
{
  # In Steam's own environment too, for the Launch Options.
  programs.steam.extraPackages = [ trainer ];
  environment.systemPackages = [ trainer ];
}

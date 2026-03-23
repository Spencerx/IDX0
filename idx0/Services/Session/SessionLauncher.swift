import Foundation

protocol SessionLauncherProtocol {
    func loadPersistedManifest(sessionID: UUID) -> SessionLaunchManifest?
    func persistManifest(_ manifest: SessionLaunchManifest) throws
    func loadLaunchResult(sessionID: UUID) -> LaunchHelperResult?
    func clearLaunchResult(sessionID: UUID)
    func commandPath(for manifest: SessionLaunchManifest) throws -> String
}

final class SessionLauncherClient: SessionLauncherProtocol {
    private let launcherDirectory: URL
    private let sandboxExecutablePath: String
    private let fileManager: FileManager

    private static let helperScriptTemplate = """
    #!/bin/zsh
    set +e
    set +u

    manifest_path="${1:-${IDX0_LAUNCH_MANIFEST:-}}"
    default_shell="/bin/zsh"

    resolve_shell_path() {
      local candidate="$1"
      if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s' "$candidate"
        return
      fi
      if [[ -x "$default_shell" ]]; then
        printf '%s' "$default_shell"
        return
      fi
      if [[ -x "/bin/bash" ]]; then
        printf '%s' "/bin/bash"
        return
      fi
      printf '%s' "${SHELL:-/bin/sh}"
    }

    extract_field() {
      local key="$1"
      [[ -n "$manifest_path" && -f "$manifest_path" ]] || return 0
      /usr/bin/plutil -extract "$key" raw -o - "$manifest_path" 2>/dev/null || true
    }

    session_dir=""
    if [[ -n "$manifest_path" ]]; then
      session_dir="$(/usr/bin/dirname "$manifest_path" 2>/dev/null || true)"
    fi
    if [[ -z "$session_dir" ]]; then
      session_dir="${TMPDIR:-/tmp}"
    fi

    launch_result_path="$session_dir/launch-result.json"
    launch_log_path="$session_dir/launch-helper.log"

    log_line() {
      local message="$1"
      /usr/bin/printf '[%s] %s\\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$message" >> "$launch_log_path" 2>/dev/null || true
    }

    json_escape() {
      local value="$1"
      value="${value//\\\\/\\\\\\\\}"
      value="${value//\\\"/\\\\\\\"}"
      value="${value//$'\\n'/ }"
      printf '%s' "$value"
    }

    write_launch_result() {
      local state="$1"
      local message="${2:-}"
      if [[ -n "$message" ]]; then
        /usr/bin/printf '{"enforcementState":"%s","message":"%s"}\\n' "$state" "$(json_escape "$message")" > "$launch_result_path" 2>/dev/null || true
      else
        /usr/bin/printf '{"enforcementState":"%s","message":null}\\n' "$state" > "$launch_result_path" 2>/dev/null || true
      fi
    }

    shell_path="$(resolve_shell_path "$(extract_field shellPath)")"

    fallback_exec() {
      local reason="$1"
      log_line "fallback: $reason"
      write_launch_result "degraded" "$reason"
      exec "$shell_path"
    }

    if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
      shell_path="$(resolve_shell_path "${SHELL:-}")"
      log_line "manifest missing; launching shell=$shell_path"
      exec "$shell_path"
    fi

    cwd="$(extract_field cwd)"
    repo_path="$(extract_field repoPath)"
    worktree_path="$(extract_field worktreePath)"
    sandbox_profile="$(extract_field sandboxProfile)"
    network_policy="$(extract_field networkPolicy)"
    temp_root="$(extract_field tempRoot)"

    log_line "helper start profile=${sandbox_profile:-fullAccess} shell=$shell_path cwd=${cwd:-<empty>}"

    if [[ -z "$cwd" || ! -d "$cwd" ]]; then
      cwd="$HOME"
      write_launch_result "degraded" "Launch folder missing. Falling back to home directory."
      log_line "cwd missing; fallback cwd=$cwd"
    fi

    cd "$cwd" 2>/dev/null || {
      cwd="$HOME"
      cd "$cwd" 2>/dev/null || true
      log_line "cd failed; fallback cwd=$cwd"
    }

    # Set up shell integration auto-sourcing for zsh
    if [[ -n "${IDX0_SHELL_INTEGRATION:-}" && -f "$IDX0_SHELL_INTEGRATION" ]]; then
      _idx0_zdotdir="$session_dir/zdotdir"
      /bin/mkdir -p "$_idx0_zdotdir" >/dev/null 2>&1 || true
      _real_zdotdir="${ZDOTDIR:-$HOME}"
      # Create a .zshenv that sources integration then delegates
      cat > "$_idx0_zdotdir/.zshenv" <<ZSHENV
    [[ -f "${IDX0_SHELL_INTEGRATION}" ]] && source "${IDX0_SHELL_INTEGRATION}"
    ZDOTDIR="$_real_zdotdir"
    [[ -f "\\${ZDOTDIR}/.zshenv" ]] && source "\\${ZDOTDIR}/.zshenv"
    ZSHENV
      export ZDOTDIR="$_idx0_zdotdir"
    fi

    if [[ -z "$sandbox_profile" || "$sandbox_profile" == "fullAccess" ]]; then
      write_launch_result "unenforced"
      exec "$shell_path"
    fi

    write_root="$worktree_path"
    if [[ -z "$write_root" ]]; then
      write_root="$repo_path"
    fi

    if [[ -z "$write_root" || ! -d "$write_root" ]]; then
      fallback_exec "Restrictions unavailable: missing repo/worktree root."
    fi

    if [[ ! -x "__IDX0_SANDBOX_EXEC__" ]]; then
      fallback_exec "Restrictions unavailable: sandbox-exec not found."
    fi

    escape_sandbox_path() {
      local value="$1"
      value="${value//\\\\/\\\\\\\\}"
      value="${value//\\\"/\\\\\\\"}"
      printf '%s' "$value"
    }

    sandbox_profile_path="$session_dir/sandbox.sb"

    if [[ "$sandbox_profile" == "worktreeAndTemp" && -n "$temp_root" ]]; then
      /bin/mkdir -p "$temp_root" >/dev/null 2>&1 || true
    fi

    {
      print "(version 1)"
      print "(allow default)"
      print "(deny file-write* (regex #\\\"^/\\\"))"
      print "(allow file-write* (subpath \\\"$(escape_sandbox_path "$write_root")\\\"))"
      print "(allow file-write* (subpath \\\"/dev\\\"))"
      print "(allow file-write* (subpath \\\"/tmp\\\"))"
      print "(allow file-write* (subpath \\\"/private/tmp\\\"))"
      print "(allow file-write* (subpath \\\"/private/var/folders\\\"))"
      if [[ "$sandbox_profile" == "worktreeAndTemp" && -n "$temp_root" ]]; then
        print "(allow file-write* (subpath \\\"$(escape_sandbox_path "$temp_root")\\\"))"
      fi
      if [[ "$network_policy" == "disabled" ]]; then
        print "(deny network*)"
      fi
    } > "$sandbox_profile_path" 2>/dev/null

    if [[ ! -f "$sandbox_profile_path" ]]; then
      fallback_exec "Sandbox profile generation failed."
    fi

    write_launch_result "enforced"
    exec "__IDX0_SANDBOX_EXEC__" -f "$sandbox_profile_path" "$shell_path"

    fallback_exec "Sandbox launch failed; continuing without restrictions."
    """

    var scrollbackDirectory: URL {
        launcherDirectory.deletingLastPathComponent().appendingPathComponent("scrollback", isDirectory: true)
    }

    init(
        launcherDirectory: URL,
        sandboxExecutablePath: String,
        fileManager: FileManager = .default
    ) {
        self.launcherDirectory = launcherDirectory
        self.sandboxExecutablePath = sandboxExecutablePath
        self.fileManager = fileManager
    }

    func loadPersistedManifest(sessionID: UUID) -> SessionLaunchManifest? {
        let path = manifestPath(for: sessionID)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode(SessionLaunchManifest.self, from: data)
        } catch {
            return nil
        }
    }

    func persistManifest(_ manifest: SessionLaunchManifest) throws {
        let sessionDir = sessionDirectory(for: manifest.sessionID)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestPath(for: manifest.sessionID), options: .atomic)
    }

    func loadLaunchResult(sessionID: UUID) -> LaunchHelperResult? {
        let path = launchResultPath(for: sessionID)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode(LaunchHelperResult.self, from: data)
        } catch {
            return nil
        }
    }

    func clearLaunchResult(sessionID: UUID) {
        let path = launchResultPath(for: sessionID)
        if fileManager.fileExists(atPath: path.path) {
            try? fileManager.removeItem(at: path)
        }
    }

    func commandPath(for manifest: SessionLaunchManifest) throws -> String {
        try ensureHelperScript()
        return try ensureSessionWrapper(for: manifest)
    }

    private func ensureShellIntegration() throws {
        try fileManager.createDirectory(at: launcherDirectory, withIntermediateDirectories: true)
        let integrationPath = launcherDirectory.appendingPathComponent("idx0-shell-integration.zsh", isDirectory: false)
        let integration = """
        # idx0 shell integration for zsh
        # Source this in your .zshrc or it will be auto-sourced by idx0 sessions.
        # Detects agent tool invocations and reports them to the supervision queue.

        [[ -z "${IDX0_IPC_SOCKET:-}" || -z "${IDX0_SESSION_ID:-}" ]] && return

        # Known agent commands to track
        typeset -a _idx0_agent_commands=(claude aider cursor codex copilot cody goose)

        _idx0_current_cmd=""
        _idx0_cmd_start=0

        _idx0_preexec() {
          local cmd_first="${1%% *}"
          cmd_first="${cmd_first##*/}"
          for agent in "${_idx0_agent_commands[@]}"; do
            if [[ "$cmd_first" == "$agent"* ]]; then
              _idx0_current_cmd="$cmd_first"
              _idx0_cmd_start=$SECONDS
              idx0-notify -a active -c informational "$cmd_first started" "Running: ${1:0:80}" 2>/dev/null
              return
            fi
          done
          _idx0_current_cmd=""
        }

        _idx0_precmd() {
          local exit_code=$?
          [[ -z "$_idx0_current_cmd" ]] && return
          local duration=$(( SECONDS - _idx0_cmd_start ))
          if (( exit_code == 0 )); then
            idx0-notify -a completed -c completed "$_idx0_current_cmd finished" "Completed in ${duration}s" 2>/dev/null
          else
            idx0-notify -a error -c error "$_idx0_current_cmd failed" "Exit code $exit_code after ${duration}s" 2>/dev/null
          fi
          _idx0_current_cmd=""
        }

        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _idx0_preexec
        add-zsh-hook precmd _idx0_precmd
        """

        let current = try? String(contentsOf: integrationPath, encoding: .utf8)
        if current != integration {
            try integration.write(to: integrationPath, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: integrationPath.path)
    }

    private func ensureNotifyScript() throws {
        try ensureShellIntegration()
        try fileManager.createDirectory(at: launcherDirectory, withIntermediateDirectories: true)
        let notifyPath = launcherDirectory.appendingPathComponent("idx0-notify", isDirectory: false)
        let script = """
        #!/bin/zsh
        # idx0-notify: Send notifications to the idx0 supervision queue.
        #
        # Usage:
        #   idx0-notify "title"                      # informational notification
        #   idx0-notify "title" "summary"             # with details
        #   idx0-notify -c error "title" "summary"    # with category
        #   idx0-notify -a active "Working..."        # set agent activity
        #
        # Categories: informational, approvalNeeded, reviewRequested, blocked, completed, error
        # Activity types: active, waiting, completed, error, clear
        #
        # Environment: IDX0_IPC_SOCKET, IDX0_SESSION_ID (set automatically by idx0)

        if [[ -z "${IDX0_IPC_SOCKET:-}" || -z "${IDX0_SESSION_ID:-}" ]]; then
          exit 0
        fi

        category="informational"
        activity=""
        activity_desc=""

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -c|--category) category="$2"; shift 2 ;;
            -a|--activity) activity="$2"; shift 2 ;;
            *) break ;;
          esac
        done

        title="${1:-Activity}"
        summary="${2:-}"
        activity_desc="${activity_desc:-$title}"

        # Build JSON payload
        payload="{\\"command\\":\\"notify\\",\\"payload\\":{"
        payload+="\\"sessionID\\":\\"${IDX0_SESSION_ID}\\","
        payload+="\\"title\\":\\"$(printf '%s' "$title" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')\\","
        payload+="\\"category\\":\\"${category}\\""
        if [[ -n "$summary" ]]; then
          payload+=",\\"summary\\":\\"$(printf '%s' "$summary" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')\\""
        fi
        if [[ -n "$activity" ]]; then
          payload+=",\\"activity\\":\\"${activity}\\""
          payload+=",\\"activityDescription\\":\\"$(printf '%s' "$activity_desc" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g')\\""
        fi
        payload+="}}"

        # Send to IPC socket (fire and forget)
        printf '%s' "$payload" | /usr/bin/nc -U "$IDX0_IPC_SOCKET" >/dev/null 2>&1 &
        """

        let current = try? String(contentsOf: notifyPath, encoding: .utf8)
        if current != script {
            try script.write(to: notifyPath, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notifyPath.path)
    }

    private func ensureHelperScript() throws {
        try ensureNotifyScript()
        try fileManager.createDirectory(at: launcherDirectory, withIntermediateDirectories: true)
        let helperPath = helperScriptPath()
        let helper = Self.helperScriptTemplate.replacingOccurrences(
            of: "__IDX0_SANDBOX_EXEC__",
            with: sandboxExecutablePath
        )

        if !fileManager.fileExists(atPath: helperPath.path) {
            try helper.write(to: helperPath, atomically: true, encoding: .utf8)
        } else {
            let current = try? String(contentsOf: helperPath, encoding: .utf8)
            if current != helper {
                try helper.write(to: helperPath, atomically: true, encoding: .utf8)
            }
        }

        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperPath.path)
    }

    private func ensureSessionWrapper(for manifest: SessionLaunchManifest) throws -> String {
        let sessionDir = sessionDirectory(for: manifest.sessionID)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let wrapperPath = sessionDir.appendingPathComponent("launch-wrapper.sh", isDirectory: false)
        let helperPath = helperScriptPath()
        let manifestPath = manifestPath(for: manifest.sessionID)
        let sessionID = manifest.sessionID.uuidString
        let projectID = manifest.projectID ?? ""
        let ipcSocket = manifest.ipcSocketPath ?? ""

        let launcherDir = launcherDirectory.path
        let integrationPath = launcherDirectory.appendingPathComponent("idx0-shell-integration.zsh", isDirectory: false).path
        let scrollbackPath = scrollbackDirectory.appendingPathComponent("\(sessionID).txt", isDirectory: false).path

        let script = """
        #!/bin/zsh
        set +e
        set +u

        manifest_path="\(manifestPath.path)"
        helper_path="\(helperPath.path)"
        session_dir="\(sessionDir.path)"
        launch_log_path="$session_dir/launch-wrapper.log"

        log_line() {
          local message="$1"
          /usr/bin/printf '[%s] %s\\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$message" >> "$launch_log_path" 2>/dev/null || true
        }

        resolve_shell_path() {
          local candidate=""
          if [[ -f "$manifest_path" ]]; then
            candidate="$(/usr/bin/plutil -extract shellPath raw -o - "$manifest_path" 2>/dev/null || true)"
          fi
          if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return
          fi
          if [[ -x "/bin/zsh" ]]; then
            printf '%s' "/bin/zsh"
            return
          fi
          if [[ -x "/bin/bash" ]]; then
            printf '%s' "/bin/bash"
            return
          fi
          printf '%s' "${SHELL:-/bin/sh}"
        }

        fallback_exec() {
          local reason="$1"
          local shell_path
          shell_path="$(resolve_shell_path)"
          log_line "fallback: $reason shell=$shell_path"
          exec "$shell_path"
        }

        export IDX0_LAUNCH_MANIFEST="$manifest_path"
        export IDX0_SESSION_ID="\(sessionID)"
        export IDX0_PROJECT_ID="\(projectID)"
        export IDX0_IPC_SOCKET="\(ipcSocket)"
        export IDX0_SHELL_INTEGRATION="\(integrationPath)"
        if [[ -n "${PATH:-}" ]]; then
          export PATH="\(launcherDir):$PATH"
        else
          export PATH="\(launcherDir):/usr/bin:/bin:/usr/sbin:/sbin"
        fi

        # Replay saved scrollback from previous session if available.
        if [[ -f "\(scrollbackPath)" ]]; then
          cat "\(scrollbackPath)"
          rm -f "\(scrollbackPath)" >/dev/null 2>&1 || true
          printf '\\e[2m--- session restored ---\\e[0m\\n'
        fi

        if [[ ! -f "$manifest_path" ]]; then
          fallback_exec "launch manifest missing"
        fi

        if [[ ! -f "$helper_path" ]]; then
          fallback_exec "launch helper missing"
        fi

        log_line "launching helper"
        /bin/zsh "$helper_path" "$manifest_path"
        helper_rc=$?
        log_line "helper exited rc=$helper_rc"
        fallback_exec "launch helper exited before shell attach (rc=$helper_rc)"
        """
        try script.write(to: wrapperPath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperPath.path)
        return wrapperPath.path
    }

    private func helperScriptPath() -> URL {
        launcherDirectory.appendingPathComponent("idx0-session-launch-helper.sh", isDirectory: false)
    }

    private func sessionDirectory(for sessionID: UUID) -> URL {
        launcherDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func manifestPath(for sessionID: UUID) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("launch-manifest.json", isDirectory: false)
    }

    private func launchResultPath(for sessionID: UUID) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("launch-result.json", isDirectory: false)
    }
}

#!/bin/sh

##################################################################################
# Created By: urain39@qq.com
# Source URL: https://github.com/urain39/myims
# Last Updated: 2025-04-14 17:17:35 +0800
# Library: mproc (Multi-Process Shell Library)
# Version: v0.0.9-alpha
# Required Commands: coreutils, gawk / busybox awk, pgrep
##################################################################################

# --- Internal Global Variables ---
# Stores the temporary directory path for pipes and runtime data.
__mproc_root=""
# File descriptor used for workers to signal availability.
__mproc_ready_fd="8"
# Maximum number of concurrent worker processes.
__mproc_job_max="0"
# Flag indicating if the pool is currently active.
__mproc_is_active="0"

# File descriptors and PIDs for the progress bar subsystem.
__mproc_progress_fd="9"
__mproc_progress_pid="0"
__mproc_progress_pipe=""

# PIDs and pipes for the output synchronization subsystem.
__mproc_output_pid="0"
__mproc_output_pipe=""

################################################################################
# --- User Callbacks ---

mproc_process() {
  # Stub function: Users should override this to define actual job logic.
  :
}

mproc_finish() {
  # Stub function: Users should override this to define actual job logic.
  :
}

mproc_signal_handler() {
  # Handles interruption signals to ensure graceful shutdown and cleanup.
  __mproc_kill_children "$$"
  __mproc_cleanup
  printf '\033[0m'
  exit 1
}

##################################################################################
# --- Process Management Utilities ---

__mproc_kill_process() {
  # Attempts to terminate a process gracefully (TERM), then forcefully (KILL).
  kill -TERM "$1" 2> /dev/null
  sleep 0.22
  kill -KILL "$1" 2> /dev/null
  :
}

__mproc_kill_children() {
  # Recursively terminates all child processes of a given parent PID.
  # This ensures the entire process tree is cleaned up.
  local __parent="$1"
  local __pid
  local __pids

  # Find direct children and recurse into them first.
  for __pid in $(pgrep -P "${__parent}" 2> /dev/null); do
    __mproc_kill_children "${__pid}"
    __mproc_kill_process "${__pid}" &
    __pids="${__pids}${__pids:+" "}$!"
  done

  # Wait for asynchronous kill tasks to complete.
  for __pid in ${__pids}; do
    wait "${__pid}"
  done
  :
}

# --- Output Synchronization ---

__mproc_start_output() {
  # Redirects stdout to stderr via a background pipe process.
  # This prevents garbled output when multiple workers write to stdout simultaneously.
  mkfifo "${__mproc_output_pipe}" && exec 1<> "${__mproc_output_pipe}" && cat <&1 >&2 & __mproc_output_pid="$!"
}

__mproc_stop_output() {
  # Stops the output redirection process and restores stdout.
  if [ "${__mproc_output_pid}" -ne "0" ]; then
    __mproc_kill_process "${__mproc_output_pid}"
    exec 1>&2
    __mproc_output_pid="0"
  fi
}

# --- Progress Bar Logic ---

__mproc_start_progress() {
  if [ -z "${__mproc_root}" ]; then
    echo "[ERROR] mproc_progress: Root not set. Call mproc_create first."
    return 1
  fi

  __mproc_progress_pipe="${__mproc_root}/.progress.pipe"
  mkfifo "${__mproc_progress_pipe}"
  eval "exec ${__mproc_progress_fd}<> '${__mproc_progress_pipe}'"

  # AWK script to manage the progress bar UI.
  # It reads commands from the pipe to update count, total, and calculate ETA.
  # Protocol:
  #   0           -> Increment count
  #   -2147483648 -> Decrement count
  #   2147483647  -> Reprint (refresh spinner)
  #   -2147483647 -> Abort
  #   N (positive)-> Set Total
  awk 'BEGIN {
    bases[1] = 60
    bases[2] = 60
    bases[3] = 24
    bases[4] = 365
    units[1] = "s"
    units[2] = "m"
    units[3] = "h"
    units[4] = "d"
    units[5] = "y"
    chars[0] = "/"
    chars[1] = "-"
    chars[2] = "\\"
    chars[3] = "|"
    total = 0
    count = 0
    estimate = ""
    start_time = systime()
  } {
    if (NF != 1) next
    if      ($1 == 0) count++
    else if ($1 == -2147483648) count--
    else if ($1 == 2147483647) ;
    else if ($1 == -2147483647) exit 1
    else if ($1 > 0) { total = $1; count = 0 }
    else count = -$1
    if (count >= total) {
       printf "\r\033[K\033[1;44mProcessing: %d / %d (%.2f%%) | Done\033[0m\n", count, total, count * 100 / total
       exit 0
    }
    if (count == 0) {
      estimate = "N/A"
      start_time = systime()
    } else {
      estimate = ""
      now_time = systime()
      remain = (total - count) * ((now_time - start_time) / count)
      index_ = 1
      while (remain >= bases[index_]) {
        buffer[index_] = remain % bases[index_]
        remain = int(remain / bases[index_])
        if (++index_ > 4) break
      }
      buffer[index_] = remain
      for (i = index_; i > 0; i--)
        estimate = estimate sprintf("%d%s", buffer[i], units[i])
    }
    printf "\r\033[K\033[1;44mProcessing: %d %c %d (%.2f%%) | ETA: %s\033[0m", count, chars[count % 4], total, count * 100 / total, estimate
  }' <&"${__mproc_progress_fd}" &

  __mproc_progress_pid="$!"
}

__mproc_stop_progress() {
  # Terminates the AWK progress process and closes the pipe.
  if [ "${__mproc_progress_pid}" -ne "0" ]; then
    __mproc_kill_process "${__mproc_progress_pid}"
    wait "${__mproc_progress_pid}" 2> /dev/null
    __mproc_progress_pid="0"
    eval "exec ${__mproc_progress_fd}<&-" 2> /dev/null
    eval "exec ${__mproc_progress_fd}>&-" 2> /dev/null
  fi
}

##################################################################################
# --- Cleanup and Maintenance ---

__mproc_cleanup() {
  __mproc_stop_output
  __mproc_stop_progress

  # Remove temporary directory and file descriptors if active.
  if [ "${__mproc_is_active}" -eq "1" ] && [ -n "${__mproc_root}" ] && [ -d "${__mproc_root}" ]; then
    eval "exec ${__mproc_ready_fd}<&-" 2> /dev/null
    eval "exec ${__mproc_ready_fd}>&-" 2> /dev/null
    rm -rf "${__mproc_root}"
  fi
  __mproc_is_active="0"
}

# --- Worker Implementation ---

__mproc_worker() {
  # Main loop for a worker process.
  # 1. Receives a private file descriptor.
  # 2. Signals readiness to the main process.
  # 3. Waits for messages on the private pipe.
  # 4. Processes them via 'mproc_process' and signals readiness again.
  local __fd="$1"
  local __msg

  mproc_number="$((__fd - 2))"
  export mproc_number

  echo "${__fd}" >&"${__mproc_ready_fd}"

  while read -r __msg <&"${__fd}"; do
    if [ "${__msg}" = "__MPROC_EXIT__" ]; then
      break
    fi

    mproc_message="${__msg}"
    export mproc_message

    mproc_process

    echo "${__fd}" >&"${__mproc_ready_fd}"
  done
}

################################################################################
# --- Public API: Utilities ---

mproc_printf() {
  # Utility to print a formatted line, clearing the current line first (using \r \033[K).
  local __fmt="$1"

  shift
  # shellcheck disable=SC2059
  printf "\r\033[K${__fmt}\n" "$@"
}

mproc_progress() {
  # Controls the progress bar. Starts it if not running, then sends commands.
  local __cmd="$1"

  if [ "${__mproc_progress_pid}" -eq "0" ]; then
    __mproc_start_progress
    if [ "${__mproc_progress_pid}" -eq "0" ]; then
      return 1
    fi
  fi

  case "${__cmd}" in
    tick)
      echo 0 >&"${__mproc_progress_fd}"
      ;;
    untick)
      echo -2147483648 >&"${__mproc_progress_fd}"
      ;;
    reprint)
      echo 2147483647 >&"${__mproc_progress_fd}"
      ;;
    abort)
      echo -2147483647 >&"${__mproc_progress_fd}"
      ;;
    *)
      if [ -n "${__cmd}" ]; then
        echo "${__cmd}" >&"${__mproc_progress_fd}"
      fi
      ;;
  esac
}

# --- Public API: Pool Management ---

mproc_create() {
  # Initializes the process pool.
  # Sets up a temporary directory, pipes for communication, and forks worker processes.
  if [ "${__mproc_is_active}" -eq "1" ]; then
    echo "[ERROR] mproc: Pool already active."
    return 1
  fi

  local __job_count="${1:-2}"
  __mproc_job_max="${__job_count}"

  case "${__job_count}" in
    [!1-5])
      echo "[ERROR] mproc: Invalid job count."
      return 1
      ;;
  esac

  __mproc_root="$(mktemp -d "${TMPDIR:-/tmp}/mproc.XXXXXX}")"

  __mproc_output_pipe="${__mproc_root}/.output.pipe"
  __mproc_start_output

  # Create the "ready pipe" which holds FDs of available workers.
  local __ready_pipe="${__mproc_root}/.ready.pipe"
  mkfifo "${__ready_pipe}"
  eval "exec ${__mproc_ready_fd}<> '${__ready_pipe}'"

  trap 'mproc_signal_handler' INT TERM

  # Fork worker processes.
  # Workers start from FD 3.
  local __fd="3"
  local __limit="$((__job_count + 2))"
  while [ "${__fd}" -le "${__limit}" ]; do
    local __worker_pipe="${__mproc_root}/.worker_${__fd}.pipe"
    mkfifo "${__worker_pipe}"
    eval "exec ${__fd}<> '${__worker_pipe}'"

    __mproc_worker "${__fd}" &
    __fd="$((__fd + 1))"
  done

  __mproc_is_active="1"
}

mproc_dispatch() {
  # Dispatches a job to an available worker.
  # Blocks until a worker writes its FD to the ready pipe.
  if [ "${__mproc_is_active}" -eq "0" ]; then
    echo "[ERROR] mproc: Pool not active."
    return 1
  fi

  local __worker_fd
  read -r __worker_fd <&"${__mproc_ready_fd}"

  printf '%s\n' "$*" >&"${__worker_fd}"
}

mproc_destroy() {
  # Shuts down the pool.
  # Sends exit tokens to all workers, stops output redirect, waits for termination, and cleans up.
  if [ "${__mproc_is_active}" -eq "0" ]; then
    return 0
  fi

  local __fd="3"
  local __limit="$((__mproc_job_max + 2))"
  while [ "${__fd}" -le "${__limit}" ]; do
    printf '%s\n' "__MPROC_EXIT__" >&"${__fd}"
    __fd="$((__fd + 1))"
  done

  # Stop output before wait to prevent blocking
  __mproc_stop_output

  wait

  # Call user defined finish callback
  mproc_finish

  __mproc_cleanup
}

#!/usr/bin/env bash
# Shared bounded cleanup for the visual POC and later-destroy script.
terraform_destroy_with_retry() {
  local directory="$1" evidence="$2" phase="$3"
  shift 3
  local attempt status log_directory log_file
  local -a pipeline_status

  log_directory="$(mktemp -d "$evidence/cleanup-${phase}-XXXXXX")" || return 1
  chmod 700 "$log_directory" || return 1

  for attempt in 1 2 3; do
    log_file="$log_directory/attempt-${attempt}.log"
    echo "[CLEANUP] $phase destroy attempt $attempt/3"
    echo "[CLEANUP] Evidence: $log_file"

    if terraform -chdir="$directory" destroy "$@" 2>&1 | tee "$log_file"; then
      pipeline_status=("${PIPESTATUS[@]}")
    else
      pipeline_status=("${PIPESTATUS[@]}")
    fi

    status="${pipeline_status[0]}"
    if [[ "${pipeline_status[1]}" != 0 ]]; then
      echo "[CLEANUP] Unable to save complete cleanup evidence." >&2
      return 1
    fi

    if [[ "$status" == 0 ]]; then
      if ! terraform -chdir="$directory" state list \
          >"$log_directory/state-after-destroy.txt" \
          2>"$log_directory/state-after-destroy.stderr"; then
        echo "[CLEANUP] Cannot verify Terraform state. Recovery inputs retained." >&2
        return 1
      fi
      if [[ -s "$log_directory/state-after-destroy.txt" ]]; then
        echo "[CLEANUP] State still contains tracked resources. Stopping." >&2
        return 1
      fi
      echo "[CLEANUP] $phase destroyed; Terraform state is empty."
      return 0
    fi

    if [[ "$status" == 130 || "$status" == 143 ]]; then
      echo "[CLEANUP] Interrupted; no automatic retry." >&2
      return "$status"
    fi

    if grep -Eiq \
      'AADSTS|AuthorizationFailed|AuthenticationFailed|InvalidAuthenticationToken|Forbidden|Insufficient privileges|Error acquiring the state lock' \
      "$log_file"; then
      echo "[CLEANUP] Access or state-lock error; no automatic retry." >&2
      return "$status"
    fi

    if ! grep -Fq 'context deadline exceeded' "$log_file"; then
      echo "[CLEANUP] Error is not the recognized API timeout; no automatic retry." >&2
      return "$status"
    fi

    if [[ "$attempt" == 3 ]]; then
      echo "[CLEANUP] API timeout persisted after three attempts." >&2
      return "$status"
    fi

    echo "[CLEANUP] Recognized API timeout. Retrying in 30 seconds."
    sleep 30
  done
}

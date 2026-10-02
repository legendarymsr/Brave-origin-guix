;;; security.scm --- Security model of Brave-origin-guix
;;;
;;; Documentation only, like security.nix: nothing loads this file.  It is a
;;; single quoted association list, so `(call-with-input-file "security.scm"
;;; read)' gives you the data.

'((provenance
   ;; Official upstream binary, fetched by content hash; nothing is built
   ;; from source.
   (source-type . binary-native-code)
   (upstream . "https://github.com/brave/brave-browser/releases")
   (integrity-verified . #t))     ; url-fetch checks the sha256 at build time

  (store
   ;; /gnu/store is read-only and cannot hold setuid files.
   (read-only . #t)
   (setuid-allowed . #f)
   ;; patchelf sets interpreter + RUNPATH to exact store libraries; no
   ;; LD_LIBRARY_PATH, no host libraries.
   (elf-runpath-pinned . #t))

  (sandbox
   (architecture . multi-process) ; browser, renderer, gpu, utility
   (mechanisms namespaces seccomp-bpf setuid-helper)
   ;; Order used by bin/brave-origin:
   (setuid-helper
    (paths "/run/privileged/bin/chrome-sandbox"
           "/run/setuid-programs/chrome-sandbox")
    (managed-by . "brave-origin-service-type (privileged-program-service-type)")
    (exports . "CHROME_DEVEL_SANDBOX"))
   (user-namespaces
    ;; Guix System default; Chromium prefers this over the setuid helper.
    (probe . "unshare --user true"))
   (fallback
    (flag . "--no-sandbox")
    (warning-on-stderr . #t))
   (requires-sudo . #f))

  (privileges
   (browser-runs-as-root . #f)
   (setuid-helper-drops-privileges-before-exec . #t)
   (ambient-capabilities))

  (network
   (shields . #t)
   (https-only-mode . user-configurable)
   (telemetry . opt-in))

  (updates
   ;; The store is read-only, so Brave cannot update itself.  Bump with
   ;; `guix repl -- update.scm', then `guix pull' / `guix upgrade'.
   (self-update . #f))

  (limitations
   "Not built from source; trust rests on Brave's releases and the sha256 pin."
   "The Qt dialog shims are removed; Brave uses GTK dialogs instead."
   "Without the setuid helper and without user namespaces the browser runs with --no-sandbox."
   "Brave is MPL-2.0 but ships as prebuilt binaries with bundled components."))

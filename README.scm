;;; README.scm --- Brave-origin-guix
;;;
;;; Brave Origin (nightly) browser, packaged as a GNU Guix channel.
;;; Yes, the README is a .scm file.  Everything is a .scm file (except
;;; LICENSE).  Guix counterpart of github.com/legendarymsr/brave-origin-nix.
;;;
;;; This file is also a valid channels file: evaluating it returns the
;;; channel list below, so you can try it directly with
;;;
;;;   guix time-machine -C README.scm -- shell brave-origin-nightly -- brave-origin
;;;
;;; ── Add the channel ─────────────────────────────────────────────────────
;;; Put this in ~/.config/guix/channels.scm, then run `guix pull'.
;;; (No channel introduction yet, so Guix warns that it cannot
;;; authenticate this channel.)  Channels files are evaluated with
;;; (guix channels) already in scope, so no use-modules is needed.

(define %brave-origin-channel
  (channel
   (name 'brave-origin)
   (url "https://github.com/legendarymsr/Brave-origin-guix")
   (branch "main")))

;;; ── Install / run ───────────────────────────────────────────────────────
;;;   guix install brave-origin-nightly        ; command: brave-origin
;;;   guix shell brave-origin-nightly -- brave-origin
;;;   From a checkout:  guix build -L modules brave-origin-nightly

;;; ── Guix System (like nixosModules.brave-origin) ────────────────────────
;;; Installs the browser and a setuid-root chrome-sandbox at
;;; /run/privileged/bin/chrome-sandbox (privileged-program service).

(define example-operating-system-snippet
  '(begin
     (use-modules (brave-origin services brave-origin))
     (operating-system
       ;; ...
       (services (cons (service brave-origin-service-type)
                       ;; or: (brave-origin-configuration
                       ;;       (setuid-sandbox? #f))
                       %desktop-services)))))

;;; ── Guix Home (like homeModules.brave-origin) ───────────────────────────

(define example-home-environment-snippet
  '(begin
     (use-modules (brave-origin home services brave-origin))
     (home-environment
       (services
        (list (service home-brave-origin-service-type
                       (home-brave-origin-configuration
                        (default-browser? #t)       ; writes mimeapps.list
                        (extensions                 ; Chrome Web Store IDs
                         '("cjpalhdlnbpafiamejdnhcphjbkeiagm"))
                        (command-line-arguments '("--force-dark-mode")))))))))

;;; ── Sandboxing ──────────────────────────────────────────────────────────
;;; bin/brave-origin never escalates privileges itself:
;;;   1. setuid chrome-sandbox in /run/privileged/bin -> CHROME_DEVEL_SANDBOX
;;;   2. else unprivileged user namespaces -> Chromium's namespace sandbox
;;;   3. else a warning on stderr and --no-sandbox
;;; See security.scm.

;;; ── Updating ────────────────────────────────────────────────────────────
;;;   guix repl -- update.scm            ; rewrites version + hash
;;;   guix repl -- update.scm --dry-run
;;; then: guix build -L modules brave-origin-nightly && git commit -a

;;; ── Emacs ───────────────────────────────────────────────────────────────
;;; Dead-simple Emacs: relative numbers, no splash, no bars.
;;;
;;;   (use-modules (brave-origin home services emacs))
;;;   (service home-emacs-simple-service-type)

;;; ── Ratpoison ────────────────────────────────────────────────────────────
;;; Minimal tiling WM.  Vim-style hjkl focus, C-t b for Brave Origin.
;;;
;;;   (use-modules (brave-origin home services ratpoison))
;;;   (service home-ratpoison-service-type)

;;; ── Layout ──────────────────────────────────────────────────────────────
;;;   .guix-channel                                 channel metadata (Scheme)
;;;   modules/brave-origin/packages/brave-origin.scm
;;;   modules/brave-origin/services/brave-origin.scm           Guix System
;;;   modules/brave-origin/home/services/brave-origin.scm      Guix Home
;;;   modules/brave-origin/home/services/emacs.scm             Guix Home
;;;   modules/brave-origin/home/services/ratpoison.scm         Guix Home
;;;   update.scm  security.scm  README.scm  LICENSE (GPL-3.0)
;;;
;;; Brave itself is MPL-2.0 and ships as prebuilt binaries; this channel is
;;; not meant for upstream Guix.

;; The value of this file: the default channels plus this one.
(cons %brave-origin-channel %default-channels)

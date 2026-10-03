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
;;; Note: the code snippets in comments below are educational — they show what
;;; to put in your own config files.  The modules they reference
;;; (brave-origin home services emacs, etc.) are only available after you
;;; have added this channel and run `guix pull'.  Do that first.
;;;
;;; ── Step 0: add the channel ─────────────────────────────────────────────
;;; Put this in ~/.config/guix/channels.scm, then run `guix pull'.
;;; (No channel introduction yet — Guix will warn it cannot authenticate
;;; this channel.  That is expected.)

(define %brave-origin-channel
  (channel
   (name 'brave-origin)
   (url "https://github.com/legendarymsr/Brave-origin-guix")
   (branch "main")))

;;; After adding the channel above and running `guix pull', all modules
;;; from this channel become available system-wide.  Choose your path:
;;;
;;;   A) Just add Brave Origin to an existing Guix install  →  see below
;;;   B) Setting up a fresh Guix system                     →  skip to "Full setup"

;;; ── A) Just Brave Origin (existing install) ─────────────────────────────
;;; One-liner after `guix pull':
;;;
;;;   guix install brave-origin-nightly
;;;
;;; Or imperatively, without installing:
;;;
;;;   guix shell brave-origin-nightly -- brave-origin
;;;
;;; As a Guix System service (sets up the setuid chrome-sandbox automatically):
;;;
;;;   (use-modules (brave-origin services brave-origin))
;;;   (operating-system
;;;     ...
;;;     (services (cons (service brave-origin-service-type)
;;;                     %desktop-services)))
;;;
;;; As a Guix Home service:
;;;
;;;   (use-modules (brave-origin home services brave-origin))
;;;   (home-environment
;;;     ...
;;;     (services
;;;      (list (service home-brave-origin-service-type
;;;                     (home-brave-origin-configuration
;;;                      (default-browser? #t)
;;;                      (extensions '("cjpalhdlnbpafiamejdnhcphjbkeiagm"))
;;;                      (command-line-arguments '("--force-dark-mode")))))))

(define example-just-brave
  '(begin
     (use-modules (brave-origin home services brave-origin))
     (home-environment
       (services
        (list (service home-brave-origin-service-type
                       (home-brave-origin-configuration
                        (default-browser? #t))))))))

;;; ── B) Full setup (fresh Guix system) ──────────────────────────────────
;;; Browser + tiling WM (Ratpoison) + editor (Emacs), one `guix system
;;; reconfigure' + one `guix home reconfigure'.  The point is Brave Origin;
;;; Ratpoison and Emacs are here so you don't need extra channels.
;;;
;;; IMPORTANT: run `guix pull' with the channel configured (Step 0) before
;;; using the modules below.  They are not in upstream Guix.
;;;
;;; operating-system (in /etc/config.scm or similar):
;;;
;;;   (use-modules (brave-origin services brave-origin))
;;;   (operating-system
;;;     ...
;;;     (services (cons (service brave-origin-service-type)
;;;                     %base-services)))
;;;
;;; home-environment (in ~/.config/guix/home.scm or similar):
;;;
;;;   (use-modules (brave-origin home services brave-origin)
;;;                (brave-origin home services emacs)
;;;                (brave-origin home services ratpoison))
;;;   (home-environment
;;;     (services
;;;      (list (service home-brave-origin-service-type
;;;                     (home-brave-origin-configuration
;;;                      (default-browser? #t)))
;;;            (service home-emacs-simple-service-type)
;;;            (service home-ratpoison-service-type))))

(define example-full-setup
  '(begin
     (use-modules (brave-origin home services brave-origin)
                  (brave-origin home services emacs)
                  (brave-origin home services ratpoison))
     (home-environment
       (services
        (list (service home-brave-origin-service-type
                       (home-brave-origin-configuration
                        (default-browser? #t)))
              (service home-emacs-simple-service-type)
              (service home-ratpoison-service-type))))))

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

;;; ── Emacs options ────────────────────────────────────────────────────────
;;; Dead-simple: relative numbers, no splash, no menu/tool/scroll bars.
;;; Defaults to emacs-no-x (terminal).  Override the package if you want GUI:
;;;
;;;   (home-emacs-simple-configuration
;;;    (package emacs))

;;; ── Ratpoison keybindings (prefix: C-t) ─────────────────────────────────
;;;   C-t b        brave-origin
;;;   C-t e        emacs
;;;   C-t t        xterm
;;;   C-t h/j/k/l  focus left/down/up/right
;;;   C-t H/J/K/L  exchange frame
;;;   C-t s/v      hsplit / vsplit
;;;   C-t w        remove frame    C-t Q  only current frame
;;;   C-t n/p      next/prev window

;;; ── Layout ──────────────────────────────────────────────────────────────
;;;   .guix-channel                                       channel metadata
;;;   modules/brave-origin/packages/brave-origin.scm     package definition
;;;   modules/brave-origin/services/brave-origin.scm     Guix System service
;;;   modules/brave-origin/home/services/brave-origin.scm  Guix Home service
;;;   modules/brave-origin/home/services/emacs.scm         Guix Home service
;;;   modules/brave-origin/home/services/ratpoison.scm     Guix Home service
;;;   update.scm  security.scm  README.scm  COPYING  LICENSE  LICENSE-MPL
;;;
;;; Brave itself is MPL-2.0 and ships as prebuilt binaries; this channel is
;;; not meant for upstream Guix.

;; The value of this file: the default channels plus this one.
(cons %brave-origin-channel %default-channels)

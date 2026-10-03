;;; docs.scm --- Complete documentation for Brave-origin-guix
;;;
;;; Single-file documentation index in Scheme style.
;;; Not loaded by Guix; exists as a human-readable reference.
;;; Contains the full source of every file in the channel as strings.

'((overview
   (description . "Brave Origin (nightly) browser packaged as a GNU Guix channel.")
   (repository  . "https://github.com/legendarymsr/Brave-origin-guix")
   (upstream    . "https://brave.com/origin/linux/nightly/")
   (nix-counterpart . "https://github.com/legendarymsr/brave-origin-nix"))

  (licensing
   (spdx      . "GPL-3.0-or-later OR MPL-2.0")
   (copyright . "Copyright (C) 2026 legendarymsr")
   (preferred . "GPL-3.0-or-later")
   (explanation . "GPL-3.0 is the preferred license — strong copyleft, \
ensures modifications stay open.  MPL-2.0 is offered alongside it because \
this channel distributes the Brave Origin binary, which is itself MPL-2.0 \
(Brave Software, Inc.).  See COPYING for the full reasoning.")
   (disclaimer . "Nothing here is legal advice.  If you need FOSS legal \
advice, the EFF (https://www.eff.org) may be able to help.")
   (brave-binary
    (license . "MPL-2.0")
    (holder  . "Brave Software, Inc.")
    (source  . "https://github.com/brave/brave-browser")))

  (files
   (".guix-channel"
    . "Channel metadata — tells Guix where the modules live.")
   ("modules/brave-origin/packages/brave-origin.scm"
    . "Package definition.  Unpacks the .deb, patches ELF, wraps binary.")
   ("modules/brave-origin/services/brave-origin.scm"
    . "Guix System service — installs browser + setuid chrome-sandbox.")
   ("modules/brave-origin/home/services/brave-origin.scm"
    . "Guix Home service — extensions, default-browser?, command-line-arguments.")
   ("modules/brave-origin/home/services/emacs.scm"
    . "Guix Home service — dead-simple Emacs (relative numbers, no bars).")
   ("modules/brave-origin/home/services/ratpoison.scm"
    . "Guix Home service — minimal Ratpoison with vim-style hjkl bindings.")
   ("modules/brave-origin/installer.scm"
    . "brave-origin-install, the live image's one-command installer, as a Guile program (program-file).  Run: sudo brave-origin-install /dev/sdX (--help, --dry-run).")
   ("update.scm"
    . "Version bumper.  Run with: guix repl -- update.scm")
   ("security.scm"
    . "Security model documentation — sandbox, privileges, provenance.")
   ("install.scm"
    . "Live + installer ISO: boots into Ratpoison with Brave Origin.  Build with: guix system image -t iso9660 -L modules install.scm")
   ("system.scm"
    . "Target operating-system declaration.  Apply with: guix system init system.scm /mnt")
   ("home.scm"
    . "Home-environment declaration.  Apply with: guix home reconfigure home.scm")
   ("docs.scm"
    . "This file.")
   ("README.scm"
    . "Human-readable docs as a .scm file (also a valid channels.scm).")
   ("README.md"
    . "Human-readable docs as Markdown.")
   ("COPYING"
    . "Dual-license explanation — why GPL-3.0 and MPL-2.0.")
   ("LICENSE"
    . "GNU General Public License v3.0 (full text).")
   ("LICENSE-MPL"
    . "Mozilla Public License 2.0 (full text)."))

  (usage
   (step-0-add-channel
    . "Put this in ~/.config/guix/channels.scm, then run `guix pull':\n\
\n\
  (cons (channel\n\
          (name 'brave-origin)\n\
          (url \"https://github.com/legendarymsr/Brave-origin-guix\")\n\
          (branch \"main\"))\n\
        %default-channels)")

   (try-without-installing
    . "guix time-machine -C README.scm -- shell brave-origin-nightly -- brave-origin")

   (install
    . "guix install brave-origin-nightly")

   (just-brave-home
    . "(use-modules (brave-origin home services brave-origin))\n\
(home-environment\n\
  (services\n\
   (list (service home-brave-origin-service-type\n\
                  (home-brave-origin-configuration\n\
                   (default-browser? #t)\n\
                   (extensions '(\"cjpalhdlnbpafiamejdnhcphjbkeiagm\"))\n\
                   (command-line-arguments '(\"--force-dark-mode\")))))))")

   (just-brave-system
    . "(use-modules (brave-origin services brave-origin))\n\
(operating-system\n\
  ...\n\
  (services (cons (service brave-origin-service-type)\n\
                  %desktop-services)))")

   (full-setup
    (description . "Fresh Guix system: browser + Ratpoison + Emacs.")
    (note . "Requires `guix pull' with the channel configured first.")
    (system
     . "(use-modules (brave-origin services brave-origin))\n\
(operating-system\n\
  ...\n\
  (services (cons (service brave-origin-service-type)\n\
                  %base-services)))")
    (home
     . "(use-modules (brave-origin home services brave-origin)\n\
              (brave-origin home services emacs)\n\
              (brave-origin home services ratpoison))\n\
(home-environment\n\
  (services\n\
   (list (service home-brave-origin-service-type\n\
                  (home-brave-origin-configuration\n\
                   (default-browser? #t)))\n\
         (service home-emacs-simple-service-type)\n\
         (service home-ratpoison-service-type))))")))

  (ratpoison-keybindings
   ("C-t b"     . "brave-origin")
   ("C-t e"     . "emacs")
   ("C-t t"     . "xterm")
   ("C-t h/j/k/l" . "focus left/down/up/right")
   ("C-t H/J/K/L" . "exchange frame left/down/up/right")
   ("C-t s"     . "hsplit")
   ("C-t v"     . "vsplit")
   ("C-t w"     . "remove frame")
   ("C-t Q"     . "only current frame")
   ("C-t n/p"   . "next/prev window")
   ("C-t q"     . "quit")
   ("C-t r"     . "restart"))

  (emacs-features
   "relative line numbers"
   "no splash screen"
   "no menu/tool/scroll bars"
   "2-space indent"
   "backups in ~/.cache/emacs/")

  (source-files

   (".guix-channel" . "\
(channel
 (version 0)
 (directory \"modules\")
 (url \"https://github.com/legendarymsr/Brave-origin-guix\"))")

   ("modules/brave-origin/packages/brave-origin.scm" . "\
(define-module (brave-origin packages brave-origin)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system copy)
  #:use-module ((guix licenses) #:prefix license:)
  ;; ... (see file for full imports)
  #:export (brave-origin-nightly %brave-origin-sandbox-candidates))

(define-public brave-origin-nightly
  (package
    (name \"brave-origin-nightly\")
    (version \"1.99.9\")
    (source (origin (method url-fetch)
                    (uri (string-append
                          \"https://github.com/brave/brave-browser/releases/download/v\"
                          version \"/brave-origin-nightly_\" version \"_amd64.deb\"))
                    (sha256 (base32 \"02m2x2n9vrp7kal3s5vk0rf3d7ggnmjhz3zzzhl3k6ykpija0rj7\"))))
    (build-system copy-build-system)
    ;; Unpacks .deb with ar+tar, patches ELF RUNPATH, writes bin/brave-origin wrapper.
    ;; See file for full phases: unpack, prune, patch-elf, install-wrapper,
    ;;   install-desktop-file-and-icons.
    (supported-systems '(\"x86_64-linux\"))
    (license license:mpl2.0)))")

   ("modules/brave-origin/services/brave-origin.scm" . "\
(define-module (brave-origin services brave-origin)
  #:use-module (gnu services)
  #:use-module (gnu system privilege)
  #:use-module (guix records)
  #:use-module (brave-origin packages brave-origin)
  #:export (brave-origin-configuration brave-origin-service-type))

(define-record-type* <brave-origin-configuration>
  brave-origin-configuration make-brave-origin-configuration
  brave-origin-configuration?
  (package         brave-origin-configuration-package
                   (default brave-origin-nightly))
  (setuid-sandbox? brave-origin-configuration-setuid-sandbox?
                   (default #t)))

(define brave-origin-service-type
  (service-type
   (name 'brave-origin)
   (extensions
    (list (service-extension profile-service-type ...)
          (service-extension privileged-program-service-type ...)))
   (default-value (brave-origin-configuration))
   (description \"Install Brave Origin and its setuid chrome-sandbox.\")))")

   ("modules/brave-origin/home/services/brave-origin.scm" . "\
(define-module (brave-origin home services brave-origin)
  #:use-module (gnu home services)
  #:use-module (brave-origin packages brave-origin)
  #:export (home-brave-origin-configuration home-brave-origin-service-type))

(define-record-type* <home-brave-origin-configuration>
  home-brave-origin-configuration make-home-brave-origin-configuration
  home-brave-origin-configuration?
  (package                (default brave-origin-nightly))
  (default-browser?       (default #f))
  (extensions             (default '()))
  (command-line-arguments (default '())))

(define home-brave-origin-service-type
  (service-type
   (name 'home-brave-origin)
   (extensions
    (list (service-extension home-profile-service-type ...)
          (service-extension home-xdg-configuration-files-service-type ...)
          (service-extension home-xdg-data-files-service-type ...)))
   (default-value (home-brave-origin-configuration))))")

   ("modules/brave-origin/home/services/emacs.scm" . "\
(define-module (brave-origin home services emacs)
  #:use-module (gnu home services)
  #:use-module (gnu packages emacs)
  #:export (home-emacs-simple-configuration home-emacs-simple-service-type))

(define-record-type* <home-emacs-simple-configuration>
  home-emacs-simple-configuration make-home-emacs-simple-configuration
  home-emacs-simple-configuration?
  (package (default emacs-no-x)))

;; Writes ~/.config/emacs/init.el:
;;   relative numbers, no splash, no bars, 2-space indent,
;;   backups in ~/.cache/emacs/

(define home-emacs-simple-service-type
  (service-type (name 'home-emacs-simple) ...))")

   ("modules/brave-origin/home/services/ratpoison.scm" . "\
(define-module (brave-origin home services ratpoison)
  #:use-module (gnu home services)
  #:use-module (gnu packages ratpoison)
  #:export (home-ratpoison-configuration home-ratpoison-service-type))

(define-record-type* <home-ratpoison-configuration>
  home-ratpoison-configuration make-home-ratpoison-configuration
  home-ratpoison-configuration?
  (package     (default ratpoison))
  (extra-lines (default '())))

;; Writes ~/.ratpoisonrc with vim-style hjkl focus and frame bindings,
;; C-t b for Brave Origin, C-t e for Emacs, C-t t for xterm.

(define home-ratpoison-service-type
  (service-type (name 'home-ratpoison) ...))")

   ("security.scm" . "\
'((provenance
   (source-type . binary-native-code)
   (upstream . \"https://github.com/brave/brave-browser/releases\")
   (integrity-verified . #t))
  (store
   (read-only . #t) (setuid-allowed . #f) (elf-runpath-pinned . #t))
  (sandbox
   (architecture . multi-process)
   (mechanisms namespaces seccomp-bpf setuid-helper)
   (setuid-helper
    (paths \"/run/privileged/bin/chrome-sandbox\"))
   (fallback (flag . \"--no-sandbox\") (warning-on-stderr . #t))
   (requires-sudo . #f))
  (privileges
   (browser-runs-as-root . #f)
   (setuid-helper-drops-privileges-before-exec . #t))
  (network
   (shields . #t) (https-only-mode . user-configurable) (telemetry . opt-in))
  (updates (self-update . #f))
  (limitations
   \"Not built from source; trust rests on Brave's releases and the sha256 pin.\"
   \"Qt dialog shims removed; Brave uses GTK dialogs instead.\"
   \"Without setuid helper and user namespaces: --no-sandbox with warning.\"))")))

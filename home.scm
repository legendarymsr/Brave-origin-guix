;;; home.scm --- Brave-origin-guix home-environment configuration
;;;
;;; Pairs with system.scm.  Apply with:
;;;
;;;   guix home reconfigure home.scm
;;;
;;; Requires the brave-origin channel to be pulled first:
;;;   ~/.config/guix/channels.scm → see README.md or README.scm
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 legendarymsr

(use-modules
 (gnu home)
 (gnu home services)
 (gnu home services shells)
 (gnu packages)
 ;; This channel
 (brave-origin home services brave-origin)
 (brave-origin home services emacs)
 (brave-origin home services ratpoison))

(home-environment

 ;; Extra packages available in the user profile
 (packages
  (map specification->package
       '("xterm"
         "font-dejavu"
         "font-liberation"
         "htop"
         "git"
         "curl")))

 (services
  (list

   ;; ── Brave Origin ──────────────────────────────────────────────────────
   (service home-brave-origin-service-type
            (home-brave-origin-configuration
             ;; Register as the default browser via XDG
             (default-browser? #t)
             ;; Pre-install extension IDs (uBlock Origin as example)
             (extensions '("cjpalhdlnbpafiamejdnhcphjbkeiagm"))
             ;; Extra flags; remove or adjust as needed
             (command-line-arguments '("--force-dark-mode"))))

   ;; ── Emacs (terminal, dead-simple) ────────────────────────────────────
   ;; Writes ~/.config/emacs/init.el: relative numbers, no bars, 2-space indent.
   ;; Switch to (package emacs) for the GTK GUI build.
   (service home-emacs-simple-service-type)

   ;; ── Ratpoison ────────────────────────────────────────────────────────
   ;; Writes ~/.ratpoisonrc with vim-style hjkl bindings.
   ;; Prefix: C-t.  Key highlights:
   ;;   C-t b → brave-origin   C-t e → emacs   C-t t → xterm
   ;;   C-t h/j/k/l → focus    C-t s/v → hsplit/vsplit
   (service home-ratpoison-service-type
            (home-ratpoison-configuration
             ;; Add your own lines here, e.g.:
             ;; (extra-lines '("set border 2"
             ;;                "bind m exec mpv"))
             ))

   ;; ── Shell: Bash ───────────────────────────────────────────────────────
   (service home-bash-service-type
            (home-bash-configuration
             (aliases
              '(("ls"  . "ls --color=auto")
                ("ll"  . "ls -lah --color=auto")
                ("brv" . "brave-origin")))
             (bashrc
              (list
               ;; XDG vars for apps that need them
               (plain-file "xdg.sh"
                           (string-append
                            "export XDG_DATA_HOME=\"$HOME/.local/share\"\n"
                            "export XDG_CONFIG_HOME=\"$HOME/.config\"\n"
                            "export XDG_CACHE_HOME=\"$HOME/.cache\"\n"))
               ;; Start Ratpoison when logging in on tty1
               (plain-file "start-ratpoison.sh"
                           (string-append
                            "if [[ -z \"$DISPLAY\" && \"$XDG_VTNR\" -eq 1 ]]; then\n"
                            "  exec startx ~/.xinitrc\n"
                            "fi\n"))))
             (bash-profile
              (list
               (plain-file "guix-profile.sh"
                           (string-append
                            "# Guix home profile\n"
                            "export GUIX_PROFILE=\"$HOME/.guix-home/profile\"\n"
                            ". \"$GUIX_PROFILE/etc/profile\"\n"))))))

   ;; ── .xinitrc: exec ratpoison ──────────────────────────────────────────
   (service home-files-service-type
            (list
             (list ".xinitrc"
                   (plain-file "xinitrc"
                               (string-append
                                "#!/bin/sh\n"
                                "# Set cursor\n"
                                "xsetroot -cursor_name left_ptr\n"
                                "# Load X resources if present\n"
                                "[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources\n"
                                "# Start Ratpoison\n"
                                "exec ratpoison\n"))))))))

;;; home.scm ends here

;;; install.scm --- Brave-origin-guix live + installer ISO
;;;
;;; A bootable Guix System live image that comes up straight into a graphical
;;; Ratpoison session (SLiM autologin as `guest') with Brave Origin (nightly)
;;; installed system-wide and its setuid chrome-sandbox provided by
;;; `brave-origin-service-type'.  Brave Origin is started on login.
;;;
;;; It doubles as the installer: it inherits the stock Guix installation
;;; image (live file systems, passwordless `guest' and root, disk tools,
;;; copy-on-write store for installing) and ships the one-command installer:
;;;
;;;   sudo brave-origin-install /dev/sdX
;;;
;;; (a Guile program from (brave-origin installer); also at
;;; /etc/brave-origin-templates/brave-origin-install, `--help' for usage).
;;;
;;; Text consoles are on Ctrl+Alt+F1..F6 (log in as root, no password).
;;; The Guix *guided* installer is not included: it can only be built from a
;;; pulled Guix or a checkout, not from the Guix release tarball CI uses.
;;;
;;; Build (from the repository root, so `-L modules' finds the channel):
;;;
;;;   guix system image -t iso9660 -L modules install.scm
;;;
;;; Write to USB:
;;;
;;;   sudo dd if=brave-origin-guix-live.iso of=/dev/sdX bs=4M status=progress oflag=sync
;;;
;;; Ratpoison keys (prefix C-t): b brave-origin, t xterm, e emacs,
;;; h/j/k/l focus, s/v split, w remove frame, n/p next/prev window.
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 legendarymsr

(use-modules
 (gnu)
 (gnu system)
 (gnu system install)
 (gnu system privilege)
 (gnu home)
 (gnu services)
 (gnu services base)
 (gnu services guix)                    ; guix-home-service-type
 (gnu services dbus)                    ; dbus-root-service-type
 (gnu services networking)              ; connman, wpa-supplicant
 (gnu services xorg)                    ; slim, xorg-configuration
 (gnu packages admin)                   ; sudo, fastfetch
 (gnu packages curl)                    ; curl
 (gnu packages disk)                    ; parted, gptfdisk
 (gnu packages fonts)                   ; font-dejavu, font-liberation
 (gnu packages ratpoison)               ; ratpoison
 (gnu packages tls)                     ; openssl
 (gnu packages linux)                   ; util-linux (blkid)
 (gnu packages ncurses)                 ; ncurses
 (gnu packages xorg)                    ; xterm, xsetroot
 (guix gexp)
 ;; This channel (build with `-L modules').
 (brave-origin services brave-origin)
 (brave-origin home services ratpoison)
 (brave-origin installer))

(define %live-user "guest")             ; the passwordless user of installation-os

(define %brave-origin-channel-snippet
  "(cons (channel\n\
        (name 'brave-origin)\n\
        (url \"https://github.com/legendarymsr/Brave-origin-guix\")\n\
        (branch \"main\"))\n\
      %default-channels)\n")

;;;
;;; Live desktop: Ratpoison, configured by this channel's home service.
;;;

(define %live-home
  ;; Activated for `guest' at boot by guix-home-service-type: writes
  ;; ~/.ratpoisonrc (C-t b brave-origin, C-t t xterm, hjkl, ...) and opens
  ;; Brave Origin as soon as Ratpoison starts.
  (home-environment
   (services
    (list (service home-ratpoison-service-type
                   (home-ratpoison-configuration
                    (extra-lines '("exec brave-origin"))))))))

(define %live-xsession
  ;; ~/.xsession, run by SLiM's xinitrc.  Guix Home is activated by a
  ;; one-shot Shepherd service that may still be running when SLiM logs us
  ;; in, so wait (briefly) for ~/.ratpoisonrc before starting Ratpoison.
  (computed-file
   "live-xsession"
   #~(begin
       (call-with-output-file #$output
         (lambda (port)
           (format port "#!/bin/sh
# ~~/.xsession -- Brave-origin-guix live session
~a/bin/xsetroot -cursor_name left_ptr -solid '#1a1b26'
i=0
while [ ! -e \"$HOME/.ratpoisonrc\" ] && [ $i -lt 120 ]; do
  sleep 1; i=$((i + 1))
done
exec ~a/bin/ratpoison
"
                   #$xsetroot #$ratpoison)))
       (chmod #$output #o555))))

(define %live-skeletons
  (cons* (list ".xsession" %live-xsession)
         (list ".Xdefaults" (plain-file "Xdefaults" %brave-origin-xdefaults))
         (list ".Xresources" (plain-file "Xresources" %brave-origin-xdefaults))
         ;; Ours replaces the default ~/.Xdefaults.
         (filter (lambda (skeleton)
                   (not (string=? (car skeleton) ".Xdefaults")))
                 (default-skeletons))))

;;;
;;; Packages and services on top of the installation image.
;;;

(define %extra-packages
  (list
   ;; Live desktop
   ratpoison
   xterm
   xsetroot
   font-liberation
   font-dejavu                          ; xterm face (~/.Xdefaults)
   fastfetch
   ncurses                              ; clear, reset, tput
   ;; brave-origin-install (+ tools for doing it by hand)
   brave-origin-installer
   curl
   parted
   gptfdisk
   openssl
   util-linux))

(define %extra-services
  (list
   ;; Brave Origin system-wide + setuid chrome-sandbox in /run/privileged/bin.
   (service brave-origin-service-type)

   ;; Graphical login: SLiM on vt7, autologin straight into the session.
   (service slim-service-type
            (slim-configuration
             (auto-login? #t)
             (default-user %live-user)
             (allow-empty-passwords? #t)
             (xorg-configuration
              (xorg-configuration
               (keyboard-layout (keyboard-layout "us"))
               ;; No screen saver / DPMS blanking on the live desktop.
               (server-arguments
                (cons* "-s" "0" "-dpms"
                       %default-xorg-server-arguments))))))

   ;; ~/.ratpoisonrc & co. for the live user.
   (service guix-home-service-type
            `((,%live-user ,%live-home)))

   (simple-service
    'brave-origin-channel-hint
    etc-service-type
    (list
     (list "channels.scm"
           (plain-file "brave-origin-channels.scm"
                       %brave-origin-channel-snippet))))

   (simple-service
    'brave-origin-templates
    etc-service-type
    (list
     ;; This channel's modules: brave-origin-install runs
     ;; `guix system init -L' on them instead of pulling the channel.
     (list "brave-origin-templates/channel"
           (local-file "modules" "brave-origin-channel" #:recursive? #t))
     (list "brave-origin-templates/README"
           (plain-file "brave-origin-readme"
                       (string-append
                        "Brave Origin Guix System live/installer image\n"
                        "=============================================\n"
                        "\n"
                        "You are in Ratpoison (prefix C-t): C-t b Brave Origin,\n"
                        "C-t t xterm, C-t n/p next/previous window.\n"
                        "\n"
                        "One command installs everything:\n"
                        "\n"
                        "  sudo brave-origin-install /dev/sdX\n"
                        "\n"
                        "(Use lsblk to find your disk name.)\n"
                        "\n"
                        "Asks for: username, password, hostname, timezone.\n"
                        "After it finishes: remove the USB and reboot.\n"
                        "Log in, then run startx to launch Ratpoison.\n"
                        "Brave Origin: C-t b\n")))
     (list "brave-origin-templates/brave-origin-install"
           brave-origin-install-program)
     (list "brave-origin-templates/home.scm"
           (local-file "home.scm"))))))

;;;
;;; Base services for a live medium.
;;;

(define %cow-store-service
  ;; From the stock installation image (not exported): `herd start cow-store
  ;; /mnt' sends store writes to the target disk instead of the RAM-backed
  ;; root during `guix system init'.  brave-origin-install starts it.
  ((@@ (gnu system install) cow-store-service)))

(define %live-base-services
  (cons*
   %cow-store-service
   ;; Networking, like the stock installer.
   (service wpa-supplicant-service-type)
   (service dbus-root-service-type)
   (service connman-service-type
            (connman-configuration
             (disable-vpn? #t)))
   (modify-services %base-services
     ;; Passwordless root shells on tty2-tty6, as on the stock installer.
     (mingetty-service-type
      config => (if (string=? "tty1" (mingetty-configuration-tty config))
                    config
                    (mingetty-configuration
                     (inherit config)
                     (auto-login "root")
                     (login-pause? #t)))))))

(operating-system
 (inherit installation-os)

 (host-name "brave-origin-live")
 (timezone "UTC")
 (locale "en_US.utf8")
 (label "Brave Origin Guix live")

 (keyboard-layout (keyboard-layout "us"))

 ;; installation-os resolves .local names through Avahi, which is not run here.
 (name-service-switch %default-nss)

 (skeletons %live-skeletons)

 (packages
  (append %extra-packages
          (operating-system-packages installation-os)))

 ;; installation-os only has a setuid passwd; add sudo so the passwordless
 ;; `guest' (in "wheel") can run the installer from the desktop.
 (privileged-programs
  (append (list (file-like->setuid-program (file-append sudo "/bin/sudo")))
          (operating-system-privileged-programs installation-os)))

 (services
  (append %extra-services
          %live-base-services)))

;;; install.scm ends here

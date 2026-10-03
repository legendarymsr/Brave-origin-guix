;;; install.scm --- Custom Guix installer ISO for Brave-origin-guix
;;;
;;; Extends the stock Guix installer OS with the brave-origin channel
;;; pre-seeded and the one-command install script on the live system.
;;;
;;; Build:
;;;   guix system image -t iso9660 install.scm
;;;
;;; Write to USB:
;;;   sudo dd if=result of=/dev/sdX bs=4M status=progress oflag=sync
;;;
;;; Once booted (terminal-only live env):
;;;   bash /etc/brave-origin-templates/brave-origin-install /dev/sdX
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 legendarymsr

(use-modules
 (gnu)
 (gnu system)
 (gnu system install)
 (gnu services)
 (gnu services base)
 (gnu packages curl)   ; curl
 (gnu packages disk)   ; parted, gptfdisk
 (gnu packages tls)    ; openssl
 (gnu packages linux)  ; util-linux (blkid)
 (guix gexp))

(define %brave-origin-channel-snippet
  "(cons (channel\n\
        (name 'brave-origin)\n\
        (url \"https://github.com/legendarymsr/Brave-origin-guix\")\n\
        (branch \"main\"))\n\
      %default-channels)\n")

;;; Minimal extra packages — only what brave-origin-install needs.
(define %extra-packages
  (list
   curl
   parted
   gptfdisk
   openssl
   util-linux))

(define %extra-services
  (list
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
     (list "brave-origin-templates/README"
           (plain-file "brave-origin-readme"
                       (string-append
                        "Brave Origin Guix System Installer\n"
                        "====================================\n"
                        "\n"
                        "One command installs everything:\n"
                        "\n"
                        "  bash /etc/brave-origin-templates/brave-origin-install /dev/sdX\n"
                        "\n"
                        "(Use lsblk to find your disk name.)\n"
                        "\n"
                        "Asks for: username, password, hostname, timezone.\n"
                        "After it finishes: remove the USB and reboot.\n"
                        "Log in, then run startx to launch Ratpoison.\n"
                        "Brave Origin: C-t b\n")))
     (list "brave-origin-templates/brave-origin-install"
           (local-file "installer/brave-origin-install"))))))

(operating-system
 (inherit installation-os)

 (host-name "brave-origin-installer")
 (timezone "UTC")
 (locale "en_US.utf8")

 (keyboard-layout (keyboard-layout "us"))

 (packages
  (append %extra-packages
          (operating-system-packages installation-os)))

 (services
  (append %extra-services
          (operating-system-services installation-os))))

;;; install.scm ends here

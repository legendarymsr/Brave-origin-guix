;;; install.scm --- Custom Guix installer ISO for Brave-origin-guix
;;;
;;; Extends the stock Guix installer OS with the brave-origin channel
;;; pre-configured and Ratpoison available in the live environment so
;;; you can browse documentation during install.
;;;
;;; Build the ISO (takes a while; ~1–2 GB):
;;;
;;;   guix system image -t iso9660 install.scm
;;;
;;; Write it to a USB drive:
;;;
;;;   sudo dd if=$(guix system image -t iso9660 install.scm) \
;;;            of=/dev/sdX bs=4M status=progress oflag=sync
;;;
;;; Or with pv:
;;;
;;;   guix system image -t iso9660 install.scm | \
;;;     sudo pv > /dev/sdX
;;;
;;; Once booted:
;;;   1. Log in as root (no password in the installer).
;;;   2. Partition and format your disk (cfdisk / parted).
;;;   3. Mount root at /mnt (and /mnt/boot/efi for UEFI).
;;;   4. Copy system.scm to /mnt/etc/config.scm and edit the FIXMEs.
;;;   5. guix system init /mnt/etc/config.scm /mnt
;;;   6. Reboot, pull the brave-origin channel, run: guix home reconfigure home.scm
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 legendarymsr

(use-modules
 (gnu)
 (gnu system)
 (gnu system install)
 (gnu services)
 (gnu services base)
 (gnu services networking)
 (gnu services xorg)
 (gnu packages xorg)
 (gnu packages wm)
 (gnu packages terminals)
 (gnu packages curl)
 (gnu packages admin)
 (gnu packages fonts)
 (gnu packages version-control)
 (guix gexp))

;;;
;;; Brave-origin channel definition (embedded so the installer can
;;; guide the user to pull it immediately after first boot).
;;;

(define %brave-origin-channel-snippet
  ;; Written to /etc/channels.scm in the live image so the user can
  ;; copy it to /mnt/root/.config/guix/channels.scm during install.
  "(cons (channel\n\
        (name 'brave-origin)\n\
        (url \"https://github.com/legendarymsr/Brave-origin-guix\")\n\
        (branch \"main\"))\n\
      %default-channels)\n")

;;;
;;; Xorg config for the live environment
;;;

(define %installer-xorg
  (xorg-configuration
   (keyboard-layout (keyboard-layout "us"))))

;;;
;;; Extra packages available in the live ISO
;;;

(define %extra-packages
  (list
   ;; Tiling WM — run `ratpoison' after `startx' to get a graphical env
   ratpoison
   ;; Terminal
   xterm
   ;; Network
   curl
   ;; Fonts (so xterm is legible)
   font-dejavu
   ;; Handy during install
   git
   htop
   parted
   ;; gptfdisk for sgdisk
   gptfdisk))

;;;
;;; Extra services for the live ISO
;;;

(define %extra-services
  (list
   ;; Xorg server so the user can start a graphical session
   (service xorg-server-service-type %installer-xorg)

   ;; Seed a channels.scm for the brave-origin channel in /etc
   (simple-service
    'brave-origin-channel-hint
    etc-service-type
    (list
     (list "channels.scm"
           (plain-file "brave-origin-channels.scm"
                       %brave-origin-channel-snippet))))

   ;; Seed system.scm + home.scm into /etc/brave-origin-templates/
   ;; so the user has a starting point without needing network access.
   (simple-service
    'brave-origin-templates
    etc-service-type
    (list
     (list "brave-origin-templates/README"
           (plain-file "brave-origin-readme"
                       (string-append
                        "Brave-origin-guix installation templates\n"
                        "========================================\n"
                        "\n"
                        "Brave Origin is NOT on this ISO — it is downloaded and installed\n"
                        "on your target disk during `guix system init'.  The ISO stays\n"
                        "small; your disk gets everything.\n"
                        "\n"
                        "Files in this directory:\n"
                        "\n"
                        "  system.scm  — operating-system declaration (includes brave-origin)\n"
                        "               Copy to /mnt/etc/config.scm and edit FIXMEs.\n"
                        "\n"
                        "  home.scm    — home-environment declaration\n"
                        "               Apply after first boot.\n"
                        "\n"
                        "Quick install steps:\n"
                        "\n"
                        "  1. cfdisk /dev/sdX                          # partition\n"
                        "  2. mkfs.ext4 /dev/sdXn                      # format root\n"
                        "     mkfs.vfat /dev/sdX1                      # EFI (if UEFI)\n"
                        "  3. mount /dev/sdXn /mnt\n"
                        "     mkdir -p /mnt/boot/efi\n"
                        "     mount /dev/sdX1 /mnt/boot/efi\n"
                        "  4. cp /etc/brave-origin-templates/system.scm /mnt/etc/config.scm\n"
                        "  5. nano /mnt/etc/config.scm                 # fill in FIXMEs\n"
                        "  6. guix system init /mnt/etc/config.scm /mnt\n"
                        "     (Brave Origin is fetched from the internet here)\n"
                        "  7. reboot\n"
                        "\n"
                        "After first boot:\n"
                        "\n"
                        "  mkdir -p ~/.config/guix\n"
                        "  cp /etc/channels.scm ~/.config/guix/channels.scm\n"
                        "  guix pull\n"
                        "  guix home reconfigure /etc/brave-origin-templates/home.scm\n"
                        "  startx\n")))))))

;;;
;;; The custom installer OS
;;;
;;; `installation-os' from (gnu system install) is the stock Guix
;;; installer.  We inherit from it and layer our additions on top.
;;;

(operating-system
 (inherit installation-os)

 (host-name "brave-origin-installer")
 (timezone "UTC")
 (locale "en_US.utf8")

 ;; Keyboard layout passed to both the kernel and Xorg
 (keyboard-layout (keyboard-layout "us"))

 ;; Merge our extra packages with whatever the stock installer provides
 (packages
  (append %extra-packages
          (operating-system-packages installation-os)))

 ;; Merge our extra services
 (services
  (append %extra-services
          (operating-system-services installation-os))))

;;; install.scm ends here

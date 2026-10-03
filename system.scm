;;; system.scm --- Brave-origin-guix target system configuration
;;;
;;; Full operating-system declaration for a Guix System install that ships
;;; Brave Origin, Ratpoison, and Emacs out of the box.
;;;
;;; Usage (after partitioning and mounting at /mnt):
;;;
;;;   guix system init system.scm /mnt
;;;
;;; Or to reconfigure a running system:
;;;
;;;   sudo guix system reconfigure system.scm
;;;
;;; IMPORTANT: adjust the marked sections (FIXME) for your hardware before use:
;;;   - bootloader device
;;;   - file-system UUIDs / devices
;;;   - hostname, timezone, locale
;;;   - user name and groups
;;;
;;; Requires the brave-origin channel to be pulled first:
;;;   ~/.config/guix/channels.scm → see README.md or README.scm
;;;
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 legendarymsr

(use-modules
 ;; Guix core
 (gnu)
 (gnu system)
 (gnu system install)
 ;; Bootloader
 (gnu bootloader)
 (gnu bootloader grub)
 ;; File systems
 (gnu system file-systems)
 ;; Services
 (gnu services)
 (gnu services base)
 (gnu services desktop)
 (gnu services networking)
 (gnu services ssh)
 (gnu services xorg)
 ;; Packages
 (gnu packages xorg)
 (gnu packages wm)
 (gnu packages terminals)
 (gnu packages fonts)
 (gnu packages admin)
 ;; This channel
 (brave-origin services brave-origin))

;;;
;;; Bootloader
;;;

(define %bootloader
  (bootloader-configuration
   (bootloader grub-efi-bootloader)
   (targets '("/boot/efi"))               ; FIXME: "/dev/sda" for BIOS/MBR
   (keyboard-layout (keyboard-layout "us"))))

;;;
;;; File systems  (FIXME: replace UUIDs with your actual disk UUIDs)
;;;
;;; Tip:  lsblk -o NAME,UUID,FSTYPE,MOUNTPOINT
;;;

(define %file-systems
  (list
   ;; Root
   (file-system
    (mount-point "/")
    (device (uuid "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" 'ext4))  ; FIXME
    (type "ext4"))
   ;; EFI system partition (remove if using BIOS/MBR)
   (file-system
    (mount-point "/boot/efi")
    (device (uuid "XXXX-XXXX" 'fat32))                           ; FIXME
    (type "vfat"))
   ;; Swap (optional; alternatively use a swap file)
   ;; (swap-space (target (uuid "…")))
   ))

;;;
;;; Users
;;;

(define %user-name "user")                ; FIXME: your username

(define %users
  (list
   (user-account
    (name %user-name)
    (comment "Brave Origin user")
    (group "users")
    (supplementary-groups
     '("wheel"     ; sudo
       "netdev"    ; network manager
       "audio"
       "video"
       "input"     ; evdev / libinput
       "kvm"))     ; virtualisation (optional)
    (home-directory (string-append "/home/" %user-name)))))

;;;
;;; Packages installed system-wide
;;;

(define %system-packages
  (append
   (list
    ;; Xorg essentials
    xterm
    ratpoison
    ;; Fonts
    font-dejavu
    font-liberation
    ;; Utilities
    git
    curl
    htop
    nss-certs)   ; TLS certificates for HTTPS
   %base-packages))

;;;
;;; Services
;;;

(define %xorg-config
  (xorg-configuration
   (keyboard-layout (keyboard-layout "us"))))

(define %services
  (cons*
   ;; Brave Origin + setuid chrome-sandbox
   (service brave-origin-service-type)

   ;; Xorg — starts an X server; log in at the console and run `startx'
   ;; or switch to slim/gdm by replacing with slim-service-type.
   (service xorg-server-service-type %xorg-config)

   ;; Networking via NetworkManager (or replace with dhcpd-service-type)
   (service network-manager-service-type)
   (service wpa-supplicant-service-type)

   ;; Optional: SSH server
   ;; (service openssh-service-type
   ;;          (openssh-configuration
   ;;           (port-number 22)
   ;;           (permit-root-login #f)
   ;;           (password-authentication? #f)))

   %base-services))

;;;
;;; Operating system
;;;

(operating-system
 (host-name "brave-origin-box")           ; FIXME: your hostname
 (timezone "UTC")                         ; FIXME: e.g. "America/New_York"
 (locale "en_US.utf8")                    ; FIXME: your locale

 (keyboard-layout (keyboard-layout "us"))

 (bootloader %bootloader)
 (file-systems %file-systems)

 (users (append %users %base-user-accounts))
 (packages %system-packages)
 (services %services))

;;; system.scm ends here

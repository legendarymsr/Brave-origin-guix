;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (brave-origin installer)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)      ;coreutils
  #:use-module (gnu packages disk)      ;gptfdisk, parted, dosfstools
  #:use-module (gnu packages linux)     ;util-linux, e2fsprogs
  #:export (brave-origin-install-program
            brave-origin-installer))

;;; Commentary:
;;;
;;; `brave-origin-install': one-command Guix System + Brave Origin installer,
;;; written in Guile.  The live image (install.scm at the repository root)
;;; ships it at /etc/brave-origin-templates/brave-origin-install and, through
;;; the `brave-origin-installer' package, as `brave-origin-install' in PATH.
;;;
;;;   sudo brave-origin-install /dev/sdX
;;;   sudo brave-origin-install --dry-run /dev/sdX   ; prompts, prints plan
;;;   brave-origin-install --help
;;;
;;; Partition layout (GPT, UEFI):
;;;   1 GB   EFI   (FAT32, /boot/efi)
;;;   4 GB   swap
;;;   rest   /     (root, ext4; holds /gnu too)
;;;
;;; Steps: partition, format, mount (and start the live image's cow-store on
;;; /mnt), write /mnt/etc/config.scm, pull the brave-origin channel from
;;; /etc/channels.scm, then `guix system init' -- Brave Origin is fetched
;;; there, not from the ISO.
;;;
;;; Code:

(define brave-origin-install-program
  (program-file
   "brave-origin-install"
   (with-imported-modules '((guix build utils))
     #~(begin
         (use-modules (guix build utils)
                      (ice-9 match)
                      (ice-9 rdelim)
                      (ice-9 popen)
                      (ice-9 pretty-print)
                      (srfi srfi-1)
                      (srfi srfi-34))

         ;; Tools, by store file name: no dependency on the caller's PATH.
         (define sgdisk    #$(file-append gptfdisk "/bin/sgdisk"))
         (define partprobe #$(file-append parted "/sbin/partprobe"))
         (define mkfs.vfat #$(file-append dosfstools "/sbin/mkfs.vfat"))
         (define mkfs.ext4 #$(file-append e2fsprogs "/sbin/mkfs.ext4"))
         (define mkswap    #$(file-append util-linux "/sbin/mkswap"))
         (define swapon    #$(file-append util-linux "/sbin/swapon"))
         (define blkid     #$(file-append util-linux "/sbin/blkid"))
         (define mount     #$(file-append util-linux "/bin/mount"))
         (define stty      #$(file-append coreutils "/bin/stty"))
         ;; herd and guix belong to the running system.
         (define herd "herd")
         (define guix "guix")

         (define rule (make-string 60 #\━))

         ;; ── Output ──────────────────────────────────────────────────────
         (define (say color fmt . args)
           (format #t "\x1b[~am~?\x1b[0m~%" color fmt args)
           (force-output))
         (define (red fmt . args)    (apply say "1;31" fmt args))
         (define (green fmt . args)  (apply say "1;32" fmt args))
         (define (yellow fmt . args) (apply say "1;33" fmt args))
         (define (bold fmt . args)   (apply say "1" fmt args))
         (define (die fmt . args)
           (apply red (string-append "ERROR: " fmt) args)
           (exit 1))

         (define (usage port)
           (format port "Usage: brave-origin-install [--dry-run] DISK
       brave-origin-install --help

One-command Guix System + Brave Origin installer.  ERASES DISK, then:
  1 GB EFI (FAT32, /boot/efi) | 4 GB swap | rest / (ext4, holds /gnu)
writes /mnt/etc/config.scm, pulls the brave-origin channel and runs
`guix system init'.  Asks for username, password, hostname and timezone.

  --dry-run   ask the questions, then print the commands and the generated
              config.scm instead of touching DISK
  --help      show this help

Examples:
  sudo brave-origin-install /dev/sda
  sudo brave-origin-install /dev/nvme0n1~%"))

         ;; ── Input ───────────────────────────────────────────────────────
         (define (ask prompt default)
           (display (if default
                        (string-append "  " prompt " [" default "]: ")
                        (string-append "  " prompt ": ")))
           (force-output)
           (let ((line (read-line)))
             (cond ((eof-object? line) (newline) (die "unexpected end of input"))
                   ((and default (string-null? (string-trim-both line)))
                    default)
                   (else (string-trim-both line)))))

         (define (ask-secret prompt)
           ;; Turn off echo on the terminal while reading.
           (dynamic-wind
             (lambda () (when (isatty? (current-input-port))
                          (system* stty "-echo")))
             (lambda () (let ((line (ask prompt #f))) (newline) line))
             (lambda () (when (isatty? (current-input-port))
                          (system* stty "echo")))))

         (define (ask-password user)
           (let loop ()
             (let* ((pw      (ask-secret (string-append "Password for " user)))
                    (confirm (ask-secret "Confirm password")))
               (cond ((string-null? pw)
                      (yellow "  Empty password, try again.") (loop))
                     ((string=? pw confirm) pw)
                     (else
                      (yellow "  Passwords do not match, try again.") (loop))))))

         ;; ── Helpers ─────────────────────────────────────────────────────
         (define (partition-name disk n)
           ;; /dev/sda -> /dev/sda1, /dev/nvme0n1 -> /dev/nvme0n1p1.
           (string-append disk
                          (if (or (string-contains disk "nvme")
                                  (string-contains disk "mmcblk")
                                  (string-contains disk "loop"))
                              "p" "")
                          (number->string n)))

         (define (block-device? file)
           (and (file-exists? file)
                (eq? 'block-special (stat:type (stat file)))))

         (define (sha512-crypt password)
           ;; "$6$" + 16 random salt characters, through libc's crypt(3).
           (define alphabet
             "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
           (let* ((bytes (call-with-input-file "/dev/urandom"
                           (lambda (port)
                             (map (lambda (_) (char->integer (read-char port)))
                                  (iota 16)))
                           #:binary #t))
                  (salt  (list->string
                          (map (lambda (b) (string-ref alphabet (modulo b 64)))
                               bytes)))
                  (hash  (crypt password (string-append "$6$" salt "$"))))
             (unless (string-prefix? "$6$" hash)
               (die "crypt(3) does not support SHA-512 here"))
             hash))

         (define (uuid-of device)
           (let* ((port (open-pipe* OPEN_READ blkid "-s" "UUID" "-o" "value"
                                    device))
                  (uuid (read-line port)))
             (close-pipe port)
             (if (eof-object? uuid)
                 (die "no UUID for ~a" device)
                 (string-trim-both uuid))))

         ;; ── The generated operating system ──────────────────────────────
         (define %xinitrc
           "#!/bin/sh\nxsetroot -cursor_name left_ptr\nexec ratpoison\n")

         (define (system-config host tz user hash root efi swap)
           ;; Return the forms of /mnt/etc/config.scm.
           `((use-modules (gnu)
                          (brave-origin services brave-origin))
             (use-service-modules base dbus desktop networking xorg)
             (use-package-modules admin curl fonts ratpoison version-control
                                  xorg)

             (operating-system
               (host-name ,host)
               (timezone ,tz)
               (locale "en_US.utf8")
               (keyboard-layout (keyboard-layout "us"))

               (bootloader
                (bootloader-configuration
                 (bootloader grub-efi-bootloader)
                 (targets '("/boot/efi"))
                 ;; Inside operating-system, `keyboard-layout' names the
                 ;; field above.
                 (keyboard-layout keyboard-layout)))

               (swap-devices
                (list (swap-space (target (uuid ,swap)))))

               (file-systems
                (cons* (file-system
                         (mount-point "/")
                         (device (uuid ,root 'ext4))
                         (type "ext4"))
                       (file-system
                         (mount-point "/boot/efi")
                         (device (uuid ,efi 'fat32))
                         (type "vfat"))
                       %base-file-systems))

               (users
                (cons* (user-account
                         (name ,user)
                         (comment "Brave Origin user")
                         (group "users")
                         (password ,hash)
                         (supplementary-groups
                          '("wheel" "netdev" "audio" "video" "input")))
                       %base-user-accounts))

               ;; ~/.xinitrc for new accounts: `startx' starts Ratpoison.
               (skeletons
                (cons (list ".xinitrc" (plain-file "xinitrc" ,%xinitrc))
                      (default-skeletons)))

               (packages
                (append (list ratpoison xterm xsetroot font-dejavu git curl
                              htop fastfetch)
                        %base-packages))

               (services
                (cons* (service brave-origin-service-type)
                       ;; X for xinit, plus `startx'; elogind lets X run
                       ;; without root on the login VT.
                       (service xorg-server-service-type
                                (xorg-configuration
                                 (keyboard-layout keyboard-layout)))
                       (service startx-command-service-type
                                (xorg-configuration
                                 (keyboard-layout keyboard-layout)))
                       (service elogind-service-type)
                       (service dbus-root-service-type)
                       (service network-manager-service-type)
                       (service wpa-supplicant-service-type)
                       %base-services)))))

         (define (write-config port forms)
           (display ";;; /etc/config.scm -- Brave Origin Guix System
;;; Generated by brave-origin-install.  Needs the brave-origin channel
;;; (see /etc/channels.scm on the live image).
" port)
           (for-each (lambda (form)
                       (newline port)
                       (pretty-print form port))
                     forms))

         ;; ── Main ────────────────────────────────────────────────────────
         (define (main dry-run? disk)
           (define (run . command)
             (if dry-run?
                 (format #t "  would run: ~a~%" (string-join command " "))
                 (apply invoke command)))

           (unless (or dry-run? (zero? (getuid)))
             (die "Run as root: sudo brave-origin-install ~a" disk))
           (unless (block-device? disk)
             (die "~a is not a block device" disk))

           (let ((efi   (partition-name disk 1))
                 (swap  (partition-name disk 2))
                 (root  (partition-name disk 3)))
             (bold rule)
             (bold " Brave Origin Guix System Installer~a"
                   (if dry-run? "  (dry run)" ""))
             (bold rule)
             (newline)
             (yellow "  Target disk : ~a" disk)
             (yellow "  Layout:")
             (yellow "    ~a  →  1 GB   EFI   (FAT32, /boot/efi)" efi)
             (yellow "    ~a  →  4 GB   swap" swap)
             (yellow "    ~a  →  rest   /     (root, ext4; holds /gnu too)" root)
             (newline)
             (red "  ALL DATA ON ~a WILL BE DESTROYED." disk)
             (newline)
             (unless (string=? "YES" (ask "Type YES to continue" #f))
               (display "Aborted.\n")
               (exit 0))
             (newline)

             (let* ((user     (ask "Username" "user"))
                    (password (ask-password user))
                    (host     (ask "Hostname" "brave-origin"))
                    (tz       (ask "Timezone" (or (getenv "TZ") "UTC"))))
               (newline)
               (green "Starting installation…")
               (newline)

               (bold "[ 1/6 ] Partitioning ~a…" disk)
               (run sgdisk "--zap-all" disk)
               (run sgdisk "--new=1:0:+1G" "--typecode=1:ef00"
                    "--change-name=1:EFI" disk)
               (run sgdisk "--new=2:0:+4G" "--typecode=2:8200"
                    "--change-name=2:swap" disk)
               ;; No separate /gnu: a 4 GB store partition is too small for
               ;; the system plus the pulled Guix (the NixOS twin of this
               ;; installer filled its 4 GB /nix in a test install).
               (run sgdisk "--new=3:0:0" "--typecode=3:8300"
                    "--change-name=3:GuixOS" disk)
               (run partprobe disk)
               (unless dry-run? (sleep 1))

               (bold "[ 2/6 ] Formatting…")
               (run mkfs.vfat "-F32" "-n" "EFI" efi)
               (run mkswap "-L" "swap" swap)
               (run mkfs.ext4 "-F" "-L" "GuixOS" root)

               (bold "[ 3/6 ] Mounting…")
               ;; Give udev a moment to re-probe the new filesystems, and
               ;; name the types rather than rely on autodetection.
               (unless dry-run? (sleep 2))
               (run mount "-t" "ext4" root "/mnt")
               (unless dry-run?
                 (mkdir-p "/mnt/boot/efi"))
               (run mount "-t" "vfat" efi "/mnt/boot/efi")
               (run swapon swap)
               (unless dry-run? (mkdir-p "/mnt/etc"))
               ;; Send store writes to the target disk instead of the live
               ;; image's RAM-backed overlay (cow-store exists on the live
               ;; image only; ignore it elsewhere).
               (if dry-run?
                   (run herd "start" "cow-store" "/mnt")
                   (unless (zero? (system* herd "start" "cow-store" "/mnt"))
                     (yellow "  (no cow-store service; continuing)")))

               (bold "[ 4/6 ] Writing system configuration…")
               (let ((forms (if dry-run?
                                (system-config host tz user
                                               (sha512-crypt password)
                                               "ROOT-UUID" "EFI-UUID"
                                               "SWAP-UUID")
                                (system-config host tz user
                                               (sha512-crypt password)
                                               (uuid-of root) (uuid-of efi)
                                               (uuid-of swap)))))
                 (if dry-run?
                     (begin
                       (display "  would write /mnt/etc/config.scm:\n\n")
                       (write-config (current-output-port) forms)
                       (newline))
                     (call-with-output-file "/mnt/etc/config.scm"
                       (lambda (port) (write-config port forms)))))

               (bold "[ 5/6 ] Pulling brave-origin channel…")
               ;; As root, with HOME=/root, so the pulled Guix lands in
               ;; /root/.config/guix/current and is used for the init below.
               (setenv "HOME" "/root")
               (unless dry-run?
                 (mkdir-p "/root/.config/guix")
                 (copy-file "/etc/channels.scm"
                            "/root/.config/guix/channels.scm"))
               (run guix "pull" "--disable-authentication")

               (bold "[ 6/6 ] Running guix system init (Brave Origin fetched from channel)…")
               (run "/root/.config/guix/current/bin/guix" "system" "init"
                    "/mnt/etc/config.scm" "/mnt")

               (newline)
               (bold rule)
               (if dry-run?
                   (green " Dry run finished; nothing was changed.")
                   (green " Done! Remove the USB and reboot."))
               (bold rule)
               (newline)
               (display "  reboot\n\n")
               (display "  After login → startx → Ratpoison\n")
               (display "  Brave Origin: C-t b\n\n")
               (display "  Optionally apply the home config:\n")
               (display "    guix home reconfigure /etc/brave-origin-templates/home.scm\n\n"))))

         (match (command-line)
           ((_ (or "-h" "--help"))
            (usage (current-output-port)))
           ((_ "--dry-run" disk)
            (main #t disk))
           ((_ disk)
            (when (string-prefix? "-" disk)
              (usage (current-error-port))
              (exit 1))
            (guard (c ((invoke-error? c)
                       (die "command failed (exit ~a): ~a ~a"
                            (invoke-error-exit-status c)
                            (invoke-error-program c)
                            (string-join (invoke-error-arguments c) " "))))
              (main #f disk)))
           (_
            (usage (current-error-port))
            (exit 1)))))))

(define-public brave-origin-installer
  ;; The program above as `bin/brave-origin-install', for profiles.
  (package
    (name "brave-origin-installer")
    (version "0.1")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list #:builder
           (with-imported-modules '((guix build utils))
             #~(begin
                 (use-modules (guix build utils))
                 (let ((bin (string-append #$output "/bin")))
                   (mkdir-p bin)
                   (symlink #$brave-origin-install-program
                            (string-append bin "/brave-origin-install")))))))
    (home-page "https://github.com/legendarymsr/Brave-origin-guix")
    (synopsis "One-command Guix System + Brave Origin installer")
    (description
     "@command{brave-origin-install DISK} partitions and formats DISK (EFI,
swap and root), writes an @code{operating-system} with Brave
Origin and Ratpoison, pulls the brave-origin channel and runs @command{guix
system init}.  Meant for the Brave-origin-guix live image.")
    (license license:gpl3+)))

;;; installer.scm ends here

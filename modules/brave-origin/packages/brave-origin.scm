;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;;
;;; This file is part of brave-origin-guix.
;;;
;;; brave-origin-guix is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by the
;;; Free Software Foundation; either version 3 of the License, or (at your
;;; option) any later version.  See the LICENSE file at the repository root.
;;;
;;; NOTE: this channel repackages Brave's prebuilt binaries.  It is not, and
;;; can never be, part of upstream Guix.

(define-module (brave-origin packages brave-origin)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix build-system copy)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cups)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages nss)
  #:use-module (gnu packages pciutils)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages video)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages xorg)
  #:export (brave-origin-nightly
            %brave-origin-sandbox-candidates))

;;; Commentary:
;;;
;;; Brave Origin, nightly channel, repackaged from the official .deb that
;;; Brave publishes on GitHub (same source as the brave-origin-nix flake).
;;;
;;; - The .deb is unpacked with `ar' + `tar' (no dpkg needed).
;;; - Every ELF file gets Guix's dynamic linker as interpreter and a RUNPATH
;;;   that points at the exact store libraries it needs (NEEDED entries and
;;;   the libraries Chromium dlopen()s: GTK, EGL/GL, libpci, PulseAudio, …).
;;;   No nonguix, no FHS container, no LD_LIBRARY_PATH.
;;; - `bin/brave-origin' is a small wrapper that picks the sandbox mode:
;;;     1. a setuid-root chrome-sandbox under /run/privileged/bin (what
;;;        `brave-origin-service-type' installs) -> CHROME_DEVEL_SANDBOX;
;;;     2. otherwise, if unprivileged user namespaces work, Chromium's own
;;;        namespace sandbox is used (no flag needed, still fully sandboxed);
;;;     3. otherwise it prints a warning on stderr and adds --no-sandbox.
;;;   It never tries to gain privileges itself (no sudo, no setuid hacks).
;;; - One desktop file (com.brave.Origin.nightly.desktop) and hicolor icons
;;;   named `brave-origin'.
;;;
;;; Bump with `guix repl -- update.scm' from the repository root.
;;;
;;; Code:

(define %brave-origin-sandbox-candidates
  ;; Where the wrapper looks for a setuid-root chrome-sandbox, in order.
  ;; /run/privileged/bin is where Guix System's privileged-program service
  ;; puts it; /run/setuid-programs is the deprecated pre-2024 location.
  '("/run/privileged/bin/chrome-sandbox"
    "/run/setuid-programs/chrome-sandbox"))

(define %runtime-libraries
  ;; Libraries Brave links against or dlopen()s at run time.  Their /lib
  ;; directories end up in the RUNPATH of every ELF file in the package.
  (list alsa-lib
        at-spi2-core                    ;atk, atk-bridge, atspi
        cairo
        cups-minimal
        dbus
        eudev                           ;libudev
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk+                            ;dlopen()ed by the GTK UI backend
        libdrm
        libnotify
        libsecret
        libva                           ;VA-API video decoding
        libx11
        libxcb
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxkbcommon
        libxrandr
        libxrender
        libxscrnsaver
        libxshmfence
        libxtst
        mesa                            ;libgbm, libEGL, libGL, libGLESv2
        nspr
        pango
        pciutils                        ;libpci, GPU detection
        pulseaudio                      ;libpulse
        wayland))

(define-public brave-origin-nightly
  (package
    (name "brave-origin-nightly")
    (version "1.99.9")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/brave/brave-browser/releases/download/v"
             version "/brave-origin-nightly_" version "_amd64.deb"))
       (sha256
        (base32 "02m2x2n9vrp7kal3s5vk0rf3d7ggnmjhz3zzzhl3k6ykpija0rj7"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:substitutable? #f               ;prebuilt binary; just fetch the .deb
      #:strip-binaries? #f              ;already stripped, and huge
      #:install-plan
      #~'(("opt/brave.com/brave-origin-nightly/"
           "libexec/brave-origin-nightly/")
          ("usr/share/man/" "share/man/")
          ("usr/share/doc/brave-origin-nightly/"
           #$(string-append "share/doc/" name "-" version "/"))
          ("usr/share/appdata/" "share/metainfo/")
          ("usr/share/applications/com.brave.Origin.nightly.desktop"
           "share/applications/"))
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack
            (lambda* (#:key source #:allow-other-keys)
              (invoke "ar" "x" source)
              (invoke "tar" "-xf" "data.tar.xz"
                      "--no-same-owner" "--no-same-permissions")
              (for-each delete-file
                        '("control.tar.xz" "data.tar.xz" "debian-binary"))))
          (add-after 'unpack 'prune
            (lambda _
              (with-directory-excursion "opt/brave.com/brave-origin-nightly"
                ;; Absolute symlink into /opt, apt cron job for self-updates,
                ;; and the Qt dialog shims (they would drag in all of Qt;
                ;; Brave falls back to GTK dialogs without them).
                (for-each delete-file
                          '("brave-origin" "libqt5_shim.so" "libqt6_shim.so"))
                (delete-file-recursively "cron"))))
          (add-after 'install 'patch-elf
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((libexec (string-append #$output
                                             "/libexec/brave-origin-nightly"))
                     (ld.so (search-input-file inputs
                                               "/lib/ld-linux-x86-64.so.2"))
                     (runpath
                      (string-join
                       (append
                        (list libexec
                              (dirname ld.so)
                              (string-append #$gcc:lib "/lib")
                              (string-append #$(this-package-input "nss")
                                             "/lib/nss"))
                        (list #$@(map (lambda (pkg) (file-append pkg "/lib"))
                                      %runtime-libraries)))
                       ":")))
                (with-directory-excursion libexec
                  (for-each (lambda (exe)
                              (invoke "patchelf" "--set-interpreter" ld.so
                                      "--set-rpath" runpath exe))
                            '("brave" "chrome_crashpad_handler"
                              "chrome-management-service" "chrome-sandbox"))
                  (for-each (lambda (lib)
                              (invoke "patchelf" "--set-rpath" runpath lib))
                            (find-files "." "\\.so(\\.[0-9]+)*$"))))))
          (add-after 'patch-elf 'install-wrapper
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((bin (string-append #$output "/bin"))
                     (wrapper (string-append bin "/brave-origin"))
                     (target (string-append
                              #$output "/libexec/brave-origin-nightly/"
                              "brave-origin-nightly"))
                     (bash (search-input-file inputs "/bin/bash"))
                     (unshare (search-input-file inputs "/bin/unshare"))
                     (data-dirs
                      (string-join
                       (list (string-append #$output "/share")
                             #$(file-append gsettings-desktop-schemas "/share")
                             #$(file-append gtk+ "/share")
                             #$(file-append mesa "/share")) ;Vulkan ICDs
                       ":"))
                     (path (string-join
                            (list #$(file-append coreutils "/bin")
                                  #$(file-append xdg-utils "/bin"))
                            ":")))
                (mkdir-p bin)
                (call-with-output-file wrapper
                  (lambda (port)
                    (format port "#!~a
# brave-origin -- Guix wrapper for Brave Origin (nightly).
export XDG_DATA_DIRS=\"~a${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}\"
export PATH=\"${PATH:+$PATH:}~a\"
export CHROME_DESKTOP=\"${CHROME_DESKTOP:-com.brave.Origin.nightly.desktop}\"

sandbox_flags=()
if [ -z \"${CHROME_DEVEL_SANDBOX:-}\" ]; then
  for candidate in ~a; do
    if [ -u \"$candidate\" ]; then
      export CHROME_DEVEL_SANDBOX=\"$candidate\"
      break
    fi
  done
fi
if [ -z \"${CHROME_DEVEL_SANDBOX:-}\" ] && ! ~a --user true 2>/dev/null; then
  echo \"brave-origin: warning: no setuid chrome-sandbox found (looked in:\" \\
       \"~a) and unprivileged user namespaces are unavailable;\" \\
       \"starting with --no-sandbox.  On Guix System, add\" \\
       \"(service brave-origin-service-type) to your operating-system.\" >&2
  sandbox_flags=(--no-sandbox)
fi

exec ~a \\
  --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations \\
  \"${sandbox_flags[@]}\" \"$@\"
"
                            bash data-dirs path
                            (string-join '#$%brave-origin-sandbox-candidates)
                            unshare
                            (string-join '#$%brave-origin-sandbox-candidates)
                            target)))
                (chmod wrapper #o555)
                (symlink "brave-origin"
                         (string-append bin "/brave-origin-nightly")))))
          (add-after 'install-wrapper 'install-desktop-file-and-icons
            (lambda _
              (let ((libexec (string-append #$output
                                            "/libexec/brave-origin-nightly"))
                    (desktop (string-append
                              #$output "/share/applications/"
                              "com.brave.Origin.nightly.desktop")))
                ;; Upstream ships two identical desktop files, the "portal"
                ;; one hidden with NoDisplay=true.  Keep only that one (its
                ;; name matches the app ID) and make it visible.
                (substitute* desktop
                  (("^NoDisplay=true\n") "")
                  (("^#.*\n") "")        ;stale comments about the above
                  (("^Exec=/usr/bin/brave-origin-nightly")
                   (string-append "Exec=" #$output "/bin/brave-origin"))
                  (("^Icon=.*") "Icon=brave-origin\n"))
                (for-each
                 (lambda (size)
                   (let ((dir (string-append #$output "/share/icons/hicolor/"
                                             size "x" size "/apps")))
                     (mkdir-p dir)
                     (copy-file (string-append libexec "/product_logo_" size
                                               "_nightly.png")
                                (string-append dir "/brave-origin.png"))))
                 '("16" "24" "32" "48" "64" "128" "256"))))))))
    (native-inputs (list binutils patchelf tar xz))
    (inputs
     (append (list bash-minimal
                   coreutils
                   `(,gcc "lib")
                   gsettings-desktop-schemas
                   nss
                   util-linux           ;unshare, for the sandbox probe
                   xdg-utils)
             %runtime-libraries))
    (supported-systems '("x86_64-linux"))
    (home-page "https://brave.com/origin/")
    (synopsis "Brave Origin web browser, nightly channel (prebuilt binary)")
    (description
     "Brave Origin is a stripped-down build of the Chromium-based Brave
browser.  This package repackages the official nightly @file{.deb} from
Brave's GitHub releases.  The binaries are not built from source.

For the setuid sandbox helper on Guix System, use
@code{brave-origin-service-type} from @code{(brave-origin services
brave-origin)}; without it the browser uses Chromium's user-namespace
sandbox, or runs with @option{--no-sandbox} (with a warning) when that is
unavailable.")
    (properties '((upstream-name . "brave-origin-nightly")))
    ;; Brave's own code is MPL-2.0; the binary also bundles Chromium (BSD-3)
    ;; and other components.  This is a prebuilt binary, not free software as
    ;; distributed by Guix: keep it out of upstream Guix.
    (license license:mpl2.0)))

;;; brave-origin.scm ends here

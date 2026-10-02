;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (brave-origin services brave-origin)
  #:use-module (gnu services)
  #:use-module (gnu system privilege)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (brave-origin packages brave-origin)
  #:export (brave-origin-configuration
            brave-origin-configuration?
            brave-origin-configuration-package
            brave-origin-configuration-setuid-sandbox?
            brave-origin-service-type))

;;; Commentary:
;;;
;;; Guix System counterpart of nixosModules.brave-origin:
;;;
;;;   (use-modules (brave-origin services brave-origin))
;;;   (operating-system
;;;     …
;;;     (services (cons (service brave-origin-service-type) %base-services)))
;;;
;;; It installs the browser system-wide and copies chrome-sandbox to
;;; /run/privileged/bin/chrome-sandbox, setuid root, through
;;; `privileged-program-service-type' (the Guix equivalent of NixOS'
;;; security.wrappers).  The bin/brave-origin wrapper finds it there and
;;; exports CHROME_DEVEL_SANDBOX.
;;;
;;; Note that Chromium prefers its user-namespace sandbox whenever
;;; unprivileged user namespaces work, which is the default on Guix System;
;;; the setuid helper is the fallback for kernels where they are disabled.
;;; Set `setuid-sandbox?' to #f if you do not want a setuid binary at all.
;;;
;;; Code:

(define-record-type* <brave-origin-configuration>
  brave-origin-configuration make-brave-origin-configuration
  brave-origin-configuration?
  (package         brave-origin-configuration-package ;file-like
                   (default brave-origin-nightly))
  (setuid-sandbox? brave-origin-configuration-setuid-sandbox? ;boolean
                   (default #t)))

(define (brave-origin-privileged-programs config)
  (if (brave-origin-configuration-setuid-sandbox? config)
      (list (privileged-program
             (program (file-append (brave-origin-configuration-package config)
                                   "/libexec/brave-origin-nightly/chrome-sandbox"))
             (setuid? #t)))
      '()))

(define (brave-origin-profile config)
  (list (brave-origin-configuration-package config)))

(define brave-origin-service-type
  (service-type
   (name 'brave-origin)
   (extensions
    (list (service-extension profile-service-type brave-origin-profile)
          (service-extension privileged-program-service-type
                             brave-origin-privileged-programs)))
   (default-value (brave-origin-configuration))
   (description
    "Install Brave Origin (nightly) system-wide and provide its setuid-root
@command{chrome-sandbox} helper at @file{/run/privileged/bin/chrome-sandbox}.")))

;;; brave-origin.scm ends here

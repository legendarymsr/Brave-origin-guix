;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (brave-origin home services brave-origin)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (brave-origin packages brave-origin)
  #:export (home-brave-origin-configuration
            home-brave-origin-configuration?
            home-brave-origin-configuration-package
            home-brave-origin-configuration-default-browser?
            home-brave-origin-configuration-extensions
            home-brave-origin-configuration-command-line-arguments
            home-brave-origin-service-type
            %brave-origin-desktop-file
            %brave-origin-mime-types))

;;; Commentary:
;;;
;;; Guix Home counterpart of homeModules.brave-origin
;;; (programs.brave-origin-nightly):
;;;
;;;   (use-modules (brave-origin home services brave-origin))
;;;   (home-environment
;;;     …
;;;     (services
;;;      (list (service home-brave-origin-service-type
;;;                     (home-brave-origin-configuration
;;;                      (default-browser? #t)
;;;                      (extensions '("cjpalhdlnbpafiamejdnhcphjbkeiagm"))
;;;                      (command-line-arguments '("--force-dark-mode")))))))
;;;
;;; - package:                installed into the home profile.
;;; - default-browser?:       writes ~/.config/mimeapps.list with Brave Origin
;;;                           as the handler for HTML/http/https.  That file is
;;;                           then owned by Guix Home: if you already use
;;;                           `home-xdg-mime-applications-service-type', leave
;;;                           this #f and add %brave-origin-mime-types there.
;;; - extensions:             Chrome Web Store IDs, installed through per-user
;;;                           "External Extensions" JSON files (Chromium never
;;;                           reads managed policies from $HOME).  Installed on
;;;                           next start; the user can still remove them.
;;; - command-line-arguments: extra flags, through a desktop entry in
;;;                           ~/.local/share/applications that shadows the one
;;;                           from the package.
;;;
;;; Code:

(define %brave-origin-desktop-file "com.brave.Origin.nightly.desktop")

(define %brave-origin-mime-types
  '("text/html"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/ftp"
    "application/xhtml+xml"
    "application/x-extension-htm"
    "application/x-extension-html"
    "application/x-extension-xhtml"
    "application/x-extension-xht"))

(define (extension-id? str)
  (and (string? str)
       (regexp-exec (make-regexp "^[a-p]{32}$") str)
       #t))

(define-record-type* <home-brave-origin-configuration>
  home-brave-origin-configuration make-home-brave-origin-configuration
  home-brave-origin-configuration?
  (package                home-brave-origin-configuration-package ;file-like
                          (default brave-origin-nightly))
  (default-browser?       home-brave-origin-configuration-default-browser?
                          (default #f))
  (extensions             home-brave-origin-configuration-extensions
                          (default '())
                          (sanitize
                           (lambda (ids)
                             (unless (and (list? ids) (every extension-id? ids))
                               (error "home-brave-origin-configuration: \
extensions must be a list of 32-character Chrome Web Store IDs (a-p):" ids))
                             ids)))
  (command-line-arguments home-brave-origin-configuration-command-line-arguments
                          (default '())))

(define (home-brave-origin-profile config)
  (list (home-brave-origin-configuration-package config)))

(define (home-brave-origin-config-files config)
  ;; ~/.config/BraveSoftware/Brave-Origin-Nightly/External Extensions/*.json
  ;; and, optionally, ~/.config/mimeapps.list.
  (append
   (map (lambda (id)
          (list (string-append "BraveSoftware/Brave-Origin-Nightly/"
                               "External Extensions/" id ".json")
                (plain-file (string-append "brave-origin-extension-" id ".json")
                            "{\"external_update_url\": \
\"https://clients2.google.com/service/update2/crx\"}\n")))
        (home-brave-origin-configuration-extensions config))
   (if (home-brave-origin-configuration-default-browser? config)
       (list (list "mimeapps.list"
                   (plain-file
                    "brave-origin-mimeapps.list"
                    (string-append
                     "[Default Applications]\n"
                     (string-concatenate
                      (map (lambda (type)
                             (string-append type "="
                                            %brave-origin-desktop-file "\n"))
                           %brave-origin-mime-types))
                     "\n[Added Associations]\n"
                     (string-concatenate
                      (map (lambda (type)
                             (string-append type "="
                                            %brave-origin-desktop-file ";\n"))
                           %brave-origin-mime-types))))))
       '())))

(define (desktop-exec-quote arg)
  "Quote ARG for the Exec key of a desktop entry, as the spec requires."
  (if (string-every (lambda (c)
                      (or (char-alphabetic? c) (char-numeric? c)
                          (memv c '(#\- #\_ #\= #\. #\, #\/ #\: #\+))))
                    arg)
      arg
      (string-append
       "\""
       (string-concatenate
        (map (lambda (c)
               ;; Exec-level escape is a backslash before " ` $ \; the file
               ;; is then read as a "string" value, so every backslash is
               ;; doubled once more.  % must always be written as %%.
               (case c
                 ((#\" #\` #\$) (string #\\ #\\ c))
                 ((#\\) "\\\\\\\\")
                 ((#\%) "%%")
                 (else (string c))))
             (string->list arg)))
       "\"")))

(define (home-brave-origin-data-files config)
  ;; Shadow the package's desktop entry when extra flags are requested.
  (match (home-brave-origin-configuration-command-line-arguments config)
    (() '())
    (args
     (let ((package (home-brave-origin-configuration-package config))
           (flags (string-join (map desktop-exec-quote args) " ")))
       (list
        (list (string-append "applications/" %brave-origin-desktop-file)
              (mixed-text-file
               "brave-origin-desktop-entry"
               "[Desktop Entry]\n"
               "Version=1.0\n"
               "Type=Application\n"
               "Name=Brave Origin (nightly)\n"
               "GenericName=Web Browser\n"
               "Comment=Brave browser, Origin (nightly) channel\n"
               "Exec=" package "/bin/brave-origin " flags " %U\n"
               "Icon=brave-origin\n"
               "Terminal=false\n"
               "StartupNotify=true\n"
               "StartupWMClass=brave-origin-nightly\n"
               "Categories=Network;WebBrowser;\n"
               "MimeType=" (string-join %brave-origin-mime-types ";") ";\n"
               "Actions=new-window;new-private-window;\n"
               "\n[Desktop Action new-window]\n"
               "Name=New Window\n"
               "Exec=" package "/bin/brave-origin " flags "\n"
               "\n[Desktop Action new-private-window]\n"
               "Name=New Private Window\n"
               "Exec=" package "/bin/brave-origin " flags " --incognito\n")))))))

(define home-brave-origin-service-type
  (service-type
   (name 'home-brave-origin)
   (extensions
    (list (service-extension home-profile-service-type
                             home-brave-origin-profile)
          (service-extension home-xdg-configuration-files-service-type
                             home-brave-origin-config-files)
          (service-extension home-xdg-data-files-service-type
                             home-brave-origin-data-files)))
   (default-value (home-brave-origin-configuration))
   (description
    "Install Brave Origin (nightly) in the home profile and optionally make it
the default browser, pre-install Chrome Web Store extensions and pass extra
command-line flags.")))

;;; brave-origin.scm ends here

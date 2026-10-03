;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (brave-origin home services emacs)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (gnu packages emacs)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (home-emacs-simple-configuration
            home-emacs-simple-configuration?
            home-emacs-simple-service-type))

;;; Commentary:
;;;
;;; Dead-simple Emacs home service.  Installs Emacs and writes a minimal
;;; init.el — relative line numbers, no splash screen, nothing else.
;;;
;;;   (use-modules (brave-origin home services emacs))
;;;   (home-environment
;;;     …
;;;     (services
;;;      (list (service home-emacs-simple-service-type))))
;;;
;;; Code:

(define-record-type* <home-emacs-simple-configuration>
  home-emacs-simple-configuration make-home-emacs-simple-configuration
  home-emacs-simple-configuration?
  (package home-emacs-simple-configuration-package
           (default emacs-no-x)))

(define %emacs-simple-init
  (plain-file "emacs-init.el"
              ";; init.el — dead simple
\(setq inhibit-startup-screen t)
\(setq ring-bell-function 'ignore)
\(menu-bar-mode -1)
\(tool-bar-mode -1)
\(scroll-bar-mode -1)
\(global-display-line-numbers-mode t)
\(setq-default display-line-numbers 'relative)
\(setq-default indent-tabs-mode nil)
\(setq-default tab-width 2)
\(setq backup-directory-alist '((\".*\" . \"~/.cache/emacs/backups\")))
\(setq auto-save-file-name-transforms '((\".*\" \"~/.cache/emacs/auto-saves/\" t)))
"))

(define (home-emacs-simple-profile config)
  (list (home-emacs-simple-configuration-package config)))

(define (home-emacs-simple-config-files config)
  (list (list "emacs/init.el" %emacs-simple-init)))

(define home-emacs-simple-service-type
  (service-type
   (name 'home-emacs-simple)
   (extensions
    (list (service-extension home-profile-service-type
                             home-emacs-simple-profile)
          (service-extension home-xdg-configuration-files-service-type
                             home-emacs-simple-config-files)))
   (default-value (home-emacs-simple-configuration))
   (description
    "Install Emacs with a minimal init.el: relative line numbers, no splash
screen, no menu/tool/scroll bars.  Nothing else.")))

;;; emacs.scm ends here

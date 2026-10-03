;;; brave-origin-guix --- Brave Origin (nightly) for GNU Guix
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (brave-origin home services ratpoison)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (gnu packages ratpoison)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (home-ratpoison-configuration
            home-ratpoison-configuration?
            home-ratpoison-service-type))

;;; Commentary:
;;;
;;; Minimal Ratpoison home service.  Installs Ratpoison and writes ~/.ratpoisonrc
;;; with vim-style keybindings and a Super+B shortcut for Brave Origin.
;;;
;;;   (use-modules (brave-origin home services ratpoison))
;;;   (home-environment
;;;     …
;;;     (services
;;;      (list (service home-ratpoison-service-type))))
;;;
;;; Default keybindings (prefix is C-t):
;;;   C-t b        brave-origin
;;;   C-t e        emacs
;;;   C-t t        xterm
;;;   C-t h/j/k/l  focus left/down/up/right
;;;   C-t H/J/K/L  exchange frame left/down/up/right
;;;   C-t s        hsplit (horizontal split)
;;;   C-t v        vsplit (vertical split)
;;;   C-t w        remove current frame
;;;   C-t Q        only keep current frame
;;;   C-t n/p      next/prev window in frame
;;;   C-t q        quit
;;;
;;; Code:

(define-record-type* <home-ratpoison-configuration>
  home-ratpoison-configuration make-home-ratpoison-configuration
  home-ratpoison-configuration?
  (package     home-ratpoison-configuration-package
               (default ratpoison))
  (extra-lines home-ratpoison-configuration-extra-lines
               (default '())))

(define (ratpoisonrc config)
  (let ((extra (home-ratpoison-configuration-extra-lines config)))
    (plain-file "ratpoisonrc"
                (string-append
                 "# ratpoisonrc — dead simple\n"
                 "\n"
                 "# Aesthetics\n"
                 "set border 1\n"
                 "set barborder 1\n"
                 "set padding 0 0 0 0\n"
                 "set font fixed\n"
                 "\n"
                 "# Status bar (top-right, brief)\n"
                 "set bargravity ne\n"
                 "set barinpadding 1\n"
                 "set inputwidth 400\n"
                 "\n"
                 "# Apps\n"
                 "bind b exec brave-origin\n"
                 "bind e exec emacs\n"
                 "bind t exec xterm\n"
                 "\n"
                 "# Vim-style focus\n"
                 "bind h focusleft\n"
                 "bind j focusdown\n"
                 "bind k focusup\n"
                 "bind l focusright\n"
                 "\n"
                 "# Vim-style frame swap\n"
                 "bind H exchangeleft\n"
                 "bind J exchangedown\n"
                 "bind K exchangeup\n"
                 "bind L exchangeright\n"
                 "\n"
                 "# Splits\n"
                 "bind s hsplit\n"
                 "bind v vsplit\n"
                 "bind w remove\n"
                 "bind Q only\n"
                 "\n"
                 "# Windows\n"
                 "bind n next\n"
                 "bind p prev\n"
                 "bind W windows\n"
                 "\n"
                 "# Misc\n"
                 "bind q quit\n"
                 "bind r restart\n"
                 "bind colon colon\n"
                 "\n"
                 (if (null? extra) ""
                     (string-append
                      "# Extra\n"
                      (string-join extra "\n")
                      "\n"))))))

(define (home-ratpoison-profile config)
  (list (home-ratpoison-configuration-package config)))

(define (home-ratpoison-home-files config)
  (list (list ".ratpoisonrc" (ratpoisonrc config))))

(define home-ratpoison-service-type
  (service-type
   (name 'home-ratpoison)
   (extensions
    (list (service-extension home-profile-service-type
                             home-ratpoison-profile)
          (service-extension home-files-service-type
                             home-ratpoison-home-files)))
   (default-value (home-ratpoison-configuration))
   (description
    "Install Ratpoison and write ~/.ratpoisonrc with vim-style hjkl focus and
frame bindings, Super+B for Brave Origin, and a minimal appearance.")))

;;; ratpoison.scm ends here

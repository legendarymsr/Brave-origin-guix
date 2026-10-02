#!/usr/bin/env -S guix repl --
!#
;;; update.scm --- bump brave-origin-nightly to the latest nightly release
;;; Copyright © 2026 legendarymsr
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;
;;; Usage (from anywhere; paths are resolved relative to this file):
;;;
;;;   guix repl -- update.scm            # bump to the newest nightly
;;;   guix repl -- update.scm --dry-run  # only report what would change
;;;   ./update.scm                       # same thing, via the shebang
;;;
;;; What it does (the Guile equivalent of update.nix in brave-origin-nix):
;;;
;;;   1. Asks the GitHub Releases API for the 50 latest releases of
;;;      brave/brave-browser and picks the newest tag that ships a
;;;      brave-origin-nightly_<version>_amd64.deb asset.
;;;   2. Streams that .deb and computes its SHA-256 (cross-checked against
;;;      the digest GitHub publishes for the asset, when there is one).
;;;   3. Rewrites (version "...") and (base32 "...") in
;;;      modules/brave-origin/packages/brave-origin.scm.
;;;
;;; Authentication (to dodge the 60 requests/hour anonymous limit), in order:
;;;   1. $GITHUB_TOKEN, if set          -> "Authorization: Bearer ..." header
;;;   2. an authenticated `gh' on PATH  -> `gh api'
;;;   3. anonymous HTTPS request
;;;
;;; Only modules that ship with Guix itself are used (guile-json,
;;; guile-gcrypt, guile-gnutls and (guix ...)), which is why it is meant to be
;;; run through `guix repl'.

(use-modules (guix base16)
             (guix base32)
             (guix http-client)
             (guix utils)
             (gcrypt hash)
             (json)
             (ice-9 match)
             (ice-9 popen)
             (ice-9 regex)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-26)
             (srfi srfi-35)
             (web uri))

(define %repository "brave/brave-browser")
(define %api-path
  (string-append "repos/" %repository "/releases?per_page=50"))

(define %package-file
  ;; Resolve relative to this script, so it works from any directory.
  (string-append (or (and=> (current-filename) dirname) ".")
                 "/modules/brave-origin/packages/brave-origin.scm"))

(define %asset-rx
  (make-regexp "^brave-origin-nightly_([0-9]+\\.[0-9]+\\.[0-9]+)_amd64\\.deb$"))

(define (die fmt . args)
  (apply format (current-error-port) (string-append "error: " fmt "~%") args)
  (exit 1))

(define (say fmt . args)
  (apply format #t (string-append fmt "~%") args)
  (force-output))


;;;
;;; GitHub API.
;;;

(define (gh-available?)
  (and (search-path (parse-path (or (getenv "PATH") "")) "gh")
       (zero? (status:exit-val
               (system* "sh" "-c" "gh auth status >/dev/null 2>&1")))))

(define (parse-path str)
  (string-split str #\:))

(define (auth-mode)
  (cond ((and=> (getenv "GITHUB_TOKEN") (negate string-null?)) 'token)
        ((gh-available?) 'gh)
        (else 'anonymous)))

(define (fetch-releases mode)
  "Return the decoded JSON array (a vector) of releases."
  (define (via-https headers)
    (let ((port (http-fetch (string->uri
                             (string-append "https://api.github.com/"
                                            %api-path))
                            #:text? #t
                            #:headers
                            (append '((user-agent . "brave-origin-guix/update.scm")
                                      (accept . ((application/vnd.github+json))))
                                    headers))))
      (let ((json (json->scm port)))
        (close-port port)
        json)))

  (match mode
    ('token
     (via-https `((authorization
                   . (bearer . (,(string->symbol (getenv "GITHUB_TOKEN"))))))))
    ('anonymous
     (via-https '()))
    ('gh
     (let* ((pipe (open-pipe* OPEN_READ "gh" "api" %api-path))
            (text (get-string-all pipe))
            (status (close-pipe pipe)))
       (unless (zero? (status:exit-val status))
         (die "`gh api ~a' failed (exit status ~a)"
              %api-path (status:exit-val status)))
       (json-string->scm text)))))

(define (release-assets release)
  (vector->list (or (assoc-ref release "assets") #())))

(define (nightly-asset release)
  "Return the brave-origin-nightly amd64 .deb asset of RELEASE, or #f."
  (find (lambda (asset)
          (regexp-exec %asset-rx (assoc-ref asset "name")))
        (release-assets release)))

(define (latest-nightly releases)
  "Return two values: the newest version with a nightly .deb, and its asset."
  (let ((candidates
         (filter-map (lambda (release)
                       (and=> (nightly-asset release)
                              (lambda (asset)
                                (cons (match:substring
                                       (regexp-exec %asset-rx
                                                    (assoc-ref asset "name"))
                                       1)
                                      asset))))
                     (vector->list releases))))
    (match (sort candidates (lambda (a b) (version>? (car a) (car b))))
      (() (values #f #f))
      (((version . asset) . _) (values version asset)))))


;;;
;;; Package file rewriting.
;;;

(define %version-rx (make-regexp "\\(version \"([^\"]*)\"\\)"))
(define %base32-rx  (make-regexp "\\(base32 \"([0-9a-z]{52})\"\\)"))

(define (single-match rx text what)
  (match (list-matches rx text)
    ((m) m)
    (() (die "no ~a found in ~a" what %package-file))
    (_  (die "more than one ~a found in ~a; refusing to guess"
             what %package-file))))

(define (current-version text)
  (match:substring (single-match %version-rx text "(version \"...\")") 1))

(define (rewrite text version hash)
  (let* ((text (regexp-substitute #f (single-match %version-rx text
                                                   "(version \"...\")")
                                  'pre "(version \"" version "\")" 'post)))
    (regexp-substitute #f (single-match %base32-rx text "(base32 \"...\")")
                       'pre "(base32 \"" hash "\")" 'post)))


;;;
;;; Main.
;;;

(define (describe-error key args)
  "Turn the KEY and ARGS of a caught exception into a one-line message."
  (match (cons key args)
    (('%exception (? http-get-error? c))
     (format #f "HTTP ~a ~a" (http-get-error-code c) (http-get-error-reason c)))
    (('%exception c)
     (if (message-condition? c)
         (condition-message c)
         (format #f "~s" c)))
    (_ (format #f "~a ~s" key args))))

(define (deb-url version)
  (string-append "https://github.com/" %repository "/releases/download/v"
                 version "/brave-origin-nightly_" version "_amd64.deb"))

(define (main args)
  (define dry-run? (member "--dry-run" args))

  (unless (file-exists? %package-file)
    (die "~a not found" %package-file))

  (let* ((text    (call-with-input-file %package-file get-string-all))
         (current (current-version text))
         (mode    (auth-mode)))
    (say "Current version: ~a" current)
    (say "Querying GitHub Releases API (~a)..." mode)
    (let ((releases
           (catch #t
             (lambda () (fetch-releases mode))
             (lambda (key . rest)
               (format (current-error-port)
                       "error: could not query the GitHub Releases API for ~a (~a): ~a~%"
                       %repository mode (describe-error key rest))
               (if (eq? mode 'token)
                   (format (current-error-port)
                           "Check that $GITHUB_TOKEN is valid (HTTP 401 means it was rejected).~%")
                   (format (current-error-port)
                           "This is usually the anonymous API rate limit (60 requests/hour per IP).~%Set GITHUB_TOKEN=<token> or log in with 'gh auth login', then retry.~%"))
               (exit 1)))))
      (call-with-values (lambda () (latest-nightly releases))
        (lambda (latest asset)
          (unless latest
            (die "no release with a brave-origin-nightly_*_amd64.deb asset in the latest 50 releases of ~a"
                 %repository))
          (cond
           ((string=? latest current)
            (say "Already up to date (~a)." current))
           ((version>? current latest)
            (say "Package file (~a) is newer than the latest nightly release (~a); nothing to do."
                 current latest))
           (dry-run?
            (say "New version available: ~a (dry run, not touching ~a)"
                 latest %package-file))
           (else
            (let ((url (deb-url latest)))
              (say "New version: ~a" latest)
              (say "Downloading ~a to compute its hash..." url)
              (let* ((port   (http-fetch (string->uri url) #:log-port #f))
                     (sha256 (port-sha256 port))
                     (_      (close-port port))
                     (hex    (bytevector->base16-string sha256))
                     (digest (assoc-ref asset "digest"))
                     (nix32  (bytevector->nix-base32-string sha256)))
                (when (and (string? digest)
                           (string-prefix? "sha256:" digest)
                           (not (string=? digest (string-append "sha256:" hex))))
                  (die "hash mismatch: downloaded sha256:~a but GitHub says ~a"
                       hex digest))
                (say "SHA-256: ~a (nix-base32 ~a)~a" hex nix32
                     (if (string? digest) ", matches GitHub's asset digest" ""))
                (call-with-output-file %package-file
                  (cut put-string <> (rewrite text latest nix32)))
                (say "~%Updated ~a -- check and commit with:" %package-file)
                (say "  guix build -L modules brave-origin-nightly")
                (say "  git commit -am \"packages: bump brave-origin-nightly to ~a\" && git push"
                     latest))))))))))

(main (command-line))

;;; update.scm ends here

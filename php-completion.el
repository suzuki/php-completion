;;; php-completion.el -- complete everything PHP with Anything.el or helm.el

;; Copyright (c) 2009 by KAYAC Inc.

;; Author: IMAKADO <ken.imakado@gmail.com>
;; blog: http://d.hatena.ne.jp/IMAKADO (japanese)
;; Author: Norio Suzuki <norio.suzuki@gmail.com>
;; GitHub: https://github.com/suzuki
;;
;; Prefix: phpcmp-

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; log:

;; ver 0.04
;;   * Norio Suzuki:
;;      * support helm
;;      * Emacs 24.3+, use cl-labels instead of labels

;; ver 0.03
;;   * IMAKADO:
;;      * candidates from TAGS file.
;;      * added some commands.
;;      * refactoring

;; ver 0.02
;;   * IMAKADO:
;;      * candidates from GLOBAL tag files.


;;; Commentary:

;; complete php functions, symbols, ini directives, keywords with Anything.el's Interface.

;;; Commands:
;;
;; Below are complete command list:
;;
;;
;;; Customizable Options:
;;
;; Below are customizable option list:
;;
;;  `phpcmp-browse-function'
;;    called with one argment URL
;;    default is (quote browse-url)
;;  `phpcmp-manual-url-format'
;;    `%s' is replaced to query.
;;    default = (cond ((ignore-errors ...) "http://jp2.php.net/manual-lookup.php?lang=ja&pattern=%s") (t "http://jp2.php.net/manual-lookup.php?lang=en&pattern=%s"))
;;  `phpcmp-lighter'
;;    value is displayed in the modeline when the php-completion-mode is on.
;;    default = " Completion"
;;  `phpcmp-global-enable-auto-update-tag-files'
;;    If value is non-nil, automatically update GNU global's tag files.
;;    default = nil
;;  `phpcmp-showtip-timeout'
;;    Seconds to wait before displaying a tooltip the first time.
;;    default = 10
;;  `phpcmp-showtip-top-adjust'
;;    Basic adjust.
;;    default = 40

;; Installation:
;;
;; put `php-completion.el' somewhere in your emacs load path.
;; add these lines to your .emacs file:
;; -------------- .emacs -----------------------------
;; (add-hook 'php-mode-hook
;;           (lambda ()
;;             (require 'php-completion)
;;             (php-completion-mode t)
;;             (define-key php-mode-map (kbd "C-o") 'phpcmp-complete)))
;; ---------------------------------------------------

;; Cooperation with auto-complete.el:
;;
;; add these lines to your .emacs file:
;; (add-hook  'php-mode-hook
;;            (lambda ()
;;              (when (require 'auto-complete nil t)
;;                (make-variable-buffer-local 'ac-sources)
;;                (add-to-list 'ac-sources 'ac-source-php-completion)
;;                ;; if you like patial match,
;;                ;; use `ac-source-php-completion-patial' instead of `ac-source-php-completion'.
;;                ;; (add-to-list 'ac-sources 'ac-source-php-completion-patial)
;;                (auto-complete-mode t))))

;; Features that might be required by this library:
;;
;; `cl' `rx' `browse-url' `url-util' `etags' `thingatpt'
;; `anything' `anything-match-plugin' `auto-complete' `pp'
;;

(require 'cl)
(require 'rx)
(require 'browse-url)
(require 'url-util)
(require 'etags)
(require 'thingatpt)
(require 'tool-bar)
(require 'auto-complete)

;; require helm or anything
(condition-case nil
    (require 'helm)
  (error (require 'anything)))

(defun phpcmp-setup-helm ()
  "Setting up function alias for helm"
  (defalias 'phpcmp-anything (symbol-function 'helm))
  (defalias 'phpcmp-anything-candidate-buffer (symbol-function 'helm-candidate-buffer))
)

(defun phpcmp-setup-anything ()
  "Setting up function alias for anything"
  (defalias 'phpcmp-anything (symbol-function 'anything))
  (defalias 'phpcmp-anything-candidate-buffer (symbol-function 'anything-candidate-buffer))
)

(if (featurep 'helm)
    (progn
      (require 'helm-match-plugin)
      (phpcmp-setup-helm))
  (progn
    (require 'anything-match-plugin)
    (phpcmp-setup-anything)))

;; Emacs 24.3+, use "cl-labels" instead of "labels"
(if (version<= emacs-version "24.3")
    (defalias 'phpcmp-labels (symbol-function 'labels))
  (defalias 'phpcmp-labels (symbol-function 'cl-labels)))

(defvar phpcmp-version 0.04)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Customize Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defgroup php-completion nil
  "php-completion"
  :group 'php-completion)

(defcustom phpcmp-browse-function 'browse-url
  "called with one argment URL"
  :group 'php-completion
  :type 'function)

(defcustom phpcmp-manual-url-format
  (cond
   ((ignore-errors
      (string= current-language-environment "Japanese"))
    "http://jp2.php.net/manual-lookup.php?lang=ja&pattern=%s")
   (t
    "http://jp2.php.net/manual-lookup.php?lang=en&pattern=%s"
    ))
  "`%s' is replaced to query.
see `phpcmp-search-url'"
  :group 'php-completion
  :type 'string)

(defcustom phpcmp-lighter " Completion"
  "value is displayed in the modeline when the php-completion-mode is on."
  :group 'php-completion
  :type 'string)

(defcustom phpcmp-global-enable-auto-update-tag-files nil
  "If value is non-nil, automatically update tag files."
  :group 'php-completion
  :type 'boolean)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar phpcmp-identifier-regexp "[a-zA-Z_][a-zA-Z_0-9]*")

;; etags
(defvar phpcmp-etags-tag-file-name "TAGS")
(defvar phpcmp-etags-tag-file-search-limit 10)
(defvar phpcmp-etags-completions-table nil
  "alist, ((name . (list of candidates))
           (name . (list of candidates))
           ...)")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Hooks ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar phpcmp--initialize-hook nil
  "run when invoke completion command")

(defvar phpcmp-obj-instance-of-module-maybe-alist nil)

(add-hook 'phpcmp--initialize-hook
          (lambda ()
            (setq phpcmp-obj-instance-of-module-maybe-alist
                  (phpcmp-get-obj-instance-of-module-maybe-alist))))

(defun phpcmp-get-obj-instance-of-module-maybe-alist ()
  (let* ((re (rx-to-string `(and (group
                                  "$" ;1 var name
                                  (regexp ,phpcmp-identifier-regexp))
                                 (* space)
                                 "="
                                 (* space)
                                 "new"
                                 (+ space)
                                 (group
                                  (regexp ,phpcmp-identifier-regexp))))))
    (save-excursion
      (loop initially (goto-char (point-min))
            while (re-search-forward re nil t)
            collect `(,(match-string-no-properties 1) . ,(match-string-no-properties 2))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Structure ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Struct `phpcmp-tag'
;; tag-file: TAGS file path

;; path: fileのfullpath

;; classes:
;; list of Struct `phpcmp-class'

;; functions: list of functions

;; variables: list of variables
(defstruct (phpcmp-tag
            (:constructor phpcmp-make-tag
                          (&key tag-file path relative-path classes functions variables)))
  tag-file path relative-path classes functions variables)

(defstruct (phpcmp-class
            (:constructor phpcmp-make-class
                          (&key name parent methods variables)))
  name parent methods variables)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Log ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar phpcmp-debug nil)
(defsubst phpcmp-log-buf ()
  (get-buffer-create "*php-completion debug*"))

(defsubst phpcmp-log-insert (type-str &rest messages)
  (ignore-errors
    (let* ((str (or (ignore-errors (apply 'format messages))
                    (pp-to-string (car messages))))
           (str (concat type-str str "\n")))
      (with-current-buffer (phpcmp-log-buf)
          (goto-char (point-max))
          (insert str)))))

(defsubst phpcmp-log (type &rest messages)
  (ignore-errors
    (when phpcmp-debug
      (require 'pp)
      (case type
        (info (apply 'phpcmp-log-insert "info: " messages))
        (debug (unless (eq phpcmp-debug 'info)
                 (apply 'phpcmp-log-insert "debug: " messages)))))))

(defsubst phpcmp-log-info (&rest messages)
  (apply 'phpcmp-log 'info messages))

(defsubst phpcmp-log-debug (&rest messages)
  (apply 'phpcmp-log 'debug messages))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Utilities ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defsubst phpcmp-get-current-directory ()
  (file-name-directory
   (expand-file-name
    (or (buffer-file-name)
        default-directory))))

(defsubst phpcmp-tramp-p ()
  (when (and (featurep 'tramp)
             (fboundp 'tramp-tramp-file-p))
    (tramp-tramp-file-p (phpcmp-get-current-directory))))

(defun* phpcmp-collect-matches
    (re &optional (count 0) (match-string-fn 'match-string)
        (point-min (point-min)) (point-max (point-max)))
  (save-excursion
    (loop initially (goto-char point-min)
          while (re-search-forward re point-max t)
          collect (funcall match-string-fn count))))

(defun* phpcmp-async-do
    (&key command args buffer-name
          (callback 'identity)
          (errorback (lambda() (message (buffer-string)))))
  (lexical-let ((buf (get-buffer-create buffer-name))
                (callback callback)
                (errorback errorback))
    (lexical-let
      ((sentinel (lambda (proc event)
         (cond ((and (string= event "finished\n")
                     (= (process-exit-status proc) 0))
                (with-current-buffer buf
                  (funcall callback))
                (ignore-errors
                    (kill-buffer buf)))
               ((and (string= event "finished\n")
                     (/= (process-exit-status proc) 0))
                (with-current-buffer buf
                  (funcall errorback)))))))
      (set-process-sentinel (apply 'start-process command buf command args) sentinel))))

(defsubst phpcmp-preceding-line-string ()
  (or (ignore-errors (buffer-substring-no-properties (point-at-bol) (point)))
      ""))

(defsubst* phpcmp-preceding-string (&optional (n 1))
  (buffer-substring-no-properties
   (point)
   (or (ignore-errors
         (save-excursion
           (backward-char n)
           (point)))
       (point))))

(defun phpcmp-remove-dups (los)
  "fast remove-duplicates"
  (let ((hash (make-hash-table :test 'equal))
        (ret nil))
    (loop for s in los
          do (puthash s nil hash))
    (maphash (lambda (k v) (push k ret)) hash)
    ret))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Candidates from php command ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; silence compiler
;; (defun phpcmp-get-functions () ())
(defun phpcmp-async-set-functions (&rest dummy))
(defun phpcmp-get-functions (&rest dummy))

(defvar phpcmp-get-functions-async-buffer-name "*php-completion functions*")
(lexical-let (set-functions-done)
  (defun phpcmp-async-set-functions ()
    (unless set-functions-done
      (let* ((buf-name phpcmp-get-functions-async-buffer-name)
             (process-running? (eq 'run
                                   (let ((proc (get-buffer-process buf-name)))
                                     (when (processp proc)
                                       (process-status proc)))))
             (php-command (executable-find "php")))
        (when (and (not (phpcmp-tramp-p))
                   (not process-running?)
                   php-command)
          (phpcmp-async-do
           :buffer-name buf-name
           :command php-command
           :args '("-r"
                   "foreach (get_defined_functions() as $vars) { foreach ($vars as $var) {echo \"$var\n\";}}")
           :callback (lambda ()
                       (let ((los (phpcmp-collect-matches "[[:print:]]+")))
                         (phpcmp-db-update 'functions los)
                         (setq set-functions-done t))))))))
  (defun phpcmp-get-functions ()
    (prog1 (phpcmp-db-get 'functions)
      (unless set-functions-done
        (phpcmp-async-set-functions)))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Completion ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar phpcmp-initial-input nil)
(defun phpcmp-get-initial-input ()
  (setq phpcmp-initial-input
        (buffer-substring-no-properties (point)
                                        (progn (save-excursion
                                                 (skip-syntax-backward "w_")
                                                 (point))))))

(defvar phpcmp--smart-sort-rules nil)
(defun phpcmp-add-smart-sort-rule (detector regexps-or-fn)
  ""
  (add-to-list 'phpcmp--smart-sort-rules (list detector regexps-or-fn)))

(defun phpcmp-smart-sort (table)
  ;; silence compiler
  (declare (special detector))
  (let ((do-sort (lambda (regexps-or-fn ret-detector)
                   (cond
                    ((functionp regexps-or-fn)
                     (if ret-detector
                         (funcall regexps-or-fn table ret-detector)
                       (error "phpcmp-smart-sort: regexps-or-fn is function. but detector returns nil.\n: %S"
                              detector)))
                    ((or (stringp regexps-or-fn)
                         (consp regexps-or-fn))
                     (phpcmp-re-sort-table regexps-or-fn table))
                    (t
                     (error "phpcmp-smart-sort: must not error!!"))))))
    (loop for (detector regexps-or-fn) in phpcmp--smart-sort-rules
          with ret-detector
          when (and (functionp detector)
                    (save-excursion
                      (setq ret-detector (funcall detector))))
          do (setq table
                   (condition-case e
                       (funcall do-sort regexps-or-fn ret-detector)
                     (error (phpcmp-log-debug (error-message-string e))
                            table)))
          finally return table)))

(defvar phpcmp-get-words-in-buffer-regexp
  (rx (>= 3 (or (syntax word)
                (syntax symbol)))))

(defun phpcmp-get-words-in-buffer ()
  (let ((cur-point (point))
        (ret nil))
    (save-excursion
      ;; search backward
      (goto-char (point-min))
      (loop always (re-search-forward phpcmp-get-words-in-buffer-regexp cur-point t)
            do (push (match-string-no-properties 0) ret))
      ;; search forward
      (goto-char cur-point)
      (loop always (re-search-forward phpcmp-get-words-in-buffer-regexp nil t)
            do (push (match-string-no-properties 0) ret)))
    ;; return
    (nreverse ret)))

(defun phpcmp-completions-table ()
  "list of list(name get-candidates-funcion)"
  (let* ((table '(("words in buffer" (lambda ()
                                      (phpcmp-get-words-in-buffer)))
                 ("functions" (lambda ()
                                (phpcmp-get-functions)))
                 ("ini directives" (lambda ()
                                     (phpcmp-db-get 'ini-directives)))
                 ("constants" (lambda ()
                                (phpcmp-db-get 'constants)))
                 ("keywords" (lambda ()
                               (phpcmp-db-get 'keywords)))
                 ("superglobals" (lambda ()
                                   (phpcmp-db-get 'superglobals)))
                 ("types" (lambda ()
                            (phpcmp-db-get 'types)))
                 ("global tags" (lambda ()
                                  (phpcmp-global-get-tags)))
                 ("global symbols" (lambda ()
                                     (phpcmp-global-get-symbols)))
		 ("phpunit assertions" (lambda ()
					 (phpcmp-db-get 'phpunit-assertions)))
		 ("phpunit methods" (lambda ()
				      (phpcmp-db-get 'phpunit-methods)))))
         (table (append table phpcmp-etags-completions-table)))
    (run-hooks 'phpcmp--initialize-hook)
    (phpcmp-smart-sort table)))

(defun phpcmp-re-sort-table (regexps table &optional reverse)
  (condition-case e
      (lexical-let*
          ((make-list (lambda (a) (if (consp a) a (list a))))
           (regexps (funcall make-list regexps))
           (any-match? (lambda (list)
                         (let ((name (first list)))
                           (some (lambda (re)
                                   (string-match re name))
                                 regexps)))))
        (phpcmp-log-info "called phpcmp-re-sort-table regexps:%s" regexps)
        (loop for list in table
              if (funcall any-match? list)
              collect list into matches
              else
              collect list into unmaches
              finally return (if reverse
                                 (nconc unmaches matches)
                               (nconc matches unmaches))))
    (error table)))

(defun phpcmp-make-completion-sources ()
  (phpcmp-labels ((make-source (&key name candidates)
            `((name . ,name)
              (init . (lambda ()
                        (with-current-buffer (phpcmp-anything-candidate-buffer 'global)
                          (insert (mapconcat 'identity
                                             (if (functionp ',candidates)
                                                 (funcall ',candidates)
                                               ',candidates)
                                             "\n")))))
              (candidates-in-buffer)
              (action . (("Insert" . (lambda (candidate)
                                       (delete-backward-char (length phpcmp-initial-input))
                                       (insert candidate)))
              ("Search". (lambda (candidate)
                           (phpcmp-search-manual candidate))))))))
    (loop for (name candidates) in (phpcmp-completions-table)
          collect (make-source
                   :name name
                   :candidates candidates))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Define Smart Completion Rule ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Class::function`!!'
(defun phpcmp-smart-sort-rule-full-name ()
  (backward-sexp)
  (let ((s (phpcmp-preceding-line-string)))
    (when (string-match (rx-to-string `(and (group (regexp ,phpcmp-identifier-regexp)) "::" eol))
                        s)
      (let ((s (match-string 1 s)))
        (prog1 s
          (phpcmp-log-info "sort-rule: full name call. returns %s" s))))))

(phpcmp-add-smart-sort-rule
 'phpcmp-smart-sort-rule-full-name
 (lambda (completion-table class-name) ; `phpcmp-smart-sort-rule-full-name' returns class-name
   (phpcmp-re-sort-table class-name completion-table)))

(phpcmp-add-smart-sort-rule
 (lambda ()
   (backward-sexp)
   (eq (preceding-char) ?$))
 "variable")

;;; $this->`!!'
(phpcmp-add-smart-sort-rule
 (lambda ()
   (backward-sexp)
   (let ((s (phpcmp-preceding-string 2)))
     (string= s "->")))
 "method")


;;; $var`!!'
(defun phpcmp-smart-sort-variable ()
  (interactive)
  (backward-sexp)
  (let ((s (phpcmp-preceding-string 1)))
    (when (and (stringp s)
               (string= s "$"))
      s)))

(phpcmp-add-smart-sort-rule
 'phpcmp-smart-sort-variable
 "variable")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Document ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun phpcmp-search-manual (query)
  (let ((url (phpcmp-search-url query)))
    (funcall phpcmp-browse-function url)))


(defun phpcmp-search-url (query)
  (format phpcmp-manual-url-format
          (url-hexify-string query)))

(defun phpcmp-get-document-string (s)
  (cond
   ((executable-find "w3m")
    (let ((url (phpcmp-search-url s)))
      (let ((coding-system-for-write 'utf-8)
            (coding-system-for-read 'utf-8))
        (let ((docstring (shell-command-to-string (format "w3m -dump %s" (shell-quote-argument (phpcmp-search-url s))))))
          (phpcmp-take-document docstring)))))
   (t
    "can't find \"w3m\" command")))

(defun phpcmp-take-document (docstring)
  (with-temp-buffer
    (cond
     ((stringp docstring)
      (insert docstring)
      (goto-char (point-min))
      (re-search-forward (rx bol "説明") nil t)
      (buffer-substring-no-properties (point-at-bol) (point-max)))
     (t
      ""))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DB ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar phpcmp--db (make-hash-table)
  "hash table.
'functions -> list of function
'variables -> list of variable
'class -> `phpcmp--db-class'")

(defvar phpcmp--db-class (make-hash-table :test 'equal)
  "String class-name -> Struct `phpcmp-class'")

;; (phpcmp-db-get 'functions)
;; (phpcmp-db-get 'variables)
;; (phpcmp-db-get 'ini-directives) ini
;; (phpcmp-db-get 'constants) constants
;; (phpcmp-db-get 'keywords) keywords
;; (phpcmp-db-get 'superglobals) superglobals
;; (phpcmp-db-get 'types) types
;; (phpcmp-db-get 'class "class-name" 'methods)
;; (phpcmp-db-get 'class "class-name" 'variables)
(defun phpcmp-db-get (type &rest args)
  (case type
    (class (apply 'phpcmp-db-get-class args))
    (otherwise (apply 'phpcmp--db-get-otherwise type args))))

(defun phpcmp--db-get-class (class-name type)
  (let ((phpcmp-class (gethash (downcase class-name) phpcmp--db-class)))
    (when (phpcmp-class-p phpcmp-class)
      (ecase type
        (methods (append (phpcmp-class-methods phpcmp-class)
                         ;; parent class
                         (let ((parent-class (phpcmp-class-parent phpcmp-class)))
                           (phpcmp--db-get-class parent-class 'methods))))
        (variables (append (phpcmp-class-variables phpcmp-class)
                           (let ((parent-class (phpcmp-class-parent phpcmp-class)))
                             (phpcmp--db-get-class parent-class 'variables))))))))

(defun phpcmp--db-get-otherwise (key)
  (gethash key phpcmp--db))

(defun phpcmp-db-update (type &rest args)
  (case type
    (class (apply 'phpcmp--db-update-class args))
    (otherwise (apply 'phpcmp--db-update-otherwise type args))))

(defun phpcmp--db-update-class (phpcmp-class)
  "`phpcmp-class' -> do update DB"
  (assert (phpcmp-class-p phpcmp-class))
  (let ((name (phpcmp-class-name phpcmp-class)))
    (and name
         (stringp name)
         ;; downcase name. case-insensitive.
         (puthash (downcase name) phpcmp-class phpcmp--db-class))))

(defun phpcmp--db-update-otherwise (key values)
  (let ((cur-val (gethash key phpcmp--db)))
    (puthash key (phpcmp-remove-dups (append cur-val values)) phpcmp--db)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; GLOBAL ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun phpcmp-global-execute-command (option)
  (let ((global-cmd (executable-find "global"))
        (tags-not-found? (lambda (los)
                           (and (stringp (car los))
                                (string= "global: GTAGS not found." (car los))))))
    (when phpcmp-global-enable-auto-update-tag-files
      (phpcmp-global-auto-update-tag-files))
    (when global-cmd
      (with-temp-buffer
        (call-process "global" nil t nil option)
        (let ((los (phpcmp-collect-matches "[[:print:]]+")))
          (unless (funcall tags-not-found? los)
            los))))))

(defun phpcmp-global-get-symbols ()
  (phpcmp-global-execute-command "-cs"))

(defun phpcmp-global-get-tags ()
  (phpcmp-global-execute-command "-c"))


(defun phpcmp-global-auto-update-tag-files ()
  (lexical-let* ((global-cmd (executable-find "global"))
                 (buf-name " *php-completion GLOBAL update*")
                 (process-running? (eq 'run
                                       (let ((proc (get-buffer-process buf-name)))
                                         (when (processp proc)
                                           (process-status proc))))))
    (when (and global-cmd
               (not process-running?))
      (phpcmp-async-do
       :command global-cmd
       :args '("-u")
       :buffer-name buf-name
       :callback (lambda ()
                   (kill-buffer buf-name))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Etags ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; this function is copied from anything-etags.el

(defun phpcmp-etags-find-tag-file ()
  "Find TAGS file, if can't find TAGS file in same directory, `phpcmp-etags-find-tag-file' try to find upper directory.
`phpcmp-etags-tag-file-search-limit' is limit number to find. default 10

Return tags file(full path).
If file is not found, return nil"
  (let ((file-exists? (lambda (dir)
                        (let ((tag-path (concat dir phpcmp-etags-tag-file-name)))
                          (and (stringp tag-path)
                               (file-exists-p tag-path)
                               (file-readable-p tag-path)))))
        (current-dir (phpcmp-get-current-directory)))
    (ignore-errors
      (loop with count = 0
            until (funcall file-exists? current-dir)
            ;; Return nil if outside the value of
            ;; `phpcmp-etags-tag-file-search-limit'.
            if (= count phpcmp-etags-tag-file-search-limit)
            do (return nil)
            ;; Or search upper directories.
            else
            do (progn (incf count)
                      (setq current-dir (expand-file-name (concat current-dir "../"))))
            finally return (concat current-dir phpcmp-etags-tag-file-name)))))

(defun* phpcmp-etags-get-tags (&optional (tag-file (phpcmp-etags-find-tag-file)))
  "Return list of struct `phpcmp-tag'"
  (when (and (stringp tag-file)
             (file-exists-p tag-file)
             (file-readable-p tag-file))
    (with-temp-buffer
      (insert-file-contents tag-file)
      (phpcmp-etags-parse-tags-buffer tag-file))))

(defun* phpcmp-etags-update-db (&optional (tags (phpcmp-etags-get-tags)))
  (let ((update-class (lambda (phpcmp-tag)
                        (loop for phpcmp-class in (phpcmp-tag-classes phpcmp-tag)
                              when (phpcmp-class-p phpcmp-class)
                              do (phpcmp-db-update 'class phpcmp-class))))
        (update-functions (lambda (phpcmp-tag)
                            (phpcmp-db-update 'functions
                                              (phpcmp-tag-functions phpcmp-tag))))
        (update-variables (lambda (phpcmp-tag)
                            (phpcmp-db-update 'variables (phpcmp-tag-variables phpcmp-tag)))))
    (mapc (lambda (tag)
            (funcall update-class tag)
            (funcall update-functions tag)
            (funcall update-variables tag))
          tags)))

(defun phpcmp-build-class-alist (class)
  (when (phpcmp-class-p class)
    (let ((name (phpcmp-class-name class))
          (methods (phpcmp-class-methods class))
          (variables (phpcmp-class-variables class)))
      `((,(concat name " methods") ,methods)
        (,(concat name " variables") ,variables)))))

(defun phpcmp-build-class-alist-from-tag (tag)
  (when (phpcmp-tag-p tag)
    (let ((classes (phpcmp-tag-classes tag)))
      (loop for class in classes
            append (phpcmp-build-class-alist class)))))

(defun phpcmp-tags-to-alist (tags)
  "list of `phpcmp-tag' to alist"
  (loop for tag in tags
        append (phpcmp-build-class-alist-from-tag tag)))

(defun phpcmp-set-etags-alist (tags)
  (setq phpcmp-etags-completions-table
        (nconc phpcmp-etags-completions-table (phpcmp-tags-to-alist tags))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Etags: TAGS Parser ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; This monster regexp matches an etags tag line.
;;   \1 is the string to match;
;;   \2 is not interesting;
;;   \3 is the guessed tag name; XXX guess should be better eg DEFUN
;;   \4 is not interesting;
;;   \5 is the explicitly-specified tag name.
;;   \6 is the line to start searching at;
;;   \7 is the char to start searching at.
(defvar phpcmp-etags-parse-tags-file-regexp
  (rx bol
      (group                                             ;1
       (regexp "\\([^\177]+[^-a-zA-Z0-9_+*$:\177]+\\)?") ;2
       (regexp "\\([-a-zA-Z0-9_+*$?:]+\\)")              ;3
       (regexp "[^-a-zA-Z0-9_+*$?:\177]*"))
      "\177"
      (regexp "\\(\\([^\n\001]+\\)\001\\)?") ;4, 5

      (regexp "\\([0-9]+\\)?")               ;6
      ","
      (regexp "\\([0-9]+\\)?")               ;7
      "\n"
      ))


(defsubst phpcmp-deftag (tag-string tag-file)
  (with-temp-buffer
    (insert tag-string)
    (goto-char (point-min))
    ;; Return struct `phpcmp-tag'
    (phpcmp-deftag-parse tag-file)))

(defun phpcmp-etags-parse-tags-buffer (tag-file)
  (let ((each-file-tag-strings
         (delete "" (split-string (buffer-string) "\14[ \n]+"))))
    (loop for s in each-file-tag-strings
          collect (phpcmp-deftag s tag-file))))


(defsubst phpcmp-deftag-parse-file-info ()
  (when (looking-at (rx bol (group (+ (not (any ",")))) "," (? (* digit)) "\n"))
    (let* ((relative-file-path (match-string 1)))
      (prog1 relative-file-path
        (forward-line)))))

(defsubst phpcmp-take-same-indent-string ()
  "move point"
  (let ((cur-indent (current-indentation))
        (cur-point (point)))
    (forward-line)
    (buffer-substring-no-properties
     cur-point
     (loop while (and
                  (not
                   (>= cur-indent
                       (current-indentation)))
                  (not (eobp)))
           do (forward-line)
           finally return (point)))))

(defsubst phpcmp-deftag-parse-class ()
  (let ((class-str (phpcmp-take-same-indent-string))
        name parent methods variables)
    (with-temp-buffer
      (insert class-str)
      (goto-char (point-min))
      (while (not (eobp))
        (cond
         ((looking-at (rx bol (* space) "class" (? (*? not-newline) "extends" (+ space) (group (+ (any alpha "_"))))))
          (let ((parent-class (match-string 1)))
            (when parent-class
              (setq parent parent-class)))
          (when (looking-at phpcmp-etags-parse-tags-file-regexp)
            (let ((class-name (match-string 5)))
              (setq name class-name)))
          (forward-line))
         ((looking-at (rx bol (* space) (? (or "public" "private")) (* space) "function"))
          (when (looking-at phpcmp-etags-parse-tags-file-regexp)
            (let ((function (match-string 5)))
              (push function methods)))
          (forward-line))
         ((looking-at (rx bol (* space) "$" (+ (any alnum "_")) (* space) "="))
          (when (looking-at phpcmp-etags-parse-tags-file-regexp)
            (let ((variable (match-string 5)))
              (push variable variables)))
          (forward-line))
         (t
          (forward-line)))))
    (phpcmp-make-class
     :name name
     :parent parent
     :methods methods
     :variables variables)))



(defun phpcmp-deftag-parse (tag-file)
  (let ((relative-file-path (phpcmp-deftag-parse-file-info)))
    (let (path relative-path classes functions variables)
      (while (not (eobp))
        (cond
         ((looking-at (rx bol (* space) "class"))
          (push (phpcmp-deftag-parse-class) classes))
         ((looking-at (rx bol (* space) (? (or "public" "private")) (* space) "function"))
          (when (looking-at phpcmp-etags-parse-tags-file-regexp)
            (let ((function (match-string 5)))
              (push function functions)))
          (forward-line))
         ((looking-at (rx bol (* space) "$" (+ (any alnum "_")) (* space) "="))
          (when (looking-at phpcmp-etags-parse-tags-file-regexp)
            (let ((variable (match-string 5)))
            (push variable variables)))
          (forward-line))
         (t
          (forward-line))))
      (phpcmp-make-tag
       :tag-file tag-file
       :path (concat (file-name-directory tag-file)
                     relative-file-path)
       :relative-path relative-file-path
       :classes classes
       :functions functions
       :variables variables))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Commands ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun phpcmp-complete ()
  (interactive)
  (phpcmp-anything (phpcmp-make-completion-sources)
		   (phpcmp-get-initial-input)))

(defun phpcmp-showdoc-at-point ()
  (interactive)
  (let* ((s (or (thing-at-point 'symbol) ""))
         (docstring (phpcmp-get-document-string s)))
    (phpcmp-showtip docstring)))

(defvar phpcmp-popup-document-buffer "*php-completion document*")
(defun phpcmp-popup-document-at-point ()
  (interactive)
  (let* ((s (or (thing-at-point 'symbol) ""))
         (docstring (phpcmp-get-document-string s)))
    (let ((b (get-buffer-create phpcmp-popup-document-buffer)))
      (with-current-buffer b
        (erase-buffer)
        (insert docstring)
        (goto-char (point-min)))
      (pop-to-buffer b))))

(defun phpcmp-reset-all-db ()
  (interactive)
  (setq phpcmp--db (make-hash-table)
        phpcmp--db-class (make-hash-table :test 'equal))
  (load (locate-library "php-completion")))

(defun phpcmp-read-tags-file (tags-file)
  (interactive "fTAGS file: ")
  (and (stringp tags-file)
       (file-readable-p tags-file)
       (phpcmp-set-etags-alist (phpcmp-etags-get-tags tags-file))))

(defun phpcmp-search ()
  (interactive)
  (let* ((initial (substring-no-properties (or (thing-at-point 'symbol) "")))
         (query (completing-read "Query: " (phpcmp-ac-get-cands) nil nil initial)))
    (and (stringp query)
         (phpcmp-search-manual query))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; auto-complete.el ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar ac-source-php-completion
  '((candidates . phpcmp-ac-build-cands)))

(defvar ac-source-php-completion-patial
  '((candidates . phpcmp-ac-build-cands-patial)))

(defun phpcmp-ac-build-cands ()
  (all-completions ac-target (phpcmp-ac-get-cands)))

(defun phpcmp-ac-build-cands-patial ()
  (let ((los (phpcmp-ac-get-cands)))
    (append (all-completions ac-target los)
            (phpcmp-ac-build-cands1 los))))

(defun phpcmp-ac-build-cands1 (los)
  (let ((match (lambda (s)
                 (and (stringp s)
                      (string-match ac-target s)
                      (not (string= ac-target s))))))
    (remove-if-not match los)))

(defun phpcmp-ac-get-cands ()
  (loop for (name get-cands-fn) in (phpcmp-completions-table)
        append (if (functionp get-cands-fn)
                   (funcall get-cands-fn)
                 get-cands-fn)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; DATA ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; (let ((s (shell-command-to-string "perl scrape-funcs.pl"))
;;       (insert (lambda (s) (insert (format "%S" s) "\n"))))
;;   (mapcar insert (split-string s "\n")))

(defconst phpcmp-php-functions-file "phpcmp-index-of-php-functions"
  "Filename of PHP functions index")

(defconst phpcmp-phpunit-assertion-file "phpcmp-index-of-phpunit-assertions"
  "Filename of PHPUnit assertion index")

(defun phpcmp-get-index-list-from-file(file)
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      file
      (file-name-directory (or load-file-name buffer-file-name))))
    (split-string (buffer-substring (point-min) (point-max)))))

(phpcmp-db-update
 'functions
 (phpcmp-get-index-list-from-file phpcmp-php-functions-file))

(phpcmp-db-update
 'ini-directives
 '(
   "allow_call_time_pass_reference"
   "allow_url_fopen"
   "allow_url_include"
   "always_populate_raw_post_data"
   "apc.cache_by_default"
   "apc.enabled"
   "apc.enable_cli"
   "apc.file_update_protection"
   "apc.filters"
   "apc.gc_ttl"
   "apc.include_once_override"
   "apc.localcache"
   "apc.localcache.size"
   "apc.max_file_size"
   "apc.mmap_file_mask"
   "apc.num_files_hint"
   "apc.optimization"
   "apc.report_autofilter"
   "apc.rfc1867"
   "apc.rfc1867_freq"
   "apc.rfc1867_name"
   "apc.rfc1867_prefix"
   "apc.shm_segments"
   "apc.shm_size"
   "apc.slam_defense"
   "apc.stat"
   "apc.stat_ctime"
   "apc.ttl"
   "apc.user_entries_hint"
   "apc.user_ttl"
   "apc.write_lock"
   "apd.bitmask"
   "apd.dumpdir"
   "apd.statement_tracing"
   "arg_separator"
   "arg_separator.input"
   "arg_separator.output"
   "asp_tags"
   "assert.active"
   "assert.bail"
   "assert.callback"
   "assert.quiet_eval"
   "assert.warning"
   "auto_append_file"
   "auto_detect_line_endings"
   "auto_globals_jit"
   "auto_prepend_file"
   "axis2.client_home"
   "axis2.enable_exception"
   "axis2.enable_trace"
   "axis2.log_path"
   "bcmath.scale"
   "bcompiler.enabled"
   "birdstep.max_links"
   "blenc.key_file"
   "browscap"
   "cgi.check_shebang_line"
   "cgi.discard_path"
   "cgi.fix_pathinfo"
   "cgi.force_redirect"
   "cgi.nph"
   "cgi.redirect_status_env"
   "cgi.rfc2616_headers"
   "child_terminate"
   "coin_acceptor.autoreset"
   "coin_acceptor.auto_initialize"
   "coin_acceptor.auto_reset"
   "coin_acceptor.command_function"
   "coin_acceptor.delay"
   "coin_acceptor.delay_coins"
   "coin_acceptor.delay_prom"
   "coin_acceptor.device"
   "coin_acceptor.lock_on_close"
   "coin_acceptor.start_unlocked"
   "com.allow_dcom"
   "com.autoregister_casesensitive"
   "com.autoregister_typelib"
   "com.autoregister_verbose"
   "com.code_page"
   "com.typelib_file"
   "crack.default_dictionary"
   "daffodildb.default_host"
   "daffodildb.default_password"
   "daffodildb.default_socket"
   "daffodildb.default_user"
   "daffodildb.port"
   "date.default_latitude"
   "date.default_longitude"
   "date.sunrise_zenith"
   "date.sunset_zenith"
   "date.timezone"
   "dba.default_handler"
   "dbx.colnames_case"
   "default_charset"
   "default_mimetype"
   "default_socket_timeout"
   "define_syslog_variables"
   "detect_unicode"
   "disable_classes"
   "disable_functions"
   "display_errors"
   "display_startup_errors"
   "docref_ext"
   "docref_root"
   "doc_root"
   "enable_dl"
   "engine"
   "error_append_string"
   "error_log"
   "error_prepend_string"
   "error_reporting"
   "etpan.default.charset"
   "etpan.default.protocol"
   "exif.decode_jis_intel"
   "exif.decode_jis_motorola"
   "exif.decode_unicode_intel"
   "exif.decode_unicode_motorola"
   "exif.encode_jis"
   "exif.encode_unicode"
   "expect.logfile"
   "expect.loguser"
   "expect.timeout"
   "expose_php"
   "extension_dir"
   "fastcgi.impersonate"
   "fastcgi.logging"
   "fbsql.allow_persistant"
   "fbsql.allow_persistent"
   "fbsql.autocommit"
   "fbsql.batchSize"
   "fbsql.batchsize"
   "fbsql.default_database"
   "fbsql.default_database_password"
   "fbsql.default_host"
   "fbsql.default_password"
   "fbsql.default_user"
   "fbsql.generate_warnings"
   "fbsql.max_connections"
   "fbsql.max_links"
   "fbsql.max_persistent"
   "fbsql.max_results"
   "fbsql.mbatchSize"
   "fbsql.show_timestamp_decimals"
   "file_uploads"
   "filter.default"
   "filter.default_flags"
   "from"
   "gd.jpeg_ignore_warning"
   "geoip.custom_directory"
   "geoip.database_standard"
   "gpc_order"
   "hidef.ini_path"
   "highlight.bg"
   "highlight.comment"
   "highlight.default"
   "highlight.html"
   "highlight.keyword"
   "highlight.string"
   "html_errors"
   "htscanner.config_file"
   "htscanner.default_docroot"
   "htscanner.default_ttl"
   "htscanner.stop_on_error"
   "http.allowed_methods"
   "http.allowed_methods_log"
   "http.cache_log"
   "http.composite_log"
   "http.etag.mode"
   "http.etag_mode"
   "http.force_exit"
   "http.log.allowed_methods"
   "http.log.cache"
   "http.log.composite"
   "http.log.not_found"
   "http.log.redirect"
   "http.ob_deflate_auto"
   "http.ob_deflate_flags"
   "http.ob_inflate_auto"
   "http.ob_inflate_flags"
   "http.only_exceptions"
   "http.persistent.handles.ident"
   "http.persistent.handles.limit"
   "http.redirect_log"
   "http.request.datashare.connect"
   "http.request.datashare.cookie"
   "http.request.datashare.dns"
   "http.request.datashare.ssl"
   "http.request.methods.allowed"
   "http.request.methods.custom"
   "http.send.deflate.start_auto"
   "http.send.deflate.start_flags"
   "http.send.inflate.start_auto"
   "http.send.inflate.start_flags"
   "http.send.not_found_404"
   "hyerwave.allow_persistent"
   "hyperwave.allow_persistent"
   "hyperwave.default_port"
   "ibase.allow_persistent"
   "ibase.dateformat"
   "ibase.default_charset"
   "ibase.default_db"
   "ibase.default_password"
   "ibase.default_user"
   "ibase.max_links"
   "ibase.max_persistent"
   "ibase.timeformat"
   "ibase.timestampformat"
   "ibm_db2.binmode"
   "ibm_db2.i5_allow_commit"
   "ibm_db2.i5_dbcs_alloc"
   "ibm_db2.instance_name"
   "iconv.input_encoding"
   "iconv.internal_encoding"
   "iconv.output_encoding"
   "ifx.allow_persistent"
   "ifx.blobinfile"
   "ifx.byteasvarchar"
   "ifx.charasvarchar"
   "ifx.default_host"
   "ifx.default_password"
   "ifx.default_user"
   "ifx.max_links"
   "ifx.max_persistent"
   "ifx.nullformat"
   "ifx.textasvarchar"
   "ignore_repeated_errors"
   "ignore_repeated_source"
   "ignore_user_abort"
   "imlib2.font_cache_max_size"
   "imlib2.font_path"
   "implicit_flush"
   "include_path"
   "ingres.allow_persistent"
   "ingres.array_index_start"
   "ingres.blob_segment_length"
   "ingres.cursor_mode"
   "ingres.default_database"
   "ingres.default_password"
   "ingres.default_user"
   "ingres.max_links"
   "ingres.max_persistent"
   "ingres.report_db_warnings"
   "ingres.timeout"
   "ingres.trace_connect"
   "ircg.control_user"
   "ircg.keep_alive_interval"
   "ircg.max_format_message_sets"
   "ircg.shared_mem_size"
   "ircg.work_dir"
   "last_modified"
   "ldap.base_dn"
   "ldap.max_links"
   "log.dbm_dir"
   "log_errors"
   "log_errors_max_len"
   "magic_quotes_gpc"
   "magic_quotes_runtime"
   "magic_quotes_sybase"
   "mail.force_extra_parameters"
   "mailparse.def_charset"
   "maxdb.default_db"
   "maxdb.default_host"
   "maxdb.default_pw"
   "maxdb.default_user"
   "maxdb.long_readlen"
   "max_execution_time"
   "max_input_nesting_level"
   "max_input_time"
   "mbstring.detect_order"
   "mbstring.encoding_translation"
   "mbstring.func_overload"
   "mbstring.http_input"
   "mbstring.http_output"
   "mbstring.internal_encoding"
   "mbstring.language"
   "mbstring.script_encoding"
   "mbstring.strict_detection"
   "mbstring.substitute_character"
   "mcrypt.algorithms_dir"
   "mcrypt.modes_dir"
   "memcache.allow_failover"
   "memcache.chunk_size"
   "memcache.default_port"
   "memcache.hash_function"
   "memcache.hash_strategy"
   "memcache.max_failover_attempts"
   "memory_limit"
   "mime_magic.debug"
   "mime_magic.magicfile"
   "msql.allow_persistent"
   "msql.max_links"
   "msql.max_persistent"
   "mssql.allow_persistent"
   "mssql.batchsize"
   "mssql.charset"
   "mssql.compatability_mode"
   "mssql.connect_timeout"
   "mssql.datetimeconvert"
   "mssql.max_links"
   "mssql.max_persistent"
   "mssql.max_procs"
   "mssql.min_error_severity"
   "mssql.min_message_severity"
   "mssql.secure_connection"
   "mssql.textlimit"
   "mssql.textsize"
   "mssql.timeout"
   "mysql.allow_local_infile"
   "mysql.allow_persistent"
   "mysql.cache_size"
   "mysql.connect_timeout"
   "mysql.default_host"
   "mysql.default_password"
   "mysql.default_port"
   "mysql.default_socket"
   "mysql.default_user"
   "mysql.max_links"
   "mysql.max_persistent"
   "mysql.trace_mode"
   "mysqli.allow_local_infile"
   "mysqli.cache_size"
   "mysqli.default_host"
   "mysqli.default_port"
   "mysqli.default_pw"
   "mysqli.default_socket"
   "mysqli.default_user"
   "mysqli.max_links"
   "mysqli.reconnect"
   "mysqlnd.collect_statistics"
   "namazu.debugmode"
   "namazu.lang"
   "namazu.loggingmode"
   "namazu.sortmethod"
   "namazu.sortorder"
   "nsapi.read_timeout"
   "oci8.default_prefetch"
   "oci8.max_persistent"
   "oci8.old_oci_close_semantics"
   "oci8.persistent_timeout"
   "oci8.ping_interval"
   "oci8.privileged_connect"
   "oci8.statement_cache_size"
   "odbc.allow_persistent"
   "odbc.check_persistent"
   "odbc.defaultbinmode"
   "odbc.defaultlrl"
   "odbc.default_db"
   "odbc.default_pw"
   "odbc.default_user"
   "odbc.max_links"
   "odbc.max_persistent"
   "odbtp.datetime_format"
   "odbtp.detach_default_queries"
   "odbtp.guid_format"
   "odbtp.interface_file"
   "odbtp.truncation_errors"
   "opendirectory.default_separator"
   "opendirectory.max_refs"
   "opendirectory.separator"
   "open_basedir"
   "oracle.allow_persistent"
   "oracle.max_links"
   "oracle.max_persistent"
   "output_buffering"
   "output_handler"
   "pam.servicename"
   "pcre.backtrack_limit"
   "pcre.recursion_limit"
   "pdo_odbc.connection_pooling"
   "pdo_odbc.db2_instance_name"
   "pfpro.defaulthost"
   "pfpro.defaultport"
   "pfpro.defaulttimeout"
   "pfpro.proxyaddress"
   "pfpro.proxylogon"
   "pfpro.proxypassword"
   "pfpro.proxyport"
   "pgsql.allow_persistent"
   "pgsql.auto_reset_persistent"
   "pgsql.ignore_notice"
   "pgsql.log_notice"
   "pgsql.max_links"
   "pgsql.max_persistent"
   "phar.extract_list"
   "phar.readonly"
   "phar.require_hash"
   "post_max_size"
   "precision"
   "printer.default_printer"
   "python.append_path"
   "python.prepend_path"
   "realpath_cache_size"
   "realpath_cache_ttl"
   "register_argc_argv"
   "register_globals"
   "register_long_arrays"
   "report_memleaks"
   "report_zend_debug"
   "runkit.internal_override"
   "runkit.superglobal"
   "safe_mode"
   "safe_mode_allowed_env_vars"
   "safe_mode_exec_dir"
   "safe_mode_gid"
   "safe_mode_include_dir"
   "safe_mode_protected_env_vars"
   "sendmail_from"
   "sendmail_path"
   "serialize_precision"
   "session.auto_start"
   "session.bug_compat_42"
   "session.bug_compat_warn"
   "session.cache_expire"
   "session.cache_limiter"
   "session.cookie_domain"
   "session.cookie_httponly"
   "session.cookie_lifetime"
   "session.cookie_path"
   "session.cookie_secure"
   "session.entropy_file"
   "session.entropy_length"
   "session.gc_dividend"
   "session.gc_divisor"
   "session.gc_maxlifetime"
   "session.gc_probability"
   "session.hash_bits_per_character"
   "session.hash_function"
   "session.name"
   "session.referer_check"
   "session.save_handler"
   "session.save_path"
   "session.serialize_handler"
   "session.use_cookies"
   "session.use_only_cookies"
   "session.use_trans_sid"
   "session_pgsql.create_table"
   "session_pgsql.db"
   "session_pgsql.disable"
   "session_pgsql.failover_mode"
   "session_pgsql.gc_interval"
   "session_pgsql.keep_expired"
   "session_pgsql.sem_file_name"
   "session_pgsql.serializable"
   "session_pgsql.short_circuit"
   "session_pgsql.use_app_vars"
   "session_pgsql.vacuum_interval"
   "short_open_tag"
   "simple_cvs.authMethod"
   "simple_cvs.compressionLevel"
   "simple_cvs.cvsRoot"
   "simple_cvs.host"
   "simple_cvs.moduleName"
   "simple_cvs.userName"
   "simple_cvs.workingDir"
   "SMTP"
   "smtp_port"
   "soap.wsdl_cache"
   "soap.wsdl_cache_dir"
   "soap.wsdl_cache_enabled"
   "soap.wsdl_cache_limit"
   "soap.wsdl_cache_ttl"
   "sql.safe_mode"
   "sqlite.assoc_case"
   "sqlite.iso8859.locale"
   "sybase.allow_persistent"
   "sybase.compatability_mode"
   "sybase.hostname"
   "sybase.interface_file"
   "sybase.login_timeout"
   "sybase.max_links"
   "sybase.max_persistent"
   "sybase.min_client_severity"
   "sybase.min_error_severity"
   "sybase.min_message_severity"
   "sybase.min_server_severity"
   "sybase.timeout"
   "sybct.allow_persistent"
   "sybct.deadlock_retry_count"
   "sybct.hostname"
   "sybct.login_timeout"
   "sybct.max_links"
   "sybct.max_persistent"
   "sybct.min_client_severity"
   "sybct.min_server_severity"
   "sybct.packet_size"
   "sybct.timeout"
   "sysvshm.init_mem"
   "tidy.clean_output"
   "tidy.default_config"
   "track_errors"
   "track_vars"
   "unicode.fallback_encoding"
   "unicode.filesystem_encoding"
   "unicode.http_input_encoding"
   "unicode.output_encoding"
   "unicode.runtime_encoding"
   "unicode.script_encoding"
   "unicode.semantics"
   "unicode.stream_encoding"
   "unserialize_callback_func"
   "uploadprogress.file.filename_template"
   "upload_max_filesize"
   "upload_tmp_dir"
   "url_rewriter.tags"
   "user_agent"
   "user_dir"
   "user_ini.cache_ttl"
   "user_ini.filename"
   "valkyrie.auto_validate"
   "valkyrie.config_path"
   "variables_order"
   "velocis.max_links"
   "vld.active"
   "vld.execute"
   "vld.skip_append"
   "vld.skip_prepend"
   "xbithack"
   "xdebug.auto_profile"
   "xdebug.auto_profile_mode"
   "xdebug.auto_trace"
   "xdebug.collect_includes"
   "xdebug.collect_params"
   "xdebug.collect_return"
   "xdebug.collect_vars"
   "xdebug.default_enable"
   "xdebug.dump.COOKIE"
   "xdebug.dump.ENV"
   "xdebug.dump.FILES"
   "xdebug.dump.GET"
   "xdebug.dump.POST"
   "xdebug.dump.REQUEST"
   "xdebug.dump.SERVER"
   "xdebug.dump.SESSION"
   "xdebug.dump_globals"
   "xdebug.dump_once"
   "xdebug.dump_undefined"
   "xdebug.extended_info"
   "xdebug.idekey"
   "xdebug.manual_url"
   "xdebug.max_nesting_level"
   "xdebug.output_dir"
   "xdebug.profiler_aggregate"
   "xdebug.profiler_append"
   "xdebug.profiler_enable"
   "xdebug.profiler_enable_trigger"
   "xdebug.profiler_output_dir"
   "xdebug.profiler_output_name"
   "xdebug.remote_autostart"
   "xdebug.remote_enable"
   "xdebug.remote_handler"
   "xdebug.remote_host"
   "xdebug.remote_log"
   "xdebug.remote_mode"
   "xdebug.remote_port"
   "xdebug.show_exception_trace"
   "xdebug.show_local_vars"
   "xdebug.show_mem_delta"
   "xdebug.trace_format"
   "xdebug.trace_options"
   "xdebug.trace_output_dir"
   "xdebug.trace_output_name"
   "xdebug.var_display_max_children"
   "xdebug.var_display_max_data"
   "xdebug.var_display_max_depth"
   "xmlrpc_errors"
   "xmlrpc_error_number"
   "xmms.path"
   "xmms.session"
   "y2k_compliance"
   "yami.response.timeout"
   "yaz.keepalive"
   "yaz.log_file"
   "yaz.log_mask"
   "yaz.max_links"
   "zend.ze1_compatibility_mode"
   "zlib.output_compression"
   "zlib.output_compression_level"
   "zlib.output_handler"
   "PHP_INI_USER"
   "PHP_INI_PERDIR"
   "PHP_INI_SYSTEM"
   "PHP_INI_ALL"
   ))


(phpcmp-db-update
 'constants
 '(
   ;; core constants
   "__LINE__" "__FILE__"
   "__FUNCTION__" "__CLASS__" "__METHOD__"
   "__TRAIT__"
   "PHP_OS" "PHP_VERSION"
   "TRUE" "FALSE" "NULL"
   "E_ERROR" "E_NOTICE" "E_PARSE" "E_WARNING" "E_ALL" "E_STRICT"
   "E_USER_ERROR" "E_USER_WARNING" "E_USER_NOTICE"
   "E_DEPRECATED" "E_USER_DEPRECATED"
   "DEFAULT_INCLUDE_PATH" "PEAR_INSTALL_DIR" "PEAR_EXTENSION_DIR"
   "PHP_BINDIR" "PHP_LIBDIR" "PHP_DATADIR" "PHP_SYSCONFDIR"
   "PHP_LOCALSTATEDIR" "PHP_CONFIG_FILE_PATH"
   "PHP_EOL"
   "PHP_BINARY" "PHP_MANDIR"

   ;; from ext/standard:
   "EXTR_OVERWRITE" "EXTR_SKIP" "EXTR_PREFIX_SAME"
   "EXTR_PREFIX_ALL" "EXTR_PREFIX_INVALID" "SORT_ASC" "SORT_DESC"
   "SORT_REGULAR" "SORT_NUMERIC" "SORT_STRING" "ASSERT_ACTIVE"
   "ASSERT_CALLBACK" "ASSERT_BAIL" "ASSERT_WARNING"
   "ASSERT_QUIET_EVAL" "CONNECTION_ABORTED" "CONNECTION_NORMAL"
   "CONNECTION_TIMEOUT" "M_E" "M_LOG2E" "M_LOG10E" "M_LN2"
   "M_LN10" "M_PI" "M_PI_2" "M_PI_4" "M_1_PI" "M_2_PI"
   "M_2_SQRTPI" "M_SQRT2" "M_SQRT1_2" "CRYPT_SALT_LENGTH"
   "CRYPT_STD_DES" "CRYPT_EXT_DES" "CRYPT_MD5" "CRYPT_BLOWFISH"
   "DIRECTORY_SEPARATOR" "SEEK_SET" "SEEK_CUR" "SEEK_END"
   "LOCK_SH" "LOCK_EX" "LOCK_UN" "LOCK_NB" "HTML_SPECIALCHARS"
   "HTML_ENTITIES" "ENT_COMPAT" "ENT_QUOTES" "ENT_NOQUOTES"
   "INFO_GENERAL" "INFO_CREDITS" "INFO_CONFIGURATION"
   "INFO_ENVIRONMENT" "INFO_VARIABLES" "INFO_LICENSE" "INFO_ALL"
   "CREDITS_GROUP" "CREDITS_GENERAL" "CREDITS_SAPI"
   "CREDITS_MODULES" "CREDITS_DOCS" "CREDITS_FULLPAGE"
   "CREDITS_QA" "CREDITS_ALL" "PHP_OUTPUT_HANDLER_START"
   "PHP_OUTPUT_HANDLER_CONT" "PHP_OUTPUT_HANDLER_END"
   "STR_PAD_LEFT" "STR_PAD_RIGHT" "STR_PAD_BOTH"
   "PATHINFO_DIRNAME" "PATHINFO_BASENAME" "PATHINFO_EXTENSION"
   "CHAR_MAX" "LC_CTYPE" "LC_NUMERIC" "LC_TIME" "LC_COLLATE"
   "LC_MONETARY" "LC_ALL" "LC_MESSAGES" "LOG_EMERG" "LOG_ALERT"
   "LOG_CRIT" "LOG_ERR" "LOG_WARNING" "LOG_NOTICE" "LOG_INFO"
   "LOG_DEBUG" "LOG_KERN" "LOG_USER" "LOG_MAIL" "LOG_DAEMON"
   "LOG_AUTH" "LOG_SYSLOG" "LOG_LPR" "LOG_NEWS" "LOG_UUCP"
   "LOG_CRON" "LOG_AUTHPRIV" "LOG_LOCAL0" "LOG_LOCAL1"
   "LOG_LOCAL2" "LOG_LOCAL3" "LOG_LOCAL4" "LOG_LOCAL5"
   "LOG_LOCAL6" "LOG_LOCAL7" "LOG_PID" "LOG_CONS" "LOG_ODELAY"
   "LOG_NDELAY" "LOG_NOWAIT" "LOG_PERROR"

   ;; Disabled by default because they slow buffer loading
   ;; If you have use for them, uncomment the strings
   ;; that you want colored.
   ;; To compile, you may have to increase 'max-specpdl-size'

   ;; from other bundled extensions:
   "CAL_EASTER_TO_xxx" "VT_NULL" "VT_EMPTY" "VT_UI1" "VT_I2"
   "VT_I4" "VT_R4" "VT_R8" "VT_BOOL" "VT_ERROR" "VT_CY" "VT_DATE"
   "VT_BSTR" "VT_DECIMAL" "VT_UNKNOWN" "VT_DISPATCH" "VT_VARIANT"
   "VT_I1" "VT_UI2" "VT_UI4" "VT_INT" "VT_UINT" "VT_ARRAY"
   "VT_BYREF" "CP_ACP" "CP_MACCP" "CP_OEMCP" "CP_SYMBOL"
   "CP_THREAD_ACP" "CP_UTF7" "CP_UTF8" "CPDF_PM_NONE"
   "CPDF_PM_OUTLINES" "CPDF_PM_THUMBS" "CPDF_PM_FULLSCREEN"
   "CPDF_PL_SINGLE" "CPDF_PL_1COLUMN" "CPDF_PL_2LCOLUMN"
   "CPDF_PL_2RCOLUMN" "CURLOPT_PORT" "CURLOPT_FILE"
   "CURLOPT_INFILE" "CURLOPT_INFILESIZE" "CURLOPT_URL"
   "CURLOPT_PROXY" "CURLOPT_VERBOSE" "CURLOPT_HEADER"
   "CURLOPT_HTTPHEADER" "CURLOPT_NOPROGRESS" "CURLOPT_NOBODY"
   "CURLOPT_FAILONERROR" "CURLOPT_UPLOAD" "CURLOPT_POST"
   "CURLOPT_FTPLISTONLY" "CURLOPT_FTPAPPEND" "CURLOPT_NETRC"
   "CURLOPT_FOLLOWLOCATION" "CURLOPT_FTPASCII" "CURLOPT_PUT"
   "CURLOPT_MUTE" "CURLOPT_USERPWD" "CURLOPT_PROXYUSERPWD"
   "CURLOPT_RANGE" "CURLOPT_TIMEOUT" "CURLOPT_POSTFIELDS"
   "CURLOPT_REFERER" "CURLOPT_USERAGENT" "CURLOPT_FTPPORT"
   "CURLOPT_LOW_SPEED_LIMIT" "CURLOPT_LOW_SPEED_TIME"
   "CURLOPT_RESUME_FROM" "CURLOPT_COOKIE" "CURLOPT_SSLCERT"
   "CURLOPT_SSLCERTPASSWD" "CURLOPT_WRITEHEADER"
   "CURLOPT_COOKIEFILE" "CURLOPT_SSLVERSION"
   "CURLOPT_TIMECONDITION" "CURLOPT_TIMEVALUE"
   "CURLOPT_CUSTOMREQUEST" "CURLOPT_STDERR" "CURLOPT_TRANSFERTEXT"
   "CURLOPT_RETURNTRANSFER" "CURLOPT_QUOTE" "CURLOPT_POSTQUOTE"
   "CURLOPT_INTERFACE" "CURLOPT_KRB4LEVEL"
   "CURLOPT_HTTPPROXYTUNNEL" "CURLOPT_FILETIME"
   "CURLOPT_WRITEFUNCTION" "CURLOPT_READFUNCTION"
   "CURLOPT_PASSWDFUNCTION" "CURLOPT_HEADERFUNCTION"
   "CURLOPT_MAXREDIRS" "CURLOPT_MAXCONNECTS" "CURLOPT_CLOSEPOLICY"
   "CURLOPT_FRESH_CONNECT" "CURLOPT_FORBID_REUSE"
   "CURLOPT_RANDOM_FILE" "CURLOPT_EGDSOCKET"
   "CURLOPT_CONNECTTIMEOUT" "CURLOPT_SSL_VERIFYPEER"
   "CURLOPT_CAINFO" "CURLOPT_BINARYTRANSER"
   "CURLCLOSEPOLICY_LEAST_RECENTLY_USED" "CURLCLOSEPOLICY_OLDEST"
   "CURLINFO_EFFECTIVE_URL" "CURLINFO_HTTP_CODE"
   "CURLINFO_HEADER_SIZE" "CURLINFO_REQUEST_SIZE"
   "CURLINFO_TOTAL_TIME" "CURLINFO_NAMELOOKUP_TIME"
   "CURLINFO_CONNECT_TIME" "CURLINFO_PRETRANSFER_TIME"
   "CURLINFO_SIZE_UPLOAD" "CURLINFO_SIZE_DOWNLOAD"
   "CURLINFO_SPEED_DOWNLOAD" "CURLINFO_SPEED_UPLOAD"
   "CURLINFO_FILETIME" "CURLE_OK" "CURLE_UNSUPPORTED_PROTOCOL"
   "CURLE_FAILED_INIT" "CURLE_URL_MALFORMAT"
   "CURLE_URL_MALFORMAT_USER" "CURLE_COULDNT_RESOLVE_PROXY"
   "CURLE_COULDNT_RESOLVE_HOST" "CURLE_COULDNT_CONNECT"
   "CURLE_FTP_WEIRD_SERVER_REPLY" "CURLE_FTP_ACCESS_DENIED"
   "CURLE_FTP_USER_PASSWORD_INCORRECT"
   "CURLE_FTP_WEIRD_PASS_REPLY" "CURLE_FTP_WEIRD_USER_REPLY"
   "CURLE_FTP_WEIRD_PASV_REPLY" "CURLE_FTP_WEIRD_227_FORMAT"
   "CURLE_FTP_CANT_GET_HOST" "CURLE_FTP_CANT_RECONNECT"
   "CURLE_FTP_COULDNT_SET_BINARY" "CURLE_PARTIAL_FILE"
   "CURLE_FTP_COULDNT_RETR_FILE" "CURLE_FTP_WRITE_ERROR"
   "CURLE_FTP_QUOTE_ERROR" "CURLE_HTTP_NOT_FOUND"
   "CURLE_WRITE_ERROR" "CURLE_MALFORMAT_USER"
   "CURLE_FTP_COULDNT_STOR_FILE" "CURLE_READ_ERROR"
   "CURLE_OUT_OF_MEMORY" "CURLE_OPERATION_TIMEOUTED"
   "CURLE_FTP_COULDNT_SET_ASCII" "CURLE_FTP_PORT_FAILED"
   "CURLE_FTP_COULDNT_USE_REST" "CURLE_FTP_COULDNT_GET_SIZE"
   "CURLE_HTTP_RANGE_ERROR" "CURLE_HTTP_POST_ERROR"
   "CURLE_SSL_CONNECT_ERROR" "CURLE_FTP_BAD_DOWNLOAD_RESUME"
   "CURLE_FILE_COULDNT_READ_FILE" "CURLE_LDAP_CANNOT_BIND"
   "CURLE_LDAP_SEARCH_FAILED" "CURLE_LIBRARY_NOT_FOUND"
   "CURLE_FUNCTION_NOT_FOUND" "CURLE_ABORTED_BY_CALLBACK"
   "CURLE_BAD_FUNCTION_ARGUMENT" "CURLE_BAD_CALLING_ORDER"
   "CURLE_HTTP_PORT_FAILED" "CURLE_BAD_PASSWORD_ENTERED"
   "CURLE_TOO_MANY_REDIRECTS" "CURLE_UNKOWN_TELNET_OPTION"
   "CURLE_TELNET_OPTION_SYNTAX" "CURLE_ALREADY_COMPLETE"
   "DBX_MYSQL" "DBX_ODBC" "DBX_PGSQL" "DBX_MSSQL" "DBX_PERSISTENT"
   "DBX_RESULT_INFO" "DBX_RESULT_INDEX" "DBX_RESULT_ASSOC"
   "DBX_CMP_TEXT" "DBX_CMP_NUMBER" "XML_ELEMENT_NODE"
   "XML_ATTRIBUTE_NODE" "XML_TEXT_NODE" "XML_CDATA_SECTION_NODE"
   "XML_ENTITY_REF_NODE" "XML_ENTITY_NODE" "XML_PI_NODE"
   "XML_COMMENT_NODE" "XML_DOCUMENT_NODE" "XML_DOCUMENT_TYPE_NODE"
   "XML_DOCUMENT_FRAG_NODE" "XML_NOTATION_NODE"
   "XML_HTML_DOCUMENT_NODE" "XML_DTD_NODE" "XML_ELEMENT_DECL_NODE"
   "XML_ATTRIBUTE_DECL_NODE" "XML_ENTITY_DECL_NODE"
   "XML_NAMESPACE_DECL_NODE" "XML_GLOBAL_NAMESPACE"
   "XML_LOCAL_NAMESPACE" "XML_ATTRIBUTE_CDATA" "XML_ATTRIBUTE_ID"
   "XML_ATTRIBUTE_IDREF" "XML_ATTRIBUTE_IDREFS"
   "XML_ATTRIBUTE_ENTITY" "XML_ATTRIBUTE_NMTOKEN"
   "XML_ATTRIBUTE_NMTOKENS" "XML_ATTRIBUTE_ENUMERATION"
   "XML_ATTRIBUTE_NOTATION" "XPATH_UNDEFINED" "XPATH_NODESET"
   "XPATH_BOOLEAN" "XPATH_NUMBER" "XPATH_STRING" "XPATH_POINT"
   "XPATH_RANGE" "XPATH_LOCATIONSET" "XPATH_USERS" "FBSQL_ASSOC"
   "FBSQL_NUM" "FBSQL_BOTH" "FDFValue" "FDFStatus" "FDFFile"
   "FDFID" "FDFFf" "FDFSetFf" "FDFClearFf" "FDFFlags" "FDFSetF"
   "FDFClrF" "FDFAP" "FDFAS" "FDFAction" "FDFAA" "FDFAPRef"
   "FDFIF" "FDFEnter" "FDFExit" "FDFDown" "FDFUp" "FDFFormat"
   "FDFValidate" "FDFKeystroke" "FDFCalculate"
   "FRIBIDI_CHARSET_UTF8" "FRIBIDI_CHARSET_8859_6"
   "FRIBIDI_CHARSET_8859_8" "FRIBIDI_CHARSET_CP1255"
   "FRIBIDI_CHARSET_CP1256" "FRIBIDI_CHARSET_ISIRI_3342"
   "FTP_ASCII" "FTP_BINARY" "FTP_IMAGE" "FTP_TEXT" "IMG_GIF"
   "IMG_JPG" "IMG_JPEG" "IMG_PNG" "IMG_WBMP" "IMG_COLOR_TILED"
   "IMG_COLOR_STYLED" "IMG_COLOR_BRUSHED"
   "IMG_COLOR_STYLEDBRUSHED" "IMG_COLOR_TRANSPARENT"
   "IMG_ARC_ROUNDED" "IMG_ARC_PIE" "IMG_ARC_CHORD"
   "IMG_ARC_NOFILL" "IMG_ARC_EDGED" "GMP_ROUND_ZERO"
   "GMP_ROUND_PLUSINF" "GMP_ROUND_MINUSINF" "HW_ATTR_LANG"
   "HW_ATTR_NR" "HW_ATTR_NONE" "IIS_READ" "IIS_WRITE"
   "IIS_EXECUTE" "IIS_SCRIPT" "IIS_ANONYMOUS" "IIS_BASIC"
   "IIS_NTLM" "NIL" "OP_DEBUG" "OP_READONLY" "OP_ANONYMOUS"
   "OP_SHORTCACHE" "OP_SILENT" "OP_PROTOTYPE" "OP_HALFOPEN"
   "OP_EXPUNGE" "OP_SECURE" "CL_EXPUNGE" "FT_UID" "FT_PEEK"
   "FT_NOT" "FT_INTERNAL" "FT_PREFETCHTEXT" "ST_UID" "ST_SILENT"
   "ST_SET" "CP_UID" "CP_MOVE" "SE_UID" "SE_FREE" "SE_NOPREFETCH"
   "SO_FREE" "SO_NOSERVER" "SA_MESSAGES" "SA_RECENT" "SA_UNSEEN"
   "SA_UIDNEXT" "SA_UIDVALIDITY" "SA_ALL" "LATT_NOINFERIORS"
   "LATT_NOSELECT" "LATT_MARKED" "LATT_UNMARKED" "SORTDATE"
   "SORTARRIVAL" "SORTFROM" "SORTSUBJECT" "SORTTO" "SORTCC"
   "SORTSIZE" "TYPETEXT" "TYPEMULTIPART" "TYPEMESSAGE"
   "TYPEAPPLICATION" "TYPEAUDIO" "TYPEIMAGE" "TYPEVIDEO"
   "TYPEOTHER" "ENC7BIT" "ENC8BIT" "ENCBINARY" "ENCBASE64"
   "ENCQUOTEDPRINTABLE" "ENCOTHER" "INGRES_ASSOC" "INGRES_NUM"
   "INGRES_BOTH" "IBASE_DEFAULT" "IBASE_TEXT" "IBASE_UNIXTIME"
   "IBASE_READ" "IBASE_COMMITTED" "IBASE_CONSISTENCY"
   "IBASE_NOWAIT" "IBASE_TIMESTAMP" "IBASE_DATE" "IBASE_TIME"
   "LDAP_DEREF_NEVER" "LDAP_DEREF_SEARCHING" "LDAP_DEREF_FINDING"
   "LDAP_DEREF_ALWAYS" "LDAP_OPT_DEREF" "LDAP_OPT_SIZELIMIT"
   "LDAP_OPT_TIMELIMIT" "LDAP_OPT_PROTOCOL_VERSION"
   "LDAP_OPT_ERROR_NUMBER" "LDAP_OPT_REFERRALS" "LDAP_OPT_RESTART"
   "LDAP_OPT_HOST_NAME" "LDAP_OPT_ERROR_STRING"
   "LDAP_OPT_MATCHED_DN" "LDAP_OPT_SERVER_CONTROLS"
   "LDAP_OPT_CLIENT_CONTROLS" "GSLC_SSL_NO_AUTH"
   "GSLC_SSL_ONEWAY_AUTH" "GSLC_SSL_TWOWAY_AUTH" "MCAL_SUNDAY"
   "MCAL_MONDAY" "MCAL_TUESDAY" "MCAL_WEDNESDAY" "MCAL_THURSDAY"
   "MCAL_FRIDAY" "MCAL_SATURDAY" "MCAL_JANUARY" "MCAL_FEBRUARY"
   "MCAL_MARCH" "MCAL_APRIL" "MCAL_MAY" "MCAL_JUNE" "MCAL_JULY"
   "MCAL_AUGUST" "MCAL_SEPTEMBER" "MCAL_OCTOBER" "MCAL_NOVEMBER"
   "MCAL_RECUR_NONE" "MCAL_RECUR_DAILY" "MCAL_RECUR_WEEKLY"
   "MCAL_RECUR_MONTHLY_MDAY" "MCAL_RECUR_MONTHLY_WDAY"
   "MCAL_RECUR_YEARLY" "MCAL_M_SUNDAY" "MCAL_M_MONDAY"
   "MCAL_M_TUESDAY" "MCAL_M_WEDNESDAY" "MCAL_M_THURSDAY"
   "MCAL_M_FRIDAY" "MCAL_M_SATURDAY" "MCAL_M_WEEKDAYS"
   "MCAL_M_WEEKEND" "MCAL_M_ALLDAYS" "MCRYPT_" "MCRYPT_"
   "MCRYPT_ENCRYPT" "MCRYPT_DECRYPT" "MCRYPT_DEV_RANDOM"
   "MCRYPT_DEV_URANDOM" "MCRYPT_RAND" "SWFBUTTON_HIT"
   "SWFBUTTON_DOWN" "SWFBUTTON_OVER" "SWFBUTTON_UP"
   "SWFBUTTON_MOUSEUPOUTSIDE" "SWFBUTTON_DRAGOVER"
   "SWFBUTTON_DRAGOUT" "SWFBUTTON_MOUSEUP" "SWFBUTTON_MOUSEDOWN"
   "SWFBUTTON_MOUSEOUT" "SWFBUTTON_MOUSEOVER"
   "SWFFILL_RADIAL_GRADIENT" "SWFFILL_LINEAR_GRADIENT"
   "SWFFILL_TILED_BITMAP" "SWFFILL_CLIPPED_BITMAP"
   "SWFTEXTFIELD_HASLENGTH" "SWFTEXTFIELD_NOEDIT"
   "SWFTEXTFIELD_PASSWORD" "SWFTEXTFIELD_MULTILINE"
   "SWFTEXTFIELD_WORDWRAP" "SWFTEXTFIELD_DRAWBOX"
   "SWFTEXTFIELD_NOSELECT" "SWFTEXTFIELD_HTML"
   "SWFTEXTFIELD_ALIGN_LEFT" "SWFTEXTFIELD_ALIGN_RIGHT"
   "SWFTEXTFIELD_ALIGN_CENTER" "SWFTEXTFIELD_ALIGN_JUSTIFY"
   "UDM_FIELD_URLID" "UDM_FIELD_URL" "UDM_FIELD_CONTENT"
   "UDM_FIELD_TITLE" "UDM_FIELD_KEYWORDS" "UDM_FIELD_DESC"
   "UDM_FIELD_DESCRIPTION" "UDM_FIELD_TEXT" "UDM_FIELD_SIZE"
   "UDM_FIELD_RATING" "UDM_FIELD_SCORE" "UDM_FIELD_MODIFIED"
   "UDM_FIELD_ORDER" "UDM_FIELD_CRC" "UDM_FIELD_CATEGORY"
   "UDM_PARAM_PAGE_SIZE" "UDM_PARAM_PAGE_NUM"
   "UDM_PARAM_SEARCH_MODE" "UDM_PARAM_CACHE_MODE"
   "UDM_PARAM_TRACK_MODE" "UDM_PARAM_PHRASE_MODE"
   "UDM_PARAM_CHARSET" "UDM_PARAM_STOPTABLE"
   "UDM_PARAM_STOP_TABLE" "UDM_PARAM_STOPFILE"
   "UDM_PARAM_STOP_FILE" "UDM_PARAM_WEIGHT_FACTOR"
   "UDM_PARAM_WORD_MATCH" "UDM_PARAM_MAX_WORD_LEN"
   "UDM_PARAM_MAX_WORDLEN" "UDM_PARAM_MIN_WORD_LEN"
   "UDM_PARAM_MIN_WORDLEN" "UDM_PARAM_ISPELL_PREFIXES"
   "UDM_PARAM_ISPELL_PREFIX" "UDM_PARAM_PREFIXES"
   "UDM_PARAM_PREFIX" "UDM_PARAM_CROSS_WORDS"
   "UDM_PARAM_CROSSWORDS" "UDM_LIMIT_CAT" "UDM_LIMIT_URL"
   "UDM_LIMIT_TAG" "UDM_LIMIT_LANG" "UDM_LIMIT_DATE"
   "UDM_PARAM_FOUND" "UDM_PARAM_NUM_ROWS" "UDM_PARAM_WORDINFO"
   "UDM_PARAM_WORD_INFO" "UDM_PARAM_SEARCHTIME"
   "UDM_PARAM_SEARCH_TIME" "UDM_PARAM_FIRST_DOC"
   "UDM_PARAM_LAST_DOC" "UDM_MODE_ALL" "UDM_MODE_ANY"
   "UDM_MODE_BOOL" "UDM_MODE_PHRASE" "UDM_CACHE_ENABLED"
   "UDM_CACHE_DISABLED" "UDM_TRACK_ENABLED" "UDM_TRACK_DISABLED"
   "UDM_PHRASE_ENABLED" "UDM_PHRASE_DISABLED"
   "UDM_CROSS_WORDS_ENABLED" "UDM_CROSSWORDS_ENABLED"
   "UDM_CROSS_WORDS_DISABLED" "UDM_CROSSWORDS_DISABLED"
   "UDM_PREFIXES_ENABLED" "UDM_PREFIX_ENABLED"
   "UDM_ISPELL_PREFIXES_ENABLED" "UDM_ISPELL_PREFIX_ENABLED"
   "UDM_PREFIXES_DISABLED" "UDM_PREFIX_DISABLED"
   "UDM_ISPELL_PREFIXES_DISABLED" "UDM_ISPELL_PREFIX_DISABLED"
   "UDM_ISPELL_TYPE_AFFIX" "UDM_ISPELL_TYPE_SPELL"
   "UDM_ISPELL_TYPE_DB" "UDM_ISPELL_TYPE_SERVER" "UDM_MATCH_WORD"
   "UDM_MATCH_BEGIN" "UDM_MATCH_SUBSTR" "UDM_MATCH_END"
   "MSQL_ASSOC" "MSQL_NUM" "MSQL_BOTH" "MYSQL_ASSOC" "MYSQL_NUM"
   "MYSQL_BOTH" "MYSQL_USE_RESULT" "MYSQL_STORE_RESULT"
   "OCI_DEFAULT" "OCI_DESCRIBE_ONLY" "OCI_COMMIT_ON_SUCCESS"
   "OCI_EXACT_FETCH" "SQLT_BFILEE" "SQLT_CFILEE" "SQLT_CLOB"
   "SQLT_BLOB" "SQLT_RDD" "OCI_B_SQLT_NTY" "OCI_SYSDATE"
   "OCI_B_BFILE" "OCI_B_CFILEE" "OCI_B_CLOB" "OCI_B_BLOB"
   "OCI_B_ROWID" "OCI_B_CURSOR" "OCI_B_BIN" "OCI_ASSOC" "OCI_NUM"
   "OCI_BOTH" "OCI_RETURN_NULLS" "OCI_RETURN_LOBS"
   "OCI_DTYPE_FILE" "OCI_DTYPE_LOB" "OCI_DTYPE_ROWID" "OCI_D_FILE"
   "OCI_D_LOB" "OCI_D_ROWID" "ODBC_TYPE" "ODBC_BINMODE_PASSTHRU"
   "ODBC_BINMODE_RETURN" "ODBC_BINMODE_CONVERT" "SQL_ODBC_CURSORS"
   "SQL_CUR_USE_DRIVER" "SQL_CUR_USE_IF_NEEDED" "SQL_CUR_USE_ODBC"
   "SQL_CONCURRENCY" "SQL_CONCUR_READ_ONLY" "SQL_CONCUR_LOCK"
   "SQL_CONCUR_ROWVER" "SQL_CONCUR_VALUES" "SQL_CURSOR_TYPE"
   "SQL_CURSOR_FORWARD_ONLY" "SQL_CURSOR_KEYSET_DRIVEN"
   "SQL_CURSOR_DYNAMIC" "SQL_CURSOR_STATIC" "SQL_KEYSET_SIZE"
   "SQL_CHAR" "SQL_VARCHAR" "SQL_LONGVARCHAR" "SQL_DECIMAL"
   "SQL_NUMERIC" "SQL_BIT" "SQL_TINYINT" "SQL_SMALLINT"
   "SQL_INTEGER" "SQL_BIGINT" "SQL_REAL" "SQL_FLOAT" "SQL_DOUBLE"
   "SQL_BINARY" "SQL_VARBINARY" "SQL_LONGVARBINARY" "SQL_DATE"
   "SQL_TIME" "SQL_TIMESTAMP" "SQL_TYPE_DATE" "SQL_TYPE_TIME"
   "SQL_TYPE_TIMESTAMP" "SQL_BEST_ROWID" "SQL_ROWVER"
   "SQL_SCOPE_CURROW" "SQL_SCOPE_TRANSACTION" "SQL_SCOPE_SESSION"
   "SQL_NO_NULLS" "SQL_NULLABLE" "SQL_INDEX_UNIQUE"
   "SQL_INDEX_ALL" "SQL_ENSURE" "SQL_QUICK"
   "X509_PURPOSE_SSL_CLIENT" "X509_PURPOSE_SSL_SERVER"
   "X509_PURPOSE_NS_SSL_SERVER" "X509_PURPOSE_SMIME_SIGN"
   "X509_PURPOSE_SMIME_ENCRYPT" "X509_PURPOSE_CRL_SIGN"
   "X509_PURPOSE_ANY" "PKCS7_DETACHED" "PKCS7_TEXT"
   "PKCS7_NOINTERN" "PKCS7_NOVERIFY" "PKCS7_NOCHAIN"
   "PKCS7_NOCERTS" "PKCS7_NOATTR" "PKCS7_BINARY" "PKCS7_NOSIGS"
   "OPENSSL_PKCS1_PADDING" "OPENSSL_SSLV23_PADDING"
   "OPENSSL_NO_PADDING" "OPENSSL_PKCS1_OAEP_PADDING"
   "ORA_BIND_INOUT" "ORA_BIND_IN" "ORA_BIND_OUT"
   "ORA_FETCHINTO_ASSOC" "ORA_FETCHINTO_NULLS"
   "PREG_PATTERN_ORDER" "PREG_SET_ORDER" "PREG_SPLIT_NO_EMPTY"
   "PREG_SPLIT_DELIM_CAPTURE"
   "PGSQL_ASSOC" "PGSQL_NUM" "PGSQL_BOTH"
   "PRINTER_COPIES" "PRINTER_MODE" "PRINTER_TITLE"
   "PRINTER_DEVICENAME" "PRINTER_DRIVERVERSION"
   "PRINTER_RESOLUTION_Y" "PRINTER_RESOLUTION_X" "PRINTER_SCALE"
   "PRINTER_BACKGROUND_COLOR" "PRINTER_PAPER_LENGTH"
   "PRINTER_PAPER_WIDTH" "PRINTER_PAPER_FORMAT"
   "PRINTER_FORMAT_CUSTOM" "PRINTER_FORMAT_LETTER"
   "PRINTER_FORMAT_LEGAL" "PRINTER_FORMAT_A3" "PRINTER_FORMAT_A4"
   "PRINTER_FORMAT_A5" "PRINTER_FORMAT_B4" "PRINTER_FORMAT_B5"
   "PRINTER_FORMAT_FOLIO" "PRINTER_ORIENTATION"
   "PRINTER_ORIENTATION_PORTRAIT" "PRINTER_ORIENTATION_LANDSCAPE"
   "PRINTER_TEXT_COLOR" "PRINTER_TEXT_ALIGN" "PRINTER_TA_BASELINE"
   "PRINTER_TA_BOTTOM" "PRINTER_TA_TOP" "PRINTER_TA_CENTER"
   "PRINTER_TA_LEFT" "PRINTER_TA_RIGHT" "PRINTER_PEN_SOLID"
   "PRINTER_PEN_DASH" "PRINTER_PEN_DOT" "PRINTER_PEN_DASHDOT"
   "PRINTER_PEN_DASHDOTDOT" "PRINTER_PEN_INVISIBLE"
   "PRINTER_BRUSH_SOLID" "PRINTER_BRUSH_CUSTOM"
   "PRINTER_BRUSH_DIAGONAL" "PRINTER_BRUSH_CROSS"
   "PRINTER_BRUSH_DIAGCROSS" "PRINTER_BRUSH_FDIAGONAL"
   "PRINTER_BRUSH_HORIZONTAL" "PRINTER_BRUSH_VERTICAL"
   "PRINTER_FW_THIN" "PRINTER_FW_ULTRALIGHT" "PRINTER_FW_LIGHT"
   "PRINTER_FW_NORMAL" "PRINTER_FW_MEDIUM" "PRINTER_FW_BOLD"
   "PRINTER_FW_ULTRABOLD" "PRINTER_FW_HEAVY" "PRINTER_ENUM_LOCAL"
   "PRINTER_ENUM_NAME" "PRINTER_ENUM_SHARED"
   "PRINTER_ENUM_DEFAULT" "PRINTER_ENUM_CONNECTIONS"
   "PRINTER_ENUM_NETWORK" "PRINTER_ENUM_REMOTE" "PSPELL_FAST"
   "PSPELL_NORMAL" "PSPELL_BAD_SPELLERS" "PSPELL_RUN_TOGETHER"
   "SID" "SID" "AF_UNIX" "AF_INET" "SOCK_STREAM" "SOCK_DGRAM"
   "SOCK_RAW" "SOCK_SEQPACKET" "SOCK_RDM" "MSG_OOB" "MSG_WAITALL"
   "MSG_PEEK" "MSG_DONTROUTE" "SO_DEBUG" "SO_REUSEADDR"
   "SO_KEEPALIVE" "SO_DONTROUTE" "SO_LINGER" "SO_BROADCAST"
   "SO_OOBINLINE" "SO_SNDBUF" "SO_RCVBUF" "SO_SNDLOWAT"
   "SO_RCVLOWAT" "SO_SNDTIMEO" "SO_RCVTIMEO" "SO_TYPE" "SO_ERROR"
   "SOL_SOCKET" "PHP_NORMAL_READ" "PHP_BINARY_READ"
   "PHP_SYSTEM_READ" "SOL_TCP" "SOL_UDP" "MOD_COLOR" "MOD_MATRIX"
   "TYPE_PUSHBUTTON" "TYPE_MENUBUTTON" "BSHitTest" "BSDown"
   "BSOver" "BSUp" "OverDowntoIdle" "IdletoOverDown"
   "OutDowntoIdle" "OutDowntoOverDown" "OverDowntoOutDown"
   "OverUptoOverDown" "OverUptoIdle" "IdletoOverUp" "ButtonEnter"
   "ButtonExit" "MenuEnter" "MenuExit" "XML_ERROR_NONE"
   "XML_ERROR_NO_MEMORY" "XML_ERROR_SYNTAX"
   "XML_ERROR_NO_ELEMENTS" "XML_ERROR_INVALID_TOKEN"
   "XML_ERROR_UNCLOSED_TOKEN" "XML_ERROR_PARTIAL_CHAR"
   "XML_ERROR_TAG_MISMATCH" "XML_ERROR_DUPLICATE_ATTRIBUTE"
   "XML_ERROR_JUNK_AFTER_DOC_ELEMENT" "XML_ERROR_PARAM_ENTITY_REF"
   "XML_ERROR_UNDEFINED_ENTITY" "XML_ERROR_RECURSIVE_ENTITY_REF"
   "XML_ERROR_ASYNC_ENTITY" "XML_ERROR_BAD_CHAR_REF"
   "XML_ERROR_BINARY_ENTITY_REF"
   "XML_ERROR_ATTRIBUTE_EXTERNAL_ENTITY_REF"
   "XML_ERROR_MISPLACED_XML_PI" "XML_ERROR_UNKNOWN_ENCODING"
   "XML_ERROR_INCORRECT_ENCODING"
   "XML_ERROR_UNCLOSED_CDATA_SECTION"
   "XML_ERROR_EXTERNAL_ENTITY_HANDLING" "XML_OPTION_CASE_FOLDING"
   "XML_OPTION_TARGET_ENCODING" "XML_OPTION_SKIP_TAGSTART"
   "XML_OPTION_SKIP_WHITE" "YPERR_BADARGS" "YPERR_BADDB"
   "YPERR_BUSY" "YPERR_DOMAIN" "YPERR_KEY" "YPERR_MAP"
   "YPERR_NODOM" "YPERR_NOMORE" "YPERR_PMAP" "YPERR_RESRC"
   "YPERR_RPC" "YPERR_YPBIND" "YPERR_YPERR" "YPERR_YPSERV"
   "YPERR_VERS" "FORCE_GZIP" "FORCE_DEFLATE"

   ;;PEAR constants
   "PEAR_ERROR_RETURN" "PEAR_ERROR_PRINT" "PEAR_ERROR_TRIGGER"
   "PEAR_ERROR_DIE" "PEAR_ERROR_CALLBACK" "OS_WINDOWS" "OS_UNIX"
   "PEAR_OS" "DB_OK" "DB_ERROR" "DB_ERROR_SYNTAX"
   "DB_ERROR_CONSTRAINT" "DB_ERROR_NOT_FOUND"
   "DB_ERROR_ALREADY_EXISTS" "DB_ERROR_UNSUPPORTED"
   "DB_ERROR_MISMATCH" "DB_ERROR_INVALID" "DB_ERROR_NOT_CAPABLE"
   "DB_ERROR_TRUNCATED" "DB_ERROR_INVALID_NUMBER"
   "DB_ERROR_INVALID_DATE" "DB_ERROR_DIVZERO"
   "DB_ERROR_NODBSELECTED" "DB_ERROR_CANNOT_CREATE"
   "DB_ERROR_CANNOT_DELETE" "DB_ERROR_CANNOT_DROP"
   "DB_ERROR_NOSUCHTABLE" "DB_ERROR_NOSUCHFIELD"
   "DB_ERROR_NEED_MORE_DATA" "DB_ERROR_NOT_LOCKED"
   "DB_ERROR_VALUE_COUNT_ON_ROW" "DB_ERROR_INVALID_DSN"
   "DB_ERROR_CONNECT_FAILED" "DB_WARNING" "DB_WARNING_READ_ONLY"
   "DB_PARAM_SCALAR" "DB_PARAM_OPAQUE" "DB_BINMODE_PASSTHRU"
   "DB_BINMODE_RETURN" "DB_BINMODE_CONVERT" "DB_FETCHMODE_DEFAULT"
   "DB_FETCHMODE_ORDERED" "DB_FETCHMODE_ASSOC"
   "DB_FETCHMODE_FLIPPED" "DB_GETMODE_ORDERED" "DB_GETMODE_ASSOC"
   "DB_GETMODE_FLIPPED" "DB_TABLEINFO_ORDER"
   "DB_TABLEINFO_ORDERTABLE" "DB_TABLEINFO_FULL"

   ;; merged from autocompletion-php.el
   "ERA" "M_E" "M_PI" "NOSTR" "T_FMT" "D_FMT" "MON_9" "MON_8" "MON_7" "MON_6" "MON_5" "MON_4" "MON_3" "MON_2" "MON_1" "DAY_7" "DAY_6" "DAY_5" "DAY_4" "DAY_3" "DAY_2" "DAY_1" "M_LN2" "E_ALL" "YESSTR" "NOEXPR" "PM_STR" "AM_STR" "MON_12" "MON_11" "MON_10" "LC_ALL" "M_2_PI" "M_1_PI" "M_PI_4" "M_PI_2" "M_LN10" "PHP_OS" "LOG_PID" "LOG_LPR" "LOG_ERR" "CODESET" "YESEXPR" "THOUSEP" "D_T_FMT" "ABMON_9" "ABMON_8" "ABMON_7" "ABMON_6" "ABMON_5" "ABMON_4" "ABMON_3" "ABMON_2" "ABMON_1" "ABDAY_7" "ABDAY_6" "ABDAY_5" "ABDAY_4" "ABDAY_3" "ABDAY_2" "ABDAY_1" "LC_TIME" "LOCK_NB" "LOCK_UN" "LOCK_EX" "LOCK_SH" "M_SQRT2" "M_LOG2E" "INI_ALL" "E_PARSE" "E_ERROR" "PHP_EOL" "PHP_ZTS" "LOG_CONS" "LOG_CRON" "LOG_UUCP" "LOG_NEWS" "LOG_AUTH" "LOG_MAIL" "LOG_USER" "LOG_KERN" "LOG_INFO" "LOG_CRIT" "GROUPING" "CRNCYSTR" "ERA_YEAR" "ABMON_12" "ABMON_11" "ABMON_10" "LC_CTYPE" "CHAR_MAX" "INFO_ALL" "SEEK_END" "SEEK_CUR" "SEEK_SET" "M_LOG10E" "INI_USER" "SORT_ASC" "E_STRICT" "E_NOTICE" "PHP_SAPI" "LOG_DEBUG" "LOG_ALERT" "LOG_EMERG" "RADIXCHAR" "ERA_T_FMT" "ERA_D_FMT" "CRYPT_MD5" "M_SQRT1_2" "SORT_DESC" "EXTR_SKIP" "E_WARNING" "PHP_DEBUG" "LOG_NOWAIT" "LOG_NDELAY" "LOG_ODELAY" "LOG_LOCAL7" "LOG_LOCAL6" "LOG_LOCAL5" "LOG_LOCAL4" "LOG_LOCAL3" "LOG_LOCAL2" "LOG_LOCAL1" "LOG_LOCAL0" "LOG_SYSLOG" "LOG_DAEMON" "LOG_NOTICE" "ALT_DIGITS" "T_FMT_AMPM" "LC_COLLATE" "LC_NUMERIC" "CREDITS_QA" "ENT_QUOTES" "ENT_COMPAT" "M_2_SQRTPI" "INI_SYSTEM" "INI_PERDIR" "CASE_UPPER" "CASE_LOWER" "PHP_LIBDIR" "PHP_BINDIR" "PHP_PREFIX" "LOG_WARNING" "N_SIGN_POSN" "P_SIGN_POSN" "FRAC_DIGITS" "ERA_D_T_FMT" "LC_MESSAGES" "LC_MONETARY" "CREDITS_ALL" "ASSERT_BAIL" "SORT_STRING" "PHP_DATADIR" "PHP_INT_MAX" "PHP_VERSION" "LOG_AUTHPRIV" "MON_GROUPING" "STR_PAD_BOTH" "STR_PAD_LEFT" "CREDITS_DOCS" "CREDITS_SAPI" "INFO_LICENSE" "INFO_MODULES" "INFO_CREDITS" "INFO_GENERAL" "ENT_NOQUOTES" "COUNT_NORMAL" "SORT_NUMERIC" "SORT_REGULAR" "E_USER_ERROR" "E_CORE_ERROR" "PHP_INT_SIZE" "THOUSANDS_SEP" "DECIMAL_POINT" "N_CS_PRECEDES" "P_CS_PRECEDES" "NEGATIVE_SIGN" "POSITIVE_SIGN" "STR_PAD_RIGHT" "CREDITS_GROUP" "HTML_ENTITIES" "CRYPT_EXT_DES" "CRYPT_STD_DES" "ASSERT_ACTIVE" "E_USER_NOTICE" "N_SEP_BY_SPACE" "P_SEP_BY_SPACE" "PATH_SEPARATOR" "INFO_VARIABLES" "CRYPT_BLOWFISH" "ASSERT_WARNING" "EXTR_IF_EXISTS" "EXTR_OVERWRITE" "E_USER_WARNING" "E_CORE_WARNING" "PHP_SYSCONFDIR" "PHP_VERSION_ID" "INT_FRAC_DIGITS" "CURRENCY_SYMBOL" "INT_CURR_SYMBOL" "CREDITS_MODULES" "CREDITS_GENERAL" "ASSERT_CALLBACK" "COUNT_RECURSIVE" "EXTR_PREFIX_ALL" "E_COMPILE_ERROR" "PATHINFO_DIRNAME" "CREDITS_FULLPAGE" "INFO_ENVIRONMENT" "EXTR_PREFIX_SAME" "PHP_SHLIB_SUFFIX" "PEAR_INSTALL_DIR" "MON_THOUSANDS_SEP" "MON_DECIMAL_POINT" "PATHINFO_BASENAME" "HTML_SPECIALCHARS" "CRYPT_SALT_LENGTH" "CONNECTION_NORMAL" "ASSERT_QUIET_EVAL" "E_COMPILE_WARNING" "PHP_LOCALSTATEDIR" "PHP_EXTENSION_DIR" "PHP_EXTRA_VERSION" "PHP_MINOR_VERSION" "PHP_MAJOR_VERSION" "PATHINFO_EXTENSION" "INFO_CONFIGURATION" "CONNECTION_TIMEOUT" "CONNECTION_ABORTED" "PEAR_EXTENSION_DIR" "DIRECTORY_SEPARATOR" "EXTR_PREFIX_INVALID" "PHP_RELEASE_VERSION" "PHP_CONFIG_FILE_PATH" "DEFAULT_INCLUDE_PATH" "EXTR_PREFIX_IF_EXISTS" "PHP_OUTPUT_HANDLER_END" "PHP_OUTPUT_HANDLER_CONT" "__COMPILER_HALT_OFFSET__" "PHP_OUTPUT_HANDLER_START" "PHP_CONFIG_FILE_SCAN_DIR"
   "__DIR__"
   ))

(phpcmp-db-update
 'keywords
 '("and" "as" "break" "continue" "declare" "do" "echo" "else" "elseif"
   "endfor" "endforeach" "endif" "endswitch" "endwhile" "exit"
   "extends" "for" "foreach" "global" "if" "include" "include_once"
   "next" "or" "require" "require_once" "return" "static" "switch"
   "then" "var" "while" "xor" "private" "throw" "catch" "try"
   "instanceof" "catch all" "finally"
   "yield" "trait"

   ;; merged from autocompletion-php.el
   "die" "use" "new" "list" "eval" "this" "goto" "case" "isset" "empty" "final" "const" "clone" "class" "array" "public" "__DIR__" "default" "__FILE__" "function" "abstract" "__CLASS__" "protected" "namespace" "interface" "cfunction" "__METHOD__" "implements" "enddeclare" "__FUNCTION__" "old_function" "__NAMESPACE__"
   ))

(phpcmp-db-update
 'superglobals
 '("$_GET" "$_POST" "$_COOKIE" "$_SESSION" "$_ENV" "$GLOBALS"
   "$_SERVER" "$_FILES" "$_REQUEST"))

(phpcmp-db-update
 'types
 '("array" "bool" "boolean" "char" "const" "double" "float"
   "int" "integer" "long" "mixed" "object" "real"
   "string"))

(phpcmp-db-update
 'phpunit-assertions
 (phpcmp-get-index-list-from-file phpcmp-phpunit-assertion-file))

(phpcmp-db-update
 'phpunit-methods
 '(
   "markTestIncomplete"
   "markTestSkipped"
   ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Mode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-minor-mode php-completion-mode
  "php-completion mode"
  :lighter phpcmp-lighter
  :group 'php-completion
  (phpcmp-async-set-functions))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; showtip ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; below is copied from showtip.el.
;; I just added prefix(phpcmp-) for name space problem.
;; why?, for portability

;; showtip.el is written by Ye Wenbin.
;; http://www.emacswiki.org/emacs/showtip.el


(defgroup phpcmp-showtip nil
  "Customization group for phpcmp-showtip"
  :group 'help)

(defcustom phpcmp-showtip-timeout 10
  "Seconds to wait before displaying a tooltip the first time."
  :type 'number
  :group 'phpcmp-showtip)

(defcustom phpcmp-showtip-top-adjust 40
  "Basic adjust."
  :type 'number
  :group 'phpcmp-showtip)

(defface phpcmp-showtip-face '((((class color)) :inherit tooltip))
  "face to display items"
  :group 'phpcmp-showtip)

(defun phpcmp-showtip-frame-posn-at-point (&optional position window)
  "Return pixel position of top left corner of glyph at POSITION,
relative to top left corner of frame containing WINDOW. Defaults
to the position of point in the selected window."
  (unless window (setq window (selected-window)))
  (unless position (setq position (window-point window)))
  (let ((x-y (posn-x-y (posn-at-point position window)))
        (edges (window-inside-pixel-edges window)))
    (cons (+ (car x-y) (car  edges))
          (+ (cdr x-y) (cadr edges)))))

(defun phpcmp-showtip (text)
  "Show tooltip text near cursor."
  (let ((pos (phpcmp-showtip-frame-posn-at-point))
        (fg (face-attribute 'phpcmp-showtip-face :foreground nil 'tooltip))
        (bg (face-attribute 'phpcmp-showtip-face :background nil 'tooltip))
        (params tooltip-frame-parameters)
        (top-adjust (- (+ (if menu-bar-mode 25 0)
                          (if tool-bar-mode 35 0)
                          phpcmp-showtip-top-adjust)
                       (if header-line-format
                           (frame-char-height) 0)))
        (max-width 84)
        (max-height 30)
        (frame-height (frame-pixel-height))
        (frame-width (frame-pixel-width))
        (lines (split-string text "\n"))
        width height left top)
    (setq height (* (frame-char-height) (min max-height (length lines))))
    (setq lines (nbutlast lines (- (length lines) (min max-height (length lines)))))
    (setq width (* (frame-char-width)
                   (min max-width (apply 'max (mapcar 'string-width lines)))))
    (setq left (+ (frame-parameter nil 'left) (frame-char-width))
          top (frame-parameter nil 'top))
    ;; if the cursor is at near the right frame fringe or at bottom
    ;; of the bottom fringe, move the frame to
    ;; -frame-width or -frame-height from right or bottom
    (if (< (- frame-width (car pos)) width)
        (setq left (+ left (max 0 (- frame-width width))))
      (setq left (+ left (car pos))))
    (if (< (- frame-height (+ (cdr pos) top-adjust)) height)
        (setq top (+ top frame-height (- height)))
      (setq top (+ top (cdr pos))))
    (setq top (+ top top-adjust))
    (when (stringp fg)
      (setq params (append params `((foreground-color . ,fg)
                                    (border-color . ,fg)))))
    (when (stringp bg)
      (setq params (append params `((background-color . ,bg)))))
    (setq params (append params `((left . ,left)
                                  (top . ,top))))
    (x-show-tip (propertize text 'face 'phpcmp-showtip-face)
                (selected-frame) params phpcmp-showtip-timeout)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Test ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defmacro phpcmp-with-php-buffer (s &rest body)
  `(with-temp-buffer
     (php-mode)
     (insert ,s)
     (goto-char (point-min))
     (when (re-search-forward (rx "`!!'") nil t)
       (replace-match ""))
     (progn
       ,@body)))


(defun phpcmp-t-to-bool (o)
  (null (null o)))

(dont-compile
  (when (fboundp 'expectations)
    (expectations
      (desc "phpcmp-re-sort-table")
      (expect "constants"
        (first
         (first
          (phpcmp-re-sort-table "constants" (phpcmp-completions-table)))))
      (expect t
        (let* ((tbl (phpcmp-re-sort-table '("global" "superglobals") (phpcmp-completions-table)))
               (first (first (first tbl)))
               (second (first (second  tbl))))
          (and (equal first "superglobals")
               (equal second "global tags"))))
      (desc "phpcmp-take-same-indent-string")
      (expect "class AdminController extends Zend_Controller_ActionAdminController 22,556
  public function init()init 35,1051
"
        (phpcmp-with-php-buffer
         "`!!'class AdminController extends Zend_Controller_ActionAdminController 22,556
  public function init()init 35,1051
function"
         (phpcmp-take-same-indent-string)))
      (desc "phpcmp-db-get")
      (desc "db-get functions")
      (expect t
        (phpcmp-t-to-bool
         (member "array_map"
                 (phpcmp-db-get 'functions))))
      (desc "db-get ini-directives")
      (expect t
        (phpcmp-t-to-bool
         (member "register_globals"
                 (phpcmp-db-get 'ini-directives))))
      (desc "db-get constants")
      (expect t
        (phpcmp-t-to-bool
         (member "__LINE__"
                 (phpcmp-db-get 'constants))))
      (desc "db-get keywords")
      (expect t
        (phpcmp-t-to-bool
         (member "elseif"
                 (phpcmp-db-get 'keywords))))
      (desc "db-get superglobals")
      (expect t
        (phpcmp-t-to-bool
         (member "$_GET"
                 (phpcmp-db-get 'superglobals))))
      (desc "db-get types")
      (expect t
        (phpcmp-t-to-bool
         (member "array"
                 (phpcmp-db-get 'types))))
      (desc "--- auto-complete.el ---")
      (desc "phpcmp-ac-get-cands")
      (expect t
        (let ((los (phpcmp-ac-get-cands)))
          (and
           (listp los)
           (stringp (first los))
           (stringp (first (last los))))))

      (desc "phpcmp-db-update remove duplicates")
      (expect t
        (phpcmp-db-update '__test-los '("a" "b"))
        (phpcmp-db-update '__test-los '("a" "c"))
        (equal (phpcmp-db-get '__test-los)
               '("c" "a" "b")))


      (desc "phpcmp-smart-sort")
      (expect "Class"
        (phpcmp-with-php-buffer
         "Class::func`!!'"
         (phpcmp-smart-sort-rule-full-name)))

      (desc "phpcmp-get-words-in-buffer")
      (expect '("test1" "test2" "test3" "test4")
        (phpcmp-with-php-buffer
         "test1\n test2\n `!!' test3\n test4"
         (phpcmp-get-words-in-buffer)))

      (desc "phpcmp-etags-parse-tags-buffer")
      (expect t

        (let ((tags (phpcmp-with-php-buffer
                     "class OS_GuessOS_Guess 100,3447
    function OS_Guess($uname = null)OS_Guess 108,3550

class SimpleCRUDSimpleCRUD 64,1683
     * $gdClient - Client class used to communicate with the Blogger serviceused 74,1824
    public function __construct($email, $password)__construct 89,2249
"
                     (phpcmp-etags-parse-tags-buffer "dummy"))))
          (and (phpcmp-tag-p (first tags))
               (phpcmp-tag-p (second tags)))))

      (expect '(("$notEmpty" . "Zend_Validate_NotEmpty"))
        (phpcmp-with-php-buffer
         "$notEmpty = new Zend_Validate_NotEmpty();"
         (phpcmp-get-obj-instance-of-module-maybe-alist)))
      (expect nil
        (phpcmp-with-php-buffer
         "$var`!!"
         (phpcmp-smart-sort-variable)))

      )))

(provide 'php-completion)

;; php-completion.el ends here.
